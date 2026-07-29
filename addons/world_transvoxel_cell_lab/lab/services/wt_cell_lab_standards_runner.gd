@tool
extends RefCounted
class_name WtCellLabStandardsRunner

const Contracts := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_contracts.gd")
const ReproStore := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_repro_store.gd")
const CASE_STANDARDS_PATH := "res://addons/world_transvoxel_cell_lab/standards/standard_cases.json"
const VISUAL_STANDARDS_PATH := "res://addons/world_transvoxel_cell_lab/standards/visual_manifest.json"
const REFERENCE_TERRAIN_STANDARD_PATH := "res://addons/world_transvoxel_cell_lab/standards/reference_terrain_standard.json"


func run(lab: Object) -> Dictionary:
	var start_usec := Time.get_ticks_usec()
	var original := ReproStore.make_snapshot(lab, {"name": "standards_runner_restore"})
	var result := {
		"schema": Contracts.STANDARDS_CORPUS_SCHEMA,
		"authority": Contracts.NATIVE_AUTHORITY,
		"repro_count": 0,
		"passing_repros": 0,
		"failing_repros": 0,
		"case_standard_count": 0,
		"passing_case_standards": 0,
		"failing_case_standards": 0,
		"visual_standard_count": 0,
		"passing_visual_standards": 0,
		"failing_visual_standards": 0,
		"reference_terrain_standard_count": 0,
		"passing_reference_terrain_standards": 0,
		"failing_reference_terrain_standards": 0,
		"repros": [],
		"case_standards": [],
		"visual_standards": [],
		"reference_terrain_standards": [],
		"sample_failures": [],
		"status": "PASS",
		"elapsed_ms": 0.0,
	}
	_run_repros(lab, result)
	_run_case_standards(lab, result)
	_run_reference_terrain_standard(lab, result)
	_run_visual_standards(result)
	if int(result["failing_repros"]) > 0 \
		or int(result["failing_case_standards"]) > 0 \
		or int(result["failing_reference_terrain_standards"]) > 0 \
		or int(result["failing_visual_standards"]) > 0:
		result["status"] = "FAIL"
	result["elapsed_ms"] = float(Time.get_ticks_usec() - start_usec) / 1000.0
	ReproStore.apply_snapshot(lab, original)
	return result


func _run_repros(lab: Object, result: Dictionary) -> void:
	var entries := ReproStore.list_repros(true)
	for entry in entries:
		if not bool(entry.get("committed", false)):
			continue
		result["repro_count"] = int(result["repro_count"]) + 1
		var loaded := ReproStore.load_snapshot(str(entry.get("path", "")))
		var item := {
			"name": entry.get("metadata", {}).get("name", entry.get("file_name", "")),
			"path": entry.get("path", ""),
			"status": "FAIL",
		}
		if bool(loaded.get("ok", false)):
			var snapshot: Dictionary = loaded.get("snapshot", {})
			var report: Dictionary = ReproStore.apply_snapshot(lab, snapshot)
			var expected_label := str(entry.get("metadata", {}).get("expected_label", "passing_standard"))
			var expects_pass := expected_label in ["passing_standard", "fixed_bug"]
			var passes := str(report.get("status", "FAIL")) == "PASS"
			item["expected_label"] = expected_label
			item["report_status"] = report.get("status", "UNKNOWN")
			item["status"] = "PASS" if passes == expects_pass else "FAIL"
		result["repros"].append(item)
		if item["status"] == "PASS":
			result["passing_repros"] = int(result["passing_repros"]) + 1
		else:
			result["failing_repros"] = int(result["failing_repros"]) + 1
			_append_failure(result, "repro standard failed: %s" % str(item["name"]))


func _run_case_standards(lab: Object, result: Dictionary) -> void:
	var standards := _load_json_dictionary(CASE_STANDARDS_PATH)
	for standard_value in standards.get("cases", []):
		var standard: Dictionary = standard_value
		result["case_standard_count"] = int(result["case_standard_count"]) + 1
		var cell_type := str(standard.get("cell_type", ""))
		var description := {}
		if cell_type == "regular":
			description = lab.describe_regular_case(int(standard.get("case_code", 0)))
		elif cell_type == "transition":
			description = lab.describe_transition_case(
				int(standard.get("case_code", 0)),
				int(standard.get("orientation", 4))
			)
		var mesh: Dictionary = description.get("mesh", {})
		var item := {
			"id": standard.get("id", ""),
			"cell_type": cell_type,
			"case_code": standard.get("case_code", 0),
			"expected_status": standard.get("status", "Ok"),
			"actual_status": mesh.get("status", "Unavailable"),
			"expected_vertices": standard.get("vertices", -1),
			"actual_vertices": mesh.get("vertex_count", -1),
			"expected_triangles": standard.get("triangles", -1),
			"actual_triangles": mesh.get("triangle_count", -1),
		}
		var passes := str(item["actual_status"]) == str(item["expected_status"]) \
			and int(item["actual_vertices"]) == int(item["expected_vertices"]) \
			and int(item["actual_triangles"]) == int(item["expected_triangles"])
		item["status"] = "PASS" if passes else "FAIL"
		result["case_standards"].append(item)
		if passes:
			result["passing_case_standards"] = int(result["passing_case_standards"]) + 1
		else:
			result["failing_case_standards"] = int(result["failing_case_standards"]) + 1
			_append_failure(result, "case standard failed: %s" % str(item["id"]))


