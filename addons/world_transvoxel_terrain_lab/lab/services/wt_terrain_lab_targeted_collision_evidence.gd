@tool
extends RefCounted
class_name WtTerrainLabTargetedCollisionEvidence

const JsonLoader := preload("res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd")
const STANDARD_PATH := "res://addons/world_transvoxel_terrain_lab/standards/targeted_collision_residency_standard.json"


static func validate_retained() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var report := JsonLoader.load_dictionary(str(standard.get("evidence", "")))
	var failures: Array[String] = []
	_expect(str(report.get("schema", "")) == "world_transvoxel.terrain_lab.targeted_collision_residency_qualification.v1", "TQP-46 report schema changed", failures)
	_expect(str(report.get("status", "")) == "PASS" and bool(report.get("retained_complete", false)), "TQP-46 report failed", failures)
	_expect(str((report.get("render_only", {}) as Dictionary).get("status", "")) == "PASS", "TQP-46 render-only control failed", failures)
	_expect(bool(report.get("targeted_subset", false)), "TQP-46 collision subset changed", failures)
	_expect(str((report.get("authoritative_query_independence", {}) as Dictionary).get("status", "")) == "PASS", "TQP-46 query independence failed", failures)
	_expect(str((report.get("swept_motion", {}) as Dictionary).get("status", "")) == "PASS", "TQP-46 swept motion failed", failures)
	_expect(str((report.get("ray_safety", {}) as Dictionary).get("status", "")) == "PASS", "TQP-46 ray safety failed", failures)
	_expect(str((report.get("navigation_consumer", {}) as Dictionary).get("status", "")) == "PASS", "TQP-46 navigation independence failed", failures)
	_expect(str((report.get("edit_replacement", {}) as Dictionary).get("status", "")) == "PASS", "TQP-46 edit replacement failed", failures)
	_expect(str((report.get("retirement", {}) as Dictionary).get("status", "")) == "PASS", "TQP-46 retirement failed", failures)
	_expect(str((report.get("applied_generation_agreement", {}) as Dictionary).get("status", "")) == "PASS", "TQP-46 applied generation mismatch", failures)
	var classes: Array[String] = []
	for value in report.get("invokers", []):
		var invoker: Dictionary = value
		classes.append(str(invoker.get("class", "")))
		_expect(str(invoker.get("status", "")) == "PASS", "TQP-46 invoker failed", failures)
	for required in standard.get("required_invoker_classes", []):
		_expect(str(required) in classes, "TQP-46 invoker missing: " + str(required), failures)
	_expect(str(report.get("shutdown", "")) == "PASS", "TQP-46 shutdown changed", failures)
	return {
		"schema": "world_transvoxel.terrain_lab.targeted_collision_residency_evidence_validation.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"scope_status": {"TQP-46": "qualified_native_targeted_collision_residency_windows_v1" if failures.is_empty() else "failed_targeted_collision"},
		"failures": failures,
	}


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
