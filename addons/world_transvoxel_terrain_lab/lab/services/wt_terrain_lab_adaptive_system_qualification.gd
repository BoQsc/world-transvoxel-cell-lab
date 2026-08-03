@tool
extends Node
class_name WtTerrainLabAdaptiveSystemQualification

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
	"res://addons/world_transvoxel_terrain_lab/standards/adaptive_system_agreement_standard.json"
)
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/tqp39_adaptive_system"
const POSITION_SCALE := 100000.0


func run() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var profile: Dictionary = standard.get("runtime_profile", {})
	var workload: Dictionary = standard.get("workload", {})
	var failures: Array[String] = []
	var actions := {}
	var settlements: Array[Dictionary] = []
	var audit_times: Array[float] = []
	Harness.remove_tree(RUNTIME_ROOT)
	var harness := Harness.new()
	add_child(harness)
	if not harness.create_runtime(
		int(profile.get("worker_count", 2)), _runtime_overrides(profile)
	):
		failures.append("native runtime harness could not be created")
		return await _finish(harness, standard, {}, actions, settlements, audit_times, failures)
	var volume: Array = profile.get("volume_chunks", [])
	if volume.size() != 3 or not await harness.start_flat_world(
		RUNTIME_ROOT.path_join("source"), int(profile.get("source_revision", 939001)),
		int(volume[0]), int(volume[1]), int(profile.get("vertical_chunk_origin", -2)), int(volume[2])
	):
		failures.append("native flat world did not reach running")
		return await _finish(harness, standard, {}, actions, settlements, audit_times, failures)
	var terrain := harness.terrain
	var viewer_revision := 1
	var collision_revision := 1
	var initial_position := _vector3(workload.get("initial_position", []))
	var initial_settlement: Dictionary = await _update_viewers_and_settle(
		harness, terrain, profile, initial_position, viewer_revision, collision_revision
	)
	settlements.append(_settlement_record("initial", initial_settlement))
	_expect(str(initial_settlement.get("status", "")) == "PASS", "initial native publication did not settle", failures)
	var initial_metrics: Dictionary = terrain.call("get_runtime_metrics")
	var targeted_collision := (
		int(initial_metrics.get("collision_required_chunk_records", 0)) > 0
		and int(initial_metrics.get("collision_required_chunk_records", 0))
			< int(initial_metrics.get("active_chunk_records", 0))
		and int(initial_metrics.get("collision_viewer_updates", 0)) > 0
	)
	_expect(targeted_collision, "collision demand is not an independent bounded subset", failures)
	actions["targeted_collision_demand"] = "PASS" if targeted_collision else "FAIL"
	var old_resources := _resource_names(terrain)
	var teleport := _vector3(workload.get("teleport_position", []))
	viewer_revision += 1
	collision_revision += 1
	var teleport_settlement: Dictionary = await _update_viewers_and_settle(
		harness, terrain, profile, teleport, viewer_revision, collision_revision
	)
	settlements.append(_settlement_record("pre_edit_teleport", teleport_settlement))
	var teleported_names := _resource_names(terrain)
	var retirement_control := _resource_retirement_control(old_resources, teleported_names)
	var retirement := bool(retirement_control.get("status", false))
	_expect(str(teleport_settlement.get("status", "")) == "PASS" and retirement, "pre-edit teleport did not retire old render/collision resources", failures)
	actions["pre_edit_teleport_retirement"] = "PASS" if retirement else "FAIL"
	viewer_revision += 1
	collision_revision += 1
	var return_settlement: Dictionary = await _update_viewers_and_settle(
		harness, terrain, profile, initial_position, viewer_revision, collision_revision
	)
	settlements.append(_settlement_record("return", return_settlement))
	_expect(str(return_settlement.get("status", "")) == "PASS", "return publication did not settle", failures)
	var rejected_before := int((terrain.call("get_runtime_metrics") as Dictionary).get("rejected_events", 0))
	var stale_submitted := bool(terrain.call(
		"update_viewer", int(profile.get("viewer_id", 39)), viewer_revision - 1,
		initial_position, int(profile.get("viewer_radius_chunks", 1)), int(profile.get("maximum_lod", 1))
	))
	var stale_rejected_async := false
	if stale_submitted:
		stale_rejected_async = await _wait_for_metric_increase(
			terrain, "rejected_events", rejected_before, 360
		)
	var stale_rejected := not stale_submitted or stale_rejected_async
	_expect(stale_rejected, "stale viewer revision was not rejected", failures)
	actions["stale_viewer_revision_control"] = "PASS" if stale_rejected else "FAIL"

	var edit: RefCounted = terrain.call("begin_edit_transaction", 3901)
	_expect(edit != null, "feature edit transaction was not created", failures)
	if edit != null:
		for feature_value in workload.get("feature_edits", []):
			var feature: Dictionary = feature_value
			_expect(_append_feature_edit(edit, feature), "feature edit was rejected: " + str(feature.get("id", "")), failures)
		_expect(bool(terrain.call("commit_edit_transaction", edit)), "feature edit transaction was rejected", failures)
	_expect(await harness.wait_for_commit(1), "feature edit transaction did not commit", failures)
	var feature_settlement: Dictionary = await harness.wait_for_settled(1)
	settlements.append(_settlement_record("feature_edits", feature_settlement))
	_expect(str(feature_settlement.get("status", "")) == "PASS", "feature edit publication did not settle", failures)
	actions["feature_edit_publication"] = "PASS" if str(feature_settlement.get("status", "")) == "PASS" else "FAIL"

	var audit_started := Time.get_ticks_usec()
	var edited_pairs := _audit_render_collision_pairs(terrain, standard)
	audit_times.append(float(Time.get_ticks_usec() - audit_started))
	_append_failures("edited pairs", edited_pairs, failures)
	actions["render_collision_triangle_agreement"] = str(edited_pairs.get("status", ""))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var ray_agreement := await _audit_query_ray_agreement(
		harness, terrain, workload.get("ray_fixtures", []), standard
	)
	_append_failures("query/ray", ray_agreement, failures)
	actions["authoritative_query_ray_agreement"] = str(ray_agreement.get("status", ""))
	var navigation := await _publish_navigation(
		terrain, str(edited_pairs.get("state_signature", "")),
		ray_agreement.get("hits", []), standard
	)
	_append_failures("navigation", navigation, failures)
	actions["terrain_derived_navigation_agreement"] = str(navigation.get("status", ""))

	var pre_stage_pair_signature := str(edited_pairs.get("pair_signature", ""))
	var pre_stage_world_revision := int(terrain.call("get_world_revision"))
	terrain.call("set_render_apply_budget", 0)
	terrain.call("set_collision_apply_budget", 0)
	var staged_spec: Dictionary = workload.get("staged_edit", {})
	var staged_edit: RefCounted = terrain.call("begin_edit_transaction", 3902)
	_expect(staged_edit != null and _append_feature_edit(staged_edit, staged_spec), "staged edit command was rejected", failures)
	if staged_edit != null:
		_expect(bool(terrain.call("commit_edit_transaction", staged_edit)), "staged edit transaction was rejected", failures)
	_expect(await harness.wait_for_commit(pre_stage_world_revision + 1), "staged edit did not commit authoritatively", failures)
	var pending_observed := await _wait_for_pending_replacement(terrain, 720)
	var pending_pairs := _audit_render_collision_pairs(terrain, standard, true)
	var staged_query := await harness.request_sample(_vector3i(staged_spec.get("center", [])))
	var old_pair_stable := (
		pending_observed
		and str(pending_pairs.get("status", "")) == "PASS"
		and str(pending_pairs.get("pair_signature", "")) == pre_stage_pair_signature
		and int(staged_query.get("world_revision", -1)) == pre_stage_world_revision + 1
	)
	_expect(old_pair_stable, "staged publication did not retain one coherent old render/collision pair", failures)
	actions["staged_edit_publication_control"] = "PASS" if old_pair_stable else "FAIL"
	terrain.call("set_render_apply_budget", 8)
	terrain.call("set_collision_apply_budget", 8)
	var post_stage_settlement: Dictionary = await harness.wait_for_settled(1)
	settlements.append(_settlement_record("post_stage", post_stage_settlement))
	audit_started = Time.get_ticks_usec()
	var post_stage_pairs := _audit_render_collision_pairs(terrain, standard)
	audit_times.append(float(Time.get_ticks_usec() - audit_started))
	_append_failures("post-stage pairs", post_stage_pairs, failures)
	var joint_replacement := (
		str(post_stage_settlement.get("status", "")) == "PASS"
		and str(post_stage_pairs.get("status", "")) == "PASS"
		and str(post_stage_pairs.get("pair_signature", "")) != pre_stage_pair_signature
	)
	_expect(joint_replacement, "post-stage render/collision generation did not replace jointly", failures)
	actions["post_edit_generation_replacement"] = "PASS" if joint_replacement else "FAIL"
	var post_stage_rays := await _audit_query_ray_agreement(
		harness, terrain, workload.get("ray_fixtures", []), standard
	)
	_append_failures("post-stage query/ray", post_stage_rays, failures)
	var post_stage_navigation := await _publish_navigation(
		terrain, str(post_stage_pairs.get("state_signature", "")),
		post_stage_rays.get("hits", []), standard
	)
	_append_failures("post-stage navigation", post_stage_navigation, failures)
	var data := {
		"initial_metrics": initial_metrics,
		"retirement_control": retirement_control,
		"stale_control": {
			"submitted_for_async_validation": stale_submitted,
			"rejected_synchronously": not stale_submitted,
			"rejected_asynchronously": stale_rejected_async,
		},
		"edited_pairs": edited_pairs,
		"ray_agreement": ray_agreement,
		"navigation": navigation,
		"pending": {
			"observed": pending_observed,
			"old_pair_stable": old_pair_stable,
			"world_revision_before": pre_stage_world_revision,
			"authoritative_query": staged_query,
			"pair_audit": pending_pairs,
		},
		"post_stage_pairs": post_stage_pairs,
		"post_stage_ray_agreement": post_stage_rays,
		"post_stage_navigation": post_stage_navigation,
		"native_metrics": terrain.call("get_runtime_metrics"),
	}
	return await _finish(harness, standard, data, actions, settlements, audit_times, failures)


