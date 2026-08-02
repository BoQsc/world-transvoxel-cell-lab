@tool
extends RefCounted
class_name WtTerrainLabTextureSystemQualification

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)

const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/texture_system_standard.json"
)
const STANDARD_SCHEMA := "world_transvoxel.terrain_lab.texture_system_standard.v1"


static func run() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var failures: Array[String] = []
	_validate_standard(standard, failures)
	var exact := _run_exact_corpus(standard, failures)
	var performance := _benchmark(standard, failures)
	var visual := _validate_visual(standard, failures)
	return {
		"milestone": "TQP-21",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"qualification_status": (
			"QUALIFIED_REFERENCE_TRIPLANAR_TEXTURE_ARRAY_V1"
			if str(visual.get("human_review", "")) == "ACCEPTED"
			else "IMPLEMENTED_PENDING_HUMAN_RENDER_REVIEW"
		),
		"fixture_count": int(exact.get("fixture_count", 0)),
		"exact_corpus": exact,
		"performance": performance,
		"memory": Statistics.memory_metrics(),
		"provenance": Statistics.provenance("tqp21_reference_triplanar_texture_array_v1"),
		"visual_evidence": visual,
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


static func _validate_standard(standard: Dictionary, failures: Array[String]) -> void:
	_expect(str(standard.get("schema", "")) == STANDARD_SCHEMA, "texture standard schema changed", failures)
	_expect(str(standard.get("milestone", "")) == "TQP-21", "texture standard milestone changed", failures)
	var contract: Dictionary = standard.get("renderer_contract", {})
	_expect(str(contract.get("albedo_storage", "")) == "Texture2DArray", "albedo storage changed", failures)
	_expect(str(contract.get("normal_storage", "")) == "Texture2DArray", "normal storage changed", failures)
	_expect(int(contract.get("layer_count", 0)) == 3, "texture layer count changed", failures)
	_expect(int(contract.get("mipmap_level_count", 0)) == 8, "mipmap level count changed", failures)
	_expect(str(contract.get("anisotropy", "")) == "filter_linear_mipmap_anisotropic", "anisotropic policy changed", failures)
	var shader_path := str(contract.get("shader", ""))
	var scene_path := str(contract.get("scene", ""))
	_expect(FileAccess.file_exists(shader_path), "texture shader is missing", failures)
	_expect(FileAccess.file_exists(scene_path), "texture scene is missing", failures)
	var shader_source := FileAccess.get_file_as_string(shader_path)
	for token in [
		"sampler2DArray terrain_textures",
		"sampler2DArray terrain_normal_textures",
		"filter_linear_mipmap_anisotropic",
		"uniform vec3 texture_world_origin",
		"global_texture_position",
		"NORMAL =",
	]:
		_expect(shader_source.contains(token), "texture shader is missing contract token: " + token, failures)
	var scene_source := FileAccess.get_file_as_string(scene_path.trim_suffix(".tscn") + ".gd")
	_expect(scene_source.contains("_build_texture_array"), "albedo texture-array builder is missing", failures)
	_expect(scene_source.contains("_build_normal_texture_array"), "normal texture-array builder is missing", failures)
	_expect(scene_source.contains("generate_mipmaps"), "texture mipmap generation is missing", failures)


static func _run_exact_corpus(standard: Dictionary, failures: Array[String]) -> Dictionary:
	var contract: Dictionary = standard.get("renderer_contract", {})
	var fixture: Dictionary = standard.get("fixture_contract", {})
	var coordinate_tolerance := float(fixture.get("coordinate_error_budget", 0.000001))
	var normal_tolerance := float(fixture.get("normal_length_error_budget", 0.00001))
	var scale_m := float(contract.get("texture_scale_m", 3.0))
	var sharpness := float(contract.get("triplanar_sharpness", 4.0))
	var fixture_count := 0
	var coordinate_records: Array[Dictionary] = []
	var global_positions: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(12.25, -8.5, 31.75),
		Vector3(-100000.25, 4000.5, 80000.75),
		Vector3(100000.25, -4000.5, -80000.75),
	]
	var origins: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(4096.0, 0.0, -8192.0),
		Vector3(-98304.0, 4096.0, 77824.0),
	]
	for global_position in global_positions:
		var direct := _triplanar_coordinates(global_position, Vector3.ZERO, scale_m)
		for origin in origins:
			var local := global_position - origin
			var shifted := _triplanar_coordinates(local, origin, scale_m)
			_expect_coordinates(shifted, direct, coordinate_tolerance, "origin-shift mapping", failures)
			fixture_count += 1
		coordinate_records.append({"global_position": global_position, "coordinates": direct})

	var normals := {
		"up": Vector3.UP,
		"down": Vector3.DOWN,
		"cliff_x": Vector3.RIGHT,
		"cliff_z": Vector3.BACK,
		"oblique": Vector3(0.25, 0.93, -0.27).normalized(),
		"cave_oblique": Vector3(-0.31, -0.88, 0.36).normalized(),
	}
	var normal_records: Array[Dictionary] = []
	for normal_name in normals:
		var geometric: Vector3 = normals[normal_name]
		var weights := _triplanar_weights(geometric, sharpness)
		_expect(absf(weights.x + weights.y + weights.z - 1.0) <= normal_tolerance, "triplanar weights do not normalize", failures)
		var flat := _reorient_normal(geometric, Vector3(0.0, 0.0, 1.0), weights)
		var perturbed := _reorient_normal(geometric, Vector3(0.12, -0.08, 0.989).normalized(), weights)
		_expect(absf(flat.length() - 1.0) <= normal_tolerance, "flat mapped normal is not normalized", failures)
		_expect(absf(perturbed.length() - 1.0) <= normal_tolerance, "perturbed mapped normal is not normalized", failures)
		_expect(flat.dot(geometric) >= float(fixture.get("normal_hemisphere_minimum_dot", 0.0)), "flat mapped normal crossed its surface hemisphere", failures)
		_expect(perturbed.dot(geometric) >= float(fixture.get("normal_hemisphere_minimum_dot", 0.0)), "perturbed mapped normal crossed its surface hemisphere", failures)
		if geometric.abs().max_axis_index() in [0, 1, 2] and (
			is_equal_approx(absf(geometric.x), 1.0)
			or is_equal_approx(absf(geometric.y), 1.0)
			or is_equal_approx(absf(geometric.z), 1.0)
		):
			_expect(flat.is_equal_approx(geometric), "axis-aligned flat normal changed", failures)
		normal_records.append({"id": normal_name, "weights": weights, "flat_normal": flat, "perturbed_normal": perturbed})
		fixture_count += 5

	for material_fixture in [
		{"material": 1, "layer": 0},
		{"material": 2, "layer": 1},
		{"material": 4, "layer": 1},
		{"material": 5, "layer": 2},
		{"material": 7, "layer": 2},
	]:
		_expect(_material_layer(int(material_fixture["material"])) == int(material_fixture["layer"]), "material-to-layer mapping changed", failures)
		fixture_count += 1

	var shared_positions: Array[Vector3] = [
		Vector3(-64.0, -16.0, 32.0),
		Vector3(0.0, 0.0, 0.0),
		Vector3(12.5, 7.25, -3.75),
		Vector3(128.0, 64.0, -256.0),
	]
	var lod_records: Array[Dictionary] = []
	for lod_value in fixture.get("qualified_lods", []):
		var lod := int(lod_value)
		var maximum_error := 0.0
		for global_position in shared_positions:
			var reference := _triplanar_coordinates(global_position, Vector3.ZERO, scale_m)
			var chunk_origin := Vector3(
				floorf(global_position.x / (16.0 * float(1 << lod))) * (16.0 * float(1 << lod)),
				0.0,
				floorf(global_position.z / (16.0 * float(1 << lod))) * (16.0 * float(1 << lod))
			)
			var reconstructed := _triplanar_coordinates(global_position - chunk_origin, chunk_origin, scale_m)
			maximum_error = maxf(maximum_error, _coordinate_error(reference, reconstructed))
			fixture_count += 1
		_expect(maximum_error <= coordinate_tolerance, "LOD%d texture coordinates exceeded budget" % lod, failures)
		lod_records.append({"lod": lod, "maximum_coordinate_error": maximum_error})

	_expect(int(contract.get("mipmap_level_count", 0)) == floori(log(float(contract.get("layer_size_px", 0))) / log(2.0)) + 1, "mipmap chain is incomplete", failures)
	fixture_count += 1
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"fixture_count": fixture_count,
		"coordinate_records": coordinate_records,
		"normal_records": normal_records,
		"lod_records": lod_records,
		"layer_count": int(contract.get("layer_count", 0)),
		"mipmap_level_count": int(contract.get("mipmap_level_count", 0)),
	}


