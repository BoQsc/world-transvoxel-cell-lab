@tool
extends RefCounted
class_name WtCellLabCaseValidator

const Contracts := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_contracts.gd")
const MeshAnalysis := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_mesh_analysis.gd")
const TRANSITION_CASE_BIT_SAMPLES := [0, 1, 2, 5, 8, 7, 6, 3, 4]


static func validate_regular(probe: RefCounted) -> Dictionary:
	var start_usec := Time.get_ticks_usec()
	var result := {
		"schema": Contracts.REGULAR_CASE_CORPUS_SCHEMA,
		"available": probe != null,
		"authority": Contracts.NATIVE_AUTHORITY,
		"case_count": 256,
		"ok_cases": 0,
		"empty_cases": 0,
		"failed_cases": 0,
		"expected_empty_mismatches": 0,
		"determinism_failures": 0,
		"buffer_failures": 0,
		"material_failures": 0,
		"provenance_failures": 0,
		"total_vertices": 0,
		"total_triangles": 0,
		"sample_failures": [],
		"status": "Unavailable" if probe == null else "PASS",
		"elapsed_ms": 0.0,
	}
	if probe == null:
		return result
	for case_code in range(256):
		var cell_mesh := mesh_regular_case(probe, case_code)
		var repeated_mesh := mesh_regular_case(probe, case_code)
		var status := str(cell_mesh.get("status", "Unknown"))
		var expected_empty := case_code == 0 or case_code == 255
		if status == "Ok":
			result["ok_cases"] = int(result["ok_cases"]) + 1
		elif status == "Empty":
			result["empty_cases"] = int(result["empty_cases"]) + 1
		else:
			result["failed_cases"] = int(result["failed_cases"]) + 1
			MeshAnalysis.append_sample_failure(result, case_code, -1, "regular status=%s" % status)
		if (status == "Empty") != expected_empty:
			result["expected_empty_mismatches"] = int(result["expected_empty_mismatches"]) + 1
			MeshAnalysis.append_sample_failure(result, case_code, -1, "regular empty classification mismatch")
		if not MeshAnalysis.cell_meshes_equivalent(cell_mesh, repeated_mesh):
			result["determinism_failures"] = int(result["determinism_failures"]) + 1
			MeshAnalysis.append_sample_failure(result, case_code, -1, "regular result is not deterministic")
		var validation := MeshAnalysis.validate_cell_mesh_buffers(
			cell_mesh,
			Contracts.REGULAR_CORNER_COUNT,
			Contracts.REGULAR_CORNER_COUNT
		)
		if int(validation.get("failures", 0)) > 0:
			result["buffer_failures"] = int(result["buffer_failures"]) + int(validation.get("failures", 0))
			MeshAnalysis.append_sample_failure(
				result,
				case_code,
				-1,
				str(validation.get("first_failure", "regular buffer validation failed"))
			)
		var provenance := _provenance_metrics(cell_mesh)
		result["material_failures"] = int(result["material_failures"]) + int(provenance.get("material_failures", 0))
		result["provenance_failures"] = int(result["provenance_failures"]) + int(provenance.get("provenance_failures", 0))
		var vertices: PackedVector3Array = cell_mesh.get("vertices", PackedVector3Array())
		var indices: PackedInt32Array = cell_mesh.get("indices", PackedInt32Array())
		result["total_vertices"] = int(result["total_vertices"]) + vertices.size()
		result["total_triangles"] = int(result["total_triangles"]) + int(indices.size() / 3)
	result["elapsed_ms"] = float(Time.get_ticks_usec() - start_usec) / 1000.0
	for key in [
		"failed_cases",
		"expected_empty_mismatches",
		"determinism_failures",
		"buffer_failures",
		"material_failures",
		"provenance_failures",
	]:
		if int(result[key]) > 0:
			result["status"] = "FAIL"
			break
	return result


