@tool
extends RefCounted
class_name WtCellLabCorrectnessQualification

const Contracts := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_contracts.gd")
const MeshAnalysis := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_mesh_analysis.gd")
const CaseValidator := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_case_validator.gd")
const AdversarialField := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_adversarial_field.gd")
const Common := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_qualification_common.gd")

const MINIMIZED_REPRO_SCHEMA := "world_transvoxel.cell_lab.minimized_native_repro.v1"
const INTERPOLATION_TOLERANCE := 0.0002
const TRANSITION_ALIAS_SAMPLES := [0, 2, 6, 8]
const EXPECTED_ADVERSARIAL_NEGATIVES := {}


func validate(
	probe: RefCounted,
	reference_terrain: RefCounted
) -> Dictionary:
	var start_usec := Time.get_ticks_usec()
	var adversarial := _validate_adversarial_corpus(probe)
	var reduction := _validate_failure_reduction(probe, reference_terrain)
	var specification := _validate_independent_specification(probe)
	var failures: Array[String] = []
	for entry in [
		["adversarial_corpus", adversarial],
		["failure_reduction", reduction],
		["independent_specification", specification],
	]:
		var section: Dictionary = entry[1]
		if str(section.get("status", "")) != "PASS":
			failures.append("%s=%s" % [str(entry[0]), str(section.get("status", "FAIL"))])
	return {
		"schema": Contracts.CORRECTNESS_QUALIFICATION_SCHEMA,
		"status": "PASS" if failures.is_empty() else "FAIL",
		"authority": Contracts.NATIVE_AUTHORITY,
		"adversarial_corpus": adversarial,
		"failure_reduction": reduction,
		"independent_specification": specification,
		"sample_failures": failures,
		"elapsed_ms": float(Time.get_ticks_usec() - start_usec) / 1000.0,
	}


func standard_signature(validation: Dictionary) -> Dictionary:
	var adversarial: Dictionary = validation.get("adversarial_corpus", {})
	var reduction: Dictionary = validation.get("failure_reduction", {})
	var specification: Dictionary = validation.get("independent_specification", {})
	return {
		"schema": Contracts.CORRECTNESS_QUALIFICATION_STANDARD_SCHEMA,
		"adversarial_profile_count": int(adversarial.get("profile_count", 0)),
		"adversarial_probe_count": int(adversarial.get("probe_count", 0)),
		"adversarial_triangle_count": int(adversarial.get("triangle_count", 0)),
		"adversarial_signature": str(adversarial.get("corpus_signature", "")),
		"minimized_fixture_id": str(reduction.get("fixture_id", "")),
		"minimized_case_code": int(reduction.get("case_code", -1)),
		"minimized_cell": reduction.get("cell", Vector3i(-1, -1, -1)),
		"minimized_sample_count": int(reduction.get("sample_count", 0)),
		"minimized_reproduced_disagreements": int(
			reduction.get("reproduced_local_disagreements", 0)
		),
		"regular_intersections_checked": int(
			specification.get("regular_intersections_checked", 0)
		),
		"transition_intersections_checked": int(
			specification.get("transition_intersections_checked", 0)
		),
		"complement_pairs_checked": int(
			specification.get("complement_pairs_checked", 0)
		),
		"orientation_probes_checked": int(
			specification.get("orientation_probes_checked", 0)
		),
		"complement_topology_asymmetries": int(
			specification.get("complement_topology_asymmetries", 0)
		),
		"status": str(validation.get("status", "FAIL")),
	}


