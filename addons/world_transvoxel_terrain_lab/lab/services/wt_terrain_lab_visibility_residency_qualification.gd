@tool
extends RefCounted
class_name WtTerrainLabVisibilityResidencyQualification

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)

const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/visibility_residency_standard.json"
)
const STANDARD_SCHEMA := "world_transvoxel.terrain_lab.visibility_residency_standard.v1"


static func run() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var failures: Array[String] = []
	_validate_standard(standard, failures)
	var corpus := _run_fixture_corpus(standard, failures)
	var performance := _benchmark(standard, failures)
	return {
		"milestone": "TQP-22",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"qualification_status": (
			"QUALIFIED_CPU_HORIZONTAL_VISIBILITY_RESIDENCY_REFERENCE_V1"
			if failures.is_empty()
			else "FAILED_CPU_HORIZONTAL_VISIBILITY_RESIDENCY_REFERENCE_V1"
		),
		"fixture_count": int(corpus.get("fixture_count", 0)),
		"fixture_corpus": corpus,
		"performance": performance,
		"memory": Statistics.memory_metrics(),
		"provenance": Statistics.provenance("tqp22_cpu_horizontal_visibility_residency_reference_v1"),
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


static func _validate_standard(standard: Dictionary, failures: Array[String]) -> void:
	_expect(str(standard.get("schema", "")) == STANDARD_SCHEMA, "visibility standard schema changed", failures)
	_expect(str(standard.get("milestone", "")) == "TQP-22", "visibility standard milestone changed", failures)
	var visibility: Dictionary = standard.get("visibility_contract", {})
	_expect(str(visibility.get("window_axes", "")) == "x_z_with_single_y_layer", "visibility axes changed", failures)
	_expect(str(visibility.get("occlusion_policy", "")) == "conservative_angular_interval_reference", "occlusion policy changed", failures)
	_expect(float(visibility.get("far_distance_m", 0.0)) > float(visibility.get("near_distance_m", 0.0)), "visibility distances are invalid", failures)
	var representation: Dictionary = standard.get("representation_contract", {})
	var rings: Array = representation.get("lod_ring_maximum_chunks", [])
	_expect(
		rings.size() == 3
			and int(rings[0]) == 3
			and int(rings[1]) == 6
			and int(rings[2]) == 10,
		"LOD ring policy changed",
		failures
	)
	_expect(int(representation.get("hlod_cluster_size_chunks", 0)) == 4, "HLOD cluster size changed", failures)
	_expect(int(representation.get("resident_memory_budget_bytes", 0)) > 0, "resident memory budget is missing", failures)


static func _run_fixture_corpus(standard: Dictionary, failures: Array[String]) -> Dictionary:
	var visibility: Dictionary = standard.get("visibility_contract", {})
	var representation: Dictionary = standard.get("representation_contract", {})
	var fixture: Dictionary = standard.get("fixture_contract", {})
	var fixture_count := 0
	var view_records: Array[Dictionary] = []
	var views := [
		{"id": "near_forward", "camera": Vector3(8.0, 8.0, 8.0), "direction": Vector3.FORWARD * -1.0, "origin": Vector3.ZERO},
		{"id": "rotated", "camera": Vector3(40.0, 8.0, -24.0), "direction": Vector3(0.70710678, 0.0, 0.70710678), "origin": Vector3.ZERO},
		{"id": "far_origin_shift", "camera": Vector3(1000008.0, 8.0, -999992.0), "direction": Vector3(0.0, 0.0, 1.0), "origin": Vector3(999424.0, 0.0, -1000448.0)},
	]
	var near_result: Dictionary = {}
	for view in views:
		var camera: Vector3 = view["camera"]
		var direction: Vector3 = view["direction"]
		var origin: Vector3 = view["origin"]
		var result := _evaluate_view(camera, direction, origin, visibility, representation)
		_expect(int(result.get("candidate_count", 0)) == 1089, "candidate count changed", failures)
		_expect(int(result.get("frustum_culled_count", 0)) > 0, "frustum culling removed nothing", failures)
		_expect(int(result.get("occluded_count", 0)) > 0, "occlusion reference removed nothing", failures)
		_expect(int(result.get("hlod_cluster_count", 0)) > 0, "distant HLOD representation is absent", failures)
		_expect(int(result.get("draw_submission_count", 0)) <= int(representation.get("draw_submission_budget", 0)), "draw submission budget exceeded", failures)
		_expect(int(result.get("resident_bytes", 0)) <= int(representation.get("resident_memory_budget_bytes", 0)), "resident memory budget exceeded", failures)
		view_records.append(_view_record(str(view["id"]), result))
		fixture_count += 6
		if str(view["id"]) == "near_forward":
			near_result = result

	var far_camera := Vector3(1000008.0, 8.0, -999992.0)
	var far_direction := Vector3(0.0, 0.0, 1.0)
	var unshifted := _evaluate_view(far_camera, far_direction, Vector3.ZERO, visibility, representation)
	var shifted := _evaluate_view(far_camera, far_direction, Vector3(999424.0, 0.0, -1000448.0), visibility, representation)
	var visibility_difference := _set_difference_count(unshifted.get("visible_chunk_ids", []), shifted.get("visible_chunk_ids", []))
	_expect(visibility_difference <= int(fixture.get("origin_shift_visibility_difference_budget", -1)), "origin shift changed visibility", failures)
	_expect(str(unshifted.get("representation_signature", "")) == str(shifted.get("representation_signature", "")), "origin shift changed representation selection", failures)
	fixture_count += 2

	var teleport_camera := Vector3(-2000008.0, 8.0, 2000008.0)
	var teleport_result := _evaluate_view(teleport_camera, Vector3(0.0, 0.0, -1.0), Vector3(-1999872.0, 0.0, 1999872.0), visibility, representation)
	_expect(_intersection_count(near_result.get("visible_chunk_ids", []), teleport_result.get("visible_chunk_ids", [])) == 0, "teleport retained abandoned visible chunks", failures)
	_expect(int(fixture.get("teleport_convergence_updates", 0)) == 1, "teleport convergence policy changed", failures)
	view_records.append(_view_record("teleport", teleport_result))
	fixture_count += 2

	var regular_ids: Array = near_result.get("regular_chunk_ids", [])
	_expect(not regular_ids.is_empty(), "edit republication has no regular resident target", failures)
	if not regular_ids.is_empty():
		var edited_id := str(regular_ids[0])
		var versions := {edited_id: 1}
		var requested_generation := int(versions[edited_id]) + 1
		versions[edited_id] = requested_generation
		_expect(not _can_publish(versions, edited_id, requested_generation - 1), "stale edited buffer was accepted", failures)
		_expect(_can_publish(versions, edited_id, requested_generation), "current edited buffer was rejected", failures)
		var base_bytes := int(near_result.get("resident_bytes", 0))
		var overlap_bytes := base_bytes + int(representation.get("lod0_bytes_per_chunk", 0))
		_expect(overlap_bytes <= int(representation.get("resident_memory_budget_bytes", 0)), "edit overlap exceeded resident budget", failures)
		fixture_count += 3

	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"fixture_count": fixture_count,
		"views": view_records,
		"origin_shift_visibility_difference": visibility_difference,
		"teleport_convergence_updates": int(fixture.get("teleport_convergence_updates", 0)),
		"draw_submission_budget": int(representation.get("draw_submission_budget", 0)),
		"resident_memory_budget_bytes": int(representation.get("resident_memory_budget_bytes", 0)),
	}


