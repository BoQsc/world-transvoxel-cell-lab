@tool
extends RefCounted
class_name WtCellLabEditValidator

const Contracts := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_contracts.gd")
const MeshAnalysis := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_mesh_analysis.gd")
const ReproStore := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_repro_store.gd")


func validate(lab: Object) -> Dictionary:
	var start_usec := Time.get_ticks_usec()
	var original := ReproStore.make_snapshot(lab, {"name": "edit_validator_restore"})
	var result := {
		"schema": Contracts.EDIT_SEQUENCE_VALIDATION_SCHEMA,
		"authority": Contracts.NATIVE_AUTHORITY,
		"sequence_steps": 4,
		"passing_steps": 0,
		"failing_steps": 0,
		"triangle_counts": [],
		"edit_counts": [],
		"affected_cell_counts": [],
		"dirty_regions": [],
		"step_deltas": [],
		"material_ids": [],
		"determinism_failures": 0,
		"sample_failures": [],
		"status": "PASS",
		"elapsed_ms": 0.0,
	}
	var previous_auto_rebuild: bool = lab.auto_rebuild
	lab.auto_rebuild = false
	lab.cells_x = 6
	lab.cells_y = 6
	lab.cells_z = 6
	lab.field_mode = 1
	lab.edits.clear()
	var steps: Array = [
		{"name": "initial", "mode": "none", "center": Vector3.ZERO, "radius": 0.0},
		{"name": "dig_center", "mode": "dig", "center": Vector3.ZERO, "radius": 1.0},
		{"name": "construct_right", "mode": "construct", "center": Vector3(1.0, 0.0, 0.0), "radius": 0.75},
		{"name": "dig_left", "mode": "dig", "center": Vector3(-1.0, 0.0, 0.0), "radius": 0.65},
	]
	var previous_report: Dictionary = {}
	for index in range(steps.size()):
		var step: Dictionary = steps[index]
		match str(step.get("mode", "none")):
			"dig":
				lab.apply_dig_at(step.get("center", Vector3.ZERO), float(step.get("radius", 1.0)))
			"construct":
				lab.apply_construct_at(step.get("center", Vector3.ZERO), float(step.get("radius", 1.0)))
		var report: Dictionary = lab.rebuild()
		var ok := _report_is_healthy(report)
		if ok:
			result["passing_steps"] = int(result["passing_steps"]) + 1
		else:
			result["failing_steps"] = int(result["failing_steps"]) + 1
			MeshAnalysis.append_sample_failure(
				result,
				index,
				-1,
				"edit step failed: %s" % str(step.get("name", index))
			)
		result["triangle_counts"].append(int(report.get("triangles", 0)))
		result["edit_counts"].append(int(report.get("edit_count", 0)))
		result["affected_cell_counts"].append(int(report.get("affected_cell_count", 0)))
		result["dirty_regions"].append(report.get("dirty_region", AABB()))
		result["material_ids"].append(_report_material_ids(lab))
		result["step_deltas"].append(_report_delta(previous_report, report))
		previous_report = report.duplicate(true)
	var sequence_snapshot := ReproStore.make_snapshot(
		lab,
		{
			"name": "deterministic_edit_sequence",
			"expected_label": "passing_standard",
			"source_layer": "world_transvoxel",
		}
	)
	var first_restore := ReproStore.apply_snapshot(lab, sequence_snapshot)
	var second_restore := ReproStore.apply_snapshot(lab, sequence_snapshot)
	if _report_signature(first_restore) != _report_signature(second_restore):
		result["determinism_failures"] = int(result["determinism_failures"]) + 1
		MeshAnalysis.append_sample_failure(result, -1, -1, "edit sequence replay is not deterministic")
	if int(result["failing_steps"]) > 0 or int(result["determinism_failures"]) > 0:
		result["status"] = "FAIL"
	result["elapsed_ms"] = float(Time.get_ticks_usec() - start_usec) / 1000.0
	ReproStore.apply_snapshot(lab, original)
	lab.auto_rebuild = previous_auto_rebuild
	return result