static func validate_transition(probe: RefCounted) -> Dictionary:
	var start_usec := Time.get_ticks_usec()
	var orientation_count := Contracts.TRANSITION_ORIENTATION_NAMES.size()
	var result := {
		"schema": Contracts.TRANSITION_CASE_CORPUS_SCHEMA,
		"available": probe != null,
		"authority": Contracts.NATIVE_AUTHORITY,
		"case_count": 512,
		"orientation_count": orientation_count,
		"probe_count": 512 * orientation_count,
		"ok_cases": 0,
		"empty_cases": 0,
		"failed_cases": 0,
		"expected_empty_mismatches": 0,
		"orientation_status_mismatches": 0,
		"orientation_count_mismatches": 0,
		"determinism_failures": 0,
		"buffer_failures": 0,
		"bounds_failures": 0,
		"material_failures": 0,
		"provenance_failures": 0,
		"total_vertices": 0,
		"total_triangles": 0,
		"sample_failures": [],
		"status": "Unavailable" if probe == null else "PASS",
		"elapsed_ms": 0.0,
	}
	if probe == null:
		return result
	for case_code in range(512):
		var canonical_mesh := mesh_transition_case(
			probe,
			case_code,
			Contracts.TRANSITION_ORIENTATION_POSITIVE_Z
		)
		var canonical_status := str(canonical_mesh.get("status", "Unknown"))
		var expected_empty := case_code == 0 or case_code == 511
		if (canonical_status == "Empty") != expected_empty:
			result["expected_empty_mismatches"] = int(result["expected_empty_mismatches"]) + 1
			MeshAnalysis.append_sample_failure(
				result,
				case_code,
				Contracts.TRANSITION_ORIENTATION_POSITIVE_Z,
				"transition empty classification mismatch"
			)
		for orientation in range(orientation_count):
			var cell_mesh := mesh_transition_case(probe, case_code, orientation)
			var repeated_mesh := mesh_transition_case(probe, case_code, orientation)
			var status := str(cell_mesh.get("status", "Unknown"))
			if status == "Ok":
				result["ok_cases"] = int(result["ok_cases"]) + 1
			elif status == "Empty":
				result["empty_cases"] = int(result["empty_cases"]) + 1
			else:
				result["failed_cases"] = int(result["failed_cases"]) + 1
				MeshAnalysis.append_sample_failure(result, case_code, orientation, "transition status=%s" % status)
			if status != canonical_status:
				result["orientation_status_mismatches"] = int(result["orientation_status_mismatches"]) + 1
				MeshAnalysis.append_sample_failure(result, case_code, orientation, "orientation changed transition status")
			if status == "Ok":
				var vertices: PackedVector3Array = cell_mesh.get("vertices", PackedVector3Array())
				var indices: PackedInt32Array = cell_mesh.get("indices", PackedInt32Array())
				var canonical_vertices: PackedVector3Array = canonical_mesh.get("vertices", PackedVector3Array())
				var canonical_indices: PackedInt32Array = canonical_mesh.get("indices", PackedInt32Array())
				if vertices.size() != canonical_vertices.size() or indices.size() != canonical_indices.size():
					result["orientation_count_mismatches"] = int(result["orientation_count_mismatches"]) + 1
					MeshAnalysis.append_sample_failure(result, case_code, orientation, "orientation changed transition counts")
				result["total_vertices"] = int(result["total_vertices"]) + vertices.size()
				result["total_triangles"] = int(result["total_triangles"]) + int(indices.size() / 3)
				var bounds_failures := MeshAnalysis.transition_bounds_failure_count(vertices, orientation)
				if bounds_failures > 0:
					result["bounds_failures"] = int(result["bounds_failures"]) + bounds_failures
					MeshAnalysis.append_sample_failure(result, case_code, orientation, "transition vertex outside canonical prism")
			if not MeshAnalysis.cell_meshes_equivalent(cell_mesh, repeated_mesh):
				result["determinism_failures"] = int(result["determinism_failures"]) + 1
				MeshAnalysis.append_sample_failure(result, case_code, orientation, "transition result is not deterministic")
			var validation := MeshAnalysis.validate_cell_mesh_buffers(
				cell_mesh,
				Contracts.TRANSITION_SAMPLE_COUNT,
				Contracts.TRANSITION_TOPOLOGY_SAMPLE_COUNT
			)
			if int(validation.get("failures", 0)) > 0:
				result["buffer_failures"] = int(result["buffer_failures"]) + int(validation.get("failures", 0))
				MeshAnalysis.append_sample_failure(
					result,
					case_code,
					orientation,
					str(validation.get("first_failure", "transition buffer validation failed"))
				)
			var provenance := _provenance_metrics(cell_mesh)
			result["material_failures"] = int(result["material_failures"]) + int(provenance.get("material_failures", 0))
			result["provenance_failures"] = int(result["provenance_failures"]) + int(provenance.get("provenance_failures", 0))
	result["elapsed_ms"] = float(Time.get_ticks_usec() - start_usec) / 1000.0
	for key in [
		"failed_cases",
		"expected_empty_mismatches",
		"orientation_status_mismatches",
		"orientation_count_mismatches",
		"determinism_failures",
		"buffer_failures",
		"bounds_failures",
		"material_failures",
		"provenance_failures",
	]:
		if int(result[key]) > 0:
			result["status"] = "FAIL"
			break
	return result


