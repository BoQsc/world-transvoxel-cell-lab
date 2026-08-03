@tool
extends RefCounted
class_name WtTerrainLabTransitionAssemblyQualification

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const TransitionField := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_transition_field.gd"
)
const NativeEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_edit_native_evidence.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)

const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/transition_assembly_standard.json"
)
const POSITION_SCALE := 10000.0
const POSITION_TOLERANCE := 0.0001
const ORIENTATION_POSITION_SCALE := 1024.0
const MINIMUM_COMPONENT_ALIGNMENT := 0.000000001


static func run(fixture_filter: String = "") -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var failures: Array[String] = []
	var contract := _qualify_contract(standard)
	if str(contract.get("status", "")) != "PASS":
		failures.append_array(contract.get("failures", []))
	var probe := NativeEvidence.create_probe()
	if probe == null:
		failures.append("WorldTransvoxelCellProbe is unavailable")
	var face_names: Array = (standard.get("contract", {}) as Dictionary).get("face_order", [])
	var face_results: Array[Dictionary] = []
	var edge_results: Array[Dictionary] = []
	var corner_results: Array[Dictionary] = []
	var boundary_results: Array[Dictionary] = []
	var all_faces_result: Dictionary = {}
	var geometry_lines: Array[String] = []
	var timing_samples: Array[float] = []
	var native_chunk_calls := 0
	var matching_interfaces := 0
	var observed_materials: Array[int] = []
	for coarse_lod_value in (standard.get("contract", {}) as Dictionary).get("coarse_lods", []):
		var coarse_lod := int(coarse_lod_value)
		var coordinate := _coordinate_profile(standard, coarse_lod)
		for face in range(face_names.size()):
			var fixture_id := "lod%d_%s" % [coarse_lod, str(face_names[face])]
			if not fixture_filter.is_empty() and fixture_filter != fixture_id:
				continue
			var result := _qualify_face_fixture(
				probe,
				fixture_id,
				coordinate,
				coarse_lod,
				face
			)
			face_results.append(result)
			_collect_result(
				result,
				geometry_lines,
				timing_samples,
				observed_materials,
				failures
			)
			native_chunk_calls += int(result.get("native_chunk_calls", 0))
			if bool(result.get("interface_matches", false)):
				matching_interfaces += 1
	for pair_value in standard.get("edge_face_pairs", []):
		var faces := _int_array(pair_value)
		var fixture_id := "edge_%d_%d" % [faces[0], faces[1]]
		if not fixture_filter.is_empty() and fixture_filter != fixture_id:
			continue
		var result := _qualify_mask_fixture(probe, fixture_id, faces, "edge")
		edge_results.append(result)
		_collect_result(result, geometry_lines, timing_samples, observed_materials, failures)
		native_chunk_calls += int(result.get("native_chunk_calls", 0))
		matching_interfaces += int(result.get("matching_interface_count", 0))
	for triple_value in standard.get("corner_face_triples", []):
		var faces := _int_array(triple_value)
		var fixture_id := "corner_%d_%d_%d" % [faces[0], faces[1], faces[2]]
		if not fixture_filter.is_empty() and fixture_filter != fixture_id:
			continue
		var result := _qualify_mask_fixture(probe, fixture_id, faces, "corner")
		corner_results.append(result)
		_collect_result(result, geometry_lines, timing_samples, observed_materials, failures)
		native_chunk_calls += int(result.get("native_chunk_calls", 0))
		matching_interfaces += int(result.get("matching_interface_count", 0))
	if fixture_filter.is_empty() or fixture_filter == "all_faces":
		all_faces_result = _qualify_mask_fixture(
			probe,
			"all_faces",
			[0, 1, 2, 3, 4, 5],
			"all_faces"
		)
		_collect_result(all_faces_result, geometry_lines, timing_samples, observed_materials, failures)
		native_chunk_calls += int(all_faces_result.get("native_chunk_calls", 0))
		matching_interfaces += int(all_faces_result.get("matching_interface_count", 0))
	for mode in ["empty", "full"]:
		if not fixture_filter.is_empty() and fixture_filter != mode:
			continue
		var result := _qualify_boundary_control(probe, mode)
		boundary_results.append(result)
		_collect_result(result, geometry_lines, timing_samples, observed_materials, failures)
		native_chunk_calls += int(result.get("native_chunk_calls", 0))
	var matched_fixture_count := (
		face_results.size()
		+ edge_results.size()
		+ corner_results.size()
		+ boundary_results.size()
		+ (0 if all_faces_result.is_empty() else 1)
	)
	if matched_fixture_count == 0:
		failures.append("no transition assembly fixture matched")
	geometry_lines.sort()
	observed_materials.sort()
	var matrix_signature := "\n".join(geometry_lines).sha256_text()
	var budgets: Dictionary = standard.get("budgets", {})
	if fixture_filter.is_empty():
		if face_results.size() < int(budgets.get("minimum_face_fixture_count", 0)):
			failures.append("transition face matrix is incomplete")
		if matching_interfaces < int(budgets.get("minimum_matching_interface_count", 0)):
			failures.append("matching interface count is incomplete")
		if edge_results.size() < int(budgets.get("minimum_edge_mask_count", 0)):
			failures.append("edge-mask matrix is incomplete")
		if corner_results.size() < int(budgets.get("minimum_corner_mask_count", 0)):
			failures.append("corner-mask matrix is incomplete")
		if boundary_results.size() < int(budgets.get("minimum_boundary_control_count", 0)):
			failures.append("empty/full controls are incomplete")
		if native_chunk_calls < int(budgets.get("minimum_native_chunk_call_count", 0)):
			failures.append("native chunk call coverage is incomplete")
		for material_id in (standard.get("contract", {}) as Dictionary).get("material_ids", []):
			if int(material_id) not in observed_materials:
				failures.append("native matrix lacks material %d" % int(material_id))
	var distribution := Statistics.distribution(timing_samples)
	if fixture_filter.is_empty() and float(distribution.get("p95_usec", INF)) \
			> float(budgets.get("maximum_fixture_p95_usec", 0.0)):
		failures.append("transition fixture p95 exceeded")
	var elapsed_usec := Time.get_ticks_usec() - started_usec
	if elapsed_usec > int(budgets.get("maximum_total_usec", 0)):
		failures.append("transition assembly qualification duration exceeded")
	return {
		"schema": "world_transvoxel.terrain_lab.transition_assembly_qualification.v1",
		"standard_id": standard.get("standard_id", ""),
		"authority": standard.get("authority", ""),
		"milestone": "TQP-31",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"retained_complete": fixture_filter.is_empty(),
		"fixture_filter": fixture_filter,
		"contract": contract,
		"matrix": {
			"geometry_signature": matrix_signature,
			"native_chunk_call_count": native_chunk_calls,
			"face_fixture_count": face_results.size(),
			"matching_interface_count": matching_interfaces,
			"edge_mask_count": edge_results.size(),
			"corner_mask_count": corner_results.size(),
			"boundary_control_count": boundary_results.size(),
			"observed_material_ids": observed_materials,
			"face_fixtures": face_results,
			"edge_masks": edge_results,
			"corner_masks": corner_results,
			"all_faces": all_faces_result,
			"boundary_controls": boundary_results,
		},
		"performance": {
			"profile": "debug_regression_reference_not_production_budget",
			"elapsed_usec": elapsed_usec,
			"fixture_distribution": distribution,
		},
		"provenance": Statistics.provenance(matrix_signature),
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


static func _qualify_contract(standard: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	var checks: Array[Dictionary] = []
	var contract: Dictionary = standard.get("contract", {})
	_check(str(contract.get("native_dependency", "")) == "WorldTransvoxelCellProbe", "native_authority", "native authority changed", checks, failures)
	_check(str(contract.get("fallback_geometry", "")) == "forbidden", "no_fallback", "fallback geometry is not forbidden", checks, failures)
	var faces: Array = contract.get("face_order", [])
	_check(
		faces == ["negative_x", "positive_x", "negative_y", "positive_y", "negative_z", "positive_z"],
		"face_order",
		"transition face order differs from the canonical native order",
		checks,
		failures
	)
	_check(contract.get("coarse_lods", []) == [1.0, 2.0, 3.0] or contract.get("coarse_lods", []) == [1, 2, 3], "permitted_lod_relationships", "coarse/fine LOD relationships changed", checks, failures)
	var edge_pairs: Array = standard.get("edge_face_pairs", [])
	var valid_edges := edge_pairs.size() == 12
	var observed_edge_keys: Array[String] = []
	for pair_value in edge_pairs:
		var pair := _int_array(pair_value)
		valid_edges = valid_edges and pair.size() == 2
		if pair.size() == 2:
			valid_edges = valid_edges and pair[0] >= 0 and pair[0] < 6 \
				and pair[1] >= 0 and pair[1] < 6 \
				and _face_axis(pair[0]) != _face_axis(pair[1])
			observed_edge_keys.append(_face_set_key(pair))
	observed_edge_keys.sort()
	var expected_edge_keys: Array[String] = [
		"0,2", "0,3", "0,4", "0,5",
		"1,2", "1,3", "1,4", "1,5",
		"2,4", "2,5", "3,4", "3,5",
	]
	expected_edge_keys.sort()
	valid_edges = valid_edges and observed_edge_keys == expected_edge_keys
	_check(valid_edges, "edge_mask_inventory", "edge masks are incomplete or contain opposite faces", checks, failures)
	var corner_triples: Array = standard.get("corner_face_triples", [])
	var valid_corners := corner_triples.size() == 8
	var observed_corner_keys: Array[String] = []
	for triple_value in corner_triples:
		var triple := _int_array(triple_value)
		var axes := []
		for face in triple:
			if face >= 0 and face < 6 and _face_axis(face) not in axes:
				axes.append(_face_axis(face))
		valid_corners = valid_corners and triple.size() == 3 and axes.size() == 3
		if triple.size() == 3:
			observed_corner_keys.append(_face_set_key(triple))
	observed_corner_keys.sort()
	var expected_corner_keys: Array[String] = [
		"0,2,4", "0,2,5", "0,3,4", "0,3,5",
		"1,2,4", "1,2,5", "1,3,4", "1,3,5",
	]
	expected_corner_keys.sort()
	valid_corners = valid_corners and observed_corner_keys == expected_corner_keys
	_check(valid_corners, "corner_mask_inventory", "corner masks are incomplete or invalid", checks, failures)
	var invalid_field := TransitionField.new()
	_check(not invalid_field.configure(Vector3i.ZERO, 0) and not invalid_field.configure(Vector3i.ZERO, 1, "unknown"), "invalid_field_configuration", "invalid transition fields were accepted", checks, failures)
	return {
		"schema": "world_transvoxel.terrain_lab.transition_assembly_contract_qualification.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"checks": checks,
		"failures": failures,
	}


static func _qualify_face_fixture(
	probe: RefCounted,
	fixture_id: String,
	coarse_coordinate: Vector3i,
	coarse_lod: int,
	face: int
) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var field := TransitionField.new()
	var failures: Array[String] = []
	if not field.configure(coarse_coordinate, coarse_lod):
		failures.append("transition field configuration failed")
	var cold := _face_pass(probe, field, coarse_coordinate, coarse_lod, face)
	var warm := _face_pass(probe, field, coarse_coordinate, coarse_lod, face)
	if str(cold.get("status", "")) != "PASS":
		failures.append_array(cold.get("failures", []))
	if str(warm.get("status", "")) != "PASS":
		failures.append_array(warm.get("failures", []))
	if str(cold.get("geometry_signature", "")) != str(warm.get("geometry_signature", "")):
		failures.append("cold/warm mixed-LOD geometry signatures differ")
	return {
		"fixture_id": fixture_id,
		"status": "PASS" if failures.is_empty() else "FAIL",
		"coarse_coordinate": coarse_coordinate,
		"coarse_lod": coarse_lod,
		"fine_lod": coarse_lod - 1,
		"face": face,
		"transition_mask": 1 << face,
		"interface_matches": cold.get("interface_matches", false),
		"coarse_only_edges": cold.get("coarse_only_edges", -1),
		"fine_only_edges": cold.get("fine_only_edges", -1),
		"coarse_signature_count": cold.get("coarse_signature_count", 0),
		"fine_signature_count": cold.get("fine_signature_count", 0),
		"transition_faces": cold.get("transition_faces", []),
		"triangle_count": cold.get("triangle_count", 0),
		"material_ids": cold.get("material_ids", []),
		"integrity": cold.get("integrity", {}),
		"geometry_signature": cold.get("geometry_signature", ""),
		"warm_geometry_signature": warm.get("geometry_signature", ""),
		"native_chunk_calls": 10,
		"elapsed_usec": Time.get_ticks_usec() - started_usec,
		"minimized_repro": {
			"runner": "res://labs/terrain_lab/tools/run_transition_assembly_validation.gd",
			"arguments": ["--fixture", fixture_id],
			"coarse_coordinate": coarse_coordinate,
			"coarse_lod": coarse_lod,
			"face": face,
			"field_signature": field.definition_signature(),
			"geometry_signature": cold.get("geometry_signature", ""),
		},
		"failures": failures,
	}


static func _face_pass(
	probe: RefCounted,
	field: RefCounted,
	coarse_coordinate: Vector3i,
	coarse_lod: int,
	face: int
) -> Dictionary:
	var failures: Array[String] = []
	var coarse := NativeEvidence.mesh_chunk(
		probe,
		field,
		coarse_coordinate,
		coarse_lod,
		1 << face
	)
	var fine_chunks: Array[Dictionary] = []
	for coordinate in _fine_neighbor_coordinates(coarse_coordinate, face):
		fine_chunks.append(NativeEvidence.mesh_chunk(probe, field, coordinate, coarse_lod - 1, 0))
	var chunks: Array[Dictionary] = [coarse]
	chunks.append_array(fine_chunks)
	var triangle_count := 0
	var material_ids: Array[int] = []
	var aggregate_integrity := _empty_integrity()
	for chunk in chunks:
		var validation := NativeEvidence.validate_chunk(chunk)
		if str(validation.get("status", "")) != "PASS":
			failures.append("native chunk failed: " + str(validation.get("failures", [])))
		triangle_count += int(validation.get("triangle_count", 0))
		for material_id in validation.get("material_ids", []):
			if int(material_id) not in material_ids:
				material_ids.append(int(material_id))
		var integrity := _chunk_integrity(chunk)
		_add_integrity(aggregate_integrity, integrity)
	var transition_faces := _transition_geometry_faces(coarse)
	if transition_faces != [face]:
		failures.append("coarse transition ownership differs from requested face")
	for fine_chunk in fine_chunks:
		if not _transition_geometry_faces(fine_chunk).is_empty():
			failures.append("fine neighbor generated transition geometry")
	if _integrity_failure_count(aggregate_integrity) > 0:
		failures.append("native winding/normal/material integrity failed")
	var comparison := _mixed_lod_comparison(coarse, fine_chunks, face)
	if not bool(comparison.get("matches", false)):
		failures.append("coarse transition and fine regular interface edges differ")
	var signature_lines: Array[String] = []
	for chunk in chunks:
		signature_lines.append(NativeEvidence.chunk_signature(chunk))
	material_ids.sort()
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"interface_matches": comparison.get("matches", false),
		"coarse_only_edges": comparison.get("coarse_only", 0),
		"fine_only_edges": comparison.get("fine_only", 0),
		"coarse_signature_count": comparison.get("coarse_signature_count", 0),
		"fine_signature_count": comparison.get("fine_signature_count", 0),
		"transition_faces": transition_faces,
		"triangle_count": triangle_count,
		"material_ids": material_ids,
		"integrity": aggregate_integrity,
		"geometry_signature": "\n".join(signature_lines).sha256_text(),
		"failures": failures,
	}


static func _qualify_mask_fixture(
	probe: RefCounted,
	fixture_id: String,
	faces: Array,
	meeting_kind: String
) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var field := TransitionField.new()
	field.configure(Vector3i.ZERO, 1)
	var mask := _face_mask(faces)
	var cold := _mask_pass(probe, field, faces, mask)
	var warm := _mask_pass(probe, field, faces, mask)
	var failures: Array[String] = []
	var expected_faces: Array[int] = []
	for face in faces:
		expected_faces.append(int(face))
	expected_faces.sort()
	if str(cold.get("status", "")) != "PASS":
		failures.append_array(cold.get("failures", []))
	if str(warm.get("status", "")) != "PASS":
		failures.append_array(warm.get("failures", []))
	var cold_signature := str(cold.get("geometry_signature", ""))
	var warm_signature := str(warm.get("geometry_signature", ""))
	if cold_signature != warm_signature:
		failures.append("cold/warm multi-face geometry signatures differ")
	return {
		"fixture_id": fixture_id,
		"meeting_kind": meeting_kind,
		"status": "PASS" if failures.is_empty() else "FAIL",
		"faces": expected_faces,
		"transition_mask": mask,
		"transition_faces": cold.get("transition_faces", []),
		"matching_interface_count": cold.get("matching_interface_count", 0),
		"interface_comparisons": cold.get("interface_comparisons", {}),
		"triangle_count": cold.get("triangle_count", 0),
		"material_ids": cold.get("material_ids", []),
		"integrity": cold.get("integrity", {}),
		"geometry_signature": cold_signature,
		"warm_geometry_signature": warm_signature,
		"native_chunk_calls": 2 * (1 + 4 * expected_faces.size()),
		"elapsed_usec": Time.get_ticks_usec() - started_usec,
		"minimized_repro": {
			"runner": "res://labs/terrain_lab/tools/run_transition_assembly_validation.gd",
			"arguments": ["--fixture", fixture_id],
			"faces": expected_faces,
			"transition_mask": mask,
			"geometry_signature": cold_signature,
		},
		"failures": failures,
	}


static func _mask_pass(
	probe: RefCounted,
	field: RefCounted,
	faces: Array,
	mask: int
) -> Dictionary:
	var failures: Array[String] = []
	var coarse := NativeEvidence.mesh_chunk(
		probe,
		field,
		Vector3i.ZERO,
		1,
		mask
	)
	var chunks: Array[Dictionary] = [coarse]
	var fine_chunks_by_face := {}
	for face_value in faces:
		var face := int(face_value)
		var face_chunks: Array[Dictionary] = []
		for coordinate in _fine_neighbor_coordinates(Vector3i.ZERO, face):
			var fine := NativeEvidence.mesh_chunk(probe, field, coordinate, 0, 0)
			face_chunks.append(fine)
			chunks.append(fine)
		fine_chunks_by_face[str(face)] = face_chunks
	var triangle_count := 0
	var material_ids: Array[int] = []
	var aggregate_integrity := _empty_integrity()
	for chunk in chunks:
		var validation := NativeEvidence.validate_chunk(chunk)
		if str(validation.get("status", "")) != "PASS":
			failures.append("native multi-face assembly chunk failed: " + str(validation.get("failures", [])))
		triangle_count += int(validation.get("triangle_count", 0))
		for material_id in validation.get("material_ids", []):
			if int(material_id) not in material_ids:
				material_ids.append(int(material_id))
		_add_integrity(aggregate_integrity, _chunk_integrity(chunk))
	var observed_faces := _transition_geometry_faces(coarse)
	var expected_faces := _int_array(faces)
	expected_faces.sort()
	if observed_faces != expected_faces:
		failures.append("transition ownership differs from requested multi-face mask")
	for chunk in chunks.slice(1):
		if not _transition_geometry_faces(chunk).is_empty():
			failures.append("fine multi-face neighbor generated transition geometry")
	if _integrity_failure_count(aggregate_integrity) > 0:
		failures.append("multi-face winding/normal/material integrity failed")
	var interface_comparisons := {}
	var matching_interface_count := 0
	for face in expected_faces:
		var comparison := _mixed_lod_comparison(
			coarse,
			fine_chunks_by_face.get(str(face), []),
			face
		)
		interface_comparisons[str(face)] = comparison
		if bool(comparison.get("matches", false)):
			matching_interface_count += 1
		else:
			failures.append("multi-face coarse/fine interface differs on face %d" % face)
	var signature_lines: Array[String] = [NativeEvidence.chunk_signature(coarse)]
	for face in expected_faces:
		for fine_chunk in fine_chunks_by_face.get(str(face), []):
			signature_lines.append("%d:%s" % [face, NativeEvidence.chunk_signature(fine_chunk)])
	material_ids.sort()
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"transition_faces": observed_faces,
		"matching_interface_count": matching_interface_count,
		"interface_comparisons": interface_comparisons,
		"triangle_count": triangle_count,
		"material_ids": material_ids,
		"integrity": aggregate_integrity,
		"geometry_signature": "\n".join(signature_lines).sha256_text(),
		"failures": failures,
	}