static func _evaluate_view(
	camera_global: Vector3,
	direction_value: Vector3,
	origin: Vector3,
	visibility: Dictionary,
	representation: Dictionary
) -> Dictionary:
	var direction := Vector3(direction_value.x, 0.0, direction_value.z).normalized()
	var right := Vector3(direction.z, 0.0, -direction.x)
	var camera_local := camera_global - origin
	var chunk_size := float(visibility.get("chunk_world_size_m", 16.0))
	var radius_chunks := int(visibility.get("candidate_radius_chunks", 16))
	var camera_chunk := Vector2i(floori(camera_global.x / chunk_size), floori(camera_global.z / chunk_size))
	var bound_radius := float(visibility.get("chunk_bound_radius_m", 0.0))
	var half_fov := deg_to_rad(float(visibility.get("horizontal_fov_degrees", 90.0)) * 0.5)
	var far_distance := float(visibility.get("far_distance_m", 0.0))
	var near_distance := float(visibility.get("near_distance_m", 0.0))
	var candidates: Array[Dictionary] = []
	for x in range(camera_chunk.x - radius_chunks, camera_chunk.x + radius_chunks + 1):
		for z in range(camera_chunk.y - radius_chunks, camera_chunk.y + radius_chunks + 1):
			var center_global := Vector3((float(x) + 0.5) * chunk_size, 0.0, (float(z) + 0.5) * chunk_size)
			var relative := (center_global - origin) - camera_local
			var forward_distance := relative.dot(direction)
			var lateral_distance := relative.dot(right)
			var distance := Vector2(relative.x, relative.z).length()
			var in_depth := forward_distance + bound_radius >= near_distance and forward_distance - bound_radius <= far_distance
			var in_angle := absf(lateral_distance) <= maxf(forward_distance, 0.0) * tan(half_fov) + bound_radius
			candidates.append({
				"id": _chunk_key(x, z),
				"coordinate": Vector2i(x, z),
				"center_global": center_global,
				"forward": forward_distance,
				"lateral": lateral_distance,
				"distance": distance,
				"frustum_visible": in_depth and in_angle and forward_distance + bound_radius > 0.0,
			})
	var occluders := _occluders(camera_global, direction, right)
	var visible: Array[Dictionary] = []
	var frustum_culled := 0
	var occluded_count := 0
	for candidate in candidates:
		if not bool(candidate.get("frustum_visible", false)):
			frustum_culled += 1
			continue
		if _is_occluded(candidate, occluders, visibility, direction, right, camera_global):
			occluded_count += 1
			continue
		visible.append(candidate)
	var regular_ids: Array[String] = []
	var visible_ids: Array[String] = []
	var hlod_clusters := {}
	var resident_bytes := 0
	var lod_counts := {0: 0, 1: 0, 2: 0}
	var rings: Array = representation.get("lod_ring_maximum_chunks", [3, 6, 10])
	for candidate in visible:
		var coordinate: Vector2i = candidate["coordinate"]
		var distance_chunks := float(candidate["distance"]) / chunk_size
		visible_ids.append(str(candidate["id"]))
		if distance_chunks <= float(rings[0]):
			regular_ids.append(str(candidate["id"]))
			lod_counts[0] = int(lod_counts[0]) + 1
			resident_bytes += int(representation.get("lod0_bytes_per_chunk", 0))
		elif distance_chunks <= float(rings[1]):
			regular_ids.append(str(candidate["id"]))
			lod_counts[1] = int(lod_counts[1]) + 1
			resident_bytes += int(representation.get("lod1_bytes_per_chunk", 0))
		elif distance_chunks <= float(rings[2]):
			regular_ids.append(str(candidate["id"]))
			lod_counts[2] = int(lod_counts[2]) + 1
			resident_bytes += int(representation.get("lod2_bytes_per_chunk", 0))
		else:
			var cluster_size := int(representation.get("hlod_cluster_size_chunks", 4))
			var cluster_id := "%d:%d" % [_floor_div(coordinate.x, cluster_size), _floor_div(coordinate.y, cluster_size)]
			hlod_clusters[cluster_id] = true
	resident_bytes += hlod_clusters.size() * int(representation.get("hlod_bytes_per_cluster", 0))
	visible_ids.sort()
	regular_ids.sort()
	var representation_parts: Array[String] = []
	for chunk_id in regular_ids:
		representation_parts.append("R:" + chunk_id)
	var cluster_ids: Array = hlod_clusters.keys()
	cluster_ids.sort()
	for cluster_id in cluster_ids:
		representation_parts.append("H:" + str(cluster_id))
	return {
		"candidate_count": candidates.size(),
		"frustum_culled_count": frustum_culled,
		"occluded_count": occluded_count,
		"visible_chunk_count": visible.size(),
		"visible_chunk_ids": visible_ids,
		"regular_chunk_ids": regular_ids,
		"lod_counts": lod_counts,
		"hlod_cluster_count": hlod_clusters.size(),
		"draw_submission_count": regular_ids.size() + hlod_clusters.size(),
		"resident_bytes": resident_bytes,
		"representation_signature": "|".join(representation_parts).sha256_text(),
	}