static func describe_regular_case(probe: RefCounted, case_code: int) -> Dictionary:
	case_code = clampi(case_code, 0, 255)
	var input := regular_case_input(case_code)
	var mesh := mesh_regular_case(probe, case_code) if probe != null else {}
	return {
		"cell_type": "regular",
		"case_code": case_code,
		"case_code_binary": _binary_string(case_code, 8),
		"densities": input["densities"],
		"gradients": input["gradients"],
		"materials": input["materials"],
		"corner_positions": regular_corner_positions(),
		"edge_intersections": _edge_intersections(mesh),
		"backend_endpoint_provenance": _endpoint_provenance(mesh),
		"mesh": mesh,
	}


static func describe_transition_case(
	probe: RefCounted,
	case_code: int,
	orientation: int
) -> Dictionary:
	case_code = clampi(case_code, 0, 511)
	orientation = clampi(orientation, 0, Contracts.TRANSITION_ORIENTATION_NAMES.size() - 1)
	var input := transition_case_input(case_code)
	var mesh := mesh_transition_case(probe, case_code, orientation) if probe != null else {}
	return {
		"cell_type": "transition",
		"case_code": case_code,
		"case_code_binary": _binary_string(case_code, 9),
		"orientation": Contracts.TRANSITION_ORIENTATION_NAMES[orientation],
		"orientation_index": orientation,
		"orientation_basis": MeshAnalysis.transition_basis(orientation),
		"densities": input["densities"],
		"gradients": input["gradients"],
		"materials": input["materials"],
		"high_resolution_samples": range(9),
		"low_resolution_alias_samples": [9, 10, 11, 12],
		"stitching_edges": _edge_intersections(mesh),
		"backend_endpoint_provenance": _endpoint_provenance(mesh),
		"mesh": mesh,
	}


static func mesh_regular_case(probe: RefCounted, case_code: int) -> Dictionary:
	if probe == null:
		return {"status": "Unavailable", "ok": false, "empty": false}
	var input := regular_case_input(case_code)
	return probe.call(
		"mesh_regular_cell",
		input["densities"],
		input["gradients"],
		input["materials"],
		Vector3.ZERO,
		1.0,
		0.0
	)


static func mesh_transition_case(
	probe: RefCounted,
	case_code: int,
	orientation: int
) -> Dictionary:
	if probe == null:
		return {"status": "Unavailable", "ok": false, "empty": false}
	var input := transition_case_input(case_code)
	return probe.call(
		"mesh_transition_cell",
		input["densities"],
		input["gradients"],
		input["materials"],
		orientation,
		Vector3.ZERO,
		1.0,
		0.25,
		0.0
	)


static func regular_case_input(case_code: int) -> Dictionary:
	var densities := PackedFloat32Array()
	var gradients := PackedVector3Array()
	var materials := PackedInt32Array()
	for corner in range(Contracts.REGULAR_CORNER_COUNT):
		densities.append(-1.0 if (case_code & (1 << corner)) != 0 else 1.0)
		gradients.append(Vector3.RIGHT)
		materials.append(corner + 1)
	return {
		"densities": densities,
		"gradients": gradients,
		"materials": materials,
	}