static func _qualify_boundary_control(probe: RefCounted, mode: String) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var field := TransitionField.new()
	field.configure(Vector3i.ZERO, 1, mode)
	var cold := NativeEvidence.mesh_chunk(probe, field, Vector3i.ZERO, 1, 0x3F)
	var warm := NativeEvidence.mesh_chunk(probe, field, Vector3i.ZERO, 1, 0x3F)
	var validation := NativeEvidence.validate_chunk(cold)
	var failures: Array[String] = []
	if str(validation.get("status", "")) != "PASS":
		failures.append_array(validation.get("failures", []))
	if int(validation.get("triangle_count", -1)) != 0:
		failures.append(mode + " control generated geometry")
	if not _transition_geometry_faces(cold).is_empty():
		failures.append(mode + " control generated transition geometry")
	var cold_signature := NativeEvidence.chunk_signature(cold)
	var warm_signature := NativeEvidence.chunk_signature(warm)
	if cold_signature != warm_signature:
		failures.append(mode + " control is nondeterministic")
	return {
		"fixture_id": mode,
		"status": "PASS" if failures.is_empty() else "FAIL",
		"native_status": cold.get("status", ""),
		"triangle_count": validation.get("triangle_count", -1),
		"transition_faces": _transition_geometry_faces(cold),
		"geometry_signature": cold_signature,
		"warm_geometry_signature": warm_signature,
		"material_ids": [],
		"native_chunk_calls": 2,
		"elapsed_usec": Time.get_ticks_usec() - started_usec,
		"minimized_repro": {
			"runner": "res://labs/terrain_lab/tools/run_transition_assembly_validation.gd",
			"arguments": ["--fixture", mode],
			"mode": mode,
			"geometry_signature": cold_signature,
		},
		"failures": failures,
	}


