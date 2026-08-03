@tool
extends RefCounted
class_name WtTerrainLabIndependentOracleEvidence

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const Oracle := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_independent_oracle.gd"
)

const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/independent_oracle_standard.json"
)


static func validate_retained() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var report := JsonLoader.load_dictionary(str(standard.get("evidence", "")))
	return validate_report(report, standard)


static func validate_report(report: Dictionary, standard: Dictionary = {}) -> Dictionary:
	if standard.is_empty():
		standard = JsonLoader.load_dictionary(STANDARD_PATH)
	var failures: Array[String] = []
	_expect(
		str(report.get("schema", ""))
			== "world_transvoxel.terrain_lab.independent_oracle_qualification.v1",
		"independent-oracle report schema changed",
		failures
	)
	_expect(str(report.get("milestone", "")) == "TQP-33", "TQP-33 report milestone changed", failures)
	_expect(str(report.get("status", "")) == "PASS", "TQP-33 retained report failed", failures)
	_expect(bool(report.get("retained_complete", false)), "TQP-33 retained report is filtered", failures)
	_expect(str((report.get("contract", {}) as Dictionary).get("status", "")) == "PASS", "TQP-33 source-independence contract failed", failures)
	var expected: Dictionary = standard.get("stable_expected", {})
	var expected_fixtures: Dictionary = expected.get("fixtures", {})
	var observed_fixture_ids := {}
	var observed_checks := {}
	for fixture_value in report.get("fixtures", []):
		var fixture: Dictionary = fixture_value
		var fixture_id := str(fixture.get("fixture_id", ""))
		observed_fixture_ids[fixture_id] = true
		_expect(str(fixture.get("status", "")) == "PASS", fixture_id + " failed", failures)
		_expect(str(fixture.get("geometry_signature", "")) == str(fixture.get("warm_geometry_signature", "")), fixture_id + " cold/warm geometry differs", failures)
		_expect(not str(expected_fixtures.get(fixture_id, "")).is_empty(), fixture_id + " lacks a retained signature", failures)
		_expect(str(fixture.get("geometry_signature", "")) == str(expected_fixtures.get(fixture_id, "")), fixture_id + " retained geometry changed", failures)
		var oracle: Dictionary = fixture.get("oracle", {})
		_expect(str(oracle.get("status", "")) == "PASS", fixture_id + " independent oracle failed", failures)
		for check_id in Oracle.CHECK_IDS:
			var check: Dictionary = (oracle.get("checks", {}) as Dictionary).get(check_id, {})
			if str(check.get("status", "")) == "PASS":
				observed_checks[check_id] = true
		var repro: Dictionary = fixture.get("minimized_repro", {})
		_expect(str(repro.get("runner", "")).ends_with("run_independent_oracle_validation.gd"), fixture_id + " lacks a minimized repro", failures)
	for fixture_value in standard.get("fixtures", []):
		_expect(observed_fixture_ids.has(str((fixture_value as Dictionary).get("id", ""))), "TQP-33 fixture is missing", failures)
	for check_id in Oracle.CHECK_IDS:
		_expect(observed_checks.has(check_id), "TQP-33 lacks an applicable passing check: " + check_id, failures)
	var matrix: Dictionary = report.get("matrix", {})
	var budgets: Dictionary = standard.get("budgets", {})
	_expect(int(matrix.get("fixture_count", 0)) >= int(budgets.get("minimum_fixture_count", 0)), "TQP-33 fixture coverage is incomplete", failures)
	_expect(int(matrix.get("native_chunk_call_count", 0)) >= int(budgets.get("minimum_native_chunk_call_count", 0)), "TQP-33 native call coverage is incomplete", failures)
	_expect(not str(expected.get("matrix_geometry_signature", "")).is_empty(), "TQP-33 retained matrix signature is missing", failures)
	_expect(str(matrix.get("geometry_signature", "")) == str(expected.get("matrix_geometry_signature", "")), "TQP-33 matrix signature changed", failures)
	var negative: Dictionary = report.get("negative_controls", {})
	_expect(str(negative.get("status", "")) == "PASS", "TQP-33 negative controls failed", failures)
	_expect(int(negative.get("control_count", 0)) >= int(budgets.get("minimum_negative_control_count", 0)), "TQP-33 negative-control coverage is incomplete", failures)
	var controlled_checks := {}
	for control_value in negative.get("controls", []):
		var control: Dictionary = control_value
		var check_id := str(control.get("designated_check", ""))
		controlled_checks[check_id] = true
		_expect(str(control.get("status", "")) == "PASS" and bool(control.get("injected_failure_detected", false)), "TQP-33 negative control failed: " + str(control.get("id", "")), failures)
	for check_id in Oracle.CHECK_IDS:
		_expect(controlled_checks.has(check_id), "TQP-33 lacks a negative control for " + check_id, failures)
	var performance: Dictionary = report.get("performance", {})
	for distribution_id in ["fixture_distribution", "oracle_distribution", "negative_control_distribution"]:
		var distribution: Dictionary = performance.get(distribution_id, {})
		for metric in ["sample_count", "p50_usec", "p95_usec", "p99_usec", "worst_usec"]:
			_expect(distribution.has(metric), "TQP-33 performance lacks " + distribution_id + "." + metric, failures)
	var memory: Dictionary = performance.get("memory", {})
	_expect(int(memory.get("retained_bytes", 0)) > 0 and int(memory.get("peak_bytes", 0)) >= int(memory.get("retained_bytes", 0)), "TQP-33 memory telemetry is invalid", failures)
	var provenance: Dictionary = report.get("provenance", {})
	for key in ["workload_signature", "build_type", "os", "architecture", "cpu", "driver", "godot_version", "backend_revision"]:
		_expect(not str(provenance.get(key, "")).is_empty(), "TQP-33 provenance lacks " + key, failures)
	var editor_inspection: Dictionary = standard.get("editor_inspection", {})
	var scene_path := str(editor_inspection.get("scene", ""))
	var capture_path := str(editor_inspection.get("capture", ""))
	_expect(FileAccess.file_exists(scene_path), "TQP-33 editor observatory scene is missing", failures)
	_expect(FileAccess.file_exists(capture_path), "TQP-33 editor observatory capture is missing", failures)
	if FileAccess.file_exists(capture_path):
		_expect(FileAccess.get_sha256(capture_path) == str(editor_inspection.get("capture_sha256", "")), "TQP-33 editor capture changed", failures)
	_expect(int(editor_inspection.get("width", 0)) == 1280 and int(editor_inspection.get("height", 0)) == 720, "TQP-33 editor capture dimensions changed", failures)
	_expect(str(editor_inspection.get("automation_status", "")) == "PASS", "TQP-33 editor inspection automation failed", failures)
	return {
		"schema": "world_transvoxel.terrain_lab.independent_oracle_evidence_validation.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"qualification_status": "QUALIFIED_INDEPENDENT_NATIVE_GEOMETRY_ORACLES_V1" if failures.is_empty() else "FAILED",
		"scope_status": {"TQP-33": "qualified_independent_geometry_topology_oracles_v1" if failures.is_empty() else "failed_independent_oracles"},
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


static func _expect(condition: bool, failure: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(failure)
