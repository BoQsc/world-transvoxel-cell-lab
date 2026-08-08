@tool
extends Node
class_name WtTerrainLabTargetedCollisionQualification

const Harness := preload("res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_runtime_harness.gd")
const JsonLoader := preload("res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd")
const Statistics := preload("res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd")
const STANDARD_PATH := "res://addons/world_transvoxel_terrain_lab/standards/targeted_collision_residency_standard.json"
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/tqp46_targeted_collision"

var _harness: Node
var _terrain: Node


func run() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var profile: Dictionary = standard.get("runtime_profile", {})
	var failures: Array[String] = []
	_validate_native_authority(standard, failures)
	Harness.remove_tree(RUNTIME_ROOT)
	_harness = Harness.new()
	add_child(_harness)
	if not _harness.create_runtime(int(profile.get("worker_count", 2)), _overrides(profile)):
		failures.append("native runtime unavailable")
		return await _finish(standard, {}, failures)
	_terrain = _harness.terrain
	var volume: Array = profile.get("volume_chunks", [])
	if volume.size() != 3 or not await _harness.start_procedural_world_preset(
		RUNTIME_ROOT, int(profile.get("source_revision", 946001)), int(profile.get("seed", 460046)),
		str(profile.get("preset", "rolling_hills_cave")), int(volume[0]), int(volume[1]),
		int(profile.get("vertical_chunk_origin", -4)), int(volume[2])
	):
		failures.append("native procedural world did not start")
		return await _finish(standard, {}, failures)

	var viewer_position := _vector3(profile.get("viewer_position", []))
	var render_started := Time.get_ticks_usec()
	var render_accepted := bool(_terrain.call(
		"update_viewer", int(profile.get("viewer_id", 460)), 1, viewer_position,
		int(profile.get("viewer_radius_chunks", 3)), int(profile.get("maximum_lod", 1))
	))
	var render_settlement: Dictionary = await _harness.wait_for_settled(1)
	var render_only_metrics: Dictionary = _terrain.call("get_runtime_metrics")
	var render_only := {
		"status": "PASS" if render_accepted and str(render_settlement.get("status", "")) == "PASS"
			and _all_required_generations_match()
			and int(render_only_metrics.get("visual_required_chunk_records", 0)) > 0
			and int(render_only_metrics.get("collision_required_chunk_records", 0)) > 0
			and int(render_only_metrics.get("collision_required_chunk_records", 0))
				< int(render_only_metrics.get("visual_required_chunk_records", 0))
			and _collision_only_count() == 0 else "FAIL",
		"settlement_usec": Time.get_ticks_usec() - render_started,
		"distant_visible_collision_free_count": int(render_only_metrics.get("visual_required_chunk_records", 0))
			- int(render_only_metrics.get("collision_required_chunk_records", 0)),
		"explicit_collision_only_count": _collision_only_count(),
		"metrics": _selected_metrics(render_only_metrics),
	}
	_expect(str(render_only.get("status", "")) == "PASS", "visual-viewer collision policy was not a bounded near-field subset", failures)

	var demand_before_query := _demand_signature()
	var query: Dictionary = await _harness.request_sample(Vector3i(_vector3(standard.get("authoritative_query_point", []))))
	var demand_after_query := _demand_signature()
	var query_independence := {
		"status": "PASS" if str(query.get("status", "")) == "PASS" and demand_before_query == demand_after_query else "FAIL",
		"sample": query,
		"before": demand_before_query,
		"after": demand_after_query,
	}
	_expect(str(query_independence.get("status", "")) == "PASS", "authoritative query mutated terrain demand", failures)

	var invokers: Array[Dictionary] = []
	var collision_latencies: Array[float] = []
	var revisions := {}
	for value in standard.get("invokers", []):
		var invoker: Dictionary = value
		var id := int(invoker.get("id", 0))
		revisions[id] = 1
		var started := Time.get_ticks_usec()
		var before: Dictionary = _terrain.call("get_runtime_metrics")
		var accepted := bool(_terrain.call(
			"update_collision_viewer", id, 1, _vector3(invoker.get("position", [])),
			int(profile.get("collision_radius_chunks", 1))
		))
		var event_observed := await _wait_for_metric(
			"collision_viewer_updates", int(before.get("collision_viewer_updates", 0)) + 1
		)
		var settlement: Dictionary = await _harness.wait_for_settled(1)
		var latency := Time.get_ticks_usec() - started
		var after: Dictionary = _terrain.call("get_runtime_metrics")
		var ready := _covering_collision_ready(_vector3(invoker.get("position", [])))
		var record := {
			"id": id,
			"class": invoker.get("class", ""),
			"status": "PASS" if accepted and event_observed and str(settlement.get("status", "")) == "PASS"
				and _all_required_generations_match() and ready else "FAIL",
			"latency_usec": latency,
			"event_observed": event_observed,
			"collision_ready": ready,
			"applied_collision_delta": int(after.get("application_applied_collision", 0)) - int(before.get("application_applied_collision", 0)),
			"collision_required_count": int(after.get("collision_required_chunk_records", 0)),
			"collision_resource_count": int(after.get("collision_resources", 0)),
		}
		invokers.append(record)
		collision_latencies.append(float(latency))
		_expect(str(record.get("status", "")) == "PASS", "collision invoker failed: " + str(invoker.get("class", "")), failures)
	var collision_metrics: Dictionary = _terrain.call("get_runtime_metrics")
	var targeted_subset := int(collision_metrics.get("collision_required_chunk_records", 0)) > 0 \
		and int(collision_metrics.get("collision_required_chunk_records", 0)) < int(collision_metrics.get("visual_required_chunk_records", 0)) \
		and _collision_only_count() > 0
	_expect(targeted_subset, "collision demand is not a bounded subset of visual demand", failures)

	var player: Dictionary = (standard.get("invokers", []) as Array)[0]
	var player_id := int(player.get("id", 461))
	var before_sweep_keys := _collision_required_keys()
	revisions[player_id] = int(revisions[player_id]) + 1
	var sweep_started := Time.get_ticks_usec()
	var sweep_accepted := bool(_terrain.call(
		"update_collision_viewer", player_id, int(revisions[player_id]),
		_vector3(standard.get("swept_motion_destination", [])), int(profile.get("collision_radius_chunks", 1))
	))
	var sweep_settlement: Dictionary = await _harness.wait_for_settled(1)
	var after_sweep_keys := _collision_required_keys()
	var sweep_ready := _covering_collision_ready(_vector3(standard.get("swept_motion_destination", [])))
	var sweep := {
		"status": "PASS" if sweep_accepted and str(sweep_settlement.get("status", "")) == "PASS"
			and _all_required_generations_match() and sweep_ready
			and _intersection_count(before_sweep_keys, after_sweep_keys) > 0 else "FAIL",
		"latency_usec": Time.get_ticks_usec() - sweep_started,
		"overlap_chunk_count": _intersection_count(before_sweep_keys, after_sweep_keys),
		"destination_collision_ready": sweep_ready,
	}
	_expect(str(sweep.get("status", "")) == "PASS", "swept collision envelope lost continuity", failures)

	await get_tree().physics_frame
	var ray_safety := _ray_safety(standard.get("invokers", []), standard.get("swept_motion_destination", []))
	_expect(str(ray_safety.get("status", "")) == "PASS", "collision ray safety failed inside an invoker envelope", failures)
	var nav_before := _demand_signature()
	var navigation := _derive_navigation_snapshot()
	var nav_after := _demand_signature()
	navigation["demand_unchanged"] = nav_before == nav_after
	navigation["status"] = "PASS" if int(navigation.get("polygon_count", 0)) > 0 and nav_before == nav_after else "FAIL"
	_expect(str(navigation.get("status", "")) == "PASS", "on-demand navigation snapshot was not independent", failures)

	var edit: Dictionary = standard.get("edit", {})
	var edit_center := _vector3(edit.get("center", []))
	var edit_before: Dictionary = _terrain.call("get_runtime_metrics")
	var transaction: RefCounted = _terrain.call("begin_edit_transaction", 4601)
	var edit_started := Time.get_ticks_usec()
	var edit_accepted := transaction != null and bool(transaction.call(
		"carve_smooth_sdf_sphere", edit_center, float(edit.get("radius", 5.0)), 1.0,
		float(edit.get("smooth_radius", 1.0))
	)) and bool(_terrain.call("commit_edit_transaction", transaction))
	var committed: bool = await _harness.wait_for_commit(1)
	var edit_settlement: Dictionary = await _harness.wait_for_settled(1)
	var edit_after: Dictionary = _terrain.call("get_runtime_metrics")
	var edit_latency := Time.get_ticks_usec() - edit_started
	var edit_result := {
		"status": "PASS" if edit_accepted and committed and str(edit_settlement.get("status", "")) == "PASS"
			and _all_required_generations_match()
			and int(edit_after.get("application_applied_collision", 0)) > int(edit_before.get("application_applied_collision", 0))
			and int(edit_after.get("collision_required_not_ready_chunk_records", -1)) == 0 else "FAIL",
		"coherence_usec": edit_latency,
		"collision_application_delta": int(edit_after.get("application_applied_collision", 0)) - int(edit_before.get("application_applied_collision", 0)),
		"replacement_delta": int(edit_after.get("edit_replacements", 0)) - int(edit_before.get("edit_replacements", 0)),
		"world_revision": int(_terrain.call("get_world_revision")),
	}
	_expect(str(edit_result.get("status", "")) == "PASS", "edited collision did not replace coherently", failures)

	var physics_samples: Array[float] = []
	for _frame in range(180):
		await get_tree().physics_frame
		physics_samples.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000000.0)
	var physics := Statistics.distribution(physics_samples)
	var retirement_before := int((_terrain.call("get_runtime_metrics") as Dictionary).get("collision_viewer_removals", 0))
	var retirement_accepted := true
	for value in standard.get("invokers", []):
		var id := int((value as Dictionary).get("id", 0))
		revisions[id] = int(revisions[id]) + 1
		var removal_accepted := bool(_terrain.call("remove_collision_viewer", id, int(revisions[id])))
		retirement_accepted = removal_accepted and retirement_accepted
	for _frame in range(Harness.MAX_WAIT_FRAMES):
		var removal_metrics: Dictionary = _terrain.call("get_runtime_metrics")
		if int(removal_metrics.get("collision_viewer_removals", 0)) >= retirement_before + (standard.get("invokers", []) as Array).size():
			break
		await get_tree().process_frame
	var replan_before := int((_terrain.call("get_runtime_metrics") as Dictionary).get("viewer_updates", 0))
	var replan_accepted := bool(_terrain.call(
		"update_viewer", int(profile.get("viewer_id", 460)), 2,
		_vector3(profile.get("viewer_position", [])), int(profile.get("viewer_radius_chunks", 3)),
		int(profile.get("maximum_lod", 1))
	))
	var replan_observed := replan_accepted and await _wait_for_metric("viewer_updates", replan_before + 1)
	var retirement_settlement: Dictionary = await _harness.wait_for_settled(1)
	var retirement_metrics: Dictionary = _terrain.call("get_runtime_metrics")
	var outlying_residue := _outlying_overlay_residue_count(
		standard.get("invokers", []), _vector3(profile.get("viewer_position", []))
	)
	var retirement := {
		"status": "PASS" if retirement_accepted and replan_observed and str(retirement_settlement.get("status", "")) == "PASS"
			and _all_required_generations_match()
			and outlying_residue == 0
			and int(retirement_metrics.get("collision_required_chunk_records", 0))
				< int(retirement_metrics.get("visual_required_chunk_records", 0))
			and int(retirement_metrics.get("visual_required_chunk_records", 0)) > 0 else "FAIL",
		"explicit_collision_only_count": _collision_only_count(),
		"outlying_invoker_residue_count": outlying_residue,
		"canonical_visual_replan_observed": replan_observed,
		"note": "collision-only edit-retention records may remain around the committed edit; removed outlying invoker envelopes may not",
		"metrics": _selected_metrics(retirement_metrics),
	}
	_expect(str(retirement.get("status", "")) == "PASS", "collision retirement did not drain independently", failures)
	var latency_distribution := Statistics.distribution(collision_latencies)
	_evaluate(standard, latency_distribution, edit_result, physics, collision_metrics, failures)
	return await _finish(standard, {
		"render_only": render_only,
		"authoritative_query_independence": query_independence,
		"invokers": invokers,
		"collision_arrival_distribution": latency_distribution,
		"targeted_subset": targeted_subset,
		"swept_motion": sweep,
		"ray_safety": ray_safety,
		"navigation_consumer": navigation,
		"edit_replacement": edit_result,
		"physics_frame_distribution": physics,
		"collision_metrics": _selected_metrics(collision_metrics),
		"applied_generation_agreement": _generation_agreement(),
		"retirement": retirement,
	}, failures)