func _finish(
	harness: Node,
	standard: Dictionary,
	data: Dictionary,
	actions: Dictionary,
	settlements: Array[Dictionary],
	audit_times: Array[float],
	failures: Array[String]
) -> Dictionary:
	if harness != null and harness.terrain != null:
		if not await harness.stop_world():
			failures.append("native system-agreement fixture did not stop cleanly")
		harness.dispose()
		harness.queue_free()
		await get_tree().process_frame
	Harness.remove_tree(RUNTIME_ROOT)
	var edited_pairs: Dictionary = data.get("edited_pairs", {})
	var post_pairs: Dictionary = data.get("post_stage_pairs", {})
	var semantic_source := {
		"actions": actions,
		"edited_pair_signature": edited_pairs.get("pair_signature", ""),
		"edited_state_signature": edited_pairs.get("state_signature", ""),
		"ray_signature": (data.get("ray_agreement", {}) as Dictionary).get("signature", ""),
		"navigation_signature": (data.get("navigation", {}) as Dictionary).get("signature", ""),
		"post_pair_signature": post_pairs.get("pair_signature", ""),
		"post_ray_signature": (data.get("post_stage_ray_agreement", {}) as Dictionary).get("signature", ""),
	}
	return {
		"schema": "world_transvoxel.terrain_lab.adaptive_system_agreement_qualification.v1",
		"milestone": "TQP-39",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"retained_complete": true,
		"standard_id": standard.get("standard_id", ""),
		"authority": standard.get("authority", ""),
		"actions": actions,
		"targeted_collision": {
			"active_chunk_records": int((data.get("initial_metrics", {}) as Dictionary).get("active_chunk_records", 0)),
			"collision_required_chunk_records": int((data.get("initial_metrics", {}) as Dictionary).get("collision_required_chunk_records", 0)),
			"collision_viewer_updates": int((data.get("initial_metrics", {}) as Dictionary).get("collision_viewer_updates", 0)),
		},
		"pre_edit_teleport_retirement": data.get("retirement_control", {}),
		"stale_viewer_control": data.get("stale_control", {}),
		"edited_pair_audit": edited_pairs,
		"query_ray_agreement": data.get("ray_agreement", {}),
		"navigation_agreement": data.get("navigation", {}),
		"staged_publication": data.get("pending", {}),
		"post_stage_pair_audit": post_pairs,
		"post_stage_query_ray_agreement": data.get("post_stage_ray_agreement", {}),
		"post_stage_navigation_agreement": data.get("post_stage_navigation", {}),
		"settlements": settlements,
		"native_metrics": data.get("native_metrics", {}),
		"performance": {
			"scope": "WINDOWS_DEBUG_DIAGNOSTIC_NOT_PRODUCTION_COLLISION_NAVIGATION_OR_FRAME_BUDGET",
			"pair_audit_usec": Statistics.distribution(audit_times),
			"memory": Statistics.memory_metrics(),
		},
		"semantic_signature": JSON.stringify(semantic_source, "", true).sha256_text(),
		"edited_pair_signature": str(edited_pairs.get("pair_signature", "")),
		"post_stage_pair_signature": str(post_pairs.get("pair_signature", "")),
		"provenance": Statistics.provenance("tqp39_native_adaptive_system_agreement_windows_v1"),
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


func _audit_render_collision_pairs(
	terrain: Node,
	standard: Dictionary,
	allow_staged_authority_lead: bool = false
) -> Dictionary:
	var failures: Array[String] = []
	var pair_lines: Array[String] = []
	var state_lines: Array[String] = []
	var pair_count := 0
	var triangle_count := 0
	var collision_triangles_absent := 0
	var omitted_render_triangles := 0
	var maximum_collision_render_displacement := 0.0
	var generation_mismatches := 0
	for state_value in terrain.call("query_active_chunk_states"):
		var state: RefCounted = state_value
		var coordinate: Vector3i = state.call("get_chunk_coordinate")
		var lod := int(state.call("get_lod"))
		var generation := int(state.call("get_generation"))
		var render_generation := int(state.call("get_render_generation"))
		var collision_generation := int(state.call("get_collision_generation"))
		var collision_required := bool(state.call("is_collision_required"))
		state_lines.append("%d,%d,%d,L%d:%d:%d:%d:%d" % [
			coordinate.x, coordinate.y, coordinate.z, lod, generation,
			render_generation, collision_generation, int(collision_required)
		])
		if not collision_required:
			continue
		var suffix := "%d_%d_%d_L%d" % [coordinate.x, coordinate.y, coordinate.z, lod]
		var render := terrain.get_node_or_null("WT_Render_" + suffix) as MeshInstance3D
		var collision := terrain.get_node_or_null("WT_Collision_" + suffix) as StaticBody3D
		if render == null and collision == null:
			continue
		if render == null or collision == null:
			collision_triangles_absent += 1
			continue
		var generations_agree := render_generation > 0 \
			and render_generation == collision_generation
		if not allow_staged_authority_lead:
			generations_agree = generations_agree and render_generation == generation \
				and bool(state.call("is_fully_ready"))
		if not generations_agree:
			generation_mismatches += 1
		var shape := _collision_shape(collision)
		if shape == null:
			collision_triangles_absent += 1
			continue
		var render_triangles := _render_triangle_keys(render)
		var collision_triangles := _collision_triangle_keys(collision, shape)
		pair_count += 1
		triangle_count += render_triangles.size()
		var comparison := _compare_pair_geometry(render, collision, shape)
		var absent_count := int(comparison.get("nonexact_triangle_count", 0))
		collision_triangles_absent += absent_count
		maximum_collision_render_displacement = maxf(
			maximum_collision_render_displacement,
			float(comparison.get("maximum_nonexact_vertex_displacement_m", 0.0))
		)
		omitted_render_triangles += maxi(0, render_triangles.size() - collision_triangles.size())
		pair_lines.append("%s:%d:%s" % [
			suffix, render_generation, "\n".join(collision_triangles).sha256_text()
		])
	pair_lines.sort()
	state_lines.sort()
	if pair_count == 0:
		failures.append("no nonempty native render/collision pair was audited")
	if maximum_collision_render_displacement > float((standard.get("budgets", {}) as Dictionary).get("maximum_nonexact_collision_vertex_displacement_m", 0.0)):
		failures.append(
			"collision/render transition displacement exceeded budget: %.9f"
			% maximum_collision_render_displacement
		)
	if generation_mismatches > int((standard.get("budgets", {}) as Dictionary).get("maximum_generation_mismatches", 0)):
		failures.append("render/collision generation mismatches: %d" % generation_mismatches)
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"pair_count": pair_count,
		"triangle_count": triangle_count,
		"collision_triangles_absent_from_render": collision_triangles_absent,
		"render_triangles_omitted_from_collision": omitted_render_triangles,
		"maximum_nonexact_collision_vertex_displacement_m": maximum_collision_render_displacement,
		"generation_mismatch_count": generation_mismatches,
		"pair_signature": "\n".join(pair_lines).sha256_text(),
		"state_signature": "\n".join(state_lines).sha256_text(),
		"failures": failures,
	}