static func _validate_visual(standard: Dictionary, failures: Array[String]) -> Dictionary:
	var evidence := JsonLoader.load_dictionary(str(standard.get("visual_evidence", "")))
	var image_path := str(evidence.get("image", ""))
	_expect(FileAccess.file_exists(image_path), "texture-system visual is missing", failures)
	if FileAccess.file_exists(image_path):
		_expect(FileAccess.get_sha256(image_path) == str(evidence.get("sha256", "")), "texture-system visual hash changed", failures)
	var automated: Dictionary = evidence.get("automated_checks", {})
	_expect(str(automated.get("status", "")) == "PASS", "texture-system visual automation failed", failures)
	_expect(
		int(automated.get("surface_seam_pair_count", 0)) == 27,
		"texture-system visual seam corpus changed",
		failures
	)
	_expect(
		int(automated.get("surface_seam_errors", -1)) == 0,
		"texture-system visual contains seam errors",
		failures
	)
	_expect(
		str(automated.get("tangent_edit_regression", "")) == "PASS",
		"texture-system tangent edit regression failed",
		failures
	)
	var tangent: Dictionary = evidence.get("tangent_seam_regression", {})
	var tangent_image_path := str(tangent.get("image", ""))
	_expect(FileAccess.file_exists(tangent_image_path), "texture-system tangent seam visual is missing", failures)
	if FileAccess.file_exists(tangent_image_path):
		_expect(
			FileAccess.get_sha256(tangent_image_path)
				== str(tangent.get("sha256", "")),
			"texture-system tangent seam visual hash changed",
			failures
		)
	var review: Dictionary = evidence.get("human_review", {})
	return {
		"image": image_path,
		"sha256": str(evidence.get("sha256", "")),
		"automated_status": str(automated.get("status", "")),
		"surface_seam_pair_count": int(automated.get("surface_seam_pair_count", 0)),
		"surface_seam_errors": int(automated.get("surface_seam_errors", -1)),
		"tangent_seam_image": tangent_image_path,
		"tangent_seam_sha256": str(tangent.get("sha256", "")),
		"human_review": str(review.get("status", "PENDING")),
	}


