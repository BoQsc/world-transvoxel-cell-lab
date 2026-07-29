@tool
extends RefCounted
class_name WtCellLabAuthorityValidator

const Contracts := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_contracts.gd")
const MeshAnalysis := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_mesh_analysis.gd")
const CaseValidator := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_case_validator.gd")
const ChunkValidator := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_chunk_validator.gd")

const NEAR_ISOVALUE_EPSILONS := [0.0000001, 0.00001, 0.001]
const VERTICAL_CHUNK_COUNT := 3
const VERTICAL_MIXED_FACES := [2, 3]

var _chunk_validator := ChunkValidator.new()


func validate(probe: RefCounted) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var result := {
		"schema": Contracts.AUTHORITY_STRESS_VALIDATION_SCHEMA,
		"authority": Contracts.NATIVE_AUTHORITY,
		"available": probe != null \
			and probe.has_method("mesh_regular_cell") \
			and probe.has_method("mesh_transition_cell") \
			and probe.has_method("mesh_chunk_with_callable"),
		"near_isovalue": {},
		"vertical_stack": {},
		"failure_count": 0,
		"sample_failures": [],
		"status": "Unavailable",
		"elapsed_ms": 0.0,
	}
	if not bool(result["available"]):
		_append_failure(result, "required native cell or chunk probe method is unavailable")
		result["failure_count"] = 1
		result["status"] = "FAIL"
		return result
	result["near_isovalue"] = _validate_near_isovalue(probe)
	result["vertical_stack"] = _validate_vertical_stack(probe)
	for section_name in ["near_isovalue", "vertical_stack"]:
		var section: Dictionary = result[section_name]
		result["failure_count"] = int(result["failure_count"]) + int(
			section.get("failure_count", 0)
		)
		for failure in section.get("sample_failures", []):
			_append_failure(result, str(failure))
	result["status"] = "PASS" if int(result["failure_count"]) == 0 else "FAIL"
	result["elapsed_ms"] = float(Time.get_ticks_usec() - started_usec) / 1000.0
	return result


func standard_signature() -> Dictionary:
	return {
		"near_isovalue_epsilons": NEAR_ISOVALUE_EPSILONS,
		"regular_case_count": 256,
		"regular_probe_count": 256 * NEAR_ISOVALUE_EPSILONS.size(),
		"transition_case_count": 512,
		"transition_orientation": Contracts.TRANSITION_ORIENTATION_NAMES[
			Contracts.TRANSITION_ORIENTATION_POSITIVE_Z
		],
		"transition_probe_count": 512 * NEAR_ISOVALUE_EPSILONS.size(),
		"vertical_chunk_count": VERTICAL_CHUNK_COUNT,
		"vertical_same_lod_interfaces": VERTICAL_CHUNK_COUNT - 1,
		"vertical_mixed_lod_faces": [
			Contracts.CHUNK_FACE_NAMES[VERTICAL_MIXED_FACES[0]],
			Contracts.CHUNK_FACE_NAMES[VERTICAL_MIXED_FACES[1]],
		],
	}