func _audit_query_ray_agreement(
	harness: Node,
	terrain: Node,
	fixtures_value: Variant,
	standard: Dictionary
) -> Dictionary:
	var failures: Array[String] = []
	var records: Array[Dictionary] = []
	var hit_points: Array[Vector3] = []
	var maximum_error := 0.0
	var budget := float((standard.get("budgets", {}) as Dictionary).get("maximum_ray_crossing_error_m", 1.25))
	for fixture_value in fixtures_value:
		var fixture: Dictionary = fixture_value
		var from := _vector3(fixture.get("from", []))
		var to := _vector3(fixture.get("to", []))
		var distance := from.distance_to(to)
		var steps := maxi(1, ceili(distance))
		var points: Array[Vector3i] = []
		for step in range(steps + 1):
			points.append(Vector3i(from.lerp(to, float(step) / float(steps)).round()))
		var samples: Array[Dictionary] = await harness.request_samples(points)
		var crossing: Dictionary = _first_air_to_solid_crossing(samples, points)
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.hit_back_faces = true
		query.hit_from_inside = true
		var hit: Dictionary = terrain.get_world_3d().direct_space_state.intersect_ray(query)
		var collider := hit.get("collider") as Node
		var hit_point: Vector3 = hit.get("position", Vector3(INF, INF, INF))
		var hit_valid := collider != null and collider.name.begins_with("WT_Collision_")
		var independent_hit := _independent_collision_hit(terrain, from, to)
		var independent_render_hit := _independent_render_hit(terrain, from, to)
		var crossing_valid := bool(crossing.get("found", false))
		var error := hit_point.distance_to(crossing.get("position", Vector3.ZERO)) if hit_valid and crossing_valid else INF
		maximum_error = maxf(maximum_error, error)
		if not hit_valid or not crossing_valid or error > budget:
			failures.append("query/ray crossing mismatch: " + str(fixture.get("id", "")))
		if hit_valid:
			hit_points.append(hit_point)
		records.append({
			"id": fixture.get("id", ""),
			"hit": hit_valid,
			"collider": str(collider.name) if collider != null else "",
			"hit_position": hit_point,
			"crossing_position": crossing.get("position", Vector3.ZERO),
			"crossing_error_m": error,
			"sample_count": samples.size(),
			"independent_collision_hit": bool(independent_hit.get("hit", false)),
			"independent_collision_position": independent_hit.get("position", Vector3.ZERO),
			"independent_render_hit": bool(independent_render_hit.get("hit", false)),
			"independent_render_position": independent_render_hit.get("position", Vector3.ZERO),
		})
	var lines: Array[String] = []
	for record in records:
		lines.append("%s:%d:%d" % [
			str(record.get("id", "")),
			roundi((record.get("hit_position", Vector3.ZERO) as Vector3).distance_to(Vector3.ZERO) * POSITION_SCALE),
			roundi(float(record.get("crossing_error_m", 0.0)) * POSITION_SCALE),
		])
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"fixture_count": records.size(),
		"maximum_crossing_error_m": maximum_error,
		"records": records,
		"hits": hit_points,
		"signature": "\n".join(lines).sha256_text(),
		"failures": failures,
	}


