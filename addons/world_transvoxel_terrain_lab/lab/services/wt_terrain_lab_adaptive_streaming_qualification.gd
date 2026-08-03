@tool
extends Node
class_name WtTerrainLabAdaptiveStreamingQualification

const Harness := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_runtime_harness.gd"
)
const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/adaptive_streaming_residency_standard.json"
)
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/tqp40_adaptive_streaming"


func run() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var profile: Dictionary = standard.get("runtime_profile", {})
	var workload: Dictionary = standard.get("workload", {})
	var failures: Array[String] = []
	var actions := {}
	var settlements: Array[Dictionary] = []
	var settlement_times: Array[float] = []
	Harness.remove_tree(RUNTIME_ROOT)
	var harness := Harness.new()
	add_child(harness)
	if not harness.create_runtime(
		int(profile.get("worker_count", 2)), _runtime_overrides(profile)
	):
		failures.append("native runtime harness could not be created")
		return await _finish(harness, standard, {}, actions, settlements, settlement_times, failures)
	var volume: Array = profile.get("volume_chunks", [])
	var started := volume.size() == 3 and await harness.start_procedural_world_preset(
		RUNTIME_ROOT.path_join("source"), int(profile.get("source_revision", 940001)),
		int(profile.get("seed", 400040)), str(profile.get("procedural_preset", "rolling_hills_cave")),
		int(volume[0]), int(volume[1]), int(profile.get("vertical_chunk_origin", -16)), int(volume[2])
	)
	if not started:
		failures.append("native multi-layer procedural world did not reach running")
		return await _finish(harness, standard, {}, actions, settlements, settlement_times, failures)
	var terrain := harness.terrain
	var cave: Dictionary = workload.get("cave_viewer", {})
	var surface: Dictionary = workload.get("surface_viewer", {})
	var prefetch: Dictionary = workload.get("prefetch_viewer", {})

	var cave_settlement := await _update_and_settle(harness, terrain, [cave], 1)
	_record_settlement("cave", cave_settlement, settlements, settlement_times)
	_expect(str(cave_settlement.get("status", "")) == "PASS", "cave viewer did not settle", failures)
	var cave_snapshot := _state_snapshot(terrain)
	var vertical := await _vertical_audit(harness, workload.get("vertical_probe", {}))
	var cave_valid := str(vertical.get("status", "")) == "PASS" \
		and _snapshot_matches_expected(cave_snapshot, (standard.get("stable_expected", {}) as Dictionary), "cave")
	_expect(cave_valid, "multi-layer cave residency or vertical crossings changed", failures)
	actions["multi_layer_cave_residency"] = _status(cave_valid)
	var parent_child := _all_lods_present(cave_snapshot, 2) \
		and int((cave_snapshot.get("metrics", {}) as Dictionary).get("transition_mesh_completions", 0)) > 0
	_expect(parent_child, "adaptive parent/child hierarchy is incomplete", failures)
	actions["adaptive_parent_child_coverage"] = _status(parent_child)

	var cave_refresh := cave.duplicate(true)
	cave_refresh["_revision"] = 2
	var surface_add := surface.duplicate(true)
	surface_add["_revision"] = 1
	var prefetch_add := prefetch.duplicate(true)
	prefetch_add["_revision"] = 1
	var prefetch_settlement := await _update_and_settle(
		harness, terrain, [cave_refresh, surface_add, prefetch_add], 1
	)
	_record_settlement("multi_viewer_union", prefetch_settlement, settlements, settlement_times)
	var multi_snapshot := _state_snapshot(terrain)
	var union_valid := str(prefetch_settlement.get("status", "")) == "PASS" \
		and _snapshot_matches_expected(multi_snapshot, (standard.get("stable_expected", {}) as Dictionary), "multi_viewer")
	_expect(union_valid, "multi-viewer union changed", failures)
	actions["multi_viewer_union"] = _status(union_valid)

	var origin_rebase := await _presentation_origin_rebase(terrain, workload)
	var origin_valid := str(origin_rebase.get("status", "")) == "PASS"
	_expect(origin_valid, "presentation origin rebase changed native state or local resources", failures)
	actions["presentation_origin_rebase"] = _status(origin_valid)
	var all_viewer_keys := _key_set(terrain)
	var remove_prefetch_probe := await _remove_and_settle(
		harness, terrain, int(prefetch.get("id", 403)), 2
	)
	_record_settlement("prefetch_removal_probe", remove_prefetch_probe, settlements, settlement_times)
	var without_prefetch_keys := _key_set(terrain)
	var prefetch_additions := _set_difference(all_viewer_keys, without_prefetch_keys)
	var prefetch_valid := str(remove_prefetch_probe.get("status", "")) == "PASS" \
		and not prefetch_additions.is_empty()
	_expect(prefetch_valid, "prefetch viewer contributed no unique resident chunk", failures)
	actions["prefetch_unique_coverage"] = _status(prefetch_valid)
	var prefetch_restore := prefetch.duplicate(true)
	prefetch_restore["_revision"] = 3
	var restored := await _update_and_settle(harness, terrain, [prefetch_restore], 3)
	_record_settlement("prefetch_restore", restored, settlements, settlement_times)
	_expect(str(restored.get("status", "")) == "PASS", "prefetch viewer did not restore", failures)

	var old_keys := _key_set(terrain)
	var old_resources := _resource_names(terrain)
	var teleport_viewers: Array = workload.get("teleport_viewers", []).duplicate(true)
	var teleport_revisions := [3, 2, 4]
	for index in range(teleport_viewers.size()):
		(teleport_viewers[index] as Dictionary)["_revision"] = teleport_revisions[index]
	var teleport_settlement := await _update_and_settle(
		harness, terrain, teleport_viewers, 2
	)
	_record_settlement("teleport", teleport_settlement, settlements, settlement_times)
	var teleport_snapshot := _state_snapshot(terrain)
	var retained_old_keys := _set_intersection(old_keys, _key_set(terrain))
	var retained_old_resources := _array_intersection(old_resources, _resource_names(terrain))
	var teleport_valid := str(teleport_settlement.get("status", "")) == "PASS" \
		and _snapshot_matches_expected(teleport_snapshot, (standard.get("stable_expected", {}) as Dictionary), "teleport") \
		and retained_old_keys.is_empty() and retained_old_resources.is_empty()
	_expect(teleport_valid, "teleport retained old keys/resources or changed the resident signature", failures)
	actions["teleport_eviction"] = _status(teleport_valid)

	var bounded := _bounded_snapshot(teleport_snapshot, standard)
	var bounded_valid := str(bounded.get("status", "")) == "PASS"
	_expect(bounded_valid, "resident resources or queues exceeded the declared envelope", failures)
	actions["bounded_residency_and_resources"] = _status(bounded_valid)

	var remove_prefetch := await _remove_and_settle(harness, terrain, int(prefetch.get("id", 403)), 5)
	_record_settlement("remove_prefetch", remove_prefetch, settlements, settlement_times)
	var drain_valid := str(remove_prefetch.get("status", "")) == "PASS"
	drain_valid = drain_valid and bool(terrain.call("remove_viewer", int(cave.get("id", 0)), 4))
	drain_valid = drain_valid and bool(terrain.call("remove_viewer", int(surface.get("id", 0)), 3))
	drain_valid = drain_valid and await _wait_for_drain(terrain)
	var drain_metrics: Dictionary = terrain.call("get_runtime_metrics")
	drain_valid = drain_valid and int(drain_metrics.get("active_chunk_records", -1)) == 0 \
		and int(drain_metrics.get("render_resources", -1)) == 0 \
		and int(drain_metrics.get("collision_resources", -1)) == 0
	_expect(drain_valid, "viewer retirement did not drain all native resources", failures)
	actions["viewer_retirement_and_drain"] = _status(drain_valid)

	var data := {
		"cave": cave_snapshot,
		"vertical": vertical,
		"multi_viewer": multi_snapshot,
		"prefetch_unique_keys": prefetch_additions,
		"prefetch_probe": {
			"with_count": all_viewer_keys.size(),
			"without_count": without_prefetch_keys.size(),
			"expected_root_with": all_viewer_keys.has("21:-1:21:2"),
			"expected_root_without": without_prefetch_keys.has("21:-1:21:2"),
		},
		"origin_rebase": origin_rebase,
		"teleport": teleport_snapshot,
		"teleport_retained_old_keys": retained_old_keys,
		"teleport_retained_old_resources": retained_old_resources,
		"bounded": bounded,
		"drain_metrics": _selected_metrics(drain_metrics),
	}
	return await _finish(harness, standard, data, actions, settlements, settlement_times, failures)