static func _occluders(camera: Vector3, direction: Vector3, right: Vector3) -> Array[Dictionary]:
	return [
		{"center": camera + direction * 56.0, "half_width": 30.0, "depth_radius": 8.0},
		{"center": camera + direction * 104.0 - right * 55.0, "half_width": 22.0, "depth_radius": 8.0},
	]


static func _is_occluded(
	candidate: Dictionary,
	occluders: Array[Dictionary],
	visibility: Dictionary,
	direction: Vector3,
	right: Vector3,
	camera: Vector3
) -> bool:
	var candidate_forward := float(candidate.get("forward", 0.0))
	var candidate_lateral := float(candidate.get("lateral", 0.0))
	var candidate_half_width := float(visibility.get("chunk_bound_radius_m", 0.0))
	for occluder in occluders:
		var relative: Vector3 = (occluder["center"] as Vector3) - camera
		var occluder_forward := relative.dot(direction)
		var occluder_lateral := relative.dot(right)
		if candidate_forward <= occluder_forward + float(occluder.get("depth_radius", 0.0)) + float(visibility.get("occlusion_epsilon_m", 0.0)):
			continue
		var scale := candidate_forward / maxf(occluder_forward, 0.001)
		var projected_min := (occluder_lateral - float(occluder.get("half_width", 0.0))) * scale
		var projected_max := (occluder_lateral + float(occluder.get("half_width", 0.0))) * scale
		if candidate_lateral - candidate_half_width >= projected_min and candidate_lateral + candidate_half_width <= projected_max:
			return true
	return false


