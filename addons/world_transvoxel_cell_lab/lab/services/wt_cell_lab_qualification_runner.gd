@tool
extends RefCounted
class_name WtCellLabQualificationRunner

const Contracts := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_contracts.gd")
const ReproStore := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_repro_store.gd")
const CorrectnessQualification := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_correctness_qualification.gd")
const RuntimeQualification := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_runtime_qualification.gd")
const ReleaseQualification := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_release_qualification.gd")

const STANDARD_PATH := "res://addons/world_transvoxel_cell_lab/standards/qualification_standard.json"

var _correctness := CorrectnessQualification.new()
var _runtime := RuntimeQualification.new()
var _release := ReleaseQualification.new()


func run_correctness(lab: Object, reference_terrain: RefCounted) -> Dictionary:
	return _correctness.validate(lab.call("get_native_probe"), reference_terrain)


func run_runtime(lab: Object, reference_terrain: RefCounted) -> Dictionary:
	return _runtime.validate(
		lab,
		lab.call("get_native_probe"),
		reference_terrain
	)


func run(
	lab: Object,
	reference_terrain: RefCounted,
	compare_standard: bool = true
) -> Dictionary:
	var start_usec := Time.get_ticks_usec()
	var probe: RefCounted = lab.call("get_native_probe")
	var correctness := _correctness.validate(probe, reference_terrain)
	var runtime := _runtime.validate(lab, probe, reference_terrain)
	var release := _release.validate(lab, correctness, runtime)
	var base_status_ok := str(correctness.get("status", "")) == "PASS" \
		and str(runtime.get("status", "")) == "PASS" \
		and str(release.get("status", "")) == "PASS"
	var validation := {
		"schema": Contracts.QUALIFICATION_SUITE_SCHEMA,
		"status": "PASS" if base_status_ok else "FAIL",
		"authority": Contracts.NATIVE_AUTHORITY,
		"milestones": {
			"16": str(
				(correctness.get("adversarial_corpus", {}) as Dictionary)
					.get("status", "FAIL")
			),
			"17": str(
				(correctness.get("failure_reduction", {}) as Dictionary)
					.get("status", "FAIL")
			),
			"18": str(
				(correctness.get("independent_specification", {}) as Dictionary)
					.get("status", "FAIL")
			),
			"19": str(
				(runtime.get("edit_stress", {}) as Dictionary).get("status", "FAIL")
			),
			"20": str(
				(runtime.get("scaling", {}) as Dictionary).get("status", "FAIL")
			),
			"21": str(
				(runtime.get("memory", {}) as Dictionary).get("status", "FAIL")
			),
			"22": str(
				(runtime.get("rendering_quality", {}) as Dictionary)
					.get("status", "FAIL")
			),
			"23": str(
				(runtime.get("collision_queries", {}) as Dictionary)
					.get("status", "FAIL")
			),
			"24": str(
				(runtime.get("streaming", {}) as Dictionary).get("status", "FAIL")
			),
			"25": str(
				(runtime.get("persistence", {}) as Dictionary).get("status", "FAIL")
			),
			"26": str(
				(release.get("integration_parity", {}) as Dictionary)
					.get("status", "FAIL")
			),
			"27": str(
				(release.get("platform_renderer_matrix", {}) as Dictionary)
					.get("status", "FAIL")
			),
			"28": str(
				(release.get("release_bundle", {}) as Dictionary).get("status", "FAIL")
			),
			"29": str(
				(release.get("upstream_governance", {}) as Dictionary)
					.get("status", "FAIL")
			),
		},
		"correctness": correctness,
		"runtime": runtime,
		"release": release,
		"sample_failures": [],
	}
	var signature := standard_signature(validation)
	validation["standard_signature"] = signature
	var standard_comparison := {
		"status": "SKIPPED",
		"path": STANDARD_PATH,
		"mismatches": [],
	}
	if compare_standard:
		standard_comparison = _compare_standard(signature)
		if str(standard_comparison.get("status", "")) != "PASS":
			validation["status"] = "FAIL"
			validation["sample_failures"].append("qualification standard changed")
	validation["standard_comparison"] = standard_comparison
	for key in ["correctness", "runtime", "release"]:
		var section: Dictionary = validation[key]
		if str(section.get("status", "")) != "PASS":
			validation["sample_failures"].append(
				"%s qualification failed" % key
			)
	validation["elapsed_ms"] = float(Time.get_ticks_usec() - start_usec) / 1000.0
	return validation


func standard_signature(validation: Dictionary) -> Dictionary:
	var correctness: Dictionary = validation.get("correctness", {})
	var runtime: Dictionary = validation.get("runtime", {})
	var release: Dictionary = validation.get("release", {})
	return {
		"schema": Contracts.QUALIFICATION_STANDARD_SCHEMA,
		"milestones": validation.get("milestones", {}),
		"correctness": _correctness.standard_signature(correctness),
		"runtime": _runtime.standard_signature(runtime),
		"release": _release.standard_signature(release),
		"status": (
			"PASS"
			if str(correctness.get("status", "")) == "PASS"
				and str(runtime.get("status", "")) == "PASS"
				and str(release.get("status", "")) == "PASS"
			else "FAIL"
		),
	}


func _compare_standard(actual: Dictionary) -> Dictionary:
	var expected := _load_json(STANDARD_PATH)
	var mismatches: Array[String] = []
	if expected.is_empty():
		mismatches.append("qualification standard is missing or invalid")
	else:
		_compare_values(
			ReproStore.to_json_safe(expected),
			ReproStore.to_json_safe(actual),
			"$",
			mismatches
		)
	return {
		"status": "PASS" if mismatches.is_empty() else "FAIL",
		"path": STANDARD_PATH,
		"mismatches": mismatches,
	}


func _compare_values(
	expected: Variant,
	actual: Variant,
	path: String,
	mismatches: Array[String]
) -> void:
	if mismatches.size() >= 64:
		return
	if typeof(expected) != typeof(actual):
		if expected is float or expected is int:
			if actual is float or actual is int:
				if absf(float(expected) - float(actual)) <= 0.00001:
					return
		mismatches.append("%s expected=%s actual=%s" % [path, str(expected), str(actual)])
		return
	match typeof(expected):
		TYPE_DICTIONARY:
			var expected_dictionary: Dictionary = expected
			var actual_dictionary: Dictionary = actual
			for key in expected_dictionary.keys():
				if not actual_dictionary.has(key):
					mismatches.append("%s.%s missing" % [path, str(key)])
					continue
				_compare_values(
					expected_dictionary[key],
					actual_dictionary[key],
					"%s.%s" % [path, str(key)],
					mismatches
				)
			for key in actual_dictionary.keys():
				if not expected_dictionary.has(key):
					mismatches.append("%s.%s unexpected" % [path, str(key)])
		TYPE_ARRAY:
			var expected_array: Array = expected
			var actual_array: Array = actual
			if expected_array.size() != actual_array.size():
				mismatches.append("%s size expected=%d actual=%d" % [
					path,
					expected_array.size(),
					actual_array.size(),
				])
				return
			for index in range(expected_array.size()):
				_compare_values(
					expected_array[index],
					actual_array[index],
					"%s[%d]" % [path, index],
					mismatches
				)
		TYPE_FLOAT:
			if absf(float(expected) - float(actual)) > 0.00001:
				mismatches.append("%s expected=%s actual=%s" % [
					path,
					str(expected),
					str(actual),
				])
		_:
			if expected != actual:
				mismatches.append("%s expected=%s actual=%s" % [
					path,
					str(expected),
					str(actual),
				])


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed := JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
