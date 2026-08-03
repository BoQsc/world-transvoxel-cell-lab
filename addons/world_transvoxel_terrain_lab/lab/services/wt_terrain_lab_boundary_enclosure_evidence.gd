@tool
extends RefCounted
class_name WtTerrainLabBoundaryEnclosureEvidence

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/boundary_enclosure_standard.json"
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
			== "world_transvoxel.terrain_lab.boundary_enclosure_standard.v1",
		"TQP-32 standard schema changed",
		failures
	)
	_expect(
		str(report.get("schema", ""))
			== "world_transvoxel.terrain_lab.boundary_enclosure_qualification.v1",
		"TQP-32 report schema changed",
		failures
	)
	_expect(str(report.get("milestone", "")) == "TQP-32", "TQP-32 report milestone changed", failures)
	_expect(str(report.get("standard_id", "")) == str(standard.get("standard_id", "")), "TQP-32 report standard changed", failures)
	_expect(str(report.get("authority", "")) == str(standard.get("authority", "")), "TQP-32 report authority changed", failures)
	_expect(bool(report.get("retained_complete", false)), "TQP-32 report is filtered", failures)
	_expect(str(report.get("status", "")) == "PASS", "TQP-32 retained report failed", failures)
	var contract: Dictionary = report.get("contract", {})
	_expect(str(contract.get("status", "")) == "PASS", "TQP-32 contract failed", failures)
	var check_status := {}
	for check_value in contract.get("checks", []):
		var check: Dictionary = check_value
		check_status[str(check.get("id", ""))] = str(check.get("status", ""))
	for check_id in [
		"native_authority",
		"no_fallback",
		"outside_field_sampling",
		"unloaded_neighbor",
		"closed_contours",
		"open_contours",
		"cap_ownership",
		"forbidden_corrections",
		"catalog_rejection",
	]:
		_expect(str(check_status.get(check_id, "")) == "PASS", "TQP-32 lacks passing check " + check_id, failures)
	var expected: Dictionary = standard.get("stable_expected", {})
	var expected_fixtures: Dictionary = expected.get("fixtures", {})
	var fixture_definitions := {}
	for fixture_value in standard.get("fixtures", []):
		var fixture_definition: Dictionary = fixture_value
		fixture_definitions[str(fixture_definition.get("id", ""))] = fixture_definition
	var observed_fixture_ids := {}
	var observed_lods: Array[int] = []
	for fixture_value in report.get("fixtures", []):
		var fixture: Dictionary = fixture_value
		var fixture_id := str(fixture.get("fixture_id", ""))
		observed_fixture_ids[fixture_id] = true
		var fixture_lod := int(fixture.get("lod", -1))
		if fixture_lod not in observed_lods:
			observed_lods.append(fixture_lod)
		_expect(str(fixture.get("status", "")) == "PASS", fixture_id + " failed", failures)
		_expect(str(fixture.get("geometry_signature", "")) == str(fixture.get("warm_geometry_signature", "")), fixture_id + " cold/warm geometry differs", failures)
		_expect(str(fixture.get("geometry_signature", "")) == str(expected_fixtures.get(fixture_id, "")), fixture_id + " retained geometry changed", failures)
		var topology: Dictionary = fixture.get("topology", {})
		_expect(str(topology.get("status", "")) == "PASS", fixture_id + " topology failed", failures)
		_expect(int(topology.get("interior_open_edge_count", -1)) == 0, fixture_id + " has interior open edges", failures)
		_expect(int(topology.get("nonmanifold_edge_count", -1)) == 0, fixture_id + " has nonmanifold edges", failures)
		var fixture_definition: Dictionary = fixture_definitions.get(fixture_id, {})
		var declared_open_faces: Array = fixture_definition.get("declared_open_faces", [])
		_expect(
			fixture.get("declared_open_faces", []) == declared_open_faces,
			fixture_id + " retained open-face declaration changed",
			failures
		)
		var open_edge_faces: Dictionary = fixture.get("open_edge_faces", {})
		_expect(
			int(open_edge_faces.get("exterior_open_edge_count", -1))
				== int(topology.get("exterior_open_edge_count", -2)),
			fixture_id + " open-edge face inventory differs from topology inventory",
			failures
		)
		_expect(
			int(open_edge_faces.get("unclassified_open_edge_count", -1)) == 0,
			fixture_id + " has open edges outside the exterior planes",
			failures
		)
		var face_counts: Dictionary = open_edge_faces.get("face_counts", {})
		for face in ["negative_x", "positive_x", "negative_y", "positive_y", "negative_z", "positive_z"]:
			var face_count := int(face_counts.get(face, 0))
			_expect(
				face_count > 0 if face in declared_open_faces else face_count == 0,
				fixture_id + " open contours do not match declared face " + face,
				failures
			)
		if str(fixture.get("contour", "")) == "closed":
			_expect(int(topology.get("exterior_open_edge_count", -1)) == 0, fixture_id + " is not closed", failures)
		else:
			_expect(int(topology.get("exterior_open_edge_count", 0)) > 0, fixture_id + " lacks declared exterior openings", failures)
		var audit: Dictionary = fixture.get("sample_audit", {})
		_expect(int(audit.get("outside_sample_count", 0)) > 0, fixture_id + " lacks outside-field halo samples", failures)
		for face in ["negative_x", "positive_x", "negative_y", "positive_y", "negative_z", "positive_z"]:
			_expect(int((audit.get("outside_face_counts", {}) as Dictionary).get(face, 0)) > 0, fixture_id + " lacks halo samples on " + face, failures)
	for fixture_value in standard.get("fixtures", []):
		_expect(observed_fixture_ids.has(str((fixture_value as Dictionary).get("id", ""))), "TQP-32 fixture is missing", failures)
	observed_lods.sort()
	_expect(observed_lods == [0, 2], "TQP-32 must retain LOD0 and LOD2 boundary fixtures", failures)
	var matrix: Dictionary = report.get("matrix", {})
	var budgets: Dictionary = standard.get("budgets", {})
	_expect(int(matrix.get("fixture_count", 0)) >= int(budgets.get("minimum_fixture_count", 0)), "TQP-32 fixture coverage is incomplete", failures)
	_expect(int(matrix.get("native_chunk_call_count", 0)) >= int(budgets.get("minimum_native_chunk_call_count", 0)), "TQP-32 native call coverage is incomplete", failures)
	_expect(str(matrix.get("geometry_signature", "")) == str(expected.get("matrix_geometry_signature", "")), "TQP-32 matrix geometry signature changed", failures)
	var catalog: Dictionary = report.get("catalog_policy", {})
	_expect(str(catalog.get("status", "")) == "PASS", "TQP-32 catalog policy failed", failures)
	_expect(str((catalog.get("world_catalog", {}) as Dictionary).get("status", "")) == "PASS", "TQP-32 world catalog failed", failures)
	_expect(str((catalog.get("partial_residency", {}) as Dictionary).get("status", "")) == "PASS", "TQP-32 partial residency failed", failures)
	var unloaded: Dictionary = report.get("unloaded_neighbor", {})
	_expect(str(unloaded.get("status", "")) == "PASS", "TQP-32 unloaded-neighbor fixture failed", failures)
	_expect(bool(unloaded.get("geometry_invariant", false)), "TQP-32 target geometry depends on neighbor residency", failures)
	_expect(bool(unloaded.get("resident_coupled_negative_detected", false)), "TQP-32 resident-coupled negative was not detected", failures)
	_expect(str(unloaded.get("signature", "")) == str(expected.get("unloaded_neighbor_signature", "")), "TQP-32 unloaded-neighbor signature changed", failures)
	var negative: Dictionary = report.get("negative_controls", {})
	_expect(str(negative.get("status", "")) == "PASS", "TQP-32 negative controls failed", failures)
	_expect(int(negative.get("control_count", 0)) >= int(budgets.get("minimum_negative_control_count", 0)), "TQP-32 negative-control coverage is incomplete", failures)
	for control_value in negative.get("controls", []):
		var control: Dictionary = control_value
		_expect(str(control.get("status", "")) == "PASS" and bool(control.get("injected_failure_detected", false)), "TQP-32 negative control failed: " + str(control.get("id", "")), failures)
	var performance: Dictionary = report.get("performance", {})
	var distribution: Dictionary = performance.get("fixture_distribution", {})
	_expect(float(distribution.get("p95_usec", INF)) <= float(budgets.get("maximum_fixture_p95_usec", 0)), "TQP-32 fixture p95 exceeded", failures)
	_expect(int(performance.get("elapsed_usec", 0)) <= int(budgets.get("maximum_total_usec", 0)), "TQP-32 total duration exceeded", failures)
	var provenance: Dictionary = report.get("provenance", {})
	for key in ["workload_signature", "build_type", "os", "architecture", "cpu", "driver", "godot_version", "backend_revision"]:
		_expect(not str(provenance.get(key, "")).is_empty(), "TQP-32 provenance lacks " + key, failures)
	var editor_inspection: Dictionary = standard.get("editor_inspection", {})
	var scene_path := str(editor_inspection.get("scene", ""))
	var capture_path := str(editor_inspection.get("capture", ""))
	_expect(FileAccess.file_exists(scene_path), "TQP-32 editor observatory scene is missing", failures)
	_expect(FileAccess.file_exists(capture_path), "TQP-32 editor capture is missing", failures)
	if FileAccess.file_exists(capture_path):
		_expect(FileAccess.get_sha256(capture_path) == str(editor_inspection.get("capture_sha256", "")), "TQP-32 editor capture changed", failures)
	_expect(int(editor_inspection.get("width", 0)) == 1280 and int(editor_inspection.get("height", 0)) == 720, "TQP-32 editor capture dimensions changed", failures)
	_expect(str(editor_inspection.get("automation_status", "")) == "PASS", "TQP-32 editor inspection automation failed", failures)
	return {
		"schema": "world_transvoxel.terrain_lab.boundary_enclosure_evidence_validation.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"qualification_status": "QUALIFIED_NATIVE_BOUNDARY_ENCLOSURE_WINDOWS_V1" if failures.is_empty() else "FAILED",
		"scope_status": {"TQP-32": "qualified_native_boundary_enclosure_policy_v1" if failures.is_empty() else "failed_boundary_enclosure_policy"},
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


static func _expect(condition: bool, failure: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(failure)
