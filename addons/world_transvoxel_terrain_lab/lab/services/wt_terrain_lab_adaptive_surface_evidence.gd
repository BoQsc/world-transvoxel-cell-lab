@tool
extends RefCounted
class_name WtTerrainLabAdaptiveSurfaceEvidence

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/adaptive_surface_continuity_standard.json"
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
			== "world_transvoxel.terrain_lab.adaptive_surface_continuity_qualification.v1",
		"TQP-38 report schema changed", failures
	)
	_expect(str(report.get("milestone", "")) == "TQP-38", "TQP-38 milestone changed", failures)
	_expect(str(report.get("status", "")) == "PASS", "TQP-38 retained report failed", failures)
	_expect(bool(report.get("retained_complete", false)), "TQP-38 report is filtered", failures)
	_expect(
		str(report.get("authority", ""))
			== "world_transvoxel_authoritative_samples_and_native_render_payload",
		"TQP-38 authority changed", failures
	)
	var actions: Dictionary = report.get("actions", {})
	for action_value in (standard.get("workload", {}) as Dictionary).get("required_actions", []):
		var action := str(action_value)
		_expect(str(actions.get(action, "")) == "PASS", "TQP-38 action failed: " + action, failures)
	var audits: Dictionary = report.get("payload_audits", {})
	for audit_id in ["baseline", "edited", "returned"]:
		var audit: Dictionary = audits.get(audit_id, {})
		_expect(str(audit.get("status", "")) == "PASS", "TQP-38 payload audit failed: " + audit_id, failures)
		_expect(int(audit.get("vertex_count", 0)) > 0, "TQP-38 has no native vertices: " + audit_id, failures)
		for metric in ["vertex_payload_errors", "shared_position_payload_errors", "normal_tangent_errors"]:
			_expect(int(audit.get(metric, -1)) == 0, "TQP-38 invariant failed: %s.%s" % [audit_id, metric], failures)
	var edited: Dictionary = audits.get("edited", {})
	_expect(int(edited.get("authored_vertex_count", 0)) > 0, "TQP-38 authored provenance is absent", failures)
	_expect(int(edited.get("material_7_vertex_count", 0)) > 0, "TQP-38 construction material is absent", failures)
	_expect(int(edited.get("material_8_vertex_count", 0)) > 0, "TQP-38 painted material is absent", failures)
	var lod_identity: Dictionary = report.get("lod_cycle_identity", {})
	_expect(str(lod_identity.get("status", "")) == "PASS", "TQP-38 LOD-cycle payload identity changed", failures)
	_expect(
		int(lod_identity.get("changed_shared_position_count", -1)) == 0,
		"TQP-38 LOD-cycle changed shared-position material payload", failures
	)
	_expect(
		float(lod_identity.get("shared_position_ratio", 0.0))
			>= float(lod_identity.get("minimum_shared_position_ratio", 1.0)),
		"TQP-38 LOD-cycle shared-position corpus is too small", failures
	)
	var query: Dictionary = report.get("authoritative_queries", {})
	_expect(str(query.get("status", "")) == "PASS", "TQP-38 authoritative query agreement failed", failures)
	var anchor: Dictionary = report.get("large_coordinate_anchor", {})
	_expect(str(anchor.get("status", "")) == "PASS", "TQP-38 texture anchor failed", failures)
	_expect(
		str(anchor.get("qualified_as", ""))
			== "presentation_coordinate_compensation_not_native_horizontal_streaming",
		"TQP-38 large-coordinate scope overclaims native streaming", failures
	)
	var shader: Dictionary = report.get("shader_contract", {})
	_expect(str(shader.get("status", "")) == "PASS", "TQP-38 shader contract failed", failures)
	_expect(int(shader.get("texture_layer_count", 0)) == 8, "TQP-38 texture layer count changed", failures)
	_expect(int(shader.get("mipmap_level_count", 0)) == 7, "TQP-38 mip chain changed", failures)
	var stable: Dictionary = standard.get("stable_expected", {})
	for signature_id in ["semantic_signature", "shader_contract_signature"]:
		var expected := str(stable.get(signature_id, ""))
		_expect(not expected.is_empty(), "TQP-38 expected signature is absent: " + signature_id, failures)
		_expect(str(report.get(signature_id, "")) == expected, "TQP-38 signature changed: " + signature_id, failures)
	_validate_motion(motion, standard, failures)
	var provenance: Dictionary = report.get("provenance", {})
	for key in ["workload_signature", "build_type", "os", "architecture", "cpu", "driver", "godot_version", "backend_revision"]:
		_expect(not str(provenance.get(key, "")).is_empty(), "TQP-38 provenance lacks " + key, failures)
	return {
		"schema": "world_transvoxel.terrain_lab.adaptive_surface_continuity_evidence_validation.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"scope_status": {"TQP-38": "qualified_native_adaptive_surface_continuity_v1" if failures.is_empty() else "failed_adaptive_surface_continuity"},
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
			== "world_transvoxel.terrain_lab.adaptive_surface_continuity_motion.v1",
		"TQP-38 motion schema changed", failures
	)
	_expect(str(motion.get("status", "")) == "PASS", "TQP-38 motion evidence failed", failures)
	_expect(str(motion.get("scene", "")) == str(standard.get("observatory_scene", "")), "TQP-38 observatory scene changed", failures)
	var captures: Array = motion.get("captures", [])
	_expect(captures.size() >= 3, "TQP-38 capture sequence is incomplete", failures)
	var observed := {}
	for capture_value in captures:
		var capture: Dictionary = capture_value
		var mode := str(capture.get("mode", ""))
		observed[mode] = true
		var path := str(capture.get("path", ""))
		_expect(FileAccess.file_exists(path), "TQP-38 capture is missing: " + mode, failures)
		if FileAccess.file_exists(path):
			_expect(FileAccess.get_sha256(path) == str(capture.get("sha256", "")), "TQP-38 capture changed: " + mode, failures)
		_expect(int(capture.get("surface_samples", 0)) >= 250, "TQP-38 terrain is absent: " + mode, failures)
	for mode in ["lit", "material", "provenance"]:
		_expect(observed.has(mode), "TQP-38 capture mode is missing: " + mode, failures)


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
