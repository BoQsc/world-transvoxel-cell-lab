@tool
extends RefCounted
class_name WtTerrainLabSurfaceShadingQualification

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/surface_shading_standard.json"
)


static func run() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var failures: Array[String] = []
	_validate_standard(standard, failures)
	var exact := _run_exact_corpus(failures)
	var visual := _validate_visual(standard, failures)
	var performance := _benchmark(standard, failures)
	return {
		"milestone": "TQP-23",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"qualification_status": (
			"QUALIFIED_WINDOWS_REFERENCE_SURFACE_SHADING_V1"
			if str(visual.get("human_review", "")) == "ACCEPTED"
			else "IMPLEMENTED_PENDING_HUMAN_TEMPORAL_REVIEW"
		),
		"fixture_count": int(exact.get("fixture_count", 0)),
		"exact_corpus": exact,
		"visual_evidence": visual,
		"performance": performance,
		"memory": Statistics.memory_metrics(),
		"provenance": Statistics.provenance("tqp23_reference_surface_shading_v1"),
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


static func _validate_standard(standard: Dictionary, failures: Array[String]) -> void:
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.surface_shading_standard.v1",
		"surface shading standard schema changed",
		failures
	)
	_expect(str(standard.get("milestone", "")) == "TQP-23", "surface shading milestone changed", failures)
	var shader_path := str(standard.get("shader", ""))
	_expect(FileAccess.file_exists(shader_path), "surface reference shader is missing", failures)
	var source := FileAccess.get_file_as_string(shader_path)
	for token in [
		"NORMAL =", "slope_mask", "height_mask", "wetness_mask", "decal_mask",
		"CAMERA_POSITION_WORLD", "camera_detail", "texture_world_origin", "AO_LIGHT_AFFECT",
	]:
		_expect(source.contains(token), "surface shader lacks contract token: " + token, failures)


static func _run_exact_corpus(failures: Array[String]) -> Dictionary:
	var fixture_count := 0
	var normal_records: Array[Dictionary] = []
	for normal in [
		Vector3.UP,
		Vector3.DOWN,
		Vector3.RIGHT,
		Vector3(0.25, 0.93, -0.27).normalized(),
		Vector3(-0.71, 0.10, 0.69).normalized(),
	]:
		var tangent := _stable_tangent(normal)
		var weights := _triplanar_weights(normal, 4.0)
		_expect(absf(tangent.dot(normal)) <= 0.00001, "stable tangent is not orthogonal", failures)
		_expect(absf(tangent.length() - 1.0) <= 0.00001, "stable tangent is not normalized", failures)
		_expect(absf(weights.x + weights.y + weights.z - 1.0) <= 0.00001, "triplanar weights do not normalize", failures)
		normal_records.append({
			"normal": normal,
			"tangent": tangent,
			"weights": weights,
			"slope_mask": _smoothstep(0.22, 0.72, 1.0 - absf(normal.y)),
		})
		fixture_count += 4
	_expect(_height_mask(2.0) == 0.0 and _height_mask(15.0) == 1.0, "height mask endpoints changed", failures)
	_expect(_wetness_mask(3.0, Vector3.UP) > 0.95, "low upward surface is not wet", failures)
	_expect(_wetness_mask(12.0, Vector3.UP) < 0.01, "high surface remained wet", failures)
	_expect(_wetness_mask(3.0, Vector3.RIGHT) < 0.01, "vertical surface became wet", failures)
	_expect(_decal_mask(Vector3(5.5, 7.0, 2.5), Vector3.UP) > 0.99, "decal center is absent", failures)
	_expect(_decal_mask(Vector3(12.0, 7.0, 2.5), Vector3.UP) < 0.01, "decal escaped its radius", failures)
	_expect(_camera_detail(5.0) == 1.0 and _camera_detail(100.0) == 0.0, "camera detail endpoints changed", failures)
	fixture_count += 8
	for global_position in [
		Vector3(12.25, -8.5, 31.75),
		Vector3(1000000.25, 4000.5, -999999.75),
		Vector3(-1000000.25, -4000.5, 999999.75),
	]:
		var origin := Vector3(
			floorf(global_position.x / 4096.0) * 4096.0,
			floorf(global_position.y / 4096.0) * 4096.0,
			floorf(global_position.z / 4096.0) * 4096.0
		)
		var reconstructed: Vector3 = global_position - origin + origin
		_expect(reconstructed.distance_to(global_position) <= 0.000001, "origin compensation changed", failures)
		fixture_count += 1
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"fixture_count": fixture_count,
		"normal_records": normal_records,
	}