func _finish(
	harness: Node,
	standard: Dictionary,
	data: Dictionary,
	actions: Dictionary,
	settlements: Array[Dictionary],
	settlement_times: Array[float],
	failures: Array[String]
) -> Dictionary:
	if harness != null and harness.terrain != null:
		if not await harness.stop_world():
			failures.append("native adaptive streaming world did not stop cleanly")
		harness.dispose()
		harness.queue_free()
		await get_tree().process_frame
	Harness.remove_tree(RUNTIME_ROOT)
	var semantic_source := {
		"actions": actions,
		"cave": (data.get("cave", {}) as Dictionary).get("state_signature", ""),
		"vertical": (data.get("vertical", {}) as Dictionary).get("signature", ""),
		"multi": (data.get("multi_viewer", {}) as Dictionary).get("state_signature", ""),
		"prefetch": data.get("prefetch_unique_keys", []),
		"origin": (data.get("origin_rebase", {}) as Dictionary).get("state_signature", ""),
		"teleport": (data.get("teleport", {}) as Dictionary).get("state_signature", ""),
	}
	return {
		"schema": "world_transvoxel.terrain_lab.adaptive_streaming_residency_qualification.v1",
		"milestone": "TQP-40",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"retained_complete": true,
		"standard_id": standard.get("standard_id", ""),
		"authority": standard.get("authority", ""),
		"actions": actions,
		"cave_residency": data.get("cave", {}),
		"vertical_cave_audit": data.get("vertical", {}),
		"multi_viewer_residency": data.get("multi_viewer", {}),
		"prefetch_unique_keys": data.get("prefetch_unique_keys", []),
		"prefetch_probe": data.get("prefetch_probe", {}),
		"presentation_origin_rebase": data.get("origin_rebase", {}),
		"teleport_residency": data.get("teleport", {}),
		"teleport_retained_old_keys": data.get("teleport_retained_old_keys", []),
		"teleport_retained_old_resources": data.get("teleport_retained_old_resources", []),
		"bounded_residency": data.get("bounded", {}),
		"drain_metrics": data.get("drain_metrics", {}),
		"settlements": settlements,
		"performance": {
			"scope": "WINDOWS_DEBUG_DIAGNOSTIC_NOT_PRODUCTION_FRAME_OR_POWER_BUDGET",
			"settlement_usec": Statistics.distribution(settlement_times),
			"memory": Statistics.memory_metrics(),
		},
		"semantic_signature": JSON.stringify(semantic_source, "", true).sha256_text(),
		"provenance": Statistics.provenance("tqp40_native_multi_layer_streaming_windows_v1"),
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


func _update_and_settle(harness: Node, terrain: Node, viewers_value: Variant, revision: int) -> Dictionary:
	var viewers: Array = viewers_value
	var before := int((terrain.call("get_runtime_metrics") as Dictionary).get("viewer_updates", 0))
	for viewer_value in viewers:
		var viewer: Dictionary = viewer_value
		if not bool(terrain.call(
			"update_viewer", int(viewer.get("id", 0)), int(viewer.get("_revision", revision)),
			_vector3(viewer.get("position", [])), int(viewer.get("radius_chunks", 0)), 2
		)):
			return {"status": "FAIL", "error": "viewer update was rejected"}
	if not await _wait_for_metric(terrain, "viewer_updates", before + viewers.size()):
		return {"status": "FAIL", "error": "viewer update was not consumed"}
	await get_tree().process_frame
	return await harness.wait_for_settled()


func _remove_and_settle(harness: Node, terrain: Node, viewer_id: int, revision: int) -> Dictionary:
	var before := int((terrain.call("get_runtime_metrics") as Dictionary).get("viewer_removals", 0))
	if not bool(terrain.call("remove_viewer", viewer_id, revision)):
		return {"status": "FAIL", "error": "viewer removal was rejected"}
	if not await _wait_for_metric(terrain, "viewer_removals", before + 1):
		return {"status": "FAIL", "error": "viewer removal was not consumed"}
	await get_tree().process_frame
	return await harness.wait_for_settled()


func _vertical_audit(harness: Node, probe: Dictionary) -> Dictionary:
	var points: Array[Vector3i] = []
	for y in range(
		int(probe.get("minimum_y", -72)), int(probe.get("maximum_y", 36)) + 1,
		int(probe.get("step", 4))
	):
		points.append(Vector3i(int(probe.get("x", 1024)), y, int(probe.get("z", 1024))))
	var samples: Array[Dictionary] = await harness.request_samples(points)
	var failures: Array[String] = []
	var crossings: Array[Dictionary] = []
	for index in range(1, samples.size()):
		var a: Dictionary = samples[index - 1]
		var b: Dictionary = samples[index]
		if str(a.get("status", "")) != "PASS" or str(b.get("status", "")) != "PASS":
			continue
		if (float(a.get("density", 0.0)) < 0.0) != (float(b.get("density", 0.0)) < 0.0):
			crossings.append({"from": points[index - 1], "to": points[index]})
	var viewer_y := int(probe.get("viewer_y", -20))
	var below := false
	var above := false
	for crossing in crossings:
		var from: Vector3i = crossing.get("from", Vector3i.ZERO)
		var to: Vector3i = crossing.get("to", Vector3i.ZERO)
		below = below or to.y < viewer_y
		above = above or from.y > viewer_y
	if not below:
		failures.append("no cave sign crossing exists below the viewer")
	if not above:
		failures.append("no cave sign crossing exists above the viewer")
	var lines: Array[String] = []
	for sample in samples:
		lines.append("%s:%d" % [sample.get("point", ""), roundi(float(sample.get("density", 0.0)) * 1000000.0)])
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"sample_count": samples.size(),
		"crossings": crossings,
		"below_viewer": below,
		"above_viewer": above,
		"signature": "\n".join(lines).sha256_text(),
		"failures": failures,
	}