func _validate_adversarial_corpus(probe: RefCounted) -> Dictionary:
	var failures: Array = []
	var cases: Array[Dictionary] = []
	var total_triangles := 0
	var total_vertices := 0
	var total_samples := 0
	var total_local_disagreements := 0
	var detected_negative_probes := 0
	var signature_lines: Array[String] = []
	for profile_id in AdversarialField.PROFILE_IDS:
		for lod in [0, 1]:
			var field := AdversarialField.new()
			field.configure(profile_id)
			var first := Common.mesh_chunk(probe, field, Vector3i.ZERO, lod, 0)
			var second := Common.mesh_chunk(probe, field, Vector3i.ZERO, lod, 0)
			var integrity := Common.validate_chunk(first)
			var first_signature := Common.chunk_signature(first)
			var second_signature := Common.chunk_signature(second)
			var deterministic := first_signature == second_signature
			var triangles := int(integrity.get("triangle_count", 0))
			var vertices := int(integrity.get("vertex_count", 0))
			var negative_key := "%s:%d" % [profile_id, lod]
			var expected_negative: Dictionary = EXPECTED_ADVERSARIAL_NEGATIVES.get(
				negative_key,
				{}
			)
			var negative_detected := false
			var case_ok := false
			if expected_negative.is_empty():
				case_ok = str(integrity.get("status", "")) == "PASS" \
					and deterministic \
					and triangles > 0 \
					and int(first.get("sample_count", 0)) > 0
			else:
				negative_detected = deterministic \
					and int(integrity.get("interior_open_edges", -1)) == int(
						expected_negative.get("interior_open_edges", -2)
					) \
					and int(
						integrity.get("local_winding_normal_disagreements", -1)
					) == int(
						expected_negative.get(
							"local_winding_normal_disagreements",
							-2
						)
					) \
					and int(integrity.get("nonmanifold_edges", -1)) == 0 \
					and int(integrity.get("orientation_conflict_edges", -1)) == 0
				case_ok = negative_detected
				if negative_detected:
					detected_negative_probes += 1
			var entry := {
				"profile_id": profile_id,
				"lod": lod,
				"status": "PASS" if case_ok else "FAIL",
				"expected_negative": not expected_negative.is_empty(),
				"negative_detected": negative_detected,
				"deterministic": deterministic,
				"sample_count": int(first.get("sample_count", 0)),
				"active_cells": int(first.get("active_cells", 0)),
				"vertices": vertices,
				"triangles": triangles,
				"local_winding_normal_disagreements": int(
					integrity.get("local_winding_normal_disagreements", 0)
				),
				"local_winding_normal_ambiguous": int(
					integrity.get("local_winding_normal_ambiguous", 0)
				),
				"geometry_signature": first_signature,
				"sample_failures": integrity.get("sample_failures", []),
			}
			cases.append(entry)
			total_triangles += triangles
			total_vertices += vertices
			total_samples += int(first.get("sample_count", 0))
			total_local_disagreements += int(
				integrity.get("local_winding_normal_disagreements", 0)
			)
			signature_lines.append("%s:%d:%s:%d:%d" % [
				profile_id,
				lod,
				first_signature,
				vertices,
				triangles,
			])
			if not case_ok and failures.size() < 32:
				failures.append({
					"profile_id": profile_id,
					"lod": lod,
					"integrity": integrity,
					"deterministic": deterministic,
				})
	return {
		"schema": Contracts.ADVERSARIAL_CORPUS_SCHEMA,
		"status": "PASS" if failures.is_empty() else "FAIL",
		"profile_count": AdversarialField.PROFILE_IDS.size(),
		"lod_count": 2,
		"probe_count": cases.size(),
		"passing_probes": cases.size() - failures.size(),
		"failing_probes": failures.size(),
		"expected_negative_probe_count": EXPECTED_ADVERSARIAL_NEGATIVES.size(),
		"detected_negative_probe_count": detected_negative_probes,
		"sample_count": total_samples,
		"vertex_count": total_vertices,
		"triangle_count": total_triangles,
		"observed_local_winding_normal_disagreements": total_local_disagreements,
		"corpus_signature": "\n".join(signature_lines).sha256_text(),
		"cases": cases,
		"sample_failures": failures,
	}


