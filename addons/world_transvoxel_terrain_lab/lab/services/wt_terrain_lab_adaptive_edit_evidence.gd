@tool
extends RefCounted
class_name WtTerrainLabAdaptiveEditEvidence

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/adaptive_edit_standard.json"
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
			== "world_transvoxel.terrain_lab.adaptive_edit_qualification.v1",
		"TQP-37 report schema changed",
		failures
	)
	_expect(str(report.get("milestone", "")) == "TQP-37", "TQP-37 milestone changed", failures)
	_expect(str(report.get("status", "")) == "PASS", "TQP-37 retained report failed", failures)
	_expect(bool(report.get("retained_complete", false)), "TQP-37 report is filtered", failures)
	_expect(
		str(report.get("authority", "")) == "world_transvoxel_native_runtime",
		"TQP-37 authority changed",
		failures
	)
	var expected_ids: Array[String] = []
	for scenario_value in (standard.get("workload", {}) as Dictionary).get("scenarios", []):
		expected_ids.append(str((scenario_value as Dictionary).get("id", "")))
	var scenarios := {}
	for scenario_value in report.get("scenarios", []):
		var scenario: Dictionary = scenario_value
		var scenario_id := str(scenario.get("id", ""))
		scenarios[scenario_id] = scenario
		_expect(str(scenario.get("status", "")) == "PASS", "TQP-37 scenario failed: " + scenario_id, failures)
		_expect(not str(scenario.get("semantic_signature", "")).is_empty(), "TQP-37 semantic signature is absent: " + scenario_id, failures)
		_validate_topology(scenario_id, scenario.get("topology", {}), failures)
	var actual_ids: Array[String] = []
	for scenario_id in scenarios:
		actual_ids.append(str(scenario_id))
	expected_ids.sort()
	actual_ids.sort()
	_expect(actual_ids == expected_ids and actual_ids.size() == 6, "TQP-37 scenario matrix is incomplete", failures)
	_validate_required_actions(standard, scenarios, failures)
	_validate_scenario_semantics(scenarios, failures)
	var coverage: Dictionary = report.get("coverage", {})
	_expect(int(coverage.get("scenario_count", 0)) == 6, "TQP-37 scenario count changed", failures)
	_expect(int(coverage.get("passed_scenario_count", 0)) == 6, "TQP-37 pass coverage changed", failures)
	_expect(int(coverage.get("dig_scenario_count", 0)) >= 2, "TQP-37 digging coverage is incomplete", failures)
	_expect(int(coverage.get("construction_scenario_count", 0)) >= 3, "TQP-37 construction coverage is incomplete", failures)
	var retained_trace_count := (report.get("frame_trace", []) as Array).size()
	_expect(retained_trace_count > 0 and int(coverage.get("audited_frame_count", 0)) >= retained_trace_count, "TQP-37 sampled frame trace is incomplete", failures)
	var temporal: Dictionary = report.get("temporal_invariants", {})
	for metric in [
		"visible_hole_frames",
		"render_overlap_frames",
		"double_collision_frames",
		"frame_failure_count",
	]:
		_expect(int(temporal.get(metric, -1)) == 0, "TQP-37 temporal invariant failed: " + metric, failures)
	var stable: Dictionary = standard.get("stable_expected", {})
	for signature in ["scenario_matrix_signature", "final_semantic_signature"]:
		_expect(
			str(report.get(signature, "")) == str(stable.get(signature, ""))
				and not str(report.get(signature, "")).is_empty(),
			"TQP-37 stable signature changed: " + signature,
			failures
		)
	var history: Dictionary = report.get("history_policy", {})
	var declared_history: Dictionary = standard.get("history_policy", {})
	_expect(str(history.get("qualified_method", "")) == str(declared_history.get("qualified_method", "")), "TQP-37 history authority changed", failures)
	_expect(str(history.get("in_place_generic_csg_undo", "")) == str(declared_history.get("in_place_generic_csg_undo", "")), "TQP-37 overclaims generic in-place undo", failures)
	var resources: Dictionary = report.get("resources", {})
	_expect(int(resources.get("maximum_active_chunk_records", 0)) > 0, "TQP-37 active records are absent", failures)
	_expect(int(resources.get("maximum_collision_resources", -1)) >= 0, "TQP-37 collision telemetry is absent", failures)
	var runtime_profile: Dictionary = standard.get("runtime_profile", {})
	_expect(float(runtime_profile.get("collision_activation_distance", 0.0)) > 0.0 and float(runtime_profile.get("collision_deactivation_distance", 0.0)) > float(runtime_profile.get("collision_activation_distance", 0.0)), "TQP-37 bounded collision hysteresis profile changed", failures)
	_validate_performance(report.get("performance", {}), failures)
	var provenance: Dictionary = report.get("provenance", {})
	for key in [
		"workload_signature", "build_type", "os", "architecture", "cpu",
		"driver", "godot_version", "backend_revision",
	]:
		_expect(not str(provenance.get(key, "")).is_empty(), "TQP-37 provenance lacks " + key, failures)
	return {
		"schema": "world_transvoxel.terrain_lab.adaptive_edit_evidence_validation.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"scope_status": {
			"TQP-37": "qualified_adaptive_editing_v1"
				if failures.is_empty() else "failed_adaptive_editing"
		},
		"failures": failures,
	}


