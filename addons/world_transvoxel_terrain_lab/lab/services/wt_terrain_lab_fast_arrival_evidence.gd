@tool
extends RefCounted
class_name WtTerrainLabFastArrivalEvidence

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/fast_arrival_responsiveness_standard.json"
)


static func validate_retained() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	return validate_report(JsonLoader.load_dictionary(str(standard.get("evidence", ""))), standard)


static func validate_report(report: Dictionary, standard: Dictionary = {}) -> Dictionary:
	if standard.is_empty():
		standard = JsonLoader.load_dictionary(STANDARD_PATH)
	var failures: Array[String] = []
	_expect(str(report.get("schema", "")) == "world_transvoxel.terrain_lab.fast_arrival_responsiveness_qualification.v1", "TQP-45 report schema changed", failures)
	_expect(str(report.get("milestone", "")) == "TQP-45", "TQP-45 milestone changed", failures)
	_expect(str(report.get("status", "")) == "PASS" and bool(report.get("retained_complete", false)), "TQP-45 retained report failed", failures)
	for group_name in (standard.get("workload", {}) as Dictionary).get("required_scenario_classes", []):
		var samples: Array = (report.get("groups", {}) as Dictionary).get(str(group_name), [])
		_expect(not samples.is_empty(), "TQP-45 group absent: " + str(group_name), failures)
		for sample_value in samples:
			var sample: Dictionary = sample_value
			_expect(str(sample.get("status", "")) == "PASS", "TQP-45 sample failed", failures)
			var readiness: Dictionary = sample.get("readiness", {})
			var visual_leaf: Dictionary = readiness.get("visual_leaf", {})
			var collision_leaf: Dictionary = readiness.get("collision_leaf", {})
			_expect(bool(visual_leaf.get("visual_ready", false)), "TQP-45 visual readiness not observable", failures)
			_expect(bool(collision_leaf.get("collision_ready", false)), "TQP-45 collision readiness not observable", failures)
			_expect(str((sample.get("generation_agreement", {}) as Dictionary).get("status", "")) == "PASS", "TQP-45 applied generation mismatch", failures)
	var supersession: Dictionary = report.get("supersession", {})
	_expect(
		str(supersession.get("status", "")) == "PASS"
			and int(supersession.get("coalesced_event_delta", 0)) > 0
			and bool(supersession.get("final_demand_matches_canonical_baseline", false)),
		"TQP-45 local supersession changed", failures
	)
	for stage in (standard.get("workload", {}) as Dictionary).get("required_latency_stages", []):
		for group_name in (report.get("distributions", {}) as Dictionary):
			var distribution: Dictionary = (((report.get("distributions", {}) as Dictionary).get(group_name, {}) as Dictionary).get(str(stage), {}))
			_expect(int(distribution.get("sample_count", 0)) > 0, "TQP-45 distribution absent: %s/%s" % [group_name, stage], failures)
	_expect(str(report.get("shutdown", "")) == "PASS", "TQP-45 shutdown changed", failures)
	return {
		"schema": "world_transvoxel.terrain_lab.fast_arrival_responsiveness_evidence_validation.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"scope_status": {"TQP-45": "qualified_native_fast_arrival_edit_responsiveness_windows_v1" if failures.is_empty() else "failed_fast_arrival"},
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