func _finish(standard: Dictionary, payload: Dictionary, failures: Array[String]) -> Dictionary:
	var final_metrics := _terrain.call("get_runtime_metrics") as Dictionary if is_instance_valid(_terrain) else {}
	var stopped := true
	if is_instance_valid(_harness) and is_instance_valid(_terrain):
		stopped = await _harness.stop_world()
		_harness.dispose()
		_harness.queue_free()
		await get_tree().process_frame
	Harness.remove_tree(RUNTIME_ROOT)
	_expect(stopped, "native runtime did not stop cleanly", failures)
	var report := {
		"schema": "world_transvoxel.terrain_lab.targeted_collision_residency_qualification.v1",
		"milestone": "TQP-46",
		"standard_id": standard.get("standard_id", ""),
		"authority": standard.get("authority", ""),
		"status": "PASS" if failures.is_empty() else "FAIL",
		"retained_complete": failures.is_empty(),
		"provenance": Statistics.provenance("tqp46_targeted_collision_windows_v1"),
		"memory": Statistics.memory_metrics(),
		"final_metrics": _selected_metrics(final_metrics),
		"shutdown": "PASS" if stopped else "FAIL",
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}
	for key in payload:
		report[key] = payload[key]
	return report


func _derive_navigation_snapshot() -> Dictionary:
	var navigation := NavigationMesh.new()
	var vertices := PackedVector3Array()
	var polygon_count := 0
	for child in _terrain.get_children():
		if not child is StaticBody3D or not str(child.name).begins_with("WT_Collision_"):
			continue
		var shape_node := child.get_node_or_null("Shape") as CollisionShape3D
		if shape_node == null or not shape_node.shape is ConcavePolygonShape3D:
			continue
		var faces: PackedVector3Array = (shape_node.shape as ConcavePolygonShape3D).get_faces()
		var limit := mini(faces.size(), 3072)
		for index in range(0, limit - 2, 3):
			var base := vertices.size()
			vertices.append(child.position + faces[index])
			vertices.append(child.position + faces[index + 1])
			vertices.append(child.position + faces[index + 2])
			navigation.add_polygon(PackedInt32Array([base, base + 1, base + 2]))
			polygon_count += 1
		break
	navigation.set_vertices(vertices)
	return {"vertex_count": vertices.size(), "polygon_count": polygon_count, "lifecycle": "derived_then_released"}