func _validate_failure_reduction(
	probe: RefCounted,
	reference_terrain: RefCounted
) -> Dictionary:
	var fixture: Dictionary = reference_terrain.call(
		"build_topology_alias_fixture",
		probe
	)
	var coarse_buffer: Dictionary = fixture.get("coarse_buffer", {})
	var vertices: PackedVector3Array = coarse_buffer.get(
		"vertices",
		PackedVector3Array()
	)
	var normals: PackedVector3Array = coarse_buffer.get("normals", PackedVector3Array())
	var indices: PackedInt32Array = coarse_buffer.get("indices", PackedInt32Array())
	var integrity := MeshAnalysis.validate_triangle_mesh_integrity(
		vertices,
		normals,
		indices
	)
	var samples: Array = integrity.get("local_winding_normal_samples", [])
	var minimized := {}
	for sample_value in samples:
		var sample: Dictionary = sample_value
		var triangle_index := int(sample.get("triangle_index", -1))
		var candidate := _minimize_triangle_cell(
			probe,
			fixture.get("field"),
			coarse_buffer,
			triangle_index
		)
		if int(candidate.get("reproduced_local_disagreements", 0)) > 0:
			minimized = candidate
			break
	if minimized.is_empty() and not samples.is_empty():
		minimized = _minimize_triangle_cell(
			probe,
			fixture.get("field"),
			coarse_buffer,
			int((samples[0] as Dictionary).get("triangle_index", -1))
		)
	var status_ok := not minimized.is_empty() \
		and int(integrity.get("local_winding_normal_disagreements", 0)) == 8 \
		and int(minimized.get("sample_count", 0)) == 8 \
		and int(minimized.get("mixed_sign_edge_count", 0)) > 0 \
		and int(minimized.get("reproduced_local_disagreements", 0)) > 0 \
		and str(minimized.get("repro_schema", "")) == MINIMIZED_REPRO_SCHEMA
	var result := {
		"schema": Contracts.FAILURE_REDUCTION_SCHEMA,
		"status": "PASS" if status_ok else "FAIL",
		"fixture_id": "coarse_tunnel_roof_alias_v1",
		"source_layer": "world_transvoxel",
		"source_chunk_disagreements": int(
			integrity.get("local_winding_normal_disagreements", 0)
		),
		"candidate_triangle_count": samples.size(),
		"sample_failures": [] if status_ok else ["native one-cell reduction did not reproduce"],
	}
	result.merge(minimized)
	return result


func _minimize_triangle_cell(
	probe: RefCounted,
	field: RefCounted,
	buffer: Dictionary,
	triangle_index: int
) -> Dictionary:
	if field == null or triangle_index < 0:
		return {}
	var vertices: PackedVector3Array = buffer.get("vertices", PackedVector3Array())
	var indices: PackedInt32Array = buffer.get("indices", PackedInt32Array())
	var offset := triangle_index * 3
	if offset + 2 >= indices.size():
		return {}
	var centroid := (
		vertices[int(indices[offset])]
		+ vertices[int(indices[offset + 1])]
		+ vertices[int(indices[offset + 2])]
	) / 3.0
	var lod := int(buffer.get("lod", 1))
	var cell_size := float(1 << lod)
	var cell := Vector3i(
		clampi(floori(centroid.x / cell_size), 0, 15),
		clampi(floori(centroid.y / cell_size), 0, 15),
		clampi(floori(centroid.z / cell_size), 0, 15)
	)
	var origin: Vector3 = buffer.get("origin", Vector3.ZERO)
	var cell_world_origin := origin + Vector3(cell) * cell_size
	var densities := PackedFloat32Array()
	var gradients := PackedVector3Array()
	var materials := PackedInt32Array()
	var sample_records: Array[Dictionary] = []
	var case_code := 0
	for corner in range(8):
		var corner_offset := Vector3(
			1.0 if (corner & 1) != 0 else 0.0,
			1.0 if (corner & 2) != 0 else 0.0,
			1.0 if (corner & 4) != 0 else 0.0
		)
		var point := cell_world_origin + corner_offset * cell_size
		var sample: Dictionary = field.call("sample_point", point)
		var density_value := float(sample.get("density", 0.0))
		var gradient := _field_gradient(field, point, cell_size)
		densities.append(density_value)
		gradients.append(gradient)
		materials.append(maxi(int(sample.get("material", 1)), 1))
		if density_value < 0.0:
			case_code |= 1 << corner
		sample_records.append({
			"corner": corner,
			"position": Common.vector_dictionary(point),
			"density": density_value,
			"gradient": Common.vector_dictionary(gradient),
			"material": int(materials[corner]),
		})
	var cell_mesh: Dictionary = probe.call(
		"mesh_regular_cell",
		densities,
		gradients,
		materials,
		Vector3.ZERO,
		cell_size,
		0.0
	)
	var cell_integrity := MeshAnalysis.validate_triangle_mesh_integrity(
		cell_mesh.get("vertices", PackedVector3Array()),
		cell_mesh.get("normals", PackedVector3Array()),
		cell_mesh.get("indices", PackedInt32Array())
	)
	var mixed_edges := 0
	for pair in [
		[0, 1], [0, 2], [0, 4], [1, 3], [1, 5], [2, 3],
		[2, 6], [3, 7], [4, 5], [4, 6], [5, 7], [6, 7],
	]:
		if float(densities[pair[0]]) * float(densities[pair[1]]) < 0.0:
			mixed_edges += 1
	return {
		"repro_schema": MINIMIZED_REPRO_SCHEMA,
		"triangle_index": triangle_index,
		"cell": cell,
		"cell_world_origin": cell_world_origin,
		"cell_size": cell_size,
		"case_code": case_code,
		"sample_count": sample_records.size(),
		"samples": sample_records,
		"mixed_sign_edge_count": mixed_edges,
		"native_status": str(cell_mesh.get("status", "Unknown")),
		"native_triangles": int(
			(cell_mesh.get("indices", PackedInt32Array()) as PackedInt32Array).size() / 3
		),
		"reproduced_local_disagreements": int(
			cell_integrity.get("local_winding_normal_disagreements", 0)
		),
		"reproduced_local_ambiguous": int(
			cell_integrity.get("local_winding_normal_ambiguous", 0)
		),
		"repro_hash": Common.json_hash(sample_records),
	}