func _presentation_origin_rebase(terrain: Node, workload: Dictionary) -> Dictionary:
	var root := terrain as Node3D
	if root == null:
		return {"status": "FAIL", "error": "native terrain is not Node3D"}
	var render := _first_render(terrain)
	if render == null:
		return {"status": "FAIL", "error": "no native render resource exists"}
	var state_before := _state_snapshot(terrain)
	var local_before := render.position
	var global_before := render.global_position
	var offset := _vector3(workload.get("presentation_origin_offset", []))
	root.position = offset
	var state_after := _state_snapshot(terrain)
	var local_after := render.position
	var global_delta := render.global_position - global_before
	root.position = Vector3.ZERO
	var valid := str(state_before.get("state_signature", "")) == str(state_after.get("state_signature", "")) \
		and local_before.is_equal_approx(local_after) and global_delta.is_equal_approx(offset)
	return {
		"status": _status(valid),
		"scope": "consumer_presentation_root_transform",
		"offset": offset,
		"local_resource_unchanged": local_before.is_equal_approx(local_after),
		"global_delta_matches": global_delta.is_equal_approx(offset),
		"state_signature": state_after.get("state_signature", ""),
	}


static func _state_snapshot(terrain: Node) -> Dictionary:
	var lines: Array[String] = []
	var lod_counts := {}
	var minimum := Vector3i(2147483647, 2147483647, 2147483647)
	var maximum := Vector3i(-2147483648, -2147483648, -2147483648)
	var generation_mismatches := 0
	for value in terrain.call("query_active_chunk_states"):
		var state: RefCounted = value
		var coordinate: Vector3i = state.call("get_chunk_coordinate")
		var lod := int(state.call("get_lod"))
		lines.append("%d:%d:%d:%d" % [coordinate.x, coordinate.y, coordinate.z, lod])
		lod_counts[str(lod)] = int(lod_counts.get(str(lod), 0)) + 1
		minimum = Vector3i(mini(minimum.x, coordinate.x), mini(minimum.y, coordinate.y), mini(minimum.z, coordinate.z))
		maximum = Vector3i(maxi(maximum.x, coordinate.x), maxi(maximum.y, coordinate.y), maxi(maximum.z, coordinate.z))
		if not bool(state.call("is_fully_ready")):
			generation_mismatches += 1
	lines.sort()
	return {
		"active_count": lines.size(),
		"lod_counts": lod_counts,
		"minimum_coordinate": minimum,
		"maximum_coordinate": maximum,
		"generation_mismatch_count": generation_mismatches,
		"state_signature": "\n".join(lines).sha256_text(),
		"metrics": _selected_metrics(terrain.call("get_runtime_metrics")),
	}