static func transition_case_input(case_code: int) -> Dictionary:
	var densities := PackedFloat32Array()
	var gradients := PackedVector3Array()
	var materials := PackedInt32Array()
	for sample_index in range(Contracts.TRANSITION_SAMPLE_COUNT):
		var bit := transition_case_bit(sample_index)
		densities.append(-1.0 if (case_code & (1 << bit)) != 0 else 1.0)
		gradients.append(Vector3.RIGHT)
		materials.append(sample_index + 1)
	return {
		"densities": densities,
		"gradients": gradients,
		"materials": materials,
	}


static func regular_corner_positions() -> PackedVector3Array:
	var positions := PackedVector3Array()
	for corner in range(Contracts.REGULAR_CORNER_COUNT):
		positions.append(Vector3(
			1.0 if (corner & 1) != 0 else 0.0,
			1.0 if (corner & 2) != 0 else 0.0,
			1.0 if (corner & 4) != 0 else 0.0
		))
	return positions


static func transition_case_bit(sample_index: int) -> int:
	return TRANSITION_CASE_BIT_SAMPLES.find(sample_index)


static func _provenance_metrics(mesh: Dictionary) -> Dictionary:
	if not bool(mesh.get("ok", false)):
		return {"material_failures": 0, "provenance_failures": 0}
	var vertices: PackedVector3Array = mesh.get("vertices", PackedVector3Array())
	var materials: PackedInt32Array = mesh.get("materials", PackedInt32Array())
	var material_authored: PackedInt32Array = mesh.get("material_authored", PackedInt32Array())
	var endpoint_a: PackedInt32Array = mesh.get("endpoint_a", PackedInt32Array())
	var endpoint_b: PackedInt32Array = mesh.get("endpoint_b", PackedInt32Array())
	var material_failures := 0
	var provenance_failures := 0
	for index in range(vertices.size()):
		if index >= materials.size() or index >= material_authored.size():
			material_failures += 1
		elif int(materials[index]) <= 0 or int(material_authored[index]) != 1:
			material_failures += 1
		if index >= endpoint_a.size() or index >= endpoint_b.size() or int(endpoint_a[index]) == int(endpoint_b[index]):
			provenance_failures += 1
	return {
		"material_failures": material_failures,
		"provenance_failures": provenance_failures,
	}


static func _edge_intersections(mesh: Dictionary) -> Array:
	var intersections: Array = []
	var vertices: PackedVector3Array = mesh.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = mesh.get("normals", PackedVector3Array())
	var materials: PackedInt32Array = mesh.get("materials", PackedInt32Array())
	var endpoint_a: PackedInt32Array = mesh.get("endpoint_a", PackedInt32Array())
	var endpoint_b: PackedInt32Array = mesh.get("endpoint_b", PackedInt32Array())
	for index in range(vertices.size()):
		intersections.append({
			"vertex": index,
			"position": vertices[index],
			"normal": normals[index] if index < normals.size() else Vector3.ZERO,
			"material": int(materials[index]) if index < materials.size() else 0,
			"endpoint_a": int(endpoint_a[index]) if index < endpoint_a.size() else -1,
			"endpoint_b": int(endpoint_b[index]) if index < endpoint_b.size() else -1,
		})
	return intersections


static func _endpoint_provenance(mesh: Dictionary) -> Array:
	var result: Array = []
	for entry in _edge_intersections(mesh):
		result.append({
			"vertex": entry["vertex"],
			"edge": [entry["endpoint_a"], entry["endpoint_b"]],
			"backend_position": entry["position"],
			"backend_normal": entry["normal"],
			"backend_material": entry["material"],
		})
	return result


static func _binary_string(value: int, bit_count: int) -> String:
	var text := ""
	for bit in range(bit_count - 1, -1, -1):
		text += "1" if (value & (1 << bit)) != 0 else "0"
	return text
