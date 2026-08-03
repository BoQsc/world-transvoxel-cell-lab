@tool
extends RefCounted
class_name WtTerrainLabAdaptivePersistenceEvidence

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/adaptive_persistence_standard.json"
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
	_expect(str(report.get("schema", "")) == "world_transvoxel.terrain_lab.adaptive_persistence_qualification.v1", "TQP-41 report schema changed", failures)
	_expect(str(report.get("milestone", "")) == "TQP-41", "TQP-41 milestone changed", failures)
	_expect(str(report.get("status", "")) == "PASS", "TQP-41 retained report failed", failures)
	_expect(bool(report.get("retained_complete", false)), "TQP-41 report is filtered", failures)
	_expect(str(report.get("authority", "")) == "world_transvoxel_native_runtime_and_native_dense_baker", "TQP-41 authority changed", failures)
	var actions: Dictionary = report.get("actions", {})
	for action_value in (standard.get("workload", {}) as Dictionary).get("required_actions", []):
		var action := str(action_value)
		_expect(str(actions.get(action, "")) == "PASS", "TQP-41 action failed: " + action, failures)
	var fixture: Dictionary = report.get("fixture", {})
	_expect(str(fixture.get("schema", "")) == "world_transvoxel.terrain_lab.adaptive_persistence_fixture.v1", "TQP-41 fixture schema changed", failures)
	_expect(int(fixture.get("page_count", -1)) == int((standard.get("budgets", {}) as Dictionary).get("expected_fixture_page_count", -2)), "TQP-41 fixture page count changed", failures)
	_expect(str(fixture.get("authority", "")) == "world-transvoxel native dense baker", "TQP-41 fixture authority changed", failures)
	var initial: Dictionary = report.get("initial_residency", {})
	_expect(str(initial.get("state_signature", "")) == str((standard.get("stable_expected", {}) as Dictionary).get("initial_state_signature", "")), "TQP-41 initial adaptive state changed", failures)
	_expect(int(initial.get("ready_mismatch_count", -1)) == 0, "TQP-41 initial residency is unsettled", failures)
	var edited: Dictionary = report.get("edited_queries", {})
	_expect((edited.get("central", []) as Array).size() == 4, "TQP-41 central query corpus changed", failures)
	_expect(int((edited.get("distant", {}) as Dictionary).get("material", -1)) == 7, "TQP-41 distant material edit changed", failures)
	var crash: Dictionary = report.get("crash_recovery", {})
	_expect(bool(crash.get("started", false)) and int(crash.get("world_revision", -1)) == 1, "TQP-41 transaction-prefix recovery changed", failures)
	var inherited: Dictionary = report.get("inherited_truncated_tail_recovery", {})
	_expect(str(inherited.get("status", "")) == "PASS" and bool(inherited.get("recovered", false)), "TQP-41 inherited TQP-26 truncated-tail recovery changed", failures)
	var compaction: Dictionary = report.get("compaction", {})
	_expect(str(compaction.get("status", "")) == "PASS" and int(compaction.get("page_count", -1)) == 44 and int(compaction.get("world_revision", -1)) == 2, "TQP-41 compaction metadata changed", failures)
	var interrupted: Dictionary = report.get("interrupted_staging", {})
	_expect(str(interrupted.get("status", "")) == "FAIL" and str(interrupted.get("error", "")) == "world snapshot file writing failed", "TQP-41 interrupted staging did not fail closed", failures)
	var migration: Dictionary = report.get("migration", {})
	_expect(str(migration.get("status", "")) == "PASS" and int(migration.get("page_count", -1)) == 44, "TQP-41 migration metadata changed", failures)
	var distant_restart: Dictionary = report.get("distant_post_restart_residency", {})
	_expect(int(distant_restart.get("active_count", -1)) == 1 and int((distant_restart.get("metrics", {}) as Dictionary).get("render_resources", -1)) == 1, "TQP-41 distant post-restart resource changed", failures)
	_expect(str(report.get("large_volume_snapshot_disposition", "")) == "TQP-F002_REMAINS_EXPLICIT_CAPACITY_LIMIT", "TQP-41 hid or changed TQP-F002", failures)
	var expected: Dictionary = standard.get("stable_expected", {})
	for signature_id in ["edited_sample_signature", "edited_geometry_signature", "semantic_signature"]:
		var stable := str(expected.get(signature_id, ""))
		_expect(not stable.is_empty(), "TQP-41 expected signature is absent: " + signature_id, failures)
		_expect(str(report.get(signature_id, "")) == stable, "TQP-41 signature changed: " + signature_id, failures)
	_validate_motion(motion, standard, failures)
	_validate_provenance(report.get("provenance", {}), failures)
	return {
		"schema": "world_transvoxel.terrain_lab.adaptive_persistence_evidence_validation.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"scope_status": {"TQP-41": "qualified_native_adaptive_persistence_replay_v1" if failures.is_empty() else "failed_adaptive_persistence"},
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


static func _validate_motion(motion: Dictionary, standard: Dictionary, failures: Array[String]) -> void:
	_expect(str(motion.get("schema", "")) == "world_transvoxel.terrain_lab.adaptive_persistence_motion.v1", "TQP-41 motion schema changed", failures)
	_expect(str(motion.get("status", "")) == "PASS", "TQP-41 motion evidence failed", failures)
	_expect(str(motion.get("scene", "")) == str(standard.get("observatory_scene", "")), "TQP-41 observatory scene changed", failures)
	var observed := {}
	for capture_value in motion.get("captures", []):
		var capture: Dictionary = capture_value
		var mode := str(capture.get("mode", ""))
		observed[mode] = true
		var path := str(capture.get("path", ""))
		_expect(FileAccess.file_exists(path), "TQP-41 capture missing: " + mode, failures)
		if FileAccess.file_exists(path):
			_expect(FileAccess.get_sha256(path) == str(capture.get("sha256", "")), "TQP-41 capture changed: " + mode, failures)
		_expect(int(capture.get("surface_samples", 0)) >= 180, "TQP-41 terrain absent: " + mode, failures)
	for mode in ["edited", "replayed", "distant"]:
		_expect(observed.has(mode), "TQP-41 capture mode missing: " + mode, failures)


static func _validate_provenance(value: Variant, failures: Array[String]) -> void:
	var provenance: Dictionary = value
	for key in ["workload_signature", "build_type", "os", "architecture", "cpu", "driver", "godot_version", "backend_revision"]:
		_expect(not str(provenance.get(key, "")).is_empty(), "TQP-41 provenance lacks " + key, failures)


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