static func _validate_topology(
	scenario_id: String,
	value: Variant,
	failures: Array[String]
) -> void:
	var topology: Dictionary = value
	_expect(str(topology.get("status", "")) == "PASS", "TQP-37 topology failed: " + scenario_id, failures)
	for metric in [
		"exact_duplicate_triangle_count",
		"degenerate_triangle_count",
		"nonfinite_triangle_count",
	]:
		_expect(int(topology.get(metric, -1)) == 0, "TQP-37 topology defect in %s: %s" % [scenario_id, metric], failures)
	_expect(int(topology.get("triangle_count", 0)) > 0, "TQP-37 terrain is absent: " + scenario_id, failures)
	for interface_value in topology.get("interfaces", []):
		var interface: Dictionary = interface_value
		_expect(int(interface.get("negative_only_count", -1)) == 0 and int(interface.get("positive_only_count", -1)) == 0, "TQP-37 exact interface edge mismatch: " + scenario_id, failures)


static func _validate_required_actions(
	standard: Dictionary,
	scenarios: Dictionary,
	failures: Array[String]
) -> void:
	for scenario_value in (standard.get("workload", {}) as Dictionary).get("scenarios", []):
		var declared: Dictionary = scenario_value
		var scenario_id := str(declared.get("id", ""))
		var retained: Dictionary = scenarios.get(scenario_id, {})
		var retained_actions: Dictionary = retained.get("actions", {})
		for action_value in declared.get("actions", []):
			var action := str(action_value)
			var action_passed := str(
				(retained_actions.get(action, {}) as Dictionary).get("status", "")
			) == "PASS"
			match action:
				"commit_while_unloaded":
					action_passed = int(retained.get("edit_replacements", -1)) == 0
				"load_later":
					action_passed = str((retained.get("topology", {}) as Dictionary).get("status", "")) == "PASS" and str(retained.get("baseline_sample_signature", "")) != str(retained.get("edited_sample_signature", ""))
				"reconstructive_undo", "reconstructive_redo":
					var history: Dictionary = retained_actions.get("reconstructive_history", {})
					action_passed = str(history.get("status", "")) == "PASS" and not str(history.get("undo_sample_signature", "")).is_empty() and not str(history.get("redo_sample_signature", "")).is_empty()
			_expect(action_passed, "TQP-37 action failed: %s.%s" % [scenario_id, action], failures)