func _field_gradient(field: RefCounted, point: Vector3, step: float) -> Vector3:
	var gradient := Vector3(
		float(field.call("density", point + Vector3(step, 0.0, 0.0)))
			- float(field.call("density", point - Vector3(step, 0.0, 0.0))),
		float(field.call("density", point + Vector3(0.0, step, 0.0)))
			- float(field.call("density", point - Vector3(0.0, step, 0.0))),
		float(field.call("density", point + Vector3(0.0, 0.0, step)))
			- float(field.call("density", point - Vector3(0.0, 0.0, step)))
	)
	return gradient.normalized() if gradient.length_squared() > 0.000000000001 else Vector3.UP


func _validate_independent_specification(probe: RefCounted) -> Dictionary:
	var failures: Array = []
	var regular_checked := 0
	var transition_checked := 0
	var complement_pairs := 0
	var complement_topology_asymmetries := 0
	var orientation_checked := 0
	var regular_meshes: Array[Dictionary] = []
	regular_meshes.resize(256)
	for case_code in range(256):
		var input := CaseValidator.regular_case_input(case_code)
		var mesh := CaseValidator.mesh_regular_case(probe, case_code)
		regular_meshes[case_code] = mesh
		var check := _validate_interpolated_vertices(
			mesh,
			input.get("densities", PackedFloat32Array()),
			CaseValidator.regular_corner_positions()
		)
		regular_checked += int(check.get("checked", 0))
		_append_limited_failures(failures, check.get("failures", []), {
			"cell_type": "regular",
			"case": case_code,
		})
	for case_code in range(128):
		var complement := 255 - case_code
		complement_pairs += 1
		var first: Dictionary = regular_meshes[case_code]
		var second: Dictionary = regular_meshes[complement]
		if str(first.get("status", "")) != str(second.get("status", "")):
			_append_limited_failures(failures, ["complement status mismatch"], {
				"cell_type": "regular",
				"case": case_code,
				"complement": complement,
			})
		elif (
					first.get("indices", PackedInt32Array()) as PackedInt32Array
				).size() != (
					second.get("indices", PackedInt32Array()) as PackedInt32Array
				).size():
			complement_topology_asymmetries += 1
	var transition_meshes: Array[Dictionary] = []
	transition_meshes.resize(512)
	var transition_positions := _transition_topology_positions(
		MeshAnalysis.transition_basis(Contracts.TRANSITION_ORIENTATION_POSITIVE_Z)
	)
	for case_code in range(512):
		var input := CaseValidator.transition_case_input(case_code)
		var densities := _transition_topology_densities(
			input.get("densities", PackedFloat32Array())
		)
		var mesh := CaseValidator.mesh_transition_case(
			probe,
			case_code,
			Contracts.TRANSITION_ORIENTATION_POSITIVE_Z
		)
		transition_meshes[case_code] = mesh
		var check := _validate_interpolated_vertices(
			mesh,
			densities,
			transition_positions
		)
		transition_checked += int(check.get("checked", 0))
		_append_limited_failures(failures, check.get("failures", []), {
			"cell_type": "transition",
			"case": case_code,
			"orientation": Contracts.TRANSITION_ORIENTATION_POSITIVE_Z,
		})
	for case_code in range(256):
		var complement := 511 - case_code
		complement_pairs += 1
		var first: Dictionary = transition_meshes[case_code]
		var second: Dictionary = transition_meshes[complement]
		if str(first.get("status", "")) != str(second.get("status", "")):
			_append_limited_failures(failures, ["complement status mismatch"], {
				"cell_type": "transition",
				"case": case_code,
				"complement": complement,
			})
		elif (
					first.get("indices", PackedInt32Array()) as PackedInt32Array
				).size() != (
					second.get("indices", PackedInt32Array()) as PackedInt32Array
				).size():
			complement_topology_asymmetries += 1
	for case_code in [1, 7, 42, 85, 170, 341, 448, 510]:
		var input := CaseValidator.transition_case_input(case_code)
		var densities := _transition_topology_densities(
			input.get("densities", PackedFloat32Array())
		)
		for orientation in range(Contracts.TRANSITION_ORIENTATION_NAMES.size()):
			var mesh := CaseValidator.mesh_transition_case(probe, case_code, orientation)
			var positions := _transition_topology_positions(
				MeshAnalysis.transition_basis(orientation)
			)
			var check := _validate_interpolated_vertices(mesh, densities, positions)
			orientation_checked += 1
			_append_limited_failures(failures, check.get("failures", []), {
				"cell_type": "transition",
				"case": case_code,
				"orientation": orientation,
			})
	return {
		"schema": Contracts.SPECIFICATION_VALIDATION_SCHEMA,
		"status": "PASS" if failures.is_empty() else "FAIL",
		"regular_cases_checked": 256,
		"transition_cases_checked": 512,
		"regular_intersections_checked": regular_checked,
		"transition_intersections_checked": transition_checked,
		"complement_pairs_checked": complement_pairs,
		"complement_topology_asymmetries": complement_topology_asymmetries,
		"orientation_probes_checked": orientation_checked,
		"interpolation_tolerance": INTERPOLATION_TOLERANCE,
		"sample_failures": failures,
	}


