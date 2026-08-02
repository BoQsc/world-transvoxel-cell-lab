@tool
extends RefCounted
class_name WtTerrainLabPhase03SystemEvidence

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/phase_03_system_standard.json"
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
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.phase_03_system_standard.v1",
		"Phase 3 system standard schema mismatch",
		failures
	)
	_expect(
		str(report.get("schema", ""))
			== "world_transvoxel.terrain_lab.phase_03_system_qualification.v1",
		"Phase 3 system report schema mismatch",
		failures
	)
	_expect(str(report.get("status", "")) == "PASS", "Phase 3 system report failed", failures)
	_expect(
		str(report.get("authority", "")) == str(standard.get("authority", "")),
		"Phase 3 system authority changed",
		failures
	)
	var provenance: Dictionary = report.get("provenance", {})
	for key in [
		"workload_signature", "build_type", "os", "architecture", "cpu",
		"driver", "godot_version", "backend_revision",
	]:
		_expect(not str(provenance.get(key, "")).is_empty(), "Phase 3 provenance lacks " + key, failures)
	var memory: Dictionary = report.get("memory", {})
	_expect(
		int(memory.get("retained_bytes", 0)) > 0
			and int(memory.get("peak_bytes", 0)) >= int(memory.get("retained_bytes", 0)),
		"Phase 3 memory metadata is invalid",
		failures
	)
	var milestones: Dictionary = report.get("milestones", {})
	for milestone_id in standard.get("qualified_milestones", []):
		_expect(
			str((milestones.get(str(milestone_id), {}) as Dictionary).get("status", "")) == "PASS",
			str(milestone_id) + " native Phase 3 evidence failed",
			failures
		)
	_validate_tqp_24(
		milestones.get("TQP-24", {}),
		(standard.get("stable_expected", {}) as Dictionary).get("TQP-24", {}),
		failures
	)
	return {
		"schema": "world_transvoxel.terrain_lab.phase_03_system_evidence_validation.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"qualified_milestones": standard.get("qualified_milestones", []),
		"failures": failures,
	}


static func retained_milestone(milestone_id: String) -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var report := JsonLoader.load_dictionary(str(standard.get("evidence", "")))
	var validation := validate_report(report, standard)
	if str(validation.get("status", "")) != "PASS":
		return {"milestone": milestone_id, "status": "FAIL", "failures": validation.get("failures", [])}
	return (report.get("milestones", {}) as Dictionary).get(milestone_id, {})


static func _validate_tqp_24(
	milestone: Dictionary,
	expected: Dictionary,
	failures: Array[String]
) -> void:
	_expect(str(milestone.get("status", "")) == "PASS", "TQP-24 did not pass", failures)
	_expect(bool(milestone.get("generation_coherent_before_edit", false)), "TQP-24 initial generations diverged", failures)
	_expect(bool(milestone.get("generation_coherent_after_edit", false)), "TQP-24 edited generations diverged", failures)
	_expect(
		int(milestone.get("edited_generation", 0)) > int(milestone.get("initial_generation", 0)),
		"TQP-24 edit did not advance chunk generation",
		failures
	)
	_expect(
		int(milestone.get("world_revision", -1)) == int(expected.get("required_world_revision", -2)),
		"TQP-24 world revision changed",
		failures
	)
	_expect(
		int(milestone.get("physics_ray_hits", 0)) >= int(expected.get("minimum_physics_ray_hits", 1)),
		"TQP-24 physics ray corpus is incomplete",
		failures
	)
	_expect(
		int(milestone.get("authoritative_query_count", 0)) >= int(expected.get("minimum_authoritative_queries", 1)),
		"TQP-24 authoritative query corpus is incomplete",
		failures
	)
	_expect(
		str(milestone.get("collision_shape_type", "")) == str(expected.get("required_collision_type", "")),
		"TQP-24 collision shape type changed",
		failures
	)
	_expect(
		int(milestone.get("navigation_polygon_count", 0)) >= int(expected.get("minimum_navigation_polygon_count", 1)),
		"TQP-24 native mesh produced no navigation polygons",
		failures
	)
	_expect(bool(milestone.get("navigation_query_passed", false)), "TQP-24 navigation query failed", failures)


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