static func _mixed_lod_comparison(
	coarse: Dictionary,
	fine_chunks: Array[Dictionary],
	face: int
) -> Dictionary:
	var axis := _face_axis(face)
	var reference_origin := NativeEvidence.chunk_origin(coarse)
	var extent := float(
		TransitionField.CHUNK_CELLS_PER_AXIS * (1 << int(coarse.get("lod", 1)))
	)
	var plane := extent if _face_is_positive(face) else 0.0
	var coarse_buffers := _relative_buffers(coarse, reference_origin, face)
	var fine_buffers: Array[Dictionary] = []
	for fine_chunk in fine_chunks:
		fine_buffers.append_array(_relative_buffers(fine_chunk, reference_origin, -1))
	var coarse_signatures := _plane_open_edge_signatures(coarse_buffers, axis, plane)
	var fine_signatures := _plane_open_edge_signatures(fine_buffers, axis, plane)
	var coarse_only := 0
	var fine_only := 0
	for key in coarse_signatures:
		if not fine_signatures.has(key):
			coarse_only += 1
	for key in fine_signatures:
		if not coarse_signatures.has(key):
			fine_only += 1
	return {
		"matches": coarse_only == 0 and fine_only == 0,
		"coarse_only": coarse_only,
		"fine_only": fine_only,
		"coarse_signature_count": coarse_signatures.size(),
		"fine_signature_count": fine_signatures.size(),
	}


