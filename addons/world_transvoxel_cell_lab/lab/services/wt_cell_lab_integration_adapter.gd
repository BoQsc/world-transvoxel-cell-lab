@tool
extends RefCounted
class_name WtCellLabIntegrationAdapter

const Contracts := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_contracts.gd")
const ReproStore := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_repro_store.gd")


static func import_file(path: String, lab: Object) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "could_not_read_integration_snapshot", "path": path}
	var parsed := JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "integration_snapshot_is_not_dictionary", "path": path}
	var result := import_snapshot(parsed, lab, path)
	result["path"] = path
	result["absolute_path"] = ProjectSettings.globalize_path(path)
	return result


static func import_snapshot(snapshot: Dictionary, lab: Object, source_reference: String = "") -> Dictionary:
	var adapter_kind := _detect_adapter_kind(snapshot)
	if adapter_kind.is_empty():
		return {
			"ok": false,
			"error": "unsupported_integration_snapshot",
			"schema": Contracts.INTEGRATION_IMPORT_SCHEMA,
		}
	var operations := _extract_operations(snapshot, adapter_kind)
	var previous_auto_rebuild: bool = lab.auto_rebuild
	lab.auto_rebuild = false
	lab.edits.clear()
	for operation in operations:
		var edit := _operation_to_edit(operation, lab)
		if not edit.is_empty():
			lab.edits.append(edit)
	var center := _extract_center(snapshot)
	var radius := _extract_radius(snapshot)
	if not center.is_zero_approx() or radius > 0.0:
		var extent := maxf(radius * 2.5, 4.0)
		var cells := clampi(ceili(extent / maxf(lab.cell_size, 0.05)), 4, 24)
		lab.cells_x = cells
		lab.cells_y = cells
		lab.cells_z = cells
	var report: Dictionary = lab.rebuild()
	lab.auto_rebuild = previous_auto_rebuild
	var source_health := _source_health(snapshot)
	var comparison := classify(report, source_health)
	var metadata := {
		"name": "integration_reduction_%s" % adapter_kind,
		"notes": "Imported from %s for isolated native-backend reduction." % adapter_kind,
		"expected_label": "investigation",
		"source_layer": "integration",
		"source_reference": source_reference,
	}
	var repro := ReproStore.make_snapshot(lab, metadata)
	repro["integration_import"] = {
		"schema": Contracts.INTEGRATION_IMPORT_SCHEMA,
		"adapter_kind": adapter_kind,
		"source_health": source_health,
		"comparison": comparison,
		"source_snapshot": snapshot,
	}
	return {
		"ok": true,
		"schema": Contracts.INTEGRATION_IMPORT_SCHEMA,
		"adapter_kind": adapter_kind,
		"operation_count": operations.size(),
		"report": report,
		"comparison": comparison,
		"repro": repro,
	}


static func classify(lab_report: Dictionary, source_health: Dictionary) -> Dictionary:
	var lab_passes := str(lab_report.get("status", "FAIL")) == "PASS"
	var source_reports_artifact := bool(source_health.get("artifact_or_failure", false))
	var suspected_layer := "none"
	var reason := "source and native lab both pass"
	if not lab_passes:
		suspected_layer = "world_transvoxel"
		reason = "reduced native-authoritative lab repro fails"
	elif source_reports_artifact:
		suspected_layer = "integration"
		reason = "integration snapshot reports an artifact while reduced native lab passes"
	elif bool(source_health.get("runtime_error", false)):
		suspected_layer = "runtime"
		reason = "runtime state reports an error while reduced native lab passes"
	return {
		"lab_status": str(lab_report.get("status", "UNKNOWN")),
		"source_reports_artifact": source_reports_artifact,
		"suspected_fix_layer": suspected_layer,
		"reason": reason,
	}


static func _detect_adapter_kind(snapshot: Dictionary) -> String:
	if str(snapshot.get("schema", "")).begins_with("world_transvoxel.cell_lab.repro"):
		return "cell_lab_repro"
	if snapshot.has("world") and snapshot.has("streaming") and snapshot.has("edit"):
		return "integration_debug_snapshot"
	if snapshot.has("center") and snapshot.has("radius") and (
		snapshot.has("open_edges") or snapshot.has("watertight") or snapshot.has("mode")
	):
		return "integration_watertightness_probe"
	if snapshot.has("operation_summaries") or snapshot.has("operations"):
		return "integration_edit_snapshot"
	return ""


static func _extract_operations(snapshot: Dictionary, adapter_kind: String) -> Array:
	if adapter_kind == "cell_lab_repro":
		return snapshot.get("edits", [])
	if snapshot.has("operation_summaries"):
		return snapshot.get("operation_summaries", [])
	if snapshot.has("operations"):
		return snapshot.get("operations", [])
	var edit: Dictionary = snapshot.get("edit", {})
	var submission: Dictionary = edit.get("last_submission", {})
	return submission.get("operation_summaries", [])


static func _operation_to_edit(operation_value: Variant, lab: Object) -> Dictionary:
	if typeof(operation_value) != TYPE_DICTIONARY:
		return {}
	var operation: Dictionary = operation_value
	var mode_name := str(operation.get("mode", operation.get("operation", ""))).to_lower()
	var mode := ""
	if "carve" in mode_name or "dig" in mode_name or "subtract" in mode_name:
		mode = "dig"
	elif "construct" in mode_name or "fill" in mode_name or "place" in mode_name or "add" in mode_name:
		mode = "construct"
	if mode.is_empty():
		return {}
	return {
		"mode": mode,
		"center": ReproStore.vector3_from_variant(operation.get("center", Vector3.ZERO), Vector3.ZERO),
		"radius": maxf(float(operation.get("radius", lab.edit_radius)), 0.01),
		"material": int(operation.get("material", operation.get("material_id", lab.construct_material))),
	}


static func _extract_center(snapshot: Dictionary) -> Vector3:
	if snapshot.has("center"):
		return ReproStore.vector3_from_variant(snapshot["center"], Vector3.ZERO)
	var import_data: Dictionary = snapshot.get("probe", {})
	return ReproStore.vector3_from_variant(import_data.get("center", Vector3.ZERO), Vector3.ZERO)


static func _extract_radius(snapshot: Dictionary) -> float:
	if snapshot.has("radius"):
		return float(snapshot["radius"])
	var import_data: Dictionary = snapshot.get("probe", {})
	return float(import_data.get("radius", 0.0))


static func _source_health(snapshot: Dictionary) -> Dictionary:
	var world: Dictionary = snapshot.get("world", {})
	var last_error := str(world.get("last_error", "ok"))
	var open_edges := int(snapshot.get("open_edges", snapshot.get("interior_open_edges", 0)))
	var nonmanifold := int(snapshot.get("nonmanifold_edges", 0))
	var watertight := bool(snapshot.get("watertight", open_edges == 0 and nonmanifold == 0))
	return {
		"runtime_error": last_error != "ok" and not last_error.is_empty(),
		"runtime_error_message": last_error,
		"open_edges": open_edges,
		"nonmanifold_edges": nonmanifold,
		"watertight": watertight,
		"artifact_or_failure": not watertight or open_edges > 0 or nonmanifold > 0,
	}