func _publish_navigation(
	terrain: Node,
	source_state_signature: String,
	query_points_value: Variant,
	standard: Dictionary
) -> Dictionary:
	var failures: Array[String] = []
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var lookup := {}
	for child in terrain.get_children():
		if not child is StaticBody3D or not str(child.name).begins_with("WT_Collision_"):
			continue
		var body := child as StaticBody3D
		var shape := _collision_shape(body)
		if shape == null:
			continue
		var faces := shape.get_faces()
		for triangle in range(0, faces.size(), 3):
			var a := body.position + faces[triangle]
			var b := body.position + faces[triangle + 1]
			var c := body.position + faces[triangle + 2]
			var cross := (b - a).cross(c - a)
			# Native terrain triangles use clockwise front-face winding. Only
			# upward walkable faces have a sufficiently negative geometric Y;
			# accepting the opposite winding publishes cave ceilings as floors.
			if cross.length_squared() <= 0.000001 or cross.normalized().y > -0.55:
				continue
			var ia := _navigation_vertex_index(a, vertices, lookup)
			var ib := _navigation_vertex_index(b, vertices, lookup)
			var ic := _navigation_vertex_index(c, vertices, lookup)
			indices.append_array(PackedInt32Array([ia, ic, ib]))
	var navigation_mesh := NavigationMesh.new()
	var navigation_cell_size := float(
		(standard.get("budgets", {}) as Dictionary).get("navigation_cell_size_m", 0.05)
	)
	navigation_mesh.cell_size = navigation_cell_size
	navigation_mesh.cell_height = navigation_cell_size
	navigation_mesh.vertices = vertices
	for triangle in range(0, indices.size(), 3):
		navigation_mesh.add_polygon(PackedInt32Array([
			indices[triangle],
			indices[triangle + 1],
			indices[triangle + 2],
		]))
	var region := NavigationRegion3D.new()
	region.navigation_mesh = navigation_mesh
	terrain.add_child(region)
	NavigationServer3D.set_active(true)
	var map_rid := NavigationServer3D.map_create()
	region.set_navigation_map(map_rid)
	NavigationServer3D.map_set_use_async_iterations(map_rid, false)
	NavigationServer3D.map_set_cell_size(map_rid, navigation_mesh.cell_size)
	NavigationServer3D.map_set_cell_height(map_rid, navigation_mesh.cell_height)
	NavigationServer3D.map_set_up(map_rid, Vector3.UP)
	NavigationServer3D.map_set_active(map_rid, true)
	var synchronization_probe := Vector3.ZERO
	if indices.size() >= 3:
		synchronization_probe = (
			vertices[indices[0]] + vertices[indices[1]] + vertices[indices[2]]
		) / 3.0
	var navigation_ready := false
	for _frame in range(60):
		await get_tree().physics_frame
		NavigationServer3D.map_force_update(map_rid)
		if NavigationServer3D.map_get_closest_point_owner(
			map_rid, synchronization_probe
		).is_valid():
			navigation_ready = true
			break
	var query_count := 0
	var maximum_closest_error := 0.0
	var query_records: Array[Dictionary] = []
	for point_value in query_points_value:
		var point: Vector3 = point_value
		var closest := NavigationServer3D.map_get_closest_point(map_rid, point)
		var owner := NavigationServer3D.map_get_closest_point_owner(map_rid, point)
		var error := closest.distance_to(point)
		if owner.is_valid() and error <= 2.0:
			query_count += 1
		maximum_closest_error = maxf(maximum_closest_error, error)
		query_records.append({
			"point": point,
			"closest": closest,
			"owner_valid": owner.is_valid(),
			"error_m": error,
		})
	var polygon_count := navigation_mesh.get_polygon_count()
	if polygon_count <= 0:
		failures.append("terrain-derived navigation has no polygons")
	if query_count <= 0:
		failures.append("terrain-derived navigation accepted no terrain hit points")
	var signature := "%s:%d:%d:%d:%.6f" % [
		source_state_signature, polygon_count, vertices.size(), indices.size(),
		navigation_cell_size
	]
	var map_iteration_id := NavigationServer3D.map_get_iteration_id(map_rid)
	var map_region_count := NavigationServer3D.map_get_regions(map_rid).size()
	var region_map_valid := region.get_navigation_map().is_valid()
	region.free()
	NavigationServer3D.free_rid(map_rid)
	await get_tree().process_frame
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"source_state_signature": source_state_signature,
		"polygon_count": polygon_count,
		"navigation_cell_size_m": navigation_cell_size,
		"query_point_count": (query_points_value as Array).size(),
		"accepted_query_count": query_count,
		"maximum_closest_point_error_m": maximum_closest_error,
		"map_iteration_id": map_iteration_id,
		"map_region_count": map_region_count,
		"region_map_valid": region_map_valid,
		"navigation_ready": navigation_ready,
		"query_records": query_records,
		"authority": "consumer_derived_not_world_transvoxel_authority",
		"signature": signature.sha256_text(),
		"failures": failures,
	}