func _validate_near_isovalue(probe: RefCounted) -> Dictionary:
	var regular_failures := 0
	var transition_failures := 0
	var buffer_failures := 0
	var failures: Array[String] = []
	for case_code in range(256):
		var baseline := CaseValidator.mesh_regular_case(probe, case_code)
		var input := CaseValidator.regular_case_input(case_code)
		for epsilon_value in NEAR_ISOVALUE_EPSILONS:
			var epsilon := float(epsilon_value)
			var mesh: Dictionary = probe.call(
				"mesh_regular_cell",
				_scaled_densities(input["densities"], epsilon),
				input["gradients"],
				input["materials"],
				Vector3.ZERO,
				1.0,
				0.0
			)
			var equivalent := MeshAnalysis.cell_meshes_equivalent(baseline, mesh)
			if not equivalent:
				regular_failures += 1
				_append_case_failure(
					failures,
					"regular case %d changed at epsilon %.8f" % [case_code, epsilon]
				)
			var validation := MeshAnalysis.validate_cell_mesh_buffers(
				mesh,
				Contracts.REGULAR_CORNER_COUNT,
				Contracts.REGULAR_CORNER_COUNT
			)
			if int(validation.get("failures", 0)) > 0:
				buffer_failures += int(validation.get("failures", 0))
				_append_case_failure(
					failures,
					"regular case %d failed integrity at epsilon %.8f" % [
						case_code,
						epsilon,
					]
				)
	for case_code in range(512):
		var baseline := CaseValidator.mesh_transition_case(
			probe,
			case_code,
			Contracts.TRANSITION_ORIENTATION_POSITIVE_Z
		)
		var input := CaseValidator.transition_case_input(case_code)
		for epsilon_value in NEAR_ISOVALUE_EPSILONS:
			var epsilon := float(epsilon_value)
			var mesh: Dictionary = probe.call(
				"mesh_transition_cell",
				_scaled_densities(input["densities"], epsilon),
				input["gradients"],
				input["materials"],
				Contracts.TRANSITION_ORIENTATION_POSITIVE_Z,
				Vector3.ZERO,
				1.0,
				0.25,
				0.0
			)
			var equivalent := MeshAnalysis.cell_meshes_equivalent(baseline, mesh)
			if not equivalent:
				transition_failures += 1
				_append_case_failure(
					failures,
					"transition case %d changed at epsilon %.8f" % [
						case_code,
						epsilon,
					]
				)
			var validation := MeshAnalysis.validate_cell_mesh_buffers(
				mesh,
				Contracts.TRANSITION_SAMPLE_COUNT,
				Contracts.TRANSITION_TOPOLOGY_SAMPLE_COUNT
			)
			if int(validation.get("failures", 0)) > 0:
				buffer_failures += int(validation.get("failures", 0))
				_append_case_failure(
					failures,
					"transition case %d failed integrity at epsilon %.8f" % [
						case_code,
						epsilon,
					]
				)
	var total_failures := regular_failures + transition_failures + buffer_failures
	return {
		"status": "PASS" if total_failures == 0 else "FAIL",
		"epsilons": NEAR_ISOVALUE_EPSILONS,
		"regular_case_count": 256,
		"regular_probe_count": 256 * NEAR_ISOVALUE_EPSILONS.size(),
		"regular_geometry_mismatches": regular_failures,
		"transition_case_count": 512,
		"transition_probe_count": 512 * NEAR_ISOVALUE_EPSILONS.size(),
		"transition_geometry_mismatches": transition_failures,
		"buffer_failures": buffer_failures,
		"failure_count": total_failures,
		"sample_failures": failures,
	}


