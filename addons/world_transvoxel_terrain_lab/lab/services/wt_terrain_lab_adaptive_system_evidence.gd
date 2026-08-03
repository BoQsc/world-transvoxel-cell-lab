@tool
extends RefCounted
class_name WtTerrainLabAdaptiveSystemEvidence

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/adaptive_system_agreement_standard.json"
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
			== "world_transvoxel.terrain_lab.adaptive_system_agreement_qualification.v1",
		"TQP-39 report schema changed", failures
	)
	_expect(str(report.get("milestone", "")) == "TQP-39", "TQP-39 milestone changed", failures)
	_expect(str(report.get("status", "")) == "PASS", "TQP-39 retained report failed", failures)
	_expect(bool(report.get("retained_complete", false)), "TQP-39 report is filtered", failures)
	_expect(
		str(report.get("authority", ""))
			== "world_transvoxel_native_runtime_plus_godot_physics_and_derived_navigation",
		"TQP-39 authority changed", failures
	)
	var actions: Dictionary = report.get("actions", {})
	for action_value in (standard.get("workload", {}) as Dictionary).get("required_actions", []):
		var action := str(action_value)
		_expect(str(actions.get(action, "")) == "PASS", "TQP-39 action failed: " + action, failures)
	var targeted: Dictionary = report.get("targeted_collision", {})
	_expect(
		int(targeted.get("collision_required_chunk_records", 0)) > 0
			and int(targeted.get("collision_required_chunk_records", 0))
				< int(targeted.get("active_chunk_records", 0)),
		"TQP-39 collision demand is not bounded", failures
	)
	_expect(int(targeted.get("collision_viewer_updates", 0)) > 0, "TQP-39 collision viewer evidence is absent", failures)
	for pair_id in ["edited_pair_audit", "post_stage_pair_audit"]:
		var pair: Dictionary = report.get(pair_id, {})
		_expect(str(pair.get("status", "")) == "PASS", "TQP-39 pair audit failed: " + pair_id, failures)
		_expect(int(pair.get("pair_count", 0)) > 0, "TQP-39 pair corpus is empty: " + pair_id, failures)
		_expect(int(pair.get("triangle_count", 0)) > 0, "TQP-39 triangle corpus is empty: " + pair_id, failures)
		_expect(
			float(pair.get("maximum_nonexact_collision_vertex_displacement_m", INF))
				<= float((standard.get("budgets", {}) as Dictionary).get("maximum_nonexact_collision_vertex_displacement_m", 0.0)),
			"TQP-39 collision/render transition displacement exceeded budget: " + pair_id,
			failures
		)
		_expect(int(pair.get("generation_mismatch_count", -1)) == 0, "TQP-39 render/collision generations differ: " + pair_id, failures)
	for ray_id in ["query_ray_agreement", "post_stage_query_ray_agreement"]:
		var ray: Dictionary = report.get(ray_id, {})
		_expect(str(ray.get("status", "")) == "PASS", "TQP-39 query/ray audit failed: " + ray_id, failures)
		_expect(int(ray.get("fixture_count", 0)) == 4, "TQP-39 query/ray corpus changed: " + ray_id, failures)
		_expect(float(ray.get("maximum_crossing_error_m", INF)) <= float((standard.get("budgets", {}) as Dictionary).get("maximum_ray_crossing_error_m", 0.0)), "TQP-39 ray error exceeded budget: " + ray_id, failures)
	for navigation_id in ["navigation_agreement", "post_stage_navigation_agreement"]:
		var navigation: Dictionary = report.get(navigation_id, {})
		_expect(str(navigation.get("status", "")) == "PASS", "TQP-39 navigation audit failed: " + navigation_id, failures)
		_expect(str(navigation.get("authority", "")) == "consumer_derived_not_world_transvoxel_authority", "TQP-39 navigation overclaims upstream authority", failures)
		_expect(int(navigation.get("polygon_count", 0)) > 0, "TQP-39 navigation is empty", failures)
		_expect(
			is_equal_approx(
				float(navigation.get("navigation_cell_size_m", -1.0)),
				float((standard.get("budgets", {}) as Dictionary).get("navigation_cell_size_m", 0.0))
			),
			"TQP-39 navigation cell size changed", failures
		)
		_expect(not str(navigation.get("source_state_signature", "")).is_empty(), "TQP-39 navigation source generation is absent", failures)
	var staged: Dictionary = report.get("staged_publication", {})
	_expect(bool(staged.get("observed", false)), "TQP-39 staged replacement was not observed", failures)
	_expect(bool(staged.get("old_pair_stable", false)), "TQP-39 old pair was not stable while staged", failures)
	var staged_query: Dictionary = staged.get("authoritative_query", {})
	_expect(
		int(staged_query.get("world_revision", -1))
			== int(staged.get("world_revision_before", -2)) + 1,
		"TQP-39 staged authoritative query revision changed", failures
	)
	var stable: Dictionary = standard.get("stable_expected", {})
	for signature_id in ["semantic_signature", "edited_pair_signature", "post_stage_pair_signature"]:
		var expected := str(stable.get(signature_id, ""))
		_expect(not expected.is_empty(), "TQP-39 expected signature is absent: " + signature_id, failures)
		_expect(str(report.get(signature_id, "")) == expected, "TQP-39 signature changed: " + signature_id, failures)
	_validate_motion(motion, standard, failures)
	var provenance: Dictionary = report.get("provenance", {})
	for key in ["workload_signature", "build_type", "os", "architecture", "cpu", "driver", "godot_version", "backend_revision"]:
		_expect(not str(provenance.get(key, "")).is_empty(), "TQP-39 provenance lacks " + key, failures)
	return {
		"schema": "world_transvoxel.terrain_lab.adaptive_system_agreement_evidence_validation.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"scope_status": {"TQP-39": "qualified_native_adaptive_system_agreement_v1" if failures.is_empty() else "failed_adaptive_system_agreement"},
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
			== "world_transvoxel.terrain_lab.adaptive_system_agreement_motion.v1",
		"TQP-39 motion schema changed", failures
	)
	_expect(str(motion.get("status", "")) == "PASS", "TQP-39 motion evidence failed", failures)
	_expect(str(motion.get("scene", "")) == str(standard.get("observatory_scene", "")), "TQP-39 observatory scene changed", failures)
	var captures: Array = motion.get("captures", [])
	_expect(captures.size() >= 3, "TQP-39 capture sequence is incomplete", failures)
	var observed := {}
	for capture_value in captures:
		var capture: Dictionary = capture_value
		var mode := str(capture.get("mode", ""))
		observed[mode] = true
		var path := str(capture.get("path", ""))
		_expect(FileAccess.file_exists(path), "TQP-39 capture is missing: " + mode, failures)
		if FileAccess.file_exists(path):
			_expect(FileAccess.get_sha256(path) == str(capture.get("sha256", "")), "TQP-39 capture changed: " + mode, failures)
		_expect(int(capture.get("surface_samples", 0)) >= 250, "TQP-39 terrain is absent: " + mode, failures)
	for mode in ["overview", "cave", "thin_feature"]:
		_expect(observed.has(mode), "TQP-39 capture mode is missing: " + mode, failures)


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
