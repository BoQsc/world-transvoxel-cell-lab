@tool
extends RefCounted
class_name WtTerrainLabDynamicLodPublicationEvidence

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/dynamic_lod_publication_standard.json"
)


static func validate_retained() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var report := JsonLoader.load_dictionary(str(standard.get("evidence", "")))
	var motion := JsonLoader.load_dictionary(str(standard.get("motion_evidence", "")))
	return validate_report(report, motion, standard)


static func validate_report(
	report: Dictionary,
	motion: Dictionary = {},
	standard: Dictionary = {}
) -> Dictionary:
	if standard.is_empty():
		standard = JsonLoader.load_dictionary(STANDARD_PATH)
	if motion.is_empty():
		motion = JsonLoader.load_dictionary(str(standard.get("motion_evidence", "")))
	var failures: Array[String] = []
	_expect(
		str(report.get("schema", ""))
			== "world_transvoxel.terrain_lab.dynamic_lod_publication_qualification.v1",
		"TQP-35 report schema changed", failures
	)
	_expect(str(report.get("milestone", "")) == "TQP-35", "TQP-35 milestone changed", failures)
	_expect(str(report.get("status", "")) == "PASS", "TQP-35 retained report failed", failures)
	_expect(bool(report.get("retained_complete", false)), "TQP-35 report is filtered", failures)
	_expect(str(report.get("authority", "")) == "world_transvoxel_native_runtime", "TQP-35 authority changed", failures)

	var coverage: Dictionary = report.get("coverage", {})
	var actions: Dictionary = coverage.get("actions", {})
	for action_value in (standard.get("workload", {}) as Dictionary).get("required_actions", []):
		var action := str(action_value)
		_expect(str(actions.get(action, "")) == "PASS", "TQP-35 action failed: " + action, failures)
	for metric in [
		"audited_frame_count", "split_observations", "merge_observations",
		"replacement_frames", "transition_mesh_completions",
		"coalesced_viewer_events", "stale_application_rejections",
	]:
		_expect(int(coverage.get(metric, 0)) > 0, "TQP-35 coverage is absent: " + metric, failures)
	for control in [
		"stale_viewer_revision_rejected", "presentation_rebase_state_stable",
		"unload_clean", "reload_signature_agreed",
	]:
		_expect(bool(coverage.get(control, false)), "TQP-35 control failed: " + control, failures)
	_expect(
		int(coverage.get("retained_trace_rows", 0)) == int(coverage.get("audited_frame_count", -1)),
		"TQP-35 frame trace is incomplete", failures
	)
	_expect(
		(report.get("frame_trace", []) as Array).size() == int(coverage.get("retained_trace_rows", -1)),
		"TQP-35 retained trace row count changed", failures
	)

	var invariants: Dictionary = report.get("temporal_invariants", {})
	for metric in [
		"visible_hole_frames", "render_overlap_frames", "double_collision_frames",
		"generation_incoherence_count", "same_generation_material_mutation_count",
		"frame_failure_count",
	]:
		_expect(int(invariants.get(metric, -1)) == 0, "TQP-35 invariant failed: " + metric, failures)

	var expected: Dictionary = standard.get("stable_expected", {})
	for signature_id in ["checkpoint_matrix_signature", "reload_state_signature"]:
		var expected_signature := str(expected.get(signature_id, ""))
		_expect(not expected_signature.is_empty(), "TQP-35 expected signature is missing: " + signature_id, failures)
		_expect(str(report.get(signature_id, "")) == expected_signature, "TQP-35 signature changed: " + signature_id, failures)
	_expect((report.get("checkpoints", []) as Array).size() >= 8, "TQP-35 checkpoint matrix is incomplete", failures)

	var budgets: Dictionary = standard.get("budgets", {})
	var resources: Dictionary = report.get("resources", {})
	for pair in [
		["maximum_active_chunk_records", "maximum_active_chunk_records"],
		["maximum_render_resources", "maximum_render_resources"],
		["maximum_collision_resources", "maximum_collision_resources"],
		["maximum_render_queue", "maximum_render_queue"],
		["maximum_collision_queue", "maximum_collision_queue"],
	]:
		_expect(
			int(resources.get(pair[0], -1)) >= 0
				and int(resources.get(pair[0], 9223372036854775807)) <= int(budgets.get(pair[1], -1)),
			"TQP-35 resource budget failed: " + str(pair[0]), failures
		)
	var performance: Dictionary = report.get("performance", {})
	for distribution_id in ["frame", "action_settlement"]:
		var distribution: Dictionary = performance.get(distribution_id, {})
		for metric in ["sample_count", "p50_usec", "p95_usec", "p99_usec", "worst_usec"]:
			_expect(distribution.has(metric), "TQP-35 performance lacks " + distribution_id + "." + metric, failures)
	var memory: Dictionary = performance.get("memory", {})
	_expect(
		int(memory.get("retained_bytes", 0)) > 0
			and int(memory.get("peak_bytes", 0)) >= int(memory.get("retained_bytes", 0)),
		"TQP-35 memory telemetry is invalid", failures
	)
	var provenance: Dictionary = report.get("provenance", {})
	for key in [
		"workload_signature", "build_type", "os", "architecture", "cpu",
		"driver", "godot_version", "backend_revision",
	]:
		_expect(not str(provenance.get(key, "")).is_empty(), "TQP-35 provenance lacks " + key, failures)

	_validate_motion(motion, standard, failures)
	return {
		"schema": "world_transvoxel.terrain_lab.dynamic_lod_publication_evidence_validation.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"qualification_status": "QUALIFIED_NATIVE_DYNAMIC_LOD_PUBLICATION_V1" if failures.is_empty() else "FAILED",
		"scope_status": {"TQP-35": "qualified_native_dynamic_lod_publication_v1" if failures.is_empty() else "failed_dynamic_publication"},
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


static func _validate_motion(
	motion: Dictionary,
	standard: Dictionary,
	failures: Array[String]
) -> void:
	_expect(
		str(motion.get("schema", ""))
			== "world_transvoxel.terrain_lab.dynamic_lod_publication_motion.v1",
		"TQP-35 motion schema changed", failures
	)
	_expect(str(motion.get("status", "")) == "PASS", "TQP-35 motion evidence failed", failures)
	_expect(str(motion.get("scene", "")) == str(standard.get("observatory_scene", "")), "TQP-35 motion scene changed", failures)
	var captures: Array = motion.get("captures", [])
	_expect(captures.size() >= 4, "TQP-35 motion capture sequence is incomplete", failures)
	var observed := {}
	for capture_value in captures:
		var capture: Dictionary = capture_value
		var action := str(capture.get("action", ""))
		observed[action] = true
		var path := str(capture.get("path", ""))
		_expect(FileAccess.file_exists(path), "TQP-35 motion capture is missing: " + action, failures)
		if FileAccess.file_exists(path):
			_expect(FileAccess.get_sha256(path) == str(capture.get("sha256", "")), "TQP-35 motion capture changed: " + action, failures)
		_expect(int(capture.get("width", 0)) == 1280 and int(capture.get("height", 0)) == 720, "TQP-35 motion dimensions changed: " + action, failures)
		_expect(int(capture.get("surface_samples", 0)) >= 250, "TQP-35 terrain is absent from capture: " + action, failures)
		var snapshot: Dictionary = capture.get("snapshot", {})
		_expect(str(snapshot.get("status", "")) == "PASS", "TQP-35 motion snapshot failed: " + action, failures)
		_expect(int(snapshot.get("collision_overlap_count", -1)) == 0, "TQP-35 motion snapshot has double collision: " + action, failures)
	for action in ["initial_load", "split_approach", "merge_retreat", "rapid_supersession"]:
		_expect(observed.has(action), "TQP-35 motion action is missing: " + action, failures)


static func _expect(condition: bool, failure: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(failure)
