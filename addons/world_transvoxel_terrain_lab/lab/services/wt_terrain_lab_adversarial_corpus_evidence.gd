@tool
extends RefCounted
class_name WtTerrainLabAdversarialCorpusEvidence

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const Qualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_adversarial_corpus_qualification.gd"
)

const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/adversarial_corpus_standard.json"
)
const REPLAY_ORDERS := [
	"cold_canonical",
	"warm_canonical",
	"worker_reverse",
	"worker_seeded",
]


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
			== "world_transvoxel.terrain_lab.adversarial_corpus_qualification.v1",
		"adversarial corpus report schema changed",
		failures
	)
	_expect(str(report.get("milestone", "")) == "TQP-34", "TQP-34 report milestone changed", failures)
	_expect(str(report.get("status", "")) == "PASS", "TQP-34 retained report failed", failures)
	_expect(bool(report.get("retained_complete", false)), "TQP-34 retained report is filtered", failures)
	_expect(str((report.get("contract", {}) as Dictionary).get("status", "")) == "PASS", "TQP-34 contract validation failed", failures)
	var expected: Dictionary = standard.get("stable_expected", {})
	var expected_cases: Dictionary = expected.get("cases", {})
	var expected_definition_signatures := {}
	for definition_value in standard.get("cases", []):
		var definition: Dictionary = definition_value
		expected_definition_signatures[str(definition.get("id", ""))] = JSON.stringify(
			definition
		).sha256_text()
	var observed_cases := {}
	var observed_regressions := {}
	for case_value in report.get("cases", []):
		var case_result: Dictionary = case_value
		var case_id := str(case_result.get("case_id", ""))
		observed_cases[case_id] = true
		_expect(str(case_result.get("status", "")) == "PASS", case_id + " failed", failures)
		var signature := str(case_result.get("geometry_signature", ""))
		_expect(not signature.is_empty(), case_id + " lacks a geometry signature", failures)
		_expect(not str(expected_cases.get(case_id, "")).is_empty(), case_id + " lacks a retained expected signature", failures)
		_expect(signature == str(expected_cases.get(case_id, "")), case_id + " retained geometry changed", failures)
		_expect(str(case_result.get("case_definition_signature", "")) == str(expected_definition_signatures.get(case_id, "")), case_id + " case or oracle definition changed without regenerated evidence", failures)
		var replay_signatures: Dictionary = case_result.get("replay_signatures", {})
		for replay_order in REPLAY_ORDERS:
			_expect(str(replay_signatures.get(replay_order, "")) == signature, case_id + " differs under " + replay_order, failures)
		var replays: Array = case_result.get("replays", [])
		_expect(replays.size() == REPLAY_ORDERS.size(), case_id + " replay matrix is incomplete", failures)
		for replay_value in replays:
			var replay: Dictionary = replay_value
			_expect(str(replay.get("status", "")) == "PASS", case_id + " replay failed", failures)
			_expect(str((replay.get("oracle", {}) as Dictionary).get("status", "")) == "PASS", case_id + " replay independent oracle failed", failures)
		var repro: Dictionary = case_result.get("minimized_repro", {})
		_expect(str(repro.get("runner", "")).ends_with("run_adversarial_corpus_validation.gd"), case_id + " lacks a focused repro", failures)
		_expect(
			(repro.get("arguments", []) as Array) == ["--case", case_id],
			case_id + " focused repro arguments changed",
			failures
		)
		var decision_id := str(case_result.get("regression_decision", ""))
		if not decision_id.is_empty():
			observed_regressions[decision_id] = true
	for definition_value in standard.get("cases", []):
		var definition: Dictionary = definition_value
		_expect(observed_cases.has(str(definition.get("id", ""))), "TQP-34 retained case is missing", failures)
	for decision_id in ["TQP-D011", "TQP-D018", "TQP-D019"]:
		_expect(observed_regressions.has(decision_id), "TQP-34 regression is missing: " + decision_id, failures)
	var coverage: Dictionary = report.get("coverage", {})
	var budgets: Dictionary = standard.get("budgets", {})
	_expect(int(coverage.get("case_count", 0)) >= int(budgets.get("minimum_case_count", 0)), "TQP-34 case coverage is incomplete", failures)
	_expect((coverage.get("unique_seeds", []) as Array).size() >= int(budgets.get("minimum_unique_seed_count", 0)), "TQP-34 seed coverage is incomplete", failures)
	_expect(int(coverage.get("seeded_case_count", 0)) >= int(budgets.get("minimum_seeded_case_count", 0)), "TQP-34 seeded-case coverage is incomplete", failures)
	_expect((coverage.get("generated_field_profiles", []) as Array).size() >= int(budgets.get("minimum_generated_field_profile_count", 0)), "TQP-34 generated-field coverage is incomplete", failures)
	_expect((coverage.get("case_profiles", []) as Array).size() >= int(budgets.get("minimum_case_profile_count", 0)), "TQP-34 case-profile coverage is incomplete", failures)
	_expect((coverage.get("lod_levels", []) as Array).size() >= int(budgets.get("minimum_lod_level_count", 0)), "TQP-34 LOD coverage is incomplete", failures)
	_expect((coverage.get("transition_faces", []) as Array).size() >= int(budgets.get("minimum_transition_face_count", 0)), "TQP-34 transition-face coverage is incomplete", failures)
	_expect((coverage.get("material_ids", []) as Array).size() >= int(budgets.get("minimum_material_id_count", 0)), "TQP-34 material coverage is incomplete", failures)
	_expect(int(coverage.get("native_chunk_call_count", 0)) >= int(budgets.get("minimum_native_chunk_call_count", 0)), "TQP-34 native-call coverage is incomplete", failures)
	_expect(int(coverage.get("exact_isovalue_hit_count", 0)) > 0, "TQP-34 exact-isovalue coverage is absent", failures)
	_expect("million_grid" in coverage.get("coordinate_classes", []), "TQP-34 million-grid coverage is absent", failures)
	_expect(coverage.get("replay_orders", []) == REPLAY_ORDERS, "TQP-34 replay-order inventory changed", failures)
	_expect(not str(expected.get("matrix_signature", "")).is_empty(), "TQP-34 retained matrix signature is missing", failures)
	_expect(str(report.get("matrix_signature", "")) == str(expected.get("matrix_signature", "")), "TQP-34 matrix signature changed", failures)
	var minimizer: Dictionary = report.get("minimizer_control", {})
	_expect(str(minimizer.get("status", "")) == "PASS", "TQP-34 minimizer control failed", failures)
	_expect(bool(minimizer.get("injected_failure_detected", false)), "TQP-34 minimizer source defect was not detected", failures)
	_expect(int(minimizer.get("minimized_triangle_count", 0)) == 2, "TQP-34 minimizer did not reach two triangles", failures)
	_expect(str(minimizer.get("fixture_signature", "")) == str(minimizer.get("replay_signature", "")), "TQP-34 minimized failure replay differs", failures)
	_expect(not str(expected.get("minimized_fixture_signature", "")).is_empty(), "TQP-34 retained minimized signature is missing", failures)
	_expect(str(minimizer.get("fixture_signature", "")) == str(expected.get("minimized_fixture_signature", "")), "TQP-34 minimized fixture changed", failures)
	var minimized_replay := Qualification.replay_minimized_fixture(minimizer.get("fixture", {}))
	_expect(str(minimized_replay.get("status", "")) == "PASS", "TQP-34 serialized minimized fixture no longer reproduces", failures)
	_expect(str(minimized_replay.get("fixture_signature", "")) == str(minimizer.get("fixture_signature", "")), "TQP-34 serialized minimized fixture signature changed", failures)
	var performance: Dictionary = report.get("performance", {})
	for distribution_id in ["case_distribution", "replay_distribution", "oracle_distribution"]:
		var distribution: Dictionary = performance.get(distribution_id, {})
		for metric in ["sample_count", "p50_usec", "p95_usec", "p99_usec", "worst_usec"]:
			_expect(distribution.has(metric), "TQP-34 performance lacks " + distribution_id + "." + metric, failures)
	var memory: Dictionary = performance.get("memory", {})
	_expect(int(memory.get("retained_bytes", 0)) > 0 and int(memory.get("peak_bytes", 0)) >= int(memory.get("retained_bytes", 0)), "TQP-34 memory telemetry is invalid", failures)
	var provenance: Dictionary = report.get("provenance", {})
	for key in ["workload_signature", "build_type", "os", "architecture", "cpu", "driver", "godot_version", "backend_revision"]:
		_expect(not str(provenance.get(key, "")).is_empty(), "TQP-34 provenance lacks " + key, failures)
	var editor_inspection: Dictionary = standard.get("editor_inspection", {})
	var scene_path := str(editor_inspection.get("scene", ""))
	var capture_path := str(editor_inspection.get("capture", ""))
	_expect(FileAccess.file_exists(scene_path), "TQP-34 editor observatory scene is missing", failures)
	_expect(FileAccess.file_exists(capture_path), "TQP-34 editor observatory capture is missing", failures)
	if FileAccess.file_exists(capture_path):
		_expect(FileAccess.get_sha256(capture_path) == str(editor_inspection.get("capture_sha256", "")), "TQP-34 editor capture changed", failures)
	_expect(int(editor_inspection.get("width", 0)) == 1280 and int(editor_inspection.get("height", 0)) == 720, "TQP-34 editor capture dimensions changed", failures)
	_expect(str(editor_inspection.get("automation_status", "")) == "PASS", "TQP-34 editor inspection automation failed", failures)
	return {
		"schema": "world_transvoxel.terrain_lab.adversarial_corpus_evidence_validation.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"qualification_status": "QUALIFIED_SEEDED_ADVERSARIAL_NATIVE_CORPUS_V1" if failures.is_empty() else "FAILED",
		"scope_status": {"TQP-34": "qualified_seeded_adversarial_minimized_corpus_v1" if failures.is_empty() else "failed_adversarial_corpus"},
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


static func _expect(condition: bool, failure: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(failure)