func _run_reference_terrain_standard(lab: Object, result: Dictionary) -> void:
	var standard := _load_json_dictionary(REFERENCE_TERRAIN_STANDARD_PATH)
	result["reference_terrain_standard_count"] = 1
	var expected: Dictionary = standard.get("expected", {})
	var actual: Dictionary = lab.describe_reference_terrain_standard()
	var compared_keys := [
		"fixture_id",
		"chunk_count",
		"coarse_chunk_count",
		"fine_chunk_count",
		"transition_chunk_count",
		"sample_count",
		"triangle_count",
		"regular_triangles",
		"transition_triangles",
		"material_ids",
		"feature_count",
		"feature_ids",
		"feature_probe_count",
		"same_lod_matching_pairs",
		"mixed_lod_matching_interfaces",
		"mesh_integrity",
		"terrain_observatory",
		"native_dependency",
		"authority_stress",
		"geometry_signature",
		"status",
	]
	var mismatches: Array[String] = []
	for key in compared_keys:
		if not _standard_values_equal(actual.get(key), expected.get(key)):
			mismatches.append(str(key))
	var item := {
		"id": str(standard.get("id", "canonical_reference_terrain")),
		"expected": expected,
		"actual": actual,
		"mismatched_fields": mismatches,
		"status": "PASS" if mismatches.is_empty() else "FAIL",
	}
	result["reference_terrain_standards"].append(item)
	if mismatches.is_empty():
		result["passing_reference_terrain_standards"] = 1
	else:
		result["failing_reference_terrain_standards"] = 1
		_append_failure(
			result,
			"reference terrain standard failed: %s" % ", ".join(mismatches)
		)


func _standard_values_equal(left: Variant, right: Variant) -> bool:
	if typeof(left) in [TYPE_INT, TYPE_FLOAT] and typeof(right) in [TYPE_INT, TYPE_FLOAT]:
		return is_equal_approx(float(left), float(right))
	if typeof(left) == TYPE_ARRAY and typeof(right) == TYPE_ARRAY:
		var left_array: Array = left
		var right_array: Array = right
		if left_array.size() != right_array.size():
			return false
		for index in range(left_array.size()):
			if not _standard_values_equal(left_array[index], right_array[index]):
				return false
		return true
	if typeof(left) == TYPE_DICTIONARY and typeof(right) == TYPE_DICTIONARY:
		var left_dictionary: Dictionary = left
		var right_dictionary: Dictionary = right
		if left_dictionary.size() != right_dictionary.size():
			return false
		for key in right_dictionary.keys():
			if not left_dictionary.has(key) \
					or not _standard_values_equal(left_dictionary[key], right_dictionary[key]):
				return false
		return true
	return left == right


func _run_visual_standards(result: Dictionary) -> void:
	var manifest := _load_json_dictionary(VISUAL_STANDARDS_PATH)
	for visual_value in manifest.get("visuals", []):
		var visual: Dictionary = visual_value
		result["visual_standard_count"] = int(result["visual_standard_count"]) + 1
		var path := str(visual.get("path", ""))
		var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
		var image: Image = texture.get_image() if texture != null else null
		var width := image.get_width() if image != null else 0
		var height := image.get_height() if image != null else 0
		var actual_sha256 := FileAccess.get_sha256(path)
		var expected_sha256 := str(visual.get("sha256", ""))
		var dimensions_match := width == int(visual.get("width", width)) \
			and height == int(visual.get("height", height))
		var hash_matches := not expected_sha256.is_empty() and actual_sha256 == expected_sha256
		var nonblank := false
		if image != null and width > 0 and height > 0:
			nonblank = _image_has_variation(image)
		var item := {
			"id": visual.get("id", ""),
			"path": path,
			"width": width,
			"height": height,
			"nonblank": nonblank,
			"dimensions_match": dimensions_match,
			"sha256": actual_sha256,
			"hash_matches": hash_matches,
			"status": "PASS" if nonblank and dimensions_match and hash_matches else "FAIL",
		}
		result["visual_standards"].append(item)
		if item["status"] == "PASS":
			result["passing_visual_standards"] = int(result["passing_visual_standards"]) + 1
		else:
			result["failing_visual_standards"] = int(result["failing_visual_standards"]) + 1
			_append_failure(result, "visual standard failed: %s" % str(item["id"]))


func _image_has_variation(image: Image) -> bool:
	var first := image.get_pixel(0, 0)
	var step_x := maxi(int(image.get_width() / 32), 1)
	var step_y := maxi(int(image.get_height() / 32), 1)
	for y in range(0, image.get_height(), step_y):
		for x in range(0, image.get_width(), step_x):
			var sample := image.get_pixel(x, y)
			var difference := absf(sample.r - first.r) \
				+ absf(sample.g - first.g) \
				+ absf(sample.b - first.b) \
				+ absf(sample.a - first.a)
			if difference > 0.02:
				return true
	return false


func _load_json_dictionary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed := JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _append_failure(result: Dictionary, message: String) -> void:
	var failures: Array = result.get("sample_failures", [])
	if failures.size() < 32:
		failures.append({"message": message, "source_layer": "world_transvoxel"})
	result["sample_failures"] = failures
