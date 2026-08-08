@tool
extends RefCounted
class_name WtTerrainLabLargeWorldPerformanceEvidence

const JsonLoader := preload("res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd")
const STANDARD_PATH := "res://addons/world_transvoxel_terrain_lab/standards/large_world_performance_standard.json"


static func validate_retained() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var report := JsonLoader.load_dictionary(str(standard.get("evidence", "")))
	var failures: Array[String] = []
	_expect(str(report.get("schema", "")) == "world_transvoxel.terrain_lab.large_world_performance_qualification.v1", "TQP-47 report schema changed", failures)
	_expect(str(report.get("status", "")) == "PASS" and bool(report.get("retained_complete", false)), "TQP-47 report failed", failures)
	_expect((report.get("scenarios", []) as Array).size() == (standard.get("scenarios", []) as Array).size(), "TQP-47 scenario count changed", failures)
	for value in report.get("scenarios", []):
		var scenario: Dictionary = value
		_expect(str(scenario.get("status", "")) == "PASS", "TQP-47 scenario failed", failures)
		_expect(str((scenario.get("applied_generation_agreement", {}) as Dictionary).get("status", "")) == "PASS", "TQP-47 applied generation mismatch", failures)
		_expect(int((scenario.get("frame", {}) as Dictionary).get("sample_count", 0)) >= 120, "TQP-47 frame evidence absent", failures)
		_expect(float((scenario.get("primitives", {}) as Dictionary).get("worst_usec", 0.0)) > 0.0, "TQP-47 rendering evidence blank", failures)
	_expect(str(report.get("shutdown", "")) == "PASS", "TQP-47 shutdown changed", failures)
	return {"schema": "world_transvoxel.terrain_lab.large_world_performance_evidence_validation.v1", "status": "PASS" if failures.is_empty() else "FAIL", "scope_status": {"TQP-47": "qualified_native_large_world_performance_windows_v1" if failures.is_empty() else "failed_large_world_performance"}, "failures": failures}


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
