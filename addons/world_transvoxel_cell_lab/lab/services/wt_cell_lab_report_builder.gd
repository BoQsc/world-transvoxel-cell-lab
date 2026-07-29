@tool
extends RefCounted
class_name WtCellLabReportBuilder

const Contracts := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_contracts.gd")
const FIELD_MODE_NAMES := ["PLANE", "SPHERE", "TUNNEL", "SADDLE", "WAVES"]
const INSPECTION_MODE_NAMES := ["PATCH", "REGULAR_CASE", "TRANSITION_CASE", "MIXED_LOD"]


static func build(
	lab: Object,
	mesh_data: Dictionary,
	transition_data: Dictionary,
	chunk_data: Dictionary,
	elapsed_ms: float
) -> Dictionary:
	var failed_cells := int(mesh_data.get("failed_cells", 0))
	var interior_open_edges := int(mesh_data.get("interior_open_edges", 0))
	var nonmanifold_edges := int(mesh_data.get("nonmanifold_edges", 0))
	var orientation_conflict_edges := int(mesh_data.get("orientation_conflict_edges", 0))
	var transition_available := bool(transition_data.get("available", false))
	var transition_ok := bool(transition_data.get("ok", false))
	var transition_nonmanifold_edges := int(transition_data.get("nonmanifold_edges", 0))
	var transition_orientation_conflict_edges := int(transition_data.get("orientation_conflict_edges", 0))
	var chunk_available := bool(chunk_data.get("available", false))
	var chunk_ok := bool(chunk_data.get("ok", false))
	var chunk_nonmanifold_edges := int(chunk_data.get("nonmanifold_edges", 0))
	var chunk_orientation_conflict_edges := int(chunk_data.get("orientation_conflict_edges", 0))
	var status := "PASS"
	if failed_cells > 0 or interior_open_edges > 0 or nonmanifold_edges > 0 or orientation_conflict_edges > 0:
		status = "FAIL"
	if not transition_available or not transition_ok or transition_nonmanifold_edges > 0 or transition_orientation_conflict_edges > 0:
		status = "FAIL"
	if not chunk_available or not chunk_ok or chunk_nonmanifold_edges > 0 or chunk_orientation_conflict_edges > 0:
		status = "FAIL"
	var backend_identity: Dictionary = mesh_data.get("backend_identity", {})
	var correctness_claim := Contracts.LAB_CORRECTNESS_CLAIM \
		if bool(mesh_data.get("native_cell_probe_available", false)) \
		else str(mesh_data.get("correctness_claim", "world_transvoxel_required_no_fallback"))
	var report := {
		"schema": Contracts.REPORT_SCHEMA,
		"status": status,
		"implementation": str(mesh_data.get("implementation", Contracts.NATIVE_REGULAR_IMPLEMENTATION)),
		"render_authority": str(mesh_data.get("render_authority", Contracts.NATIVE_AUTHORITY)),
		"correctness_claim": correctness_claim,
		"native_cell_probe_available": bool(
			mesh_data.get("native_cell_probe_available", ClassDB.class_exists("WorldTransvoxelCellProbe"))
		),
		"backend_runtime_available": bool(
			mesh_data.get("backend_runtime_available", ClassDB.class_exists("WorldTransvoxelTerrain"))
		),
		"backend_identity": backend_identity,
		"backend_id": str(backend_identity.get("backend_id", "")),
		"cells": Vector3i(lab.cells_x, lab.cells_y, lab.cells_z),
		"cell_count": lab.cells_x * lab.cells_y * lab.cells_z,
		"active_cells": int(mesh_data.get("active_cells", 0)),
		"empty_cells": int(mesh_data.get("empty_cells", 0)),
		"failed_cells": failed_cells,
		"vertices": (mesh_data.get("vertices", PackedVector3Array()) as PackedVector3Array).size(),
		"triangles": int(mesh_data.get("triangles", 0)),
		"open_edges": int(mesh_data.get("open_edges", 0)),
		"boundary_open_edges": int(mesh_data.get("boundary_open_edges", 0)),
		"interior_open_edges": interior_open_edges,
		"nonmanifold_edges": nonmanifold_edges,
		"orientation_conflict_edges": orientation_conflict_edges,
		"transition_available": transition_available,
		"transition_ok": transition_ok,
		"transition_status": str(transition_data.get("status", "Unavailable")),
		"transition_orientation": str(transition_data.get("orientation", "PositiveZ")),
		"transition_orientation_index": int(
			transition_data.get("orientation_index", Contracts.TRANSITION_ORIENTATION_POSITIVE_Z)
		),
		"transition_case_code": int(transition_data.get("case_code", -1)),
		"transition_vertices": (
			transition_data.get("vertices", PackedVector3Array()) as PackedVector3Array
		).size(),
		"transition_triangles": int(transition_data.get("triangles", 0)),
		"transition_open_edges": int(transition_data.get("open_edges", 0)),
		"transition_nonmanifold_edges": transition_nonmanifold_edges,
		"transition_orientation_conflict_edges": transition_orientation_conflict_edges,
		"chunk_probe_available": chunk_available,
		"chunk_probe_ok": chunk_ok,
		"chunk_probe_status": str(chunk_data.get("status", "Unavailable")),
		"chunk_probe_error": str(chunk_data.get("error", "")),
		"chunk_probe_implementation": str(
			chunk_data.get("implementation", Contracts.CHUNK_PROBE_IMPLEMENTATION)
		),
		"chunk_probe_cells": chunk_data.get(
			"chunk_cells",
			Vector3i.ONE * Contracts.CHUNK_PROBE_CELLS_PER_AXIS
		),
		"chunk_probe_lod": int(chunk_data.get("chunk_lod", 0)),
		"chunk_probe_samples": int(chunk_data.get("sample_count", 0)),
		"chunk_probe_vertices": int(chunk_data.get("vertices_count", 0)),
		"chunk_probe_triangles": int(chunk_data.get("triangles", 0)),
		"chunk_probe_open_edges": int(chunk_data.get("open_edges", 0)),
		"chunk_probe_nonmanifold_edges": chunk_nonmanifold_edges,
		"chunk_probe_orientation_conflict_edges": chunk_orientation_conflict_edges,
		"degenerate_triangles": int(mesh_data.get("degenerate_triangles", 0)),
		"field_mode": FIELD_MODE_NAMES[clampi(lab.field_mode, 0, FIELD_MODE_NAMES.size() - 1)],
		"edit_count": lab.edits.size(),
		"affected_cell_count": int(lab.call("get_affected_cells").size()) \
			if lab.has_method("get_affected_cells") else 0,
		"dirty_region": lab.call("get_dirty_region") \
			if lab.has_method("get_dirty_region") else AABB(),
		"build_ms": elapsed_ms,
		"case_histogram": mesh_data.get("case_histogram", {}),
		"native_status_histogram": mesh_data.get("native_status_histogram", {}),
		"inspection_mode": INSPECTION_MODE_NAMES[
			clampi(int(lab.get("inspection_mode")), 0, INSPECTION_MODE_NAMES.size() - 1)
		],
	}
	report.merge(Contracts.authority_metadata())
	return report


static func attach_validation(report: Dictionary, key: String, result: Dictionary) -> void:
	report[key] = result
	if str(result.get("status", "PASS")) == "FAIL":
		report["status"] = "FAIL"
