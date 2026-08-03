@tool
extends RefCounted
class_name WtTerrainLabEditInvalidationEvidence

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/edit_invalidation_standard.json"
)


static func validate_retained() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var report := JsonLoader.load_dictionary(str(standard.get("evidence", "")))
	var result := validate_report(report)
	var failures: Array = result.get("failures", [])
	failures.append_array(_validate_motion(standard).get("failures", []))
	result["status"] = "PASS" if failures.is_empty() else "FAIL"
	result["failures"] = failures
	return result


static func validate_report(report: Dictionary) -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var failures: Array[String] = []
	_expect(
		str(report.get("schema", ""))
			== "world_transvoxel.terrain_lab.edit_invalidation_qualification.v1",
		"TQP-36 report schema changed",
		failures
	)
	_expect(str(report.get("milestone", "")) == "TQP-36", "TQP-36 milestone changed", failures)
	_expect(str(report.get("status", "")) == "PASS", "TQP-36 retained report failed", failures)
	_expect(bool(report.get("retained_complete", false)), "TQP-36 report is filtered", failures)
	_expect(
		str(report.get("authority", "")) == "world_transvoxel_native_runtime",
		"TQP-36 authority changed",
		failures
	)
	var coverage: Dictionary = report.get("coverage", {})
	var actions: Dictionary = coverage.get("actions", {})
	for action_value in (standard.get("workload", {}) as Dictionary).get("required_actions", []):
		var action := str(action_value)
		_expect(str(actions.get(action, "")) == "PASS", "TQP-36 action failed: " + action, failures)
	_expect(int(coverage.get("scenario_count", 0)) == 7, "TQP-36 scenario matrix is incomplete", failures)
	_expect(int(coverage.get("exact_affected_set_scenarios", 0)) == 7, "TQP-36 exact-set coverage is incomplete", failures)
	_expect(int(coverage.get("oracle_benchmark_samples", 0)) >= 100, "TQP-36 oracle benchmark is too short", failures)
	_expect(
		int(coverage.get("retained_trace_rows", 0))
			== (report.get("frame_trace", []) as Array).size(),
		"TQP-36 frame trace is incomplete",
		failures
	)
	var invariants: Dictionary = report.get("temporal_invariants", {})
	for metric in [
		"visible_hole_frames",
		"render_overlap_frames",
		"double_collision_frames",
		"frame_failure_count",
	]:
		_expect(int(invariants.get(metric, -1)) == 0, "TQP-36 invariant failed: " + metric, failures)
	var scenario_by_id := {}
	for scenario_value in report.get("scenarios", []):
		var scenario: Dictionary = scenario_value
		scenario_by_id[str(scenario.get("id", ""))] = scenario
		_expect(
			str(scenario.get("expected_signature", ""))
				== str(scenario.get("changed_signature", "")),
			"TQP-36 affected set differs: " + str(scenario.get("id", "")),
			failures
		)
		_expect(
			(scenario.get("expected_ids", []) as Array)
				== (scenario.get("changed_ids", []) as Array),
			"TQP-36 affected IDs differ: " + str(scenario.get("id", "")),
			failures
		)
	_validate_scenario_semantics(scenario_by_id, failures)
	var controls: Dictionary = report.get("controls", {})
	_expect(bool(controls.get("oracle_independent_of_native_spatial_query", false)), "TQP-36 oracle authority is circular", failures)
	_expect(bool(controls.get("active_enumeration_includes_empty_payloads", false)), "TQP-36 omitted empty active payloads", failures)
	_expect(bool(controls.get("rapid_publication_held", false)), "TQP-36 rapid publication was not held", failures)
	_expect(int(controls.get("rapid_stale_rejections", 0)) > 0, "TQP-36 stale-result control is absent", failures)
	_expect(int(controls.get("rapid_cancelled_generations", 0)) >= 4, "TQP-36 cancellation control is incomplete", failures)
	var stable: Dictionary = standard.get("stable_expected", {})
	for signature in ["scenario_matrix_signature", "final_active_key_signature"]:
		_expect(
			str(report.get(signature, "")) == str(stable.get(signature, ""))
				and not str(report.get(signature, "")).is_empty(),
			"TQP-36 stable signature changed: " + signature,
			failures
		)
	var performance: Dictionary = report.get("performance", {})
	for distribution_id in ["frame", "edit_settlement", "oracle"]:
		var distribution: Dictionary = performance.get(distribution_id, {})
		for metric in ["sample_count", "p50_usec", "p95_usec", "p99_usec", "worst_usec"]:
			_expect(distribution.has(metric), "TQP-36 performance lacks " + distribution_id + "." + metric, failures)
	var memory: Dictionary = performance.get("memory", {})
	_expect(int(memory.get("retained_bytes", 0)) > 0 and int(memory.get("peak_bytes", 0)) > 0, "TQP-36 memory telemetry is invalid", failures)
	var provenance: Dictionary = report.get("provenance", {})
	for key in [
		"workload_signature", "build_type", "os", "architecture", "cpu",
		"driver", "godot_version", "backend_revision",
	]:
		_expect(not str(provenance.get(key, "")).is_empty(), "TQP-36 provenance lacks " + key, failures)
	return {
		"schema": "world_transvoxel.terrain_lab.edit_invalidation_evidence_validation.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"scope_status": {
			"TQP-36": "qualified_native_edit_invalidation_v1"
				if failures.is_empty() else "failed_edit_invalidation"
		},
		"failures": failures,
	}