static func _bounded_snapshot(snapshot: Dictionary, standard: Dictionary) -> Dictionary:
	var budgets: Dictionary = standard.get("budgets", {})
	var metrics: Dictionary = snapshot.get("metrics", {})
	var memory := Statistics.memory_metrics()
	var checks := {
		"active": int(metrics.get("active_chunk_records", -1)) <= int(budgets.get("maximum_active_chunk_records", 0)),
		"render": int(metrics.get("render_resources", -1)) <= int(budgets.get("maximum_render_resources", 0)),
		"collision": int(metrics.get("collision_resources", -1)) <= int(budgets.get("maximum_collision_resources", 0)),
		"retirements": int(metrics.get("pending_chunk_retirements", -1)) == 0,
		"replacements": int(metrics.get("pending_chunk_replacements", -1)) == 0,
		"jobs": int(metrics.get("scheduler_queued_jobs", -1)) == 0 and int(metrics.get("scheduler_queued_completions", -1)) == 0,
		"visibility": int(metrics.get("visual_required_chunk_records", -1)) == int(metrics.get("active_chunk_records", -2)) and int(metrics.get("visual_ready_chunk_records", -1)) == int(metrics.get("active_chunk_records", -2)),
		"generations": int(snapshot.get("generation_mismatch_count", -1)) == 0,
		"memory": int(memory.get("peak_bytes", -1)) <= int(budgets.get("maximum_peak_process_memory_bytes", 0)),
	}
	var passed := checks.values().all(func(value: Variant) -> bool: return bool(value))
	return {"status": _status(passed), "checks": checks, "metrics": metrics, "memory": memory}