func validate_corpus(lab: Object) -> Dictionary:
	var start_usec := Time.get_ticks_usec()
	var original := ReproStore.make_snapshot(lab, {"name": "edit_corpus_restore"})
	var fixtures: Array[Dictionary] = [
		{
			"name": "terrain_dig",
			"field_mode": 1,
			"edits": [{"mode": "dig", "center": Vector3.ZERO, "radius": 1.2, "material": 0}],
		},
		{
			"name": "terrain_construction",
			"field_mode": 0,
			"edits": [{"mode": "construct", "center": Vector3(0.0, 0.8, 0.0), "radius": 1.1, "material": 4}],
		},
		{
			"name": "tunnel",
			"field_mode": 2,
			"edits": [{"mode": "dig", "center": Vector3(0.0, 0.0, 1.0), "radius": 0.7, "material": 0}],
		},
		{
			"name": "overhang",
			"field_mode": 3,
			"edits": [{"mode": "construct", "center": Vector3(0.0, -0.4, 0.0), "radius": 1.0, "material": 3}],
		},
		{
			"name": "thin_feature",
			"field_mode": 4,
			"edits": [
				{"mode": "construct", "center": Vector3(0.0, 0.15, 0.0), "radius": 0.38, "material": 2},
				{"mode": "dig", "center": Vector3(0.0, 0.15, 0.0), "radius": 0.22, "material": 0},
			],
		},
	]
	var result := {
		"schema": "world_transvoxel.cell_lab.edit_corpus.v1",
		"authority": Contracts.NATIVE_AUTHORITY,
		"fixture_count": fixtures.size(),
		"passing_fixtures": 0,
		"failing_fixtures": 0,
		"fixtures": [],
		"sample_failures": [],
		"status": "PASS",
		"elapsed_ms": 0.0,
	}
	var previous_auto_rebuild: bool = lab.auto_rebuild
	lab.auto_rebuild = false
	for fixture_index in range(fixtures.size()):
		var fixture := fixtures[fixture_index]
		lab.cells_x = 8
		lab.cells_y = 8
		lab.cells_z = 8
		lab.field_mode = int(fixture["field_mode"])
		lab.edits.clear()
		for edit_value in fixture["edits"]:
			lab.edits.append(Dictionary(edit_value).duplicate(true))
		var before_edits: Array[Dictionary] = lab.edits.duplicate(true)
		lab.edits.clear()
		var before_report: Dictionary = lab.rebuild()
		lab.edits = before_edits
		var after_report: Dictionary = lab.rebuild()
		var fixture_result := {
			"name": fixture["name"],
			"status": "PASS" if _report_is_healthy(after_report) else "FAIL",
			"edit_count": lab.edits.size(),
			"affected_cell_count": int(after_report.get("affected_cell_count", 0)),
			"dirty_region": after_report.get("dirty_region", AABB()),
			"delta": _report_delta(before_report, after_report),
			"material_ids": _report_material_ids(lab),
		}
		result["fixtures"].append(fixture_result)
		if fixture_result["status"] == "PASS":
			result["passing_fixtures"] = int(result["passing_fixtures"]) + 1
		else:
			result["failing_fixtures"] = int(result["failing_fixtures"]) + 1
			MeshAnalysis.append_sample_failure(
				result,
				fixture_index,
				-1,
				"edit corpus fixture failed: %s" % str(fixture["name"])
			)
	if int(result["failing_fixtures"]) > 0:
		result["status"] = "FAIL"
	result["elapsed_ms"] = float(Time.get_ticks_usec() - start_usec) / 1000.0
	ReproStore.apply_snapshot(lab, original)
	lab.auto_rebuild = previous_auto_rebuild
	return result


func _report_is_healthy(report: Dictionary) -> bool:
	return str(report.get("status", "")) == "PASS" \
		and int(report.get("interior_open_edges", 0)) == 0 \
		and int(report.get("nonmanifold_edges", 0)) == 0 \
		and int(report.get("orientation_conflict_edges", 0)) == 0 \
		and bool(report.get("chunk_probe_ok", false))


func _report_delta(before: Dictionary, after: Dictionary) -> Dictionary:
	if before.is_empty():
		return {
			"triangles": int(after.get("triangles", 0)),
			"vertices": int(after.get("vertices", 0)),
			"active_cells": int(after.get("active_cells", 0)),
		}
	return {
		"triangles": int(after.get("triangles", 0)) - int(before.get("triangles", 0)),
		"vertices": int(after.get("vertices", 0)) - int(before.get("vertices", 0)),
		"active_cells": int(after.get("active_cells", 0)) - int(before.get("active_cells", 0)),
		"build_ms": float(after.get("build_ms", 0.0)) - float(before.get("build_ms", 0.0)),
	}


func _report_material_ids(lab: Object) -> Array[int]:
	var ids: Array[int] = []
	for edit_value in lab.edits:
		var edit: Dictionary = edit_value
		var material := int(edit.get("material", 0))
		if material > 0 and material not in ids:
			ids.append(material)
	ids.sort()
	return ids


func _report_signature(report: Dictionary) -> String:
	return JSON.stringify({
		"status": report.get("status", ""),
		"triangles": report.get("triangles", 0),
		"vertices": report.get("vertices", 0),
		"active_cells": report.get("active_cells", 0),
		"edit_count": report.get("edit_count", 0),
		"case_histogram": report.get("case_histogram", {}),
	})
