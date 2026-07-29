@tool
extends RefCounted
class_name WtCellLabPerformance

const Contracts := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_contracts.gd")
const CaseValidator := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_case_validator.gd")
const HISTORY_PATH := "user://world_transvoxel_cell_lab/performance_history.json"
const THRESHOLDS_PATH := "res://addons/world_transvoxel_cell_lab/standards/performance_thresholds.json"
const REGRESSION_RATIO := 1.35


func run(
	lab: Object,
	chunk_validator: Object,
	edit_validator: Object,
	iterations: int = 3
) -> Dictionary:
	iterations = clampi(iterations, 1, 24)
	var probe: RefCounted = lab.get_native_probe()
	var result := {
		"schema": Contracts.PERFORMANCE_BASELINES_SCHEMA,
		"authority": Contracts.NATIVE_AUTHORITY,
		"iterations": iterations,
		"patch_rebuild_average_ms": 0.0,
		"patch_rebuild_maximum_ms": 0.0,
		"regular_cell_average_us": 0.0,
		"transition_cell_average_us": 0.0,
		"chunk_average_ms": 0.0,
		"reference_terrain_average_ms": 0.0,
		"reference_terrain_maximum_ms": 0.0,
		"reference_terrain_samples_per_ms": 0.0,
		"reference_terrain_triangles_per_ms": 0.0,
		"terrain_observatory_average_ms": 0.0,
		"terrain_observatory_maximum_ms": 0.0,
		"edit_rebuild_average_ms": 0.0,
		"chunk_lod_validation_ms": 0.0,
		"edit_sequence_validation_ms": 0.0,
		"regular_case_corpus_ms": 0.0,
		"transition_case_corpus_ms": 0.0,
		"triangles_per_ms": 0.0,
		"samples_per_ms": 0.0,
		"edit_rebuild_cost_ms": 0.0,
		"regression_threshold_ratio": REGRESSION_RATIO,
		"regression_warnings": [],
		"warning_status": "PASS",
		"status": "PASS",
	}
	var patch_timing := _benchmark_callable(Callable(lab, "rebuild"), iterations)
	result["patch_rebuild_average_ms"] = patch_timing["average_ms"]
	result["patch_rebuild_maximum_ms"] = patch_timing["maximum_ms"]
	var report: Dictionary = lab.get_last_report()
	result["triangles_per_ms"] = float(report.get("triangles", 0)) / maxf(float(patch_timing["average_ms"]), 0.000001)

	var regular_start := Time.get_ticks_usec()
	var regular_calls := iterations * 256
	for repeat in range(iterations):
		for case_code in range(256):
			CaseValidator.mesh_regular_case(probe, case_code)
	result["regular_cell_average_us"] = float(Time.get_ticks_usec() - regular_start) / float(maxi(regular_calls, 1))

	var transition_start := Time.get_ticks_usec()
	var transition_calls := iterations * 512
	for repeat in range(iterations):
		for case_code in range(512):
			CaseValidator.mesh_transition_case(
				probe,
				case_code,
				Contracts.TRANSITION_ORIENTATION_POSITIVE_Z
			)
	result["transition_cell_average_us"] = float(Time.get_ticks_usec() - transition_start) / float(maxi(transition_calls, 1))

	var chunk_timings: Array[float] = []
	var chunk_samples := 0
	for repeat in range(iterations):
		var chunk_start := Time.get_ticks_usec()
		var chunk: Dictionary = chunk_validator.mesh_chunk(probe, Vector3i.ZERO, 1, 0x3F, 0x3F)
		chunk_timings.append(float(Time.get_ticks_usec() - chunk_start) / 1000.0)
		chunk_samples += int(chunk.get("sample_count", 0))
	result["chunk_average_ms"] = _average(chunk_timings)
	result["samples_per_ms"] = float(chunk_samples) / maxf(_sum(chunk_timings), 0.000001)
	var reference_benchmark: Dictionary = lab.benchmark_reference_terrain(iterations)
	result["reference_terrain_average_ms"] = float(reference_benchmark.get("average_ms", 0.0))
	result["reference_terrain_maximum_ms"] = float(reference_benchmark.get("maximum_ms", 0.0))
	result["reference_terrain_samples_per_ms"] = float(
		reference_benchmark.get("samples_per_ms", 0.0)
	)
	result["reference_terrain_triangles_per_ms"] = float(
		reference_benchmark.get("triangles_per_ms", 0.0)
	)
	if str(reference_benchmark.get("status", "")) != "PASS":
		result["status"] = "FAIL"
	var observatory_benchmark: Dictionary = lab.benchmark_terrain_observatory(iterations)
	result["terrain_observatory_average_ms"] = float(
		observatory_benchmark.get("average_all_views_ms", 0.0)
	)
	result["terrain_observatory_maximum_ms"] = float(
		observatory_benchmark.get("maximum_all_views_ms", 0.0)
	)
	if str(observatory_benchmark.get("status", "")) != "PASS":
		result["status"] = "FAIL"

	var original_edits: Array = lab.edits.duplicate(true)
	var edit_timings: Array[float] = []
	for repeat in range(iterations):
		lab.edits = original_edits.duplicate(true)
		lab.edits.append({
			"mode": "dig",
			"center": Vector3(float(repeat) * 0.05, 0.0, 0.0),
			"radius": 0.75,
			"material": lab.construct_material,
		})
		var edit_start := Time.get_ticks_usec()
		lab.rebuild()
		edit_timings.append(float(Time.get_ticks_usec() - edit_start) / 1000.0)
	lab.edits = original_edits
	lab.rebuild()
	result["edit_rebuild_average_ms"] = _average(edit_timings)
	result["edit_rebuild_cost_ms"] = float(result["edit_rebuild_average_ms"]) - float(result["patch_rebuild_average_ms"])

	var chunk_validation_start := Time.get_ticks_usec()
	var chunk_result: Dictionary = chunk_validator.validate(probe)
	result["chunk_lod_validation_ms"] = float(Time.get_ticks_usec() - chunk_validation_start) / 1000.0
	var edit_validation_start := Time.get_ticks_usec()
	var edit_result: Dictionary = edit_validator.validate(lab)
	result["edit_sequence_validation_ms"] = float(Time.get_ticks_usec() - edit_validation_start) / 1000.0
	report = lab.get_last_report()
	var regular_corpus: Dictionary = report.get("regular_case_corpus", {})
	var transition_corpus: Dictionary = report.get("transition_case_corpus", {})
	result["regular_case_corpus_ms"] = float(regular_corpus.get("elapsed_ms", 0.0))
	result["transition_case_corpus_ms"] = float(transition_corpus.get("elapsed_ms", 0.0))
	if str(chunk_result.get("status", "")) != "PASS" or str(edit_result.get("status", "")) != "PASS":
		result["status"] = "FAIL"
	var history := load_history()
	_compare_with_history(result, history)
	_compare_with_thresholds(result)
	history.append(_history_entry(result))
	save_history(history)
	result["history_count"] = history.size()
	return result