static func _benchmark(standard: Dictionary, failures: Array[String]) -> Dictionary:
	var contract: Dictionary = standard.get("renderer_contract", {})
	var budget: Dictionary = standard.get("performance_budget", {})
	var warmup := int(budget.get("warmup_iterations", 10))
	var sample_count := int(budget.get("sample_count", 100))
	var operations := int(budget.get("mapping_operations_per_sample", 2048))
	for warmup_index in range(warmup):
		_run_mapping_batch(operations, warmup_index, contract)
	var timings: Array[float] = []
	for sample in range(sample_count):
		var started := Time.get_ticks_usec()
		_run_mapping_batch(operations, sample, contract)
		timings.append(float(Time.get_ticks_usec() - started))
	var distribution := Statistics.distribution(timings)
	distribution["warmup_iterations"] = warmup
	distribution["mapping_operations_per_sample"] = operations
	distribution["budget_p95_usec"] = float(budget.get("p95_usec", 0.0))
	distribution["scope"] = str(budget.get("scope", ""))
	distribution["budget_evaluation"] = _budget_evaluation()
	_expect(int(distribution.get("sample_count", 0)) == sample_count, "texture benchmark sample count changed", failures)
	if not Statistics.combined_program_run():
		_expect(float(distribution.get("p95_usec", INF)) <= float(budget.get("p95_usec", 0.0)), "texture contract benchmark p95 exceeded budget", failures)
	return distribution


