@tool
extends RefCounted
class_name WtTerrainLabAdaptiveLodEvidence

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/adaptive_lod_standard.json"
)


static func validate_retained() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var report := JsonLoader.load_dictionary(str(standard.get("evidence", "")))
	return validate_report(report, standard)


static func validate_report(report: Dictionary, standard: Dictionary = {}) -> Dictionary:
	if standard.is_empty():
		standard = JsonLoader.load_dictionary(STANDARD_PATH)
	var failures: Array[String] = []
	_expect(str(standard.get("schema", "")) == "world_transvoxel.terrain_lab.adaptive_lod_standard.v1", "TQP-30 standard schema changed", failures)
	_expect(str(report.get("schema", "")) == "world_transvoxel.terrain_lab.adaptive_lod_qualification.v1", "TQP-30 report schema changed", failures)
	_expect(str(report.get("milestone", "")) == "TQP-30", "TQP-30 report milestone changed", failures)
	_expect(str(report.get("standard_id", "")) == str(standard.get("standard_id", "")), "TQP-30 report standard changed", failures)
	_expect(str(report.get("authority", "")) == str(standard.get("authority", "")), "TQP-30 report authority changed", failures)
	_expect(bool(report.get("retained_complete", false)), "TQP-30 report is filtered", failures)
	_expect(str(report.get("status", "")) == "PASS", "TQP-30 retained report failed", failures)
	var contract: Dictionary = report.get("contract", {})
	_expect(str(contract.get("status", "")) == "PASS", "TQP-30 contract failed", failures)
	var required_checks := [
		"hierarchy_policy",
		"maximum_neighbor_delta",
		"viewer_metric",
		"split_merge_hysteresis",
		"origin_shift_identity",
		"teleport_convergence",
		"threshold_order",
	]
	var check_status := {}
	for check_value in contract.get("checks", []):
		var check: Dictionary = check_value
		check_status[str(check.get("id", ""))] = str(check.get("status", ""))
	for check_id in required_checks:
		_expect(str(check_status.get(check_id, "")) == "PASS", "TQP-30 lacks passing check " + check_id, failures)
	var corpus: Dictionary = report.get("scenario_corpus", {})
	var budgets: Dictionary = standard.get("budgets", {})
	_expect(int(corpus.get("scenario_count", 0)) >= int(budgets.get("minimum_scenario_count", 0)), "TQP-30 scenario coverage is incomplete", failures)
	var expected: Dictionary = standard.get("stable_expected", {})
	_expect(not str(expected.get("scenario_corpus_signature", "")).is_empty(), "TQP-30 standard lacks corpus signature", failures)
	_expect(str(corpus.get("signature", "")) == str(expected.get("scenario_corpus_signature", "")), "TQP-30 corpus signature changed", failures)
	var expected_scenarios: Dictionary = expected.get("scenarios", {})
	var observed_scenarios := {}
	for scenario_value in corpus.get("scenarios", []):
		var scenario: Dictionary = scenario_value
		var scenario_id := str(scenario.get("scenario_id", ""))
		observed_scenarios[scenario_id] = true
		_expect(str(scenario.get("status", "")) == "PASS", scenario_id + " adaptive selection failed", failures)
		_expect(str(scenario.get("signature", "")) == str(expected_scenarios.get(scenario_id, "")), scenario_id + " adaptive selection signature changed", failures)
		_expect(str(scenario.get("signature", "")) == str(scenario.get("warm_signature", "")), scenario_id + " cold/warm selection differs", failures)
		var validation: Dictionary = scenario.get("validation", {})
		for metric in ["overlap_cells", "missing_cells", "misaligned_nodes", "out_of_bounds_nodes", "invalid_lod_nodes", "vertical_incomplete_columns", "neighbor_delta_violations", "invalid_split_records"]:
			_expect(int(validation.get(metric, -1)) == 0, scenario_id + " structural metric failed: " + metric, failures)
		var repro: Dictionary = scenario.get("minimized_repro", {})
		_expect(str(repro.get("runner", "")).ends_with("run_adaptive_lod_validation.gd") and (repro.get("arguments", []) as Array).size() == 2, scenario_id + " lacks minimized repro", failures)
	for scenario_value in standard.get("scenarios", []):
		_expect(observed_scenarios.has(str((scenario_value as Dictionary).get("id", ""))), "TQP-30 missing retained scenario", failures)
	var negatives: Dictionary = report.get("negative_controls", {})
	_expect(str(negatives.get("status", "")) == "PASS", "TQP-30 negative controls failed", failures)
	_expect(int(negatives.get("control_count", 0)) >= int(budgets.get("minimum_negative_control_count", 0)), "TQP-30 negative-control coverage is incomplete", failures)
	var performance: Dictionary = report.get("performance", {})
	var distribution: Dictionary = performance.get("scenario_distribution", {})
	_expect(int(distribution.get("sample_count", 0)) >= int(budgets.get("minimum_scenario_count", 0)), "TQP-30 timing distribution is incomplete", failures)
	_expect(float(distribution.get("p95_usec", INF)) <= float(budgets.get("maximum_scenario_p95_usec", 0.0)), "TQP-30 scenario p95 exceeded", failures)
	_expect(int(performance.get("elapsed_usec", 0)) <= int(budgets.get("maximum_total_usec", 0)), "TQP-30 total duration exceeded", failures)
	var provenance: Dictionary = report.get("provenance", {})
	for key in ["workload_signature", "build_type", "os", "architecture", "cpu", "driver", "godot_version", "backend_revision"]:
		_expect(not str(provenance.get(key, "")).is_empty(), "TQP-30 provenance lacks " + key, failures)
	return {
		"schema": "world_transvoxel.terrain_lab.adaptive_lod_evidence_validation.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"qualification_status": "QUALIFIED_BOUNDED_ADAPTIVE_LOD_SELECTION_WINDOWS_V1" if failures.is_empty() else "FAILED",
		"scope_status": {"TQP-30": "qualified_bounded_adaptive_lod_selection_contract_v1" if failures.is_empty() else "failed_adaptive_lod_selection"},
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


static func _expect(condition: bool, failure: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(failure)