static func _first_air_to_solid_crossing(
	samples: Array[Dictionary],
	points: Array[Vector3i]
) -> Dictionary:
	if samples.size() != points.size() or samples.size() < 2:
		return {"found": false}
	for index in range(1, samples.size()):
		var previous_density := float(samples[index - 1].get("density", INF))
		var density := float(samples[index].get("density", INF))
		if previous_density >= 0.0 and density < 0.0:
			var denominator := previous_density - density
			var amount := previous_density / denominator if absf(denominator) > 0.000001 else 0.5
			return {
				"found": true,
				"position": Vector3(points[index - 1]).lerp(Vector3(points[index]), amount),
			}
	return {"found": false}


static func _independent_collision_hit(
	terrain: Node,
	from: Vector3,
	to: Vector3
) -> Dictionary:
	var direction := to - from
	var best_amount := INF
	var best_position := Vector3.ZERO
	var best_collider := ""
	for child in terrain.get_children():
		if not child is StaticBody3D or not str(child.name).begins_with("WT_Collision_"):
			continue
		var body := child as StaticBody3D
		var shape := _collision_shape(body)
		if shape == null:
			continue
		var faces := shape.get_faces()
		for triangle in range(0, faces.size(), 3):
			var amount := _segment_triangle_amount(
				from, direction,
				body.position + faces[triangle],
				body.position + faces[triangle + 1],
				body.position + faces[triangle + 2]
			)
			if amount >= 0.0 and amount < best_amount:
				best_amount = amount
				best_position = from + direction * amount
				best_collider = str(body.name)
	return {
		"hit": is_finite(best_amount),
		"position": best_position,
		"collider": best_collider,
	}