func _validate_vertical_stack(probe: RefCounted) -> Dictionary:
	var chunks: Array[Dictionary] = []
	var failures: Array[String] = []
	var failed_chunks := 0
	var buffer_failures := 0
	for y in range(VERTICAL_CHUNK_COUNT):
		var chunk: Dictionary = probe.call(
			"mesh_chunk_with_callable",
			Callable(self, "_sample_vertical_shell"),
			Vector3i(0, y, 0),
			0,
			0,
			0,
			0.0,
			0.25
		)
		chunks.append(chunk)
		if not bool(chunk.get("ok", false)):
			failed_chunks += 1
			_append_case_failure(failures, "vertical chunk %d failed to mesh" % y)
		var chunk_buffer_failures := _chunk_integrity_failure_count(chunk, false)
		buffer_failures += chunk_buffer_failures
		if chunk_buffer_failures > 0:
			_append_case_failure(
				failures,
				"vertical chunk %d failed %d mesh-integrity checks" % [
					y,
					chunk_buffer_failures,
				]
			)
	var matching_interfaces := 0
	var empty_interfaces := 0
	var unmatched_edges := 0
	var interfaces: Array = []
	for y in range(VERTICAL_CHUNK_COUNT - 1):
		var plane := float((y + 1) * Contracts.CHUNK_PROBE_CELLS_PER_AXIS)
		var lower_signatures := MeshAnalysis.plane_open_edge_signatures(
			[_regular_chunk_buffer(chunks[y])],
			1,
			plane
		)
		var upper_signatures := MeshAnalysis.plane_open_edge_signatures(
			[_regular_chunk_buffer(chunks[y + 1])],
			1,
			plane
		)
		var difference := MeshAnalysis.set_difference_counts(
			lower_signatures,
			upper_signatures
		)
		var signature_count := lower_signatures.size()
		var matches := int(difference["left_only"]) == 0 \
			and int(difference["right_only"]) == 0
		matching_interfaces += 1 if matches and signature_count > 0 else 0
		empty_interfaces += 1 if signature_count == 0 else 0
		unmatched_edges += int(difference["left_only"]) + int(difference["right_only"])
		if not matches or signature_count == 0:
			_append_case_failure(
				failures,
				"vertical same-LOD interface y=%.1f did not produce matching geometry" % plane
			)
		interfaces.append({
			"plane": plane,
			"signature_count": signature_count,
			"lower_only": int(difference["left_only"]),
			"upper_only": int(difference["right_only"]),
			"status": "PASS" if matches and signature_count > 0 else "FAIL",
		})
	var mixed_matching := 0
	var mixed_empty := 0
	var mixed_unmatched_edges := 0
	var mixed_interfaces: Array = []
	for face in VERTICAL_MIXED_FACES:
		var fixture := _chunk_validator.build_mixed_lod_fixture(probe, face, 1)
		var comparison: Dictionary = fixture.get("comparison", {})
		var coarse_count := int(comparison.get("coarse_signature_count", 0))
		var fine_count := int(comparison.get("fine_signature_count", 0))
		var mixed_buffer_failures := _mixed_fixture_integrity_failure_count(fixture)
		buffer_failures += mixed_buffer_failures
		var matches := bool(fixture.get("ok", false)) \
			and bool(comparison.get("matches", false)) \
			and mixed_buffer_failures == 0
		mixed_matching += 1 if matches and coarse_count > 0 and fine_count > 0 else 0
		mixed_empty += 1 if coarse_count == 0 or fine_count == 0 else 0
		mixed_unmatched_edges += int(comparison.get("coarse_only", 0)) \
			+ int(comparison.get("fine_only", 0))
		if not matches or coarse_count == 0 or fine_count == 0:
			_append_case_failure(
				failures,
				"vertical mixed-LOD interface %s did not produce matching geometry" % (
					Contracts.CHUNK_FACE_NAMES[face]
				)
			)
		mixed_interfaces.append({
			"face": Contracts.CHUNK_FACE_NAMES[face],
			"coarse_signature_count": coarse_count,
			"fine_signature_count": fine_count,
			"coarse_only": int(comparison.get("coarse_only", 0)),
			"fine_only": int(comparison.get("fine_only", 0)),
			"buffer_failures": mixed_buffer_failures,
			"status": (
				"PASS" if matches and coarse_count > 0 and fine_count > 0 else "FAIL"
			),
		})
	var failure_count := failed_chunks \
		+ buffer_failures \
		+ (VERTICAL_CHUNK_COUNT - 1 - matching_interfaces) \
		+ (VERTICAL_MIXED_FACES.size() - mixed_matching)
	return {
		"status": "PASS" if failure_count == 0 else "FAIL",
		"chunk_count": chunks.size(),
		"failed_chunks": failed_chunks,
		"buffer_failures": buffer_failures,
		"same_lod_interface_count": VERTICAL_CHUNK_COUNT - 1,
		"same_lod_matching_interfaces": matching_interfaces,
		"same_lod_empty_interfaces": empty_interfaces,
		"same_lod_unmatched_edges": unmatched_edges,
		"same_lod_interfaces": interfaces,
		"mixed_lod_interface_count": VERTICAL_MIXED_FACES.size(),
		"mixed_lod_matching_interfaces": mixed_matching,
		"mixed_lod_empty_interfaces": mixed_empty,
		"mixed_lod_unmatched_edges": mixed_unmatched_edges,
		"mixed_lod_interfaces": mixed_interfaces,
		"failure_count": failure_count,
		"sample_failures": failures,
	}