func _ray_safety(invokers: Array, sweep_value: Variant) -> Dictionary:
	var points: Array[Vector3] = []
	for value in invokers:
		points.append(_vector3((value as Dictionary).get("position", [])))
	points.append(_vector3(sweep_value))
	var hits := 0
	var world: World3D = _terrain.get_world_3d()
	if world != null:
		for point in points:
			var query := PhysicsRayQueryParameters3D.create(
				Vector3(point.x, 128.0, point.z), Vector3(point.x, -64.0, point.z)
			)
			if not world.direct_space_state.intersect_ray(query).is_empty():
				hits += 1
	return {"status": "PASS" if hits == points.size() else "FAIL", "sample_count": points.size(), "hit_count": hits}


func _covering_collision_ready(position: Vector3) -> bool:
	for state_value in _terrain.call("query_active_chunk_states"):
		var state: RefCounted = state_value
		if not bool(state.call("is_present")) or not bool(state.call("is_collision_required")):
			continue
		var lod := int(state.call("get_lod"))
		var size := 16.0 * pow(2.0, lod)
		var minimum := Vector3(state.call("get_chunk_coordinate")) * size
		if position.x >= minimum.x and position.z >= minimum.z \
				and position.x < minimum.x + size and position.z < minimum.z + size:
			return _has_current_collision(state)
	return false