static func _relative_buffers(
	chunk: Dictionary,
	reference_origin: Vector3,
	transition_face: int
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var origin := NativeEvidence.chunk_origin(chunk) - reference_origin
	var regular: Dictionary = chunk.get("regular", {})
	result.append({
		"origin": origin,
		"vertices": regular.get("vertices", PackedVector3Array()),
		"indices": regular.get("indices", PackedInt32Array()),
	})
	if transition_face >= 0:
		var transitions: Array = chunk.get("transitions", [])
		if transition_face < transitions.size():
			var transition: Dictionary = transitions[transition_face]
			result.append({
				"origin": origin,
				"vertices": transition.get("vertices", PackedVector3Array()),
				"indices": transition.get("indices", PackedInt32Array()),
			})
	return result


static func _plane_open_edge_signatures(
	buffers: Array[Dictionary],
	axis: int,
	plane: float
) -> Dictionary:
	var counts := {}
	var points := {}
	for buffer in buffers:
		var origin: Vector3 = buffer.get("origin", Vector3.ZERO)
		var vertices: PackedVector3Array = buffer.get("vertices", PackedVector3Array())
		var indices: PackedInt32Array = buffer.get("indices", PackedInt32Array())
		for offset in range(0, indices.size(), 3):
			if offset + 2 >= indices.size():
				break
			var triangle := [int(indices[offset]), int(indices[offset + 1]), int(indices[offset + 2])]
			if triangle.min() < 0 or triangle.max() >= vertices.size():
				continue
			var a := origin + vertices[triangle[0]]
			var b := origin + vertices[triangle[1]]
			var c := origin + vertices[triangle[2]]
			for edge in [[a, b], [b, c], [c, a]]:
				var key := _edge_key(edge[0], edge[1])
				counts[key] = int(counts.get(key, 0)) + 1
				points[key] = edge
	var result := {}
	for key in counts:
		if int(counts[key]) != 1:
			continue
		var edge: Array = points[key]
		if absf(edge[0][axis] - plane) <= POSITION_TOLERANCE \
				and absf(edge[1][axis] - plane) <= POSITION_TOLERANCE:
			result[_face_edge_key(edge[0], edge[1], axis)] = true
	return result


static func _chunk_integrity(chunk: Dictionary) -> Dictionary:
	var result := _empty_integrity()
	for buffer in NativeEvidence.chunk_buffers(chunk):
		var vertices: PackedVector3Array = buffer.get("vertices", PackedVector3Array())
		var normals: PackedVector3Array = buffer.get("normals", PackedVector3Array())
		var indices: PackedInt32Array = buffer.get("indices", PackedInt32Array())
		var materials: PackedInt32Array = buffer.get("materials", PackedInt32Array())
		for normal in normals:
			if not normal.is_finite() or absf(normal.length() - 1.0) > 0.01:
				result["invalid_normals"] = int(result["invalid_normals"]) + 1
		for material_id in materials:
			if int(material_id) < 1 or int(material_id) > 4:
				result["invalid_materials"] = int(result["invalid_materials"]) + 1
		var seen_triangles := {}
		var directed_edges := {}
		var undirected_edges := {}
		var edge_incidents := {}
		var triangle_alignments: Array[float] = []
		for offset in range(0, indices.size(), 3):
			if offset + 2 >= indices.size():
				break
			var ia := int(indices[offset])
			var ib := int(indices[offset + 1])
			var ic := int(indices[offset + 2])
			if ia < 0 or ib < 0 or ic < 0 or ia >= vertices.size() \
					or ib >= vertices.size() or ic >= vertices.size():
				continue
			var triangle_key_parts := [_point_key(vertices[ia]), _point_key(vertices[ib]), _point_key(vertices[ic])]
			triangle_key_parts.sort()
			var triangle_key := "|".join(triangle_key_parts)
			if seen_triangles.has(triangle_key):
				result["duplicate_triangles"] = int(result["duplicate_triangles"]) + 1
			else:
				seen_triangles[triangle_key] = true
			if normals.size() == vertices.size():
				var geometric := (vertices[ib] - vertices[ia]).cross(vertices[ic] - vertices[ia])
				var authored := normals[ia] + normals[ib] + normals[ic]
				if geometric.length_squared() > 0.0000000001 and authored.length_squared() > 0.0000000001:
					var raw_alignment := geometric.dot(authored)
					triangle_alignments.append(raw_alignment)
					var signed_alignment := geometric.normalized().dot(authored.normalized()) * -1.0
					if signed_alignment < -0.0001:
						result["local_triangle_normal_disagreements"] = int(result["local_triangle_normal_disagreements"]) + 1
						(result["local_disagreement_details"] as Array).append({
							"buffer_kind": buffer.get("kind", ""),
							"transition_face": buffer.get("face", -1),
							"lod": buffer.get("lod", -1),
							"triangle_offset": offset,
							"geometric_length": geometric.length(),
							"signed_alignment": signed_alignment,
							"vertices": [vertices[ia], vertices[ib], vertices[ic]],
							"normals": [normals[ia], normals[ib], normals[ic]],
						})
				else:
					triangle_alignments.append(0.0)
			else:
				triangle_alignments.append(0.0)
			var triangle_index := triangle_alignments.size() - 1
			for pair in [[ia, ib], [ib, ic], [ic, ia]]:
				var a_key := _orientation_point_key(vertices[pair[0]])
				var b_key := _orientation_point_key(vertices[pair[1]])
				var directed := a_key + ">" + b_key
				var undirected := a_key + "|" + b_key if a_key < b_key else b_key + "|" + a_key
				directed_edges[directed] = int(directed_edges.get(directed, 0)) + 1
				undirected_edges[undirected] = int(undirected_edges.get(undirected, 0)) + 1
				if not edge_incidents.has(undirected):
					edge_incidents[undirected] = []
				(edge_incidents[undirected] as Array).append({
					"triangle": triangle_index,
					"forward": a_key < b_key,
				})
		for key in undirected_edges:
			if int(undirected_edges[key]) != 2:
				continue
			var parts := str(key).split("|")
			if int(directed_edges.get(parts[0] + ">" + parts[1], 0)) != 1 \
					or int(directed_edges.get(parts[1] + ">" + parts[0], 0)) != 1:
				result["orientation_conflict_edges"] = int(result["orientation_conflict_edges"]) + 1
		var adjacency: Array[Array] = []
		for triangle_index in range(triangle_alignments.size()):
			adjacency.append([])
		for incidents_value in edge_incidents.values():
			var incidents: Array = incidents_value
			if incidents.size() != 2:
				continue
			var first := int((incidents[0] as Dictionary).get("triangle", -1))
			var second := int((incidents[1] as Dictionary).get("triangle", -1))
			if first >= 0 and second >= 0 and first != second:
				adjacency[first].append(second)
				adjacency[second].append(first)
		var visited := PackedByteArray()
		visited.resize(triangle_alignments.size())
		for start in range(triangle_alignments.size()):
			if visited[start] != 0:
				continue
			var pending: Array[int] = [start]
			visited[start] = 1
			var component_size := 0
			var score := 0.0
			var magnitude := 0.0
			while not pending.is_empty():
				var current := pending.pop_back()
				component_size += 1
				var alignment := triangle_alignments[current]
				score += alignment
				magnitude += absf(alignment)
				for neighbor_value in adjacency[current]:
					var neighbor := int(neighbor_value)
					if visited[neighbor] == 0:
						visited[neighbor] = 1
						pending.append(neighbor)
			if magnitude > MINIMUM_COMPONENT_ALIGNMENT and score > MINIMUM_COMPONENT_ALIGNMENT:
				result["winding_normal_conflicts"] = int(result["winding_normal_conflicts"]) + 1
				(result["conflict_details"] as Array).append({
					"buffer_kind": buffer.get("kind", ""),
					"transition_face": buffer.get("face", -1),
					"lod": buffer.get("lod", -1),
					"component_size": component_size,
					"alignment_score": score,
					"alignment_magnitude": magnitude,
				})
	return result


static func _empty_integrity() -> Dictionary:
	return {
		"invalid_normals": 0,
		"invalid_materials": 0,
		"duplicate_triangles": 0,
		"winding_normal_conflicts": 0,
		"orientation_conflict_edges": 0,
		"local_triangle_normal_disagreements": 0,
		"conflict_details": [],
		"local_disagreement_details": [],
	}


static func _add_integrity(target: Dictionary, source: Dictionary) -> void:
	for key in ["invalid_normals", "invalid_materials", "duplicate_triangles", "winding_normal_conflicts", "orientation_conflict_edges"]:
		target[key] = int(target[key]) + int(source.get(key, 0))
	target["local_triangle_normal_disagreements"] = int(target["local_triangle_normal_disagreements"]) + int(source.get("local_triangle_normal_disagreements", 0))
	(target["conflict_details"] as Array).append_array(source.get("conflict_details", []))
	(target["local_disagreement_details"] as Array).append_array(source.get("local_disagreement_details", []))


static func _integrity_failure_count(integrity: Dictionary) -> int:
	var result := 0
	for key in ["invalid_normals", "invalid_materials", "duplicate_triangles", "winding_normal_conflicts", "orientation_conflict_edges"]:
		result += int(integrity.get(key, 0))
	return result


static func _transition_geometry_faces(chunk: Dictionary) -> Array[int]:
	var result: Array[int] = []
	var transitions: Array = chunk.get("transitions", [])
	for face in range(transitions.size()):
		var transition: Dictionary = transitions[face]
		var indices: PackedInt32Array = transition.get("indices", PackedInt32Array())
		if not indices.is_empty():
			result.append(face)
	return result


static func _fine_neighbor_coordinates(coarse: Vector3i, face: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var axis := _face_axis(face)
	var fixed := coarse[axis] * 2 + (2 if _face_is_positive(face) else -1)
	var variable_axes: Array[int] = []
	for candidate in range(3):
		if candidate != axis:
			variable_axes.append(candidate)
	for first in range(2):
		for second in range(2):
			var coordinate := coarse * 2
			coordinate[axis] = fixed
			coordinate[variable_axes[0]] += first
			coordinate[variable_axes[1]] += second
			result.append(coordinate)
	return result


static func _collect_result(
	result: Dictionary,
	geometry_lines: Array[String],
	timing_samples: Array[float],
	observed_materials: Array[int],
	failures: Array[String]
) -> void:
	geometry_lines.append(str(result.get("fixture_id", "")) + ":" + str(result.get("geometry_signature", "")))
	timing_samples.append(float(result.get("elapsed_usec", 0.0)))
	for material_id in result.get("material_ids", []):
		if int(material_id) not in observed_materials:
			observed_materials.append(int(material_id))
	if str(result.get("status", "")) != "PASS":
		for failure in result.get("failures", []):
			failures.append(str(result.get("fixture_id", "")) + ": " + str(failure))


static func _coordinate_profile(standard: Dictionary, lod: int) -> Vector3i:
	return _vector3i((standard.get("coordinate_profiles", {}) as Dictionary).get(str(lod), []))


static func _face_mask(faces: Array) -> int:
	var result := 0
	for face in faces:
		result |= 1 << int(face)
	return result


static func _face_set_key(faces: Array[int]) -> String:
	var ordered := faces.duplicate()
	ordered.sort()
	var parts: Array[String] = []
	for face in ordered:
		parts.append(str(face))
	return ",".join(parts)


static func _face_axis(face: int) -> int:
	return 0 if face <= 1 else (1 if face <= 3 else 2)


static func _face_is_positive(face: int) -> bool:
	return face in [1, 3, 5]


static func _edge_key(a: Vector3, b: Vector3) -> String:
	var first := _point_key(a)
	var second := _point_key(b)
	return first + "|" + second if first < second else second + "|" + first


static func _point_key(point: Vector3) -> String:
	return "%d,%d,%d" % [
		roundi(point.x * POSITION_SCALE),
		roundi(point.y * POSITION_SCALE),
		roundi(point.z * POSITION_SCALE),
	]


static func _orientation_point_key(point: Vector3) -> String:
	return "%d,%d,%d" % [
		roundi(point.x * ORIENTATION_POSITION_SCALE),
		roundi(point.y * ORIENTATION_POSITION_SCALE),
		roundi(point.z * ORIENTATION_POSITION_SCALE),
	]


static func _face_edge_key(a: Vector3, b: Vector3, axis: int) -> String:
	var components: Array[int] = []
	for component in range(3):
		if component != axis:
			components.append(component)
	var first := "%d,%d" % [
		roundi(a[components[0]] * POSITION_SCALE),
		roundi(a[components[1]] * POSITION_SCALE),
	]
	var second := "%d,%d" % [
		roundi(b[components[0]] * POSITION_SCALE),
		roundi(b[components[1]] * POSITION_SCALE),
	]
	return first + "|" + second if first < second else second + "|" + first


static func _int_array(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if value is Array:
		for item in value:
			result.append(int(item))
	return result


static func _vector3i(value: Variant) -> Vector3i:
	if value is Array and value.size() == 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return value if value is Vector3i else Vector3i.ZERO


static func _check(
	condition: bool,
	check_id: String,
	failure: String,
	checks: Array[Dictionary],
	failures: Array[String]
) -> void:
	checks.append({"id": check_id, "status": "PASS" if condition else "FAIL"})
	if not condition:
		failures.append(failure)