static func _independent_render_hit(
	terrain: Node,
	from: Vector3,
	to: Vector3
) -> Dictionary:
	var direction := to - from
	var best_amount := INF
	var best_position := Vector3.ZERO
	var best_render := ""
	for child in terrain.get_children():
		if not child is MeshInstance3D or not str(child.name).begins_with("WT_Render_"):
			continue
		var render := child as MeshInstance3D
		if render.mesh == null:
			continue
		for surface in range(render.mesh.get_surface_count()):
			var arrays := render.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for triangle in range(0, indices.size(), 3):
				var amount := _segment_triangle_amount(
					from, direction,
					render.position + vertices[indices[triangle]],
					render.position + vertices[indices[triangle + 1]],
					render.position + vertices[indices[triangle + 2]]
				)
				if amount >= 0.0 and amount < best_amount:
					best_amount = amount
					best_position = from + direction * amount
					best_render = str(render.name)
	return {
		"hit": is_finite(best_amount),
		"position": best_position,
		"render": best_render,
	}


static func _segment_triangle_amount(
	origin: Vector3,
	direction: Vector3,
	a: Vector3,
	b: Vector3,
	c: Vector3
) -> float:
	var edge_a := b - a
	var edge_b := c - a
	var h := direction.cross(edge_b)
	var determinant := edge_a.dot(h)
	if absf(determinant) <= 0.0000001:
		return -1.0
	var inverse := 1.0 / determinant
	var offset := origin - a
	var u := inverse * offset.dot(h)
	if u < 0.0 or u > 1.0:
		return -1.0
	var q := offset.cross(edge_a)
	var v := inverse * direction.dot(q)
	if v < 0.0 or u + v > 1.0:
		return -1.0
	var amount := inverse * edge_b.dot(q)
	return amount if amount >= 0.0 and amount <= 1.0 else -1.0


static func _append_feature_edit(edit: RefCounted, feature: Dictionary) -> bool:
	match str(feature.get("operation", "")):
		"carve_smooth_sdf_sphere":
			return bool(edit.call(
				"carve_smooth_sdf_sphere", _vector3(feature.get("center", [])),
				float(feature.get("radius", 0.0)), float(feature.get("strength", 1.0)),
				float(feature.get("smooth_radius", 0.0))
			))
		"set_density_box":
			var accepted := bool(edit.call(
				"set_density_box", _vector3(feature.get("minimum", [])),
				_vector3(feature.get("maximum", [])), float(feature.get("value", -1.0))
			))
			if accepted and feature.has("material"):
				accepted = bool(edit.call(
					"paint_material_box", _vector3(feature.get("minimum", [])),
					_vector3(feature.get("maximum", [])), int(feature.get("material", 7))
				))
			return accepted
	return false