static func _validate_scenario_semantics(
	scenarios: Dictionary,
	failures: Array[String]
) -> void:
	var coarse: Dictionary = scenarios.get("coarse_parent_interior", {})
	var fine: Dictionary = scenarios.get("fine_child_interior", {})
	var boundary: Dictionary = scenarios.get("same_lod_boundary_halo", {})
	var mixed: Dictionary = scenarios.get("mixed_lod_transition_dependency", {})
	var batch: Dictionary = scenarios.get("disjoint_batch_union", {})
	var noop: Dictionary = scenarios.get("unloaded_noop", {})
	var rapid: Dictionary = scenarios.get("rapid_supersession", {})
	_expect(int((coarse.get("lod_histogram", {}) as Dictionary).get("1", 0)) > 0, "TQP-36 coarse parent was not exercised", failures)
	_expect(int((fine.get("lod_histogram", {}) as Dictionary).get("0", 0)) > 0, "TQP-36 fine child was not exercised", failures)
	_expect((boundary.get("expected_ids", []) as Array).size() >= 2, "TQP-36 same-LOD halo lacks a neighbor", failures)
	_expect(int((mixed.get("lod_histogram", {}) as Dictionary).get("0", 0)) > 0 and int((mixed.get("lod_histogram", {}) as Dictionary).get("1", 0)) > 0 and int(mixed.get("transition_mesh_completions_delta", 0)) > 0, "TQP-36 transition dependency was not rebuilt", failures)
	_expect(int(batch.get("command_count", 0)) == 2 and int(batch.get("replaced_chunks_delta", 0)) == (batch.get("expected_ids", []) as Array).size(), "TQP-36 disjoint batch replacement is not exact", failures)
	_expect((noop.get("expected_ids", []) as Array).is_empty() and int(noop.get("replaced_chunks_delta", -1)) == 0 and int(noop.get("empty_transactions_delta", 0)) == 1, "TQP-36 no-op edit rebuilt terrain", failures)
	_expect(bool(rapid.get("publication_held", false)) and int(rapid.get("stale_rejections_delta", 0)) > 0 and int(rapid.get("replaced_chunks_delta", 0)) == (rapid.get("expected_ids", []) as Array).size() * 2, "TQP-36 rapid supersession evidence is incomplete", failures)


static func _validate_motion(standard: Dictionary) -> Dictionary:
	var motion := JsonLoader.load_dictionary(str(standard.get("motion_evidence", "")))
	var failures: Array[String] = []
	_expect(
		str(motion.get("schema", ""))
			== "world_transvoxel.terrain_lab.edit_invalidation_motion.v1",
		"TQP-36 motion schema changed",
		failures
	)
	_expect(str(motion.get("status", "")) == "PASS", "TQP-36 motion evidence failed", failures)
	_expect(str(motion.get("scene", "")) == str(standard.get("observatory_scene", "")), "TQP-36 motion scene changed", failures)
	var captures: Array = motion.get("captures", [])
	_expect(captures.size() >= 3, "TQP-36 motion capture sequence is incomplete", failures)
	for capture_value in captures:
		var capture: Dictionary = capture_value
		var path := str(capture.get("path", ""))
		_expect(FileAccess.file_exists(path), "TQP-36 motion capture is missing: " + path, failures)
		if FileAccess.file_exists(path):
			_expect(FileAccess.get_sha256(path) == str(capture.get("sha256", "")), "TQP-36 motion capture changed: " + path, failures)
		_expect(int(capture.get("width", 0)) == 1280 and int(capture.get("height", 0)) == 720, "TQP-36 motion dimensions changed", failures)
		_expect(int(capture.get("surface_samples", 0)) >= 250, "TQP-36 terrain is absent from capture", failures)
	return {"status": "PASS" if failures.is_empty() else "FAIL", "failures": failures}


static func _expect(condition: bool, failure: String, failures: Array) -> void:
	if not condition and failure not in failures:
		failures.append(failure)