static func load_history() -> Array:
	var file := FileAccess.open(HISTORY_PATH, FileAccess.READ)
	if file == null:
		return []
	var parsed := JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if typeof(parsed) == TYPE_ARRAY else []


static func save_history(history: Array) -> bool:
	var absolute_directory := ProjectSettings.globalize_path(HISTORY_PATH.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return false
	var file := FileAccess.open(HISTORY_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(history, "\t"))
	file.close()
	return true


func _benchmark_callable(callable: Callable, iterations: int) -> Dictionary:
	var timings: Array[float] = []
	for repeat in range(iterations):
		var start_usec := Time.get_ticks_usec()
		callable.call()
		timings.append(float(Time.get_ticks_usec() - start_usec) / 1000.0)
	return {
		"average_ms": _average(timings),
		"maximum_ms": timings.max() if not timings.is_empty() else 0.0,
	}


func _compare_with_history(result: Dictionary, history: Array) -> void:
	if history.is_empty():
		return
	var previous: Dictionary = history.back()
	var warnings: Array = []
	for key in [
		"patch_rebuild_average_ms",
		"regular_cell_average_us",
		"transition_cell_average_us",
		"chunk_average_ms",
		"reference_terrain_average_ms",
		"terrain_observatory_average_ms",
		"edit_rebuild_average_ms",
	]:
		var baseline := float(previous.get(key, 0.0))
		var current := float(result.get(key, 0.0))
		if baseline > 0.0 and current > baseline * REGRESSION_RATIO:
			warnings.append({
				"metric": key,
				"baseline": baseline,
				"current": current,
				"ratio": current / baseline,
			})
	result["regression_warnings"] = warnings
	result["warning_status"] = "WARN" if not warnings.is_empty() else "PASS"


func _compare_with_thresholds(result: Dictionary) -> void:
	var file := FileAccess.open(THRESHOLDS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed := JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var limits: Dictionary = parsed.get("warning_limits", {})
	var warnings: Array = result.get("regression_warnings", [])
	for key in limits.keys():
		var limit := float(limits[key])
		var current := float(result.get(key, 0.0))
		if limit > 0.0 and current > limit:
			warnings.append({
				"metric": key,
				"warning_limit": limit,
				"current": current,
				"ratio": current / limit,
			})
	result["regression_warnings"] = warnings
	result["warning_status"] = "WARN" if not warnings.is_empty() else "PASS"


func _history_entry(result: Dictionary) -> Dictionary:
	return {
		"created_unix_time": Time.get_unix_time_from_system(),
		"patch_rebuild_average_ms": result["patch_rebuild_average_ms"],
		"regular_cell_average_us": result["regular_cell_average_us"],
		"transition_cell_average_us": result["transition_cell_average_us"],
		"chunk_average_ms": result["chunk_average_ms"],
		"reference_terrain_average_ms": result["reference_terrain_average_ms"],
		"terrain_observatory_average_ms": result["terrain_observatory_average_ms"],
		"edit_rebuild_average_ms": result["edit_rebuild_average_ms"],
		"triangles_per_ms": result["triangles_per_ms"],
		"samples_per_ms": result["samples_per_ms"],
		"reference_terrain_samples_per_ms": result["reference_terrain_samples_per_ms"],
		"reference_terrain_triangles_per_ms": result["reference_terrain_triangles_per_ms"],
	}


func _average(values: Array[float]) -> float:
	return _sum(values) / float(values.size()) if not values.is_empty() else 0.0


func _sum(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total