static func _benchmark(standard: Dictionary, failures: Array[String]) -> Dictionary:
	var visibility: Dictionary = standard.get("visibility_contract", {})
	var representation: Dictionary = standard.get("representation_contract", {})
	var budget: Dictionary = standard.get("performance_budget", {})
	var warmup := int(budget.get("warmup_iterations", 10))
	var sample_count := int(budget.get("sample_count", 100))
	var views_per_sample := int(budget.get("views_per_sample", 16))
	for warmup_index in range(warmup):
		_run_view_batch(views_per_sample, warmup_index, visibility, representation)
	var timings: Array[float] = []
	for sample in range(sample_count):
		var started := Time.get_ticks_usec()
		_run_view_batch(views_per_sample, sample, visibility, representation)
		timings.append(float(Time.get_ticks_usec() - started))
	var distribution := Statistics.distribution(timings)
	distribution["warmup_iterations"] = warmup
	distribution["views_per_sample"] = views_per_sample
	distribution["budget_p95_usec"] = float(budget.get("p95_usec", 0.0))
	distribution["scope"] = str(budget.get("scope", ""))
	distribution["budget_evaluation"] = _budget_evaluation()
	_expect(int(distribution.get("sample_count", 0)) == sample_count, "visibility benchmark sample count changed", failures)
	if not Statistics.combined_program_run():
		_expect(float(distribution.get("p95_usec", INF)) <= float(budget.get("p95_usec", 0.0)), "visibility benchmark p95 exceeded budget", failures)
	return distribution


static func _budget_evaluation() -> String:
	return "OBSERVATION_ONLY_COMBINED_RUN" if Statistics.combined_program_run() else "ENFORCED_FOCUSED_RUN"


static func _run_view_batch(count: int, seed: int, visibility: Dictionary, representation: Dictionary) -> void:
	for index in range(count):
		var camera := Vector3(float(seed * 17 + index * 29), 8.0, float(seed * -13 + index * 31))
		var angle := float(seed * 7 + index * 19) * 0.0174532925
		var direction := Vector3(sin(angle), 0.0, cos(angle))
		var origin := Vector3(floorf(camera.x / 1024.0) * 1024.0, 0.0, floorf(camera.z / 1024.0) * 1024.0)
		_evaluate_view(camera, direction, origin, visibility, representation)


static func _view_record(view_id: String, result: Dictionary) -> Dictionary:
	return {
		"id": view_id,
		"candidate_count": int(result.get("candidate_count", 0)),
		"frustum_culled_count": int(result.get("frustum_culled_count", 0)),
		"occluded_count": int(result.get("occluded_count", 0)),
		"visible_chunk_count": int(result.get("visible_chunk_count", 0)),
		"lod_counts": result.get("lod_counts", {}),
		"hlod_cluster_count": int(result.get("hlod_cluster_count", 0)),
		"draw_submission_count": int(result.get("draw_submission_count", 0)),
		"resident_bytes": int(result.get("resident_bytes", 0)),
		"representation_signature": str(result.get("representation_signature", "")),
	}


static func _can_publish(versions: Dictionary, chunk_id: String, generation: int) -> bool:
	return int(versions.get(chunk_id, -1)) == generation


static func _set_difference_count(left: Array, right: Array) -> int:
	var left_set := {}
	var right_set := {}
	for value in left:
		left_set[str(value)] = true
	for value in right:
		right_set[str(value)] = true
	var difference := 0
	for value in left_set:
		if not right_set.has(value):
			difference += 1
	for value in right_set:
		if not left_set.has(value):
			difference += 1
	return difference


static func _intersection_count(left: Array, right: Array) -> int:
	var left_set := {}
	for value in left:
		left_set[str(value)] = true
	var count := 0
	for value in right:
		if left_set.has(str(value)):
			count += 1
	return count


static func _floor_div(value: int, divisor: int) -> int:
	var quotient: int = value / divisor
	if value % divisor < 0:
		quotient -= 1
	return quotient


static func _chunk_key(x: int, z: int) -> String:
	return "%d:%d" % [x, z]


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