func _all_required_generations_match() -> bool:
	return bool(_generation_agreement().get("status", "") == "PASS")


func _generation_agreement() -> Dictionary:
	var visual_mismatches: Array[String] = []
	var collision_mismatches: Array[String] = []
	for state_value in _terrain.call("query_active_chunk_states"):
		var state: RefCounted = state_value
		if not bool(state.call("is_present")):
			continue
		var key := "%s@%d" % [str(state.call("get_chunk_coordinate")), int(state.call("get_lod"))]
		if bool(state.call("is_visual_required")) and not _has_current_visual(state):
			visual_mismatches.append(key)
		if bool(state.call("is_collision_required")) and not _has_current_collision(state):
			collision_mismatches.append(key)
	return {
		"status": "PASS" if visual_mismatches.is_empty() and collision_mismatches.is_empty() else "FAIL",
		"visual_mismatches": visual_mismatches,
		"collision_mismatches": collision_mismatches,
	}


static func _has_current_visual(state: RefCounted) -> bool:
	var applied := int(state.call("get_render_generation"))
	var current := int(state.call("get_generation"))
	return bool(state.call("is_visual_ready")) \
		and applied in [0, current] \
		and int(state.call("get_staged_render_generation")) == 0


static func _has_current_collision(state: RefCounted) -> bool:
	var applied := int(state.call("get_collision_generation"))
	var current := int(state.call("get_generation"))
	return bool(state.call("is_collision_ready")) \
		and applied in [0, current] \
		and int(state.call("get_staged_collision_generation")) == 0