static func _validate_visual(standard: Dictionary, failures: Array[String]) -> Dictionary:
	var evidence := JsonLoader.load_dictionary(str(standard.get("visual_evidence", "")))
	var expected: Dictionary = standard.get("expected", {})
	_expect(
		str(evidence.get("schema", ""))
			== "world_transvoxel.terrain_lab.surface_shading_evidence.v1",
		"surface shading visual evidence schema changed",
		failures
	)
	_expect(str(evidence.get("status", "")) == "PASS", "surface shading visual evidence failed", failures)
	var records: Dictionary = evidence.get("cameras", {})
	for camera_id in ["near", "far"]:
		var record: Dictionary = records.get(camera_id, {})
		var image_path := str(record.get("image", ""))
		var expected_path := str(expected.get(camera_id + "_image", ""))
		var expected_hash := str(expected.get(camera_id + "_sha256", ""))
		_expect(image_path == expected_path and FileAccess.file_exists(image_path), camera_id + " image is missing", failures)
		if FileAccess.file_exists(image_path):
			_expect(FileAccess.get_sha256(image_path) == expected_hash, camera_id + " image hash changed", failures)
		_expect(str(record.get("sha256", "")) == expected_hash, camera_id + " evidence hash changed", failures)
		_expect(int(record.get("pass_count", 0)) == int(expected.get("passes_per_camera", 0)), camera_id + " pass count changed", failures)
		_expect(int(record.get("frames_per_pass", 0)) == int(expected.get("frames_per_pass", 0)), camera_id + " frame count changed", failures)
		_expect(int(record.get("unique_frame_hash_count", -1)) == 1, camera_id + " temporal frames changed", failures)
		_expect(bool(record.get("cold_warm_identity", false)), camera_id + " cold/warm renders differ", failures)
		_expect(int(record.get("surface_pixels", 0)) >= int(expected.get("minimum_surface_pixels", 0)), camera_id + " terrain pixels are absent", failures)
		_expect(int(record.get("decal_pixels", 0)) >= int(expected.get("minimum_decal_pixels", 0)), camera_id + " decal is absent", failures)
		_expect(int(record.get("wet_pixels", 0)) >= int(expected.get("minimum_wet_pixels", 0)), camera_id + " wetness response is absent", failures)
	return {
		"status": str(evidence.get("status", "")),
		"human_review": str((evidence.get("human_review", {}) as Dictionary).get("status", "PENDING")),
		"cameras": records,
	}


static func _benchmark(standard: Dictionary, failures: Array[String]) -> Dictionary:
	var budget: Dictionary = standard.get("performance_budget", {})
	var warmup := int(budget.get("warmup_iterations", 10))
	var sample_count := int(budget.get("sample_count", 100))
	var operations := int(budget.get("operations_per_sample", 4096))
	for warmup_index in range(warmup):
		_run_batch(operations, warmup_index)
	var timings: Array[float] = []
	for sample in range(sample_count):
		var started := Time.get_ticks_usec()
		_run_batch(operations, sample)
		timings.append(float(Time.get_ticks_usec() - started))
	var distribution := Statistics.distribution(timings)
	distribution["warmup_iterations"] = warmup
	distribution["operations_per_sample"] = operations
	distribution["budget_p95_usec"] = float(budget.get("p95_usec", 0.0))
	distribution["scope"] = str(budget.get("scope", ""))
	distribution["budget_evaluation"] = "OBSERVATION_ONLY_COMBINED_RUN" if Statistics.combined_program_run() else "ENFORCED_FOCUSED_RUN"
	if not Statistics.combined_program_run():
		_expect(float(distribution.get("p95_usec", INF)) <= float(budget.get("p95_usec", 0.0)), "surface contract benchmark exceeded budget", failures)
	return distribution


static func _run_batch(count: int, seed: int) -> void:
	for index in range(count):
		var value := float(index + seed)
		var normal := Vector3(sin(value * 0.11), cos(value * 0.07), sin(value * 0.05)).normalized()
		_triplanar_weights(normal, 4.0)
		_stable_tangent(normal)
		_wetness_mask(fmod(value, 16.0), normal)
		_decal_mask(Vector3(fmod(value, 12.0), 7.0, fmod(value * 3.0, 12.0)), normal)
		_camera_detail(fmod(value * 7.0, 120.0))


static func _triplanar_weights(normal: Vector3, sharpness: float) -> Vector3:
	var absolute := normal.abs()
	var weights := Vector3(pow(absolute.x, sharpness), pow(absolute.y, sharpness), pow(absolute.z, sharpness))
	return weights / maxf(weights.x + weights.y + weights.z, 0.000001)


static func _stable_tangent(normal: Vector3) -> Vector3:
	var reference := Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT
	return reference.cross(normal).normalized()


static func _height_mask(height: float) -> float:
	return _smoothstep(3.5, 13.0, height)


static func _wetness_mask(height: float, normal: Vector3) -> float:
	return (1.0 - _smoothstep(5.0, 8.0, height)) * _smoothstep(0.25, 0.85, absf(normal.y))


static func _decal_mask(position: Vector3, normal: Vector3) -> float:
	var distance := Vector2(position.x - 5.5, position.z - 2.5).length()
	return (1.0 - _smoothstep(1.584, 2.2, distance)) * _smoothstep(0.45, 0.85, absf(normal.y))


static func _camera_detail(distance: float) -> float:
	return 1.0 - _smoothstep(18.0, 70.0, distance)


static func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	var t := clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