static func _render_triangle_keys(render: MeshInstance3D) -> Array[String]:
	var result: Array[String] = []
	for surface in range(render.mesh.get_surface_count()):
		var arrays := render.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for triangle in range(0, indices.size(), 3):
			result.append(_triangle_key(
				render.position + vertices[indices[triangle]],
				render.position + vertices[indices[triangle + 1]],
				render.position + vertices[indices[triangle + 2]]
			))
	result.sort()
	return result


static func _collision_triangle_keys(
	body: StaticBody3D,
	shape: ConcavePolygonShape3D
) -> Array[String]:
	var result: Array[String] = []
	var faces := shape.get_faces()
	for triangle in range(0, faces.size(), 3):
		result.append(_triangle_key(
			body.position + faces[triangle],
			body.position + faces[triangle + 1],
			body.position + faces[triangle + 2]
		))
	result.sort()
	return result


static func _triangle_key(a: Vector3, b: Vector3, c: Vector3) -> String:
	var points: Array[String] = [_position_key(a), _position_key(b), _position_key(c)]
	points.sort()
	return "|".join(points)


static func _position_key(point: Vector3) -> String:
	return "%d,%d,%d" % [
		roundi(point.x * POSITION_SCALE), roundi(point.y * POSITION_SCALE),
		roundi(point.z * POSITION_SCALE),
	]


static func _collision_shape(body: StaticBody3D) -> ConcavePolygonShape3D:
	if body == null:
		return null
	var shape_node := body.get_node_or_null("Shape") as CollisionShape3D
	return shape_node.shape as ConcavePolygonShape3D \
		if shape_node != null and shape_node.shape is ConcavePolygonShape3D else null


static func _resource_names(terrain: Node) -> Dictionary:
	var render: Array[String] = []
	var collision: Array[String] = []
	for child in terrain.get_children():
		var name_value := str(child.name)
		if name_value.begins_with("WT_Render_"):
			render.append(name_value)
		elif name_value.begins_with("WT_Collision_"):
			collision.append(name_value)
	render.sort()
	collision.sort()
	return {"render": render, "collision": collision}


static func _resource_retirement_control(before: Dictionary, after: Dictionary) -> Dictionary:
	var shared_render: Array[String] = []
	var shared_collision: Array[String] = []
	for name_value in before.get("render", []):
		if name_value in after.get("render", []):
			shared_render.append(str(name_value))
	for name_value in before.get("collision", []):
		if name_value in after.get("collision", []):
			shared_collision.append(str(name_value))
	return {
		"status": shared_render.is_empty() and shared_collision.is_empty(),
		"before_render_count": (before.get("render", []) as Array).size(),
		"before_collision_count": (before.get("collision", []) as Array).size(),
		"after_render_count": (after.get("render", []) as Array).size(),
		"after_collision_count": (after.get("collision", []) as Array).size(),
		"shared_render": shared_render,
		"shared_collision": shared_collision,
	}


static func _multiset_absent_count(subset: Array[String], superset: Array[String]) -> int:
	var available := {}
	for key in superset:
		available[key] = int(available.get(key, 0)) + 1
	var absent := 0
	for key in subset:
		var count := int(available.get(key, 0))
		if count <= 0:
			absent += 1
		else:
			available[key] = count - 1
	return absent


static func _compare_pair_geometry(
	render: MeshInstance3D,
	body: StaticBody3D,
	shape: ConcavePolygonShape3D
) -> Dictionary:
	var render_triangle_counts := {}
	var render_points: Array[Vector3] = []
	for surface in range(render.mesh.get_surface_count()):
		var arrays := render.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for vertex in vertices:
			render_points.append(render.position + vertex)
		for triangle in range(0, indices.size(), 3):
			var key := _triangle_key(
				render.position + vertices[indices[triangle]],
				render.position + vertices[indices[triangle + 1]],
				render.position + vertices[indices[triangle + 2]]
			)
			render_triangle_counts[key] = int(render_triangle_counts.get(key, 0)) + 1
	var nonexact := 0
	var maximum_displacement := 0.0
	var faces := shape.get_faces()
	for triangle in range(0, faces.size(), 3):
		var points: Array[Vector3] = [
			body.position + faces[triangle],
			body.position + faces[triangle + 1],
			body.position + faces[triangle + 2],
		]
		var key := _triangle_key(points[0], points[1], points[2])
		var count := int(render_triangle_counts.get(key, 0))
		if count > 0:
			render_triangle_counts[key] = count - 1
			continue
		nonexact += 1
		for point in points:
			var nearest := INF
			for render_point in render_points:
				nearest = minf(nearest, point.distance_to(render_point))
			maximum_displacement = maxf(maximum_displacement, nearest)
	return {
		"nonexact_triangle_count": nonexact,
		"maximum_nonexact_vertex_displacement_m": maximum_displacement,
	}