func _demand_signature() -> Dictionary:
	return {"visual": _keys_for_requirement(false), "collision": _keys_for_requirement(true)}


func _collision_required_keys() -> Array[String]:
	return _keys_for_requirement(true)


func _collision_only_count() -> int:
	var count := 0
	for state_value in _terrain.call("query_active_chunk_states"):
		var state: RefCounted = state_value
		if bool(state.call("is_present")) and bool(state.call("is_collision_required")) \
				and not bool(state.call("is_visual_required")):
			count += 1
	return count


func _outlying_overlay_residue_count(invokers: Array, visual_center: Vector3) -> int:
	var count := 0
	for value in invokers:
		var position := _vector3((value as Dictionary).get("position", []))
		if Vector2(position.x, position.z).distance_to(Vector2(visual_center.x, visual_center.z)) <= 64.0:
			continue
		for state_value in _terrain.call("query_active_chunk_states"):
			var state: RefCounted = state_value
			if not bool(state.call("is_present")) or not bool(state.call("is_collision_required")) \
					or bool(state.call("is_visual_required")):
				continue
			var size := 16.0 * pow(2.0, int(state.call("get_lod")))
			var minimum := Vector3(state.call("get_chunk_coordinate")) * size
			if position.x >= minimum.x and position.z >= minimum.z \
					and position.x < minimum.x + size and position.z < minimum.z + size:
				count += 1
				break
	return count


func _wait_for_metric(key: String, target: int) -> bool:
	for _frame in range(Harness.MAX_WAIT_FRAMES):
		if int((_terrain.call("get_runtime_metrics") as Dictionary).get(key, 0)) >= target:
			return true
		await get_tree().process_frame
	return false


func _keys_for_requirement(collision: bool) -> Array[String]:
	var keys: Array[String] = []
	for state_value in _terrain.call("query_active_chunk_states"):
		var state: RefCounted = state_value
		var required := bool(state.call("is_collision_required")) if collision else bool(state.call("is_visual_required"))
		if bool(state.call("is_present")) and required:
			keys.append("%s@%d" % [str(state.call("get_chunk_coordinate")), int(state.call("get_lod"))])
	keys.sort()
	return keys