func _sample_vertical_shell(point: Vector3i) -> Dictionary:
	var p := Vector3(point)
	var lower_height := 16.0 \
		+ 2.1 * sin((p.x + 1.0) * 0.31) \
		+ 1.6 * cos((p.z - 2.0) * 0.27)
	var upper_height := 32.0 \
		+ 1.8 * cos((p.x - 3.0) * 0.23) \
		+ 1.4 * sin((p.z + 2.0) * 0.29)
	var density := (p.y - lower_height) * (p.y - upper_height)
	var solid := density < 0.0
	return {
		"density": density,
		"material": 2 if solid else 0,
		"material_authored": solid,
	}


func _regular_chunk_buffer(chunk: Dictionary) -> Dictionary:
	var regular: Dictionary = chunk.get("regular", {})
	return {
		"vertices": regular.get("vertices", PackedVector3Array()),
		"indices": regular.get("indices", PackedInt32Array()),
		"origin": Vector3(
			float(chunk.get("world_origin_x", 0.0)),
			float(chunk.get("world_origin_y", 0.0)),
			float(chunk.get("world_origin_z", 0.0))
		),
	}


func _mixed_fixture_integrity_failure_count(fixture: Dictionary) -> int:
	var failures := _chunk_integrity_failure_count(
		fixture.get("coarse", {}),
		true
	)
	for fine_chunk_value in fixture.get("fine_chunks", []):
		failures += _chunk_integrity_failure_count(fine_chunk_value, false)
	return failures


func _chunk_integrity_failure_count(
	chunk: Dictionary,
	include_transitions: bool
) -> int:
	if chunk.is_empty() or not bool(chunk.get("ok", false)):
		return 0
	var meshes: Array = [chunk.get("regular", {})]
	if include_transitions:
		meshes.append_array(chunk.get("transitions", []))
	var failures := 0
	for mesh_value in meshes:
		var mesh: Dictionary = mesh_value
		var vertices: PackedVector3Array = mesh.get(
			"vertices",
			PackedVector3Array()
		)
		var normals: PackedVector3Array = mesh.get("normals", PackedVector3Array())
		var indices: PackedInt32Array = mesh.get("indices", PackedInt32Array())
		if indices.size() % 3 != 0:
			failures += 1
		for index in indices:
			if int(index) < 0 or int(index) >= vertices.size():
				failures += 1
				break
		if not vertices.is_empty() and normals.size() != vertices.size():
			failures += 1
		var integrity := MeshAnalysis.validate_triangle_mesh_integrity(
			vertices,
			normals,
			indices
		)
		for key in [
			"nonfinite_vertices",
			"degenerate_triangles",
			"duplicate_triangles",
			"winding_normal_conflicts",
		]:
			failures += int(integrity.get(key, 0))
		failures += int(
			MeshAnalysis.orientation_metrics(
				vertices,
				indices
			).get("orientation_conflict_edges", 0)
		)
	return failures


func _scaled_densities(source: PackedFloat32Array, epsilon: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for density in source:
		result.append(-epsilon if density < 0.0 else epsilon)
	return result


func _append_case_failure(failures: Array[String], message: String) -> void:
	if failures.size() < 32:
		failures.append(message)


func _append_failure(result: Dictionary, message: String) -> void:
	var failures: Array = result.get("sample_failures", [])
	if failures.size() < 32:
		failures.append(message)
	result["sample_failures"] = failures