static func _snapshot_matches_expected(snapshot: Dictionary, expected: Dictionary, prefix: String) -> bool:
	if str(snapshot.get("state_signature", "")) != str(expected.get(prefix + "_state_signature", "")):
		return false
	var observed_counts: Dictionary = snapshot.get("lod_counts", {})
	var expected_counts: Dictionary = expected.get(prefix + "_lod_counts", {})
	for lod in expected_counts:
		if int(observed_counts.get(lod, -1)) != int(expected_counts.get(lod, -2)):
			return false
	return observed_counts.size() == expected_counts.size()


static func _all_lods_present(snapshot: Dictionary, maximum_lod: int) -> bool:
	var counts: Dictionary = snapshot.get("lod_counts", {})
	for lod in range(maximum_lod + 1):
		if int(counts.get(str(lod), 0)) <= 0:
			return false
	return true


static func _key_set(terrain: Node) -> Dictionary:
	var result := {}
	for value in terrain.call("query_active_chunk_states"):
		var state: RefCounted = value
		var c: Vector3i = state.call("get_chunk_coordinate")
		result["%d:%d:%d:%d" % [c.x, c.y, c.z, int(state.call("get_lod"))]] = true
	return result


static func _set_difference(left: Dictionary, right: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in left:
		if not right.has(key):
			result.append(str(key))
	result.sort()
	return result


static func _set_intersection(left: Dictionary, right: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in left:
		if right.has(key):
			result.append(str(key))
	result.sort()
	return result


static func _resource_names(terrain: Node) -> Array[String]:
	var result: Array[String] = []
	for child in terrain.get_children():
		if str(child.name).begins_with("WT_Render_") or str(child.name).begins_with("WT_Collision_"):
			result.append(str(child.name))
	result.sort()
	return result


static func _array_intersection(left: Array[String], right: Array[String]) -> Array[String]:
	var right_set := {}
	for value in right:
		right_set[value] = true
	var result: Array[String] = []
	for value in left:
		if right_set.has(value):
			result.append(value)
	return result


static func _first_render(terrain: Node) -> MeshInstance3D:
	for child in terrain.get_children():
		if child is MeshInstance3D and str(child.name).begins_with("WT_Render_"):
			return child
	return null


static func _selected_metrics(metrics: Dictionary) -> Dictionary:
	var selected := {}
	for key in [
		"viewer_updates", "viewer_removals", "planned_demands", "sample_jobs", "mesh_jobs",
		"transition_mesh_completions", "storage_duplicate_requests", "page_cache_encoded_entries",
		"page_cache_decoded_entries", "page_cache_encoded_evictions", "page_cache_decoded_evictions",
		"page_stale_storage_completions", "application_stale_render", "application_stale_collision",
		"active_chunk_records", "visual_ready_chunk_records", "visual_required_chunk_records",
		"render_resources", "collision_resources", "pending_chunk_retirements",
		"pending_chunk_replacements", "scheduler_queued_jobs", "scheduler_queued_completions",
	]:
		selected[key] = metrics.get(key, -1)
	return selected


static func _runtime_overrides(profile: Dictionary) -> Dictionary:
	var pipeline := int(profile.get("pipeline_capacity", 4096))
	var pages := int(profile.get("page_cache_capacity", 1024))
	return {
		"active_chunk_capacity": int(profile.get("active_chunk_capacity", 1024)),
		"viewer_capacity": 8,
		"demand_capacity_per_viewer": pipeline,
		"lod_refinement_radius_chunks": int(profile.get("lod_refinement_radius_chunks", 1)),
		"storage_request_capacity": pages,
		"storage_completion_capacity": pages,
		"encoded_page_entry_capacity": pages,
		"decoded_page_entry_capacity": pages,
		"mesh_entry_capacity": pages,
		"render_entry_capacity": pages,
		"collision_entry_capacity": int(profile.get("collision_capacity", 256)),
		"render_apply_budget": 16,
		"collision_apply_budget": 4,
		"collision_activation_distance": 0.0,
		"collision_deactivation_distance": 0.0,
		"global_coarse_lod_coverage": bool(profile.get("global_coarse_lod_coverage", false)),
	}


func _wait_for_metric(terrain: Node, key: String, target: int) -> bool:
	for _frame in range(Harness.MAX_WAIT_FRAMES):
		if int((terrain.call("get_runtime_metrics") as Dictionary).get(key, 0)) >= target:
			return true
		await get_tree().process_frame
	return false


func _wait_for_drain(terrain: Node) -> bool:
	for _frame in range(Harness.MAX_WAIT_FRAMES):
		var metrics: Dictionary = terrain.call("get_runtime_metrics")
		if int(metrics.get("active_chunk_records", -1)) == 0 \
				and int(metrics.get("render_resources", -1)) == 0 \
				and int(metrics.get("collision_resources", -1)) == 0:
			return true
		await get_tree().process_frame
	return false


static func _record_settlement(id: String, settlement: Dictionary, records: Array[Dictionary], times: Array[float]) -> void:
	records.append({"id": id, "status": settlement.get("status", ""), "frames": settlement.get("frames", -1), "elapsed_usec": settlement.get("elapsed_usec", -1)})
	times.append(float(settlement.get("elapsed_usec", 0.0)))


static func _vector3(value: Variant) -> Vector3:
	var values: Array = value
	return Vector3(float(values[0]), float(values[1]), float(values[2])) if values.size() == 3 else Vector3.ZERO


static func _status(value: bool) -> String:
	return "PASS" if value else "FAIL"


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