func _validate_interpolated_vertices(
	mesh: Dictionary,
	densities: PackedFloat32Array,
	positions: PackedVector3Array
) -> Dictionary:
	var failures: Array[String] = []
	if str(mesh.get("status", "")) not in ["Ok", "Empty"]:
		return {"checked": 0, "failures": ["native status is not Ok or Empty"]}
	var vertices: PackedVector3Array = mesh.get("vertices", PackedVector3Array())
	var endpoint_a: PackedInt32Array = mesh.get("endpoint_a", PackedInt32Array())
	var endpoint_b: PackedInt32Array = mesh.get("endpoint_b", PackedInt32Array())
	var checked := 0
	for index in range(vertices.size()):
		if index >= endpoint_a.size() or index >= endpoint_b.size():
			failures.append("missing endpoint provenance")
			continue
		var a := int(endpoint_a[index])
		var b := int(endpoint_b[index])
		if a < 0 or b < 0 or a >= densities.size() or b >= densities.size() \
				or a >= positions.size() or b >= positions.size():
			failures.append("endpoint outside independent topology")
			continue
		var da := float(densities[a])
		var db := float(densities[b])
		if da * db >= 0.0:
			failures.append("endpoint densities do not bracket isovalue")
			continue
		var interpolation := da / (da - db)
		var expected := positions[a].lerp(positions[b], interpolation)
		if expected.distance_to(vertices[index]) > INTERPOLATION_TOLERANCE:
			failures.append("vertex does not match independent linear interpolation")
		checked += 1
	return {"checked": checked, "failures": failures}


func _transition_topology_densities(high_resolution: PackedFloat32Array) -> PackedFloat32Array:
	var densities := high_resolution.duplicate()
	for sample_index in TRANSITION_ALIAS_SAMPLES:
		densities.append(high_resolution[sample_index])
	return densities


func _transition_topology_positions(basis: Dictionary) -> PackedVector3Array:
	var u: Vector3 = basis.get("u", Vector3.RIGHT)
	var v: Vector3 = basis.get("v", Vector3.UP)
	var w: Vector3 = basis.get("w", Vector3.FORWARD)
	var positions := PackedVector3Array()
	for sample_index in range(9):
		positions.append(
			u * float(sample_index % 3) + v * float(int(sample_index / 3))
		)
	for sample_index in TRANSITION_ALIAS_SAMPLES:
		positions.append(
			u * float(sample_index % 3)
				+ v * float(int(sample_index / 3))
				+ w * 0.25
		)
	return positions


func _append_limited_failures(
	target: Array,
	failures: Array,
	context: Dictionary
) -> void:
	for message in failures:
		if target.size() >= 32:
			return
		var entry := context.duplicate(true)
		entry["message"] = str(message)
		target.append(entry)