static func _budget_evaluation() -> String:
	return "OBSERVATION_ONLY_COMBINED_RUN" if Statistics.combined_program_run() else "ENFORCED_FOCUSED_RUN"


static func _run_mapping_batch(count: int, seed: int, contract: Dictionary) -> void:
	var scale := float(contract.get("texture_scale_m", 3.0))
	var sharpness := float(contract.get("triplanar_sharpness", 4.0))
	for index in range(count):
		var global_position := Vector3(
			float((index * 7919 + seed * 31) % 200001 - 100000),
			float((index * 3571 + seed * 17) % 8193 - 4096),
			float((index * 104729 + seed * 13) % 200001 - 100000)
		)
		var origin := Vector3(
			floorf(global_position.x / 4096.0) * 4096.0,
			floorf(global_position.y / 4096.0) * 4096.0,
			floorf(global_position.z / 4096.0) * 4096.0
		)
		_triplanar_coordinates(global_position - origin, origin, scale)
		var geometric := Vector3(
			sin(float(index) * 0.11),
			cos(float(index + seed) * 0.07),
			sin(float(index + seed) * 0.05)
		).normalized()
		var weights := _triplanar_weights(geometric, sharpness)
		_reorient_normal(geometric, Vector3(0.08, -0.04, 0.996).normalized(), weights)


static func _triplanar_coordinates(local_position: Vector3, texture_origin: Vector3, scale_m: float) -> Dictionary:
	var global_position := local_position + texture_origin
	return {
		"xy": Vector2(global_position.x, global_position.y) / scale_m,
		"xz": Vector2(global_position.x, global_position.z) / scale_m,
		"yz": Vector2(global_position.y, global_position.z) / scale_m,
	}


static func _triplanar_weights(normal: Vector3, sharpness: float) -> Vector3:
	var absolute := normal.abs()
	var weights := Vector3(pow(absolute.x, sharpness), pow(absolute.y, sharpness), pow(absolute.z, sharpness))
	var total := weights.x + weights.y + weights.z
	return weights / maxf(total, 0.000001)


static func _reorient_normal(geometric: Vector3, sampled: Vector3, weights: Vector3) -> Vector3:
	var signs := Vector3(
		-1.0 if geometric.x < 0.0 else 1.0,
		-1.0 if geometric.y < 0.0 else 1.0,
		-1.0 if geometric.z < 0.0 else 1.0
	)
	var x_axis := Vector3(sampled.z * signs.x, sampled.x, sampled.y)
	var y_axis := Vector3(sampled.x, sampled.z * signs.y, sampled.y)
	var z_axis := Vector3(sampled.x, sampled.y, sampled.z * signs.z)
	var blended := x_axis * weights.x + y_axis * weights.y + z_axis * weights.z
	return blended.normalized()


static func _material_layer(material_id: int) -> int:
	if material_id >= 5:
		return 2
	if material_id >= 2:
		return 1
	return 0


static func _expect_coordinates(actual: Dictionary, expected: Dictionary, tolerance: float, label: String, failures: Array[String]) -> void:
	_expect(_coordinate_error(actual, expected) <= tolerance, label + " exceeded coordinate budget", failures)


static func _coordinate_error(left: Dictionary, right: Dictionary) -> float:
	var maximum_error := 0.0
	for key in ["xy", "xz", "yz"]:
		maximum_error = maxf(maximum_error, (left[key] as Vector2).distance_to(right[key] as Vector2))
	return maximum_error


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
