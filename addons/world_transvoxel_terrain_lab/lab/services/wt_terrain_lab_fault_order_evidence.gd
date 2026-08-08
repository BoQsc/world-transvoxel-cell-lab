@tool
extends RefCounted
class_name WtTerrainLabFaultOrderEvidence

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const Qualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_fault_order_qualification.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/fault_order_determinism_standard.json"
)


static func validate_retained() -> Dictionary:
	var failures: Array[String] = []
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var report := JsonLoader.load_dictionary(str(standard.get("evidence", "")))
	var native := JsonLoader.load_dictionary(
		str(standard.get("native_benchmark_evidence", ""))
	)
	var observatory := JsonLoader.load_dictionary(
		str(standard.get("observatory_evidence", ""))
	)
	var expected: Dictionary = standard.get("stable_expected", {})
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.fault_order_determinism_standard.v1",
		"TQP-43 standard schema changed", failures
	)
	_expect(
		str(report.get("schema", ""))
			== "world_transvoxel.terrain_lab.fault_order_qualification.v1",
		"TQP-43 report schema changed", failures
	)
	_expect(
		str(report.get("status", "")) == "PASS"
			and bool(report.get("retained_complete", false))
			and bool(report.get("cross_order_converged", false)),
		"TQP-43 retained report failed", failures
	)
	_expect(
		str(report.get("semantic_signature", ""))
			== str(expected.get("semantic_signature", "")),
		"TQP-43 semantic signature changed", failures
	)
	_expect(
		Qualification._native_evidence_valid(native, standard),
		"TQP-43 native authority changed", failures
	)
	var actions: Dictionary = report.get("actions", {})
	for action in (standard.get("workload", {}) as Dictionary).get("required_actions", []):
		_expect(
			str(actions.get(str(action), "")) == "PASS",
			"TQP-43 action failed: " + str(action), failures
		)
	var reference_state := ""
	var reference_geometry := ""
	var replays: Array = report.get("replays", [])
	_expect(replays.size() == 3, "TQP-43 motion-order count changed", failures)
	for replay_value in replays:
		var replay: Dictionary = replay_value
		var snapshot: Dictionary = replay.get("snapshot", {})
		if reference_state.is_empty():
			reference_state = str(snapshot.get("state_signature", ""))
			reference_geometry = str(snapshot.get("geometry_signature", ""))
		_expect(
			str(replay.get("status", "")) == "PASS"
				and bool(replay.get("viewer_drain_completed", false))
				and bool(replay.get("stale_revision_rejected", false)),
			"TQP-43 replay failed", failures
		)
		_expect(
			int((snapshot.get("metrics", {}) as Dictionary).get("render_resources", 0)) > 0
				and str(snapshot.get("state_signature", "")) == reference_state
				and str(snapshot.get("geometry_signature", "")) == reference_geometry,
			"TQP-43 replay geometry diverged or became empty", failures
		)
	_expect(
		str(observatory.get("schema", ""))
			== "world_transvoxel.terrain_lab.fault_order_observatory_validation.v1"
			and str(observatory.get("status", "")) == "PASS"
			and str((observatory.get("comparison", {}) as Dictionary).get("status", ""))
				== "PASS",
		"TQP-43 observatory evidence failed", failures
	)
	return {
		"schema": "world_transvoxel.terrain_lab.fault_order_evidence_validation.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"scope_status": {
			"TQP-43": "qualified_fault_order_determinism_v1"
				if failures.is_empty() else "failed_fault_order_determinism"
		},
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