static func _update_viewers(
	terrain: Node,
	profile: Dictionary,
	position: Vector3,
	viewer_revision: int,
	collision_revision: int
) -> bool:
	return bool(terrain.call(
		"update_viewer", int(profile.get("viewer_id", 39)), viewer_revision,
		position, int(profile.get("viewer_radius_chunks", 1)), int(profile.get("maximum_lod", 1))
	)) and bool(terrain.call(
		"update_collision_viewer", int(profile.get("collision_viewer_id", 390)),
		collision_revision, position, int(profile.get("collision_radius_chunks", 2))
	))


func _update_viewers_and_settle(
	harness: Node,
	terrain: Node,
	profile: Dictionary,
	position: Vector3,
	viewer_revision: int,
	collision_revision: int
) -> Dictionary:
	var before: Dictionary = terrain.call("get_runtime_metrics")
	if not _update_viewers(
		terrain, profile, position, viewer_revision, collision_revision
	):
		return {"status": "FAIL", "frames": 0, "elapsed_usec": 0}
	var started := Time.get_ticks_usec()
	for frame in range(Harness.MAX_WAIT_FRAMES):
		var metrics: Dictionary = terrain.call("get_runtime_metrics")
		if int(metrics.get("viewer_updates", 0)) \
				>= int(before.get("viewer_updates", 0)) + 1 \
				and int(metrics.get("collision_viewer_updates", 0)) \
					>= int(before.get("collision_viewer_updates", 0)) + 1:
			var settlement: Dictionary = await harness.wait_for_settled(1)
			settlement["event_frames"] = frame
			settlement["elapsed_usec"] = Time.get_ticks_usec() - started
			return settlement
		await get_tree().process_frame
	return {
		"status": "FAIL",
		"frames": Harness.MAX_WAIT_FRAMES,
		"elapsed_usec": Time.get_ticks_usec() - started,
	}


func _wait_for_metric_increase(
	terrain: Node,
	metric: String,
	before: int,
	maximum_frames: int
) -> bool:
	for _frame in range(maximum_frames):
		if int((terrain.call("get_runtime_metrics") as Dictionary).get(metric, 0)) > before:
			return true
		await get_tree().process_frame
	return false


func _wait_for_pending_replacement(terrain: Node, maximum_frames: int) -> bool:
	for _frame in range(maximum_frames):
		var metrics: Dictionary = terrain.call("get_runtime_metrics")
		if int(metrics.get("pending_chunk_replacements", 0)) > 0 \
				or int(metrics.get("blocked_pending_chunk_replacements", 0)) > 0 \
				or int(metrics.get("queued_render", 0)) > 0:
			return true
		await get_tree().process_frame
	return false


static func _navigation_vertex_index(
	point: Vector3,
	vertices: PackedVector3Array,
	lookup: Dictionary
) -> int:
	var key := _position_key(point)
	if lookup.has(key):
		return int(lookup[key])
	var index := vertices.size()
	vertices.append(point)
	lookup[key] = index
	return index


static func _runtime_overrides(profile: Dictionary) -> Dictionary:
	var capacity := int(profile.get("pipeline_capacity", 2048))
	return {
		"active_chunk_capacity": int(profile.get("active_chunk_capacity", 512)),
		"viewer_capacity": 8,
		"demand_capacity_per_viewer": capacity,
		"lod_refinement_radius_chunks": int(profile.get("lod_refinement_radius_chunks", 1)),
		"storage_request_capacity": capacity,
		"storage_completion_capacity": capacity,
		"encoded_page_entry_capacity": capacity,
		"decoded_page_entry_capacity": capacity,
		"mesh_entry_capacity": capacity,
		"render_entry_capacity": capacity,
		"collision_entry_capacity": capacity,
		"trace_event_capacity": 65536,
		"render_apply_budget": 8,
		"collision_apply_budget": 8,
		"collision_activation_distance": float(profile.get("collision_activation_distance", 0.0)),
		"collision_deactivation_distance": float(profile.get("collision_deactivation_distance", 0.0)),
	}


static func _settlement_record(action: String, settlement: Dictionary) -> Dictionary:
	return {
		"action": action,
		"status": settlement.get("status", ""),
		"frames": int(settlement.get("frames", -1)),
		"elapsed_usec": int(settlement.get("elapsed_usec", -1)),
	}


static func _append_failures(prefix: String, result: Dictionary, failures: Array[String]) -> void:
	for failure in result.get("failures", []):
		failures.append(prefix + ": " + str(failure))


static func _vector3(value: Variant) -> Vector3:
	var array: Array = value
	return Vector3(float(array[0]), float(array[1]), float(array[2])) if array.size() == 3 else Vector3.ZERO


static func _vector3i(value: Variant) -> Vector3i:
	var point := _vector3(value)
	return Vector3i(roundi(point.x), roundi(point.y), roundi(point.z))


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
