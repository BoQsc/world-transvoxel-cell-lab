@tool
extends RefCounted
class_name WtTerrainLabAdaptiveStreamingEvidence

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/adaptive_streaming_residency_standard.json"
)


static func validate_retained() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	return validate_report(
		JsonLoader.load_dictionary(str(standard.get("evidence", ""))),
		JsonLoader.load_dictionary(str(standard.get("motion_evidence", ""))), standard
	)


static func validate_report(report: Dictionary, motion: Dictionary = {}, standard: Dictionary = {}) -> Dictionary:
	if standard.is_empty():
		standard = JsonLoader.load_dictionary(STANDARD_PATH)
	if motion.is_empty():
		motion = JsonLoader.load_dictionary(str(standard.get("motion_evidence", "")))
	var failures: Array[String] = []
	_expect(str(report.get("schema", "")) == "world_transvoxel.terrain_lab.adaptive_streaming_residency_qualification.v1", "TQP-40 report schema changed", failures)
	_expect(str(report.get("milestone", "")) == "TQP-40", "TQP-40 milestone changed", failures)
	_expect(str(report.get("status", "")) == "PASS", "TQP-40 retained report failed", failures)
	_expect(bool(report.get("retained_complete", false)), "TQP-40 report is filtered", failures)
	_expect(str(report.get("authority", "")) == "world_transvoxel_native_runtime", "TQP-40 authority changed", failures)
	var actions: Dictionary = report.get("actions", {})
	for action_value in (standard.get("workload", {}) as Dictionary).get("required_actions", []):
		var action := str(action_value)
		_expect(str(actions.get(action, "")) == "PASS", "TQP-40 action failed: " + action, failures)
	var expected: Dictionary = standard.get("stable_expected", {})
	for pair in [["cave_residency", "cave"], ["multi_viewer_residency", "multi_viewer"], ["teleport_residency", "teleport"]]:
		var snapshot: Dictionary = report.get(pair[0], {})
		var prefix := str(pair[1])
		_expect(str(snapshot.get("state_signature", "")) == str(expected.get(prefix + "_state_signature", "")), "TQP-40 state signature changed: " + prefix, failures)
		_expect(_lod_counts_equal(snapshot.get("lod_counts", {}), expected.get(prefix + "_lod_counts", {})), "TQP-40 LOD distribution changed: " + prefix, failures)
		_expect(int(snapshot.get("generation_mismatch_count", -1)) == 0, "TQP-40 unsettled state retained: " + prefix, failures)
	var vertical: Dictionary = report.get("vertical_cave_audit", {})
	_expect(str(vertical.get("status", "")) == "PASS" and bool(vertical.get("below_viewer", false)) and bool(vertical.get("above_viewer", false)), "TQP-40 vertical cave crossings are incomplete", failures)
	_expect((report.get("prefetch_unique_keys", []) as Array).size() > 0, "TQP-40 prefetch contribution is empty", failures)
	var origin: Dictionary = report.get("presentation_origin_rebase", {})
	_expect(str(origin.get("status", "")) == "PASS" and str(origin.get("scope", "")) == "consumer_presentation_root_transform" and bool(origin.get("local_resource_unchanged", false)) and bool(origin.get("global_delta_matches", false)), "TQP-40 presentation origin rebase changed", failures)
	_expect((report.get("teleport_retained_old_keys", []) as Array).is_empty(), "TQP-40 teleport retained old keys", failures)
	_expect((report.get("teleport_retained_old_resources", []) as Array).is_empty(), "TQP-40 teleport retained old resources", failures)
	_expect(str((report.get("bounded_residency", {}) as Dictionary).get("status", "")) == "PASS", "TQP-40 bounded residency failed", failures)
	var drain: Dictionary = report.get("drain_metrics", {})
	_expect(int(drain.get("active_chunk_records", -1)) == 0 and int(drain.get("render_resources", -1)) == 0 and int(drain.get("collision_resources", -1)) == 0, "TQP-40 retirement did not drain", failures)
	for signature_id in ["semantic_signature"]:
		var stable := str(expected.get(signature_id, ""))
		_expect(not stable.is_empty(), "TQP-40 expected signature is absent: " + signature_id, failures)
		_expect(str(report.get(signature_id, "")) == stable, "TQP-40 signature changed: " + signature_id, failures)
	_validate_motion(motion, standard, failures)
	_validate_provenance(report.get("provenance", {}), failures)
	return {
		"schema": "world_transvoxel.terrain_lab.adaptive_streaming_residency_evidence_validation.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"scope_status": {"TQP-40": "qualified_native_multi_layer_adaptive_streaming_v1" if failures.is_empty() else "failed_adaptive_streaming"},
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


static func _validate_motion(motion: Dictionary, standard: Dictionary, failures: Array[String]) -> void:
	_expect(str(motion.get("schema", "")) == "world_transvoxel.terrain_lab.adaptive_streaming_residency_motion.v1", "TQP-40 motion schema changed", failures)
	_expect(str(motion.get("status", "")) == "PASS", "TQP-40 motion evidence failed", failures)
	_expect(str(motion.get("scene", "")) == str(standard.get("observatory_scene", "")), "TQP-40 observatory scene changed", failures)
	var observed := {}
	for capture_value in motion.get("captures", []):
		var capture: Dictionary = capture_value
		var mode := str(capture.get("mode", ""))
		observed[mode] = true
		var path := str(capture.get("path", ""))
		_expect(FileAccess.file_exists(path), "TQP-40 capture missing: " + mode, failures)
		if FileAccess.file_exists(path):
			_expect(FileAccess.get_sha256(path) == str(capture.get("sha256", "")), "TQP-40 capture changed: " + mode, failures)
		_expect(int(capture.get("surface_samples", 0)) >= 250, "TQP-40 terrain absent: " + mode, failures)
	for mode in ["cave", "multi_viewer", "teleport"]:
		_expect(observed.has(mode), "TQP-40 capture mode missing: " + mode, failures)


static func _validate_provenance(value: Variant, failures: Array[String]) -> void:
	var provenance: Dictionary = value
	for key in ["workload_signature", "build_type", "os", "architecture", "cpu", "driver", "godot_version", "backend_revision"]:
		_expect(not str(provenance.get(key, "")).is_empty(), "TQP-40 provenance lacks " + key, failures)


static func _lod_counts_equal(actual_value: Variant, expected_value: Variant) -> bool:
	var actual: Dictionary = actual_value
	var expected: Dictionary = expected_value
	if actual.size() != expected.size():
		return false
	for key in expected:
		if not actual.has(key) or int(actual.get(key, -1)) != int(expected.get(key, -2)):
			return false
	return true


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