static func _intersection_count(left: Array[String], right: Array[String]) -> int:
	var right_set := {}
	for key in right:
		right_set[key] = true
	var count := 0
	for key in left:
		count += 1 if right_set.has(key) else 0
	return count


static func _selected_metrics(metrics: Dictionary) -> Dictionary:
	var output := {}
	for key in [
		"visual_required_chunk_records", "collision_required_chunk_records",
		"collision_required_not_ready_chunk_records", "render_resources", "collision_resources",
		"application_submitted_collision", "application_applied_collision", "application_stale_collision",
		"application_unrequired_collision", "collision_apply_time_ns_maximum",
		"collision_apply_frame_time_ns_maximum", "collision_apply_frame_deadline_overruns",
		"collision_latency_frames_maximum", "edit_replacements", "pending_chunk_replacements",
		"pending_chunk_retirements", "queued_collision", "total_collision_backlog",
	]:
		output[key] = metrics.get(key, -1)
	return output


static func _evaluate(standard: Dictionary, latency: Dictionary, edit: Dictionary, physics: Dictionary, metrics: Dictionary, failures: Array[String]) -> void:
	var budgets: Dictionary = standard.get("budgets", {})
	_expect(float(latency.get("p99_usec", INF)) <= float(budgets.get("maximum_collision_arrival_p99_usec", 0.0)), "collision arrival p99 exceeded", failures)
	_expect(float(edit.get("coherence_usec", INF)) <= float(budgets.get("maximum_edit_collision_coherence_usec", 0.0)), "edit collision coherence exceeded", failures)
	_expect(int(metrics.get("collision_apply_time_ns_maximum", 0)) <= int(budgets.get("maximum_collision_apply_time_ns", 0)), "collision application time exceeded", failures)
	_expect(float(physics.get("p99_usec", INF)) <= float(budgets.get("maximum_physics_frame_p99_usec", 0.0)), "physics frame p99 exceeded", failures)
	_expect(int(metrics.get("collision_resources", 0)) <= int(budgets.get("maximum_collision_resources", 0)), "collision resource budget exceeded", failures)


func _validate_native_authority(standard: Dictionary, failures: Array[String]) -> void:
	var native := JsonLoader.load_dictionary(str(standard.get("native_authority_evidence", "")))
	var proof: Dictionary = native.get("proof_map", {})
	_expect(str(native.get("status", "")) == "PASS", "native closure authority failed", failures)
	_expect((proof.get("TQP-46", []) as Array).size() >= 5, "native TQP-46 proof map is incomplete", failures)


static func _overrides(profile: Dictionary) -> Dictionary:
	var pipeline := int(profile.get("pipeline_capacity", 4096))
	var cache := int(profile.get("cache_capacity", 1536))
	return {
		"active_chunk_capacity": int(profile.get("active_chunk_capacity", 1536)),
		"viewer_capacity": 16,
		"demand_capacity_per_viewer": pipeline,
		"lod_refinement_radius_chunks": 1,
		"storage_request_capacity": pipeline,
		"storage_completion_capacity": pipeline,
		"encoded_page_entry_capacity": cache,
		"decoded_page_entry_capacity": cache,
		"mesh_entry_capacity": cache,
		"render_entry_capacity": cache,
		"collision_entry_capacity": int(profile.get("collision_capacity", 256)),
		"trace_event_capacity": 65536,
		"render_apply_budget": 6,
		"collision_apply_budget": 3,
		"collision_apply_deadline_us": 12000,
		"collision_activation_distance": 64.0,
		"collision_deactivation_distance": 96.0,
		"render_transition_frames": 0,
	}


static func _vector3(value: Variant) -> Vector3:
	var array: Array = value
	return Vector3(float(array[0]), float(array[1]), float(array[2])) if array.size() == 3 else Vector3.ZERO


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