static func _validate_scenario_semantics(
	scenarios: Dictionary,
	failures: Array[String]
) -> void:
	var transition: Dictionary = scenarios.get("transition_face_carve", {})
	var corner: Dictionary = scenarios.get("chunk_edge_corner_construction", {})
	var repeated: Dictionary = scenarios.get("repeated_transition_tunnel", {})
	var under_resolved: Dictionary = scenarios.get("under_resolved_later_refinement", {})
	var unloaded: Dictionary = scenarios.get("unloaded_edit_then_load", {})
	var history: Dictionary = scenarios.get("reconstructive_undo_redo", {})
	_expect(str(transition.get("baseline_sample_signature", "")) != str(transition.get("edited_sample_signature", "")), "TQP-37 transition carve changed no authoritative samples", failures)
	_expect(str(corner.get("baseline_sample_signature", "")) != str(corner.get("edited_sample_signature", "")), "TQP-37 corner construction changed no authoritative samples", failures)
	_expect(int(repeated.get("edit_replacements", 0)) > 0, "TQP-37 repeated tunnel replaced no chunks", failures)
	var refine: Dictionary = (under_resolved.get("actions", {}) as Dictionary).get("coarsen_and_refine", {})
	_expect(str(refine.get("classification", "")) == "under_resolved_then_refined_and_retained", "TQP-37 under-resolved policy changed", failures)
	_expect(int(refine.get("coarse_triangle_count", -1)) == 0 and int(refine.get("fine_triangle_count", 0)) > 0, "TQP-37 under-resolved refinement control changed", failures)
	_expect(int(refine.get("retained_triangle_count", -1)) == int(refine.get("fine_triangle_count", -2)), "TQP-37 refined edit was not retained", failures)
	_expect(int(refine.get("edit_lod_retention_zones", 0)) > 0, "TQP-37 edit LOD retention evidence is absent", failures)
	_expect(int(unloaded.get("edit_replacements", -1)) == 0, "TQP-37 unloaded edit unexpectedly replaced active chunks", failures)
	var replay: Dictionary = (history.get("actions", {}) as Dictionary).get("reconstructive_history", {})
	_expect(str(replay.get("status", "")) == "PASS", "TQP-37 reconstructive history failed", failures)


static func _validate_performance(value: Variant, failures: Array[String]) -> void:
	var performance: Dictionary = value
	_expect(str(performance.get("scope", "")).contains("NOT_PRODUCTION_FRAME_BUDGET"), "TQP-37 performance scope overclaims production", failures)
	for distribution_id in ["frame", "scenario"]:
		var distribution: Dictionary = performance.get(distribution_id, {})
		for metric in ["sample_count", "p50_usec", "p95_usec", "p99_usec", "worst_usec"]:
			_expect(distribution.has(metric), "TQP-37 performance lacks %s.%s" % [distribution_id, metric], failures)
	var memory: Dictionary = performance.get("memory", {})
	_expect(int(memory.get("retained_bytes", 0)) > 0 and int(memory.get("peak_bytes", 0)) > 0, "TQP-37 memory telemetry is invalid", failures)


static func _validate_motion(standard: Dictionary) -> Dictionary:
	var motion := JsonLoader.load_dictionary(str(standard.get("motion_evidence", "")))
	var failures: Array[String] = []
	_expect(str(motion.get("schema", "")) == "world_transvoxel.terrain_lab.adaptive_edit_motion.v1", "TQP-37 motion schema changed", failures)
	_expect(str(motion.get("status", "")) == "PASS", "TQP-37 motion evidence failed", failures)
	_expect(str(motion.get("scene", "")) == str(standard.get("observatory_scene", "")), "TQP-37 motion scene changed", failures)
	var captures: Array = motion.get("captures", [])
	_expect(captures.size() >= 3, "TQP-37 motion capture sequence is incomplete", failures)
	for capture_value in captures:
		var capture: Dictionary = capture_value
		var path := str(capture.get("path", ""))
		_expect(FileAccess.file_exists(path), "TQP-37 motion capture is missing: " + path, failures)
		if FileAccess.file_exists(path):
			_expect(FileAccess.get_sha256(path) == str(capture.get("sha256", "")), "TQP-37 motion capture changed: " + path, failures)
		_expect(int(capture.get("width", 0)) == 1280 and int(capture.get("height", 0)) == 720, "TQP-37 motion dimensions changed", failures)
		_expect(int(capture.get("surface_samples", 0)) >= 250, "TQP-37 terrain is absent from capture", failures)
	return {"status": "PASS" if failures.is_empty() else "FAIL", "failures": failures}


static func _expect(condition: bool, failure: String, failures: Array) -> void:
	if not condition and failure not in failures:
		failures.append(failure)
