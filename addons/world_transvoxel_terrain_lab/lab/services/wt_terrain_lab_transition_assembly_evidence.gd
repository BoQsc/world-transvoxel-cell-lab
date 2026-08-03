@tool
extends RefCounted
class_name WtTerrainLabTransitionAssemblyEvidence

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/transition_assembly_standard.json"
)


static func validate_retained() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var report := JsonLoader.load_dictionary(str(standard.get("evidence", "")))
	return validate_report(report, standard)


static func validate_report(report: Dictionary, standard: Dictionary = {}) -> Dictionary:
	if standard.is_empty():
		standard = JsonLoader.load_dictionary(STANDARD_PATH)
	var failures: Array[String] = []
	_expect(str(standard.get("schema", "")) == "world_transvoxel.terrain_lab.transition_assembly_standard.v1", "TQP-31 standard schema changed", failures)
	_expect(str(report.get("schema", "")) == "world_transvoxel.terrain_lab.transition_assembly_qualification.v1", "TQP-31 report schema changed", failures)
	_expect(str(report.get("milestone", "")) == "TQP-31", "TQP-31 report milestone changed", failures)
	_expect(str(report.get("standard_id", "")) == str(standard.get("standard_id", "")), "TQP-31 report standard changed", failures)
	_expect(str(report.get("authority", "")) == str(standard.get("authority", "")), "TQP-31 report authority changed", failures)
	_expect(bool(report.get("retained_complete", false)), "TQP-31 report is filtered", failures)
	_expect(str(report.get("status", "")) == "PASS", "TQP-31 retained report failed", failures)
	var contract: Dictionary = report.get("contract", {})
	_expect(str(contract.get("status", "")) == "PASS", "TQP-31 contract failed", failures)
	var check_status := {}
	for check_value in contract.get("checks", []):
		var check: Dictionary = check_value
		check_status[str(check.get("id", ""))] = str(check.get("status", ""))
	for check_id in ["native_authority", "no_fallback", "face_order", "permitted_lod_relationships", "edge_mask_inventory", "corner_mask_inventory", "invalid_field_configuration"]:
		_expect(str(check_status.get(check_id, "")) == "PASS", "TQP-31 lacks passing check " + check_id, failures)
	var matrix: Dictionary = report.get("matrix", {})
	var budgets: Dictionary = standard.get("budgets", {})
	for count_pair in [
		["face_fixture_count", "minimum_face_fixture_count"],
		["matching_interface_count", "minimum_matching_interface_count"],
		["edge_mask_count", "minimum_edge_mask_count"],
		["corner_mask_count", "minimum_corner_mask_count"],
		["boundary_control_count", "minimum_boundary_control_count"],
		["native_chunk_call_count", "minimum_native_chunk_call_count"],
	]:
		_expect(int(matrix.get(count_pair[0], 0)) >= int(budgets.get(count_pair[1], 0)), "TQP-31 matrix coverage is incomplete: " + str(count_pair[0]), failures)
	_expect(matrix.get("observed_material_ids", []) == [1.0, 2.0, 3.0, 4.0] or matrix.get("observed_material_ids", []) == [1, 2, 3, 4], "TQP-31 material inventory changed", failures)
	var expected: Dictionary = standard.get("stable_expected", {})
	_expect(not str(expected.get("matrix_geometry_signature", "")).is_empty(), "TQP-31 standard lacks matrix signature", failures)
	_expect(str(matrix.get("geometry_signature", "")) == str(expected.get("matrix_geometry_signature", "")), "TQP-31 matrix signature changed", failures)
	var expected_faces: Dictionary = expected.get("face_fixtures", {})
	var observed_face_ids := {}
	for fixture_value in matrix.get("face_fixtures", []):
		var fixture: Dictionary = fixture_value
		var fixture_id := str(fixture.get("fixture_id", ""))
		observed_face_ids[fixture_id] = true
		_validate_fixture(fixture, str(expected_faces.get(fixture_id, "")), failures)
		_expect(bool(fixture.get("interface_matches", false)), fixture_id + " interface does not match", failures)
		_expect(int(fixture.get("coarse_only_edges", -1)) == 0 and int(fixture.get("fine_only_edges", -1)) == 0, fixture_id + " has unmatched interface edges", failures)
		_expect(_int_array(fixture.get("transition_faces", [])) == [int(fixture.get("face", -1))], fixture_id + " transition ownership changed", failures)
	var face_names: Array = (standard.get("contract", {}) as Dictionary).get("face_order", [])
	for lod_value in (standard.get("contract", {}) as Dictionary).get("coarse_lods", []):
		for face in range(face_names.size()):
			var fixture_id := "lod%d_%s" % [int(lod_value), str(face_names[face])]
			_expect(observed_face_ids.has(fixture_id), "TQP-31 missing face fixture " + fixture_id, failures)
	var expected_edges: Dictionary = expected.get("edge_masks", {})
	var observed_edge_ids := {}
	for fixture_value in matrix.get("edge_masks", []):
		var fixture: Dictionary = fixture_value
		var fixture_id := str(fixture.get("fixture_id", ""))
		observed_edge_ids[fixture_id] = true
		_validate_fixture(fixture, str(expected_edges.get(fixture_id, "")), failures)
		_expect(_int_array(fixture.get("faces", [])) == _int_array(fixture.get("transition_faces", [])), fixture_id + " edge transition ownership changed", failures)
		_expect(int(fixture.get("matching_interface_count", -1)) == 2, fixture_id + " edge interfaces are incomplete", failures)
	for pair_value in standard.get("edge_face_pairs", []):
		var pair: Array = pair_value
		var fixture_id := "edge_%d_%d" % [int(pair[0]), int(pair[1])]
		_expect(observed_edge_ids.has(fixture_id), "TQP-31 missing edge mask " + fixture_id, failures)
	var expected_corners: Dictionary = expected.get("corner_masks", {})
	var observed_corner_ids := {}
	for fixture_value in matrix.get("corner_masks", []):
		var fixture: Dictionary = fixture_value
		var fixture_id := str(fixture.get("fixture_id", ""))
		observed_corner_ids[fixture_id] = true
		_validate_fixture(fixture, str(expected_corners.get(fixture_id, "")), failures)
		_expect(_int_array(fixture.get("faces", [])) == _int_array(fixture.get("transition_faces", [])), fixture_id + " corner transition ownership changed", failures)
		_expect(int(fixture.get("matching_interface_count", -1)) == 3, fixture_id + " corner interfaces are incomplete", failures)
	for triple_value in standard.get("corner_face_triples", []):
		var triple: Array = triple_value
		var fixture_id := "corner_%d_%d_%d" % [int(triple[0]), int(triple[1]), int(triple[2])]
		_expect(observed_corner_ids.has(fixture_id), "TQP-31 missing corner mask " + fixture_id, failures)
	var all_faces: Dictionary = matrix.get("all_faces", {})
	_validate_fixture(all_faces, str(expected.get("all_faces", "")), failures)
	_expect(_int_array(all_faces.get("transition_faces", [])) == [0, 1, 2, 3, 4, 5], "TQP-31 all-face ownership changed", failures)
	_expect(int(all_faces.get("matching_interface_count", -1)) == 6, "TQP-31 all-face interfaces are incomplete", failures)
	var expected_boundary: Dictionary = expected.get("boundary_controls", {})
	var observed_boundary := {}
	for control_value in matrix.get("boundary_controls", []):
		var control: Dictionary = control_value
		var fixture_id := str(control.get("fixture_id", ""))
		observed_boundary[fixture_id] = true
		_validate_fixture(control, str(expected_boundary.get(fixture_id, "")), failures)
		_expect(int(control.get("triangle_count", -1)) == 0 and (control.get("transition_faces", []) as Array).is_empty(), fixture_id + " boundary control generated geometry", failures)
	for mode in ["empty", "full"]:
		_expect(observed_boundary.has(mode), "TQP-31 missing boundary control " + mode, failures)
	var performance: Dictionary = report.get("performance", {})
	var distribution: Dictionary = performance.get("fixture_distribution", {})
	_expect(int(distribution.get("sample_count", 0)) >= 41, "TQP-31 timing distribution is incomplete", failures)
	_expect(float(distribution.get("p95_usec", INF)) <= float(budgets.get("maximum_fixture_p95_usec", 0.0)), "TQP-31 fixture p95 exceeded", failures)
	_expect(int(performance.get("elapsed_usec", 0)) <= int(budgets.get("maximum_total_usec", 0)), "TQP-31 total duration exceeded", failures)
	var provenance: Dictionary = report.get("provenance", {})
	for key in ["workload_signature", "build_type", "os", "architecture", "cpu", "driver", "godot_version", "backend_revision"]:
		_expect(not str(provenance.get(key, "")).is_empty(), "TQP-31 provenance lacks " + key, failures)
	return {
		"schema": "world_transvoxel.terrain_lab.transition_assembly_evidence_validation.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"qualification_status": "QUALIFIED_NATIVE_TRANSITION_ASSEMBLY_WINDOWS_V1" if failures.is_empty() else "FAILED",
		"scope_status": {"TQP-31": "qualified_native_regular_transition_assembly_matrix_v1" if failures.is_empty() else "failed_transition_assembly_matrix"},
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


static func _validate_fixture(
	fixture: Dictionary,
	expected_signature: String,
	failures: Array[String]
) -> void:
	var fixture_id := str(fixture.get("fixture_id", ""))
	_expect(str(fixture.get("status", "")) == "PASS", fixture_id + " failed", failures)
	_expect(not expected_signature.is_empty(), fixture_id + " lacks retained expected signature", failures)
	_expect(str(fixture.get("geometry_signature", "")) == expected_signature, fixture_id + " geometry signature changed", failures)
	_expect(str(fixture.get("geometry_signature", "")) == str(fixture.get("warm_geometry_signature", "")), fixture_id + " cold/warm geometry differs", failures)
	var integrity: Dictionary = fixture.get("integrity", {})
	for metric in ["invalid_normals", "invalid_materials", "duplicate_triangles", "winding_normal_conflicts", "orientation_conflict_edges"]:
		if integrity.has(metric):
			_expect(int(integrity.get(metric, -1)) == 0, fixture_id + " integrity failed: " + metric, failures)
	var repro: Dictionary = fixture.get("minimized_repro", {})
	_expect(str(repro.get("runner", "")).ends_with("run_transition_assembly_validation.gd") and (repro.get("arguments", []) as Array).size() == 2, fixture_id + " lacks minimized repro", failures)


static func _expect(condition: bool, failure: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(failure)


static func _int_array(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if value is Array:
		for item in value:
			result.append(int(item))
	return result
