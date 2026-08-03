@tool
extends RefCounted
class_name WtTerrainLabIndependentOracleQualification

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)
const BoundaryField := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_boundary_field.gd"
)
const TransitionField := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_transition_field.gd"
)
const NativeAdapter := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_mesh_adapter.gd"
)
const Oracle := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_independent_oracle.gd"
)

const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/independent_oracle_standard.json"
)


static func run(fixture_filter: String = "") -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var failures: Array[String] = []
	var contract_validation := _validate_contract(standard)
	if str(contract_validation.get("status", "")) != "PASS":
		failures.append_array(contract_validation.get("failures", []))
	var probe := NativeAdapter.create_probe()
	if probe == null:
		failures.append("WorldTransvoxelCellProbe is unavailable; fallback geometry is forbidden")
	var fixture_results: Array[Dictionary] = []
	var fixture_times: Array[float] = []
	var oracle_times: Array[float] = []
	var geometry_lines: Array[String] = []
	var native_chunk_calls := 0
	var calibration_mesh := {}
	var calibration_contract := {}
	var calibration_field: RefCounted
	if probe != null:
		for fixture_value in standard.get("fixtures", []):
			var fixture: Dictionary = fixture_value
			if not fixture_filter.is_empty() and str(fixture.get("id", "")) != fixture_filter:
				continue
			var result := _qualify_fixture(probe, fixture)
			fixture_results.append(result)
			fixture_times.append(float(result.get("elapsed_usec", 0.0)))
			oracle_times.append(float(result.get("oracle_elapsed_usec", 0.0)))
			native_chunk_calls += int(result.get("native_chunk_call_count", 0))
			geometry_lines.append(
				str(result.get("fixture_id", "")) + ":" + str(result.get("geometry_signature", ""))
			)
			if str(result.get("status", "")) != "PASS":
				failures.append(
					"fixture %s failed: %s"
					% [str(result.get("fixture_id", "")), str(result.get("failures", []))]
				)
			if str(fixture.get("id", "")) == "closed_volume_lod0":
				calibration_mesh = result.get("_calibration_mesh", {})
				calibration_contract = result.get("_calibration_contract", {})
				calibration_field = result.get("_calibration_field", null)
	var complete := fixture_filter.is_empty()
	var negative_controls := {
		"status": "NOT_RUN",
		"control_count": 0,
		"controls": [],
		"performance": Statistics.distribution([]),
		"failures": [],
	}
	if complete and not calibration_mesh.is_empty():
		if calibration_field != null:
			calibration_contract["field_sampler"] = Callable(calibration_field, "sample")
		negative_controls = _negative_controls(calibration_mesh, calibration_contract)
		if str(negative_controls.get("status", "")) != "PASS":
			failures.append_array(negative_controls.get("failures", []))
	geometry_lines.sort()
	var matrix_signature := "\n".join(geometry_lines).sha256_text()
	var budgets: Dictionary = standard.get("budgets", {})
	if complete:
		if fixture_results.size() < int(budgets.get("minimum_fixture_count", 0)):
			failures.append("independent-oracle fixture coverage is incomplete")
		if native_chunk_calls < int(budgets.get("minimum_native_chunk_call_count", 0)):
			failures.append("independent-oracle native call coverage is incomplete")
		if int(negative_controls.get("control_count", 0)) < int(
			budgets.get("minimum_negative_control_count", 0)
		):
			failures.append("independent-oracle negative controls are incomplete")
		var expected: Dictionary = standard.get("stable_expected", {})
		var expected_matrix := str(expected.get("matrix_geometry_signature", ""))
		if not expected_matrix.is_empty() and matrix_signature != expected_matrix:
			failures.append("independent-oracle matrix geometry signature changed")
	var fixture_distribution := Statistics.distribution(fixture_times)
	var oracle_distribution := Statistics.distribution(oracle_times)
	if complete and float(fixture_distribution.get("p95_usec", INF)) > float(
		budgets.get("maximum_fixture_p95_usec", 0)
	):
		failures.append("independent-oracle fixture p95 exceeded")
	if complete and float(oracle_distribution.get("p95_usec", INF)) > float(
		budgets.get("maximum_oracle_p95_usec", 0)
	):
		failures.append("independent-oracle analysis p95 exceeded")
	var elapsed_usec := Time.get_ticks_usec() - started_usec
	if complete and elapsed_usec > int(budgets.get("maximum_total_usec", 0)):
		failures.append("TQP-33 total duration exceeded")
	for result in fixture_results:
		result.erase("_calibration_mesh")
		result.erase("_calibration_contract")
		result.erase("_calibration_field")
	return {
		"schema": "world_transvoxel.terrain_lab.independent_oracle_qualification.v1",
		"standard_id": standard.get("standard_id", ""),
		"authority": standard.get("authority", ""),
		"milestone": "TQP-33",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"retained_complete": complete,
		"contract": contract_validation,
		"fixtures": fixture_results,
		"negative_controls": negative_controls,
		"matrix": {
			"fixture_count": fixture_results.size(),
			"native_chunk_call_count": native_chunk_calls,
			"geometry_signature": matrix_signature,
		},
		"performance": {
			"profile": "debug_regression_reference_not_production_budget",
			"fixture_distribution": fixture_distribution,
			"oracle_distribution": oracle_distribution,
			"negative_control_distribution": negative_controls.get("performance", {}),
			"elapsed_usec": elapsed_usec,
			"memory": Statistics.memory_metrics(),
		},
		"provenance": Statistics.provenance(matrix_signature),
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


static func _validate_contract(standard: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	var checks: Array[Dictionary] = []
	var contract: Dictionary = standard.get("contract", {})
	_check(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.independent_oracle_standard.v1",
		"standard_schema",
		"independent-oracle standard schema changed",
		checks,
		failures
	)
	_check(
		str(contract.get("native_dependency", "")) == "WorldTransvoxelCellProbe",
		"native_authority",
		"independent-oracle native authority changed",
		checks,
		failures
	)
	_check(
		str(contract.get("fallback_geometry", "")) == "forbidden",
		"no_fallback",
		"fallback geometry is not forbidden",
		checks,
		failures
	)
	var required_checks: Array = contract.get("required_checks", [])
	_check(
		required_checks == Oracle.CHECK_IDS,
		"required_check_inventory",
		"independent-oracle check inventory changed",
		checks,
		failures
	)
	var oracle_source_path := str(contract.get("oracle_source", ""))
	var oracle_source := _read_text(oracle_source_path)
	var independent := not oracle_source.is_empty()
	for forbidden in [
		"WorldTransvoxelCellProbe",
		"wt_terrain_lab_edit_native_evidence",
		"NativeEvidence",
		"same_lod_window_topology",
		"validate_chunk",
		"mesh_chunk_with_callable",
	]:
		independent = independent and oracle_source.find(forbidden) < 0
	_check(
		independent,
		"source_independence",
		"independent oracle imports or calls the implementation validator/mesher",
		checks,
		failures
	)
	var adapter_source := _read_text(str(contract.get("adapter_source", "")))
	_check(
		not adapter_source.is_empty()
			and adapter_source.find("wt_terrain_lab_edit_native_evidence") < 0
			and adapter_source.find("validate_chunk") < 0
			and adapter_source.find("same_lod_window_topology") < 0,
		"adapter_separation",
		"native mesh adapter reuses validation logic",
		checks,
		failures
	)
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"checks": checks,
		"failures": failures,
	}


static func _qualify_fixture(probe: RefCounted, definition: Dictionary) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var failures: Array[String] = []
	var cold := _build_native_mesh(probe, definition, false)
	var warm := _build_native_mesh(probe, definition, true)
	if str(cold.get("status", "")) != "PASS":
		failures.append_array(cold.get("failures", []))
	if str(warm.get("status", "")) != "PASS":
		failures.append_array(warm.get("failures", []))
	if str(cold.get("geometry_signature", "")) != str(warm.get("geometry_signature", "")):
		failures.append("cold/warm normalized native geometry differs")
	var runtime_contract := _runtime_contract(definition, cold.get("field", null))
	var oracle_result := Oracle.analyze(cold.get("mesh", {}), runtime_contract)
	if str(oracle_result.get("status", "")) != "PASS":
		failures.append("independent oracle failed: " + str(oracle_result.get("failures", [])))
	var expected_fixtures: Dictionary = (
		JsonLoader.load_dictionary(STANDARD_PATH).get("stable_expected", {}) as Dictionary
	).get("fixtures", {})
	var expected_signature := str(expected_fixtures.get(str(definition.get("id", "")), ""))
	if not expected_signature.is_empty() and str(cold.get("geometry_signature", "")) \
			!= expected_signature:
		failures.append("retained fixture geometry signature changed")
	return {
		"fixture_id": definition.get("id", ""),
		"source": definition.get("source", ""),
		"status": "PASS" if failures.is_empty() else "FAIL",
		"geometry_signature": cold.get("geometry_signature", ""),
		"warm_geometry_signature": warm.get("geometry_signature", ""),
		"native_chunk_call_count": int(cold.get("native_chunk_call_count", 0))
			+ int(warm.get("native_chunk_call_count", 0)),
		"oracle": oracle_result,
		"oracle_elapsed_usec": oracle_result.get("elapsed_usec", 0),
		"elapsed_usec": Time.get_ticks_usec() - started_usec,
		"minimized_repro": {
			"runner": "res://labs/terrain_lab/tools/run_independent_oracle_validation.gd",
			"arguments": ["--fixture", definition.get("id", "")],
		},
		"_calibration_mesh": cold.get("mesh", {}),
		"_calibration_contract": runtime_contract,
		"_calibration_field": cold.get("field", null),
		"failures": failures,
	}


static func _build_native_mesh(
	probe: RefCounted,
	definition: Dictionary,
	_reverse_order: bool
) -> Dictionary:
	var source := str(definition.get("source", ""))
	var field: RefCounted
	var chunks: Array[Dictionary] = []
	if source == "boundary_field":
		field = BoundaryField.new()
		if not field.configure(definition):
			return {"status": "FAIL", "failures": ["boundary field configuration failed"]}
		var coordinates: Array[Vector3i] = []
		for z in range(field.window_chunks.z):
			for y in range(field.window_chunks.y):
				for x in range(field.window_chunks.x):
					coordinates.append(field.chunk_base + Vector3i(x, y, z))
		if _reverse_order:
			coordinates.reverse()
		for coordinate in coordinates:
			chunks.append(NativeAdapter.mesh_chunk(probe, field, coordinate, field.lod, 0))
	elif source == "transition_field":
		field = TransitionField.new()
		var coarse_coordinate := _vector3i(definition.get("coarse_coordinate", []))
		var coarse_lod := int(definition.get("coarse_lod", 1))
		var face := int(definition.get("face", 1))
		if not field.configure(coarse_coordinate, coarse_lod):
			return {"status": "FAIL", "failures": ["transition field configuration failed"]}
		var requests: Array[Dictionary] = [{
			"coordinate": coarse_coordinate,
			"lod": coarse_lod,
			"mask": 1 << face,
		}]
		for coordinate in _fine_neighbor_coordinates(coarse_coordinate, face):
			requests.append({"coordinate": coordinate, "lod": coarse_lod - 1, "mask": 0})
		if _reverse_order:
			requests.reverse()
		for request in requests:
			chunks.append(NativeAdapter.mesh_chunk(
				probe,
				field,
				request.get("coordinate", Vector3i.ZERO),
				int(request.get("lod", 0)),
				int(request.get("mask", 0))
			))
	else:
		return {"status": "FAIL", "failures": ["unknown native fixture source"]}
	var mesh := NativeAdapter.assemble(chunks, true)
	return {
		"status": mesh.get("status", ""),
		"mesh": mesh,
		"field": field,
		"geometry_signature": mesh.get("geometry_signature", ""),
		"native_chunk_call_count": chunks.size(),
		"failures": mesh.get("failures", []),
	}


static func _runtime_contract(definition: Dictionary, field: RefCounted) -> Dictionary:
	var ray_tests: Array[Dictionary] = []
	for ray_value in definition.get("ray_tests", []):
		var ray: Dictionary = ray_value
		ray_tests.append({
			"id": ray.get("id", ""),
			"origin": _vector3(ray.get("origin", [])),
			"direction": _vector3(ray.get("direction", [])),
			"expected_parity": int(ray.get("expected_parity", 0)),
			"minimum_hit_count": int(ray.get("minimum_hit_count", 0)),
		})
	return {
		"bounds_min": _vector3(definition.get("bounds_min", [])),
		"bounds_max": _vector3(definition.get("bounds_max", [])),
		"closed": bool(definition.get("closed", false)),
		"allowed_open_faces": definition.get("allowed_open_faces", []),
		"expected_component_count": int(definition.get("expected_component_count", 1)),
		"expected_euler_characteristic": definition.get("expected_euler_characteristic"),
		"expected_signed_volume_sign": int(definition.get("expected_signed_volume_sign", 0)),
		"minimum_abs_signed_volume": float(definition.get("minimum_abs_signed_volume", 0.0)),
		"field_tolerance": float(definition.get("field_tolerance", 0.0001)),
		"field_sampler": Callable(field, "sample") if field != null else Callable(),
		"ray_tests": ray_tests,
	}


static func _negative_controls(mesh: Dictionary, contract: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	var controls: Array[Dictionary] = []
	var times: Array[float] = []
	var mutations := [
		{"id": "invalid_index", "check": "index_integrity"},
		{"id": "nonfinite_vertex", "check": "finite_value"},
		{"id": "out_of_bounds_vertex", "check": "bounds"},
		{"id": "degenerate_triangle", "check": "degenerate_triangle"},
		{"id": "missing_triangle", "check": "edge_multiplicity"},
		{"id": "third_edge_incident", "check": "non_manifold"},
		{"id": "duplicate_triangle", "check": "duplicate_overlap"},
		{"id": "flipped_triangle", "check": "orientation"},
		{"id": "disconnected_tetrahedron", "check": "component"},
		{"id": "punctured_euler_surface", "check": "euler_characteristic"},
		{"id": "removed_ray_entry", "check": "ray_parity"},
		{"id": "reversed_closed_surface", "check": "signed_volume"},
		{"id": "off_isosurface_vertex", "check": "field_resampling"},
	]
	for mutation in mutations:
		var injected := _inject_defect(mesh, contract, str(mutation.get("id", "")))
		var started_usec := Time.get_ticks_usec()
		var result := Oracle.analyze(injected, contract)
		times.append(float(Time.get_ticks_usec() - started_usec))
		var check_id := str(mutation.get("check", ""))
		var designated: Dictionary = (result.get("checks", {}) as Dictionary).get(check_id, {})
		var detected := str(designated.get("status", "")) == "FAIL"
		controls.append({
			"id": mutation.get("id", ""),
			"designated_check": check_id,
			"status": "PASS" if detected else "FAIL",
			"injected_failure_detected": detected,
			"oracle_status": result.get("status", ""),
			"designated_check_result": designated,
		})
		if not detected:
			failures.append("injected defect was not detected: " + str(mutation.get("id", "")))
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"control_count": controls.size(),
		"controls": controls,
		"performance": Statistics.distribution(times),
		"failures": failures,
	}


static func _inject_defect(
	base_mesh: Dictionary,
	contract: Dictionary,
	defect_id: String
) -> Dictionary:
	var mesh := NativeAdapter.clone_mesh(base_mesh)
	var vertices: PackedVector3Array = mesh.get("vertices", PackedVector3Array())
	var indices: PackedInt32Array = mesh.get("indices", PackedInt32Array())
	match defect_id:
		"invalid_index":
			indices[0] = -1
		"nonfinite_vertex":
			vertices[0] = Vector3(NAN, vertices[0].y, vertices[0].z)
		"out_of_bounds_vertex":
			vertices[0] = contract.get("bounds_max", Vector3.ONE) + Vector3.ONE
		"degenerate_triangle":
			indices.append(indices[0])
			indices.append(indices[0])
			indices.append(indices[1])
		"missing_triangle", "punctured_euler_surface":
			indices = _remove_triangle(indices, 0)
		"third_edge_incident":
			var a := vertices[indices[0]]
			var b := vertices[indices[1]]
			vertices.append((a + b) * 0.5 + Vector3(0.17, 0.23, 0.31))
			indices.append(indices[0])
			indices.append(indices[1])
			indices.append(vertices.size() - 1)
		"duplicate_triangle":
			indices.append(indices[0])
			indices.append(indices[1])
			indices.append(indices[2])
		"flipped_triangle":
			var temporary := indices[1]
			indices[1] = indices[2]
			indices[2] = temporary
		"disconnected_tetrahedron":
			var center: Vector3 = (
				(contract.get("bounds_min", Vector3.ZERO) as Vector3)
				+ (contract.get("bounds_max", Vector3.ONE) as Vector3)
			) * 0.5
			var start := vertices.size()
			vertices.append_array(PackedVector3Array([
				center + Vector3(0.15, 0.0, -0.1),
				center + Vector3(-0.15, 0.0, -0.1),
				center + Vector3(0.0, 0.18, 0.1),
				center + Vector3(0.0, -0.18, 0.1),
			]))
			for triangle in [[0, 2, 1], [0, 1, 3], [0, 3, 2], [1, 2, 3]]:
				for corner in triangle:
					indices.append(start + corner)
		"removed_ray_entry":
			var rays: Array = contract.get("ray_tests", [])
			if not rays.is_empty():
				var ray: Dictionary = rays[0]
				var hits := Oracle.ray_intersections(
					mesh,
					ray.get("origin", Vector3.ZERO),
					ray.get("direction", Vector3.RIGHT)
				)
				if not (hits.get("hits", []) as Array).is_empty():
					indices = _remove_triangle(
						indices,
						int(((hits.get("hits", []) as Array)[0] as Dictionary).get("triangle_index", 0))
					)
		"reversed_closed_surface":
			for offset in range(0, indices.size(), 3):
				if offset + 2 >= indices.size():
					break
				var temporary := indices[offset + 1]
				indices[offset + 1] = indices[offset + 2]
				indices[offset + 2] = temporary
		"off_isosurface_vertex":
			vertices[0] = (
				(contract.get("bounds_min", Vector3.ZERO) as Vector3)
				+ (contract.get("bounds_max", Vector3.ONE) as Vector3)
			) * 0.5
	mesh["vertices"] = vertices
	mesh["indices"] = indices
	return mesh


static func _remove_triangle(indices: PackedInt32Array, triangle_index: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	var remove_offset := triangle_index * 3
	for offset in range(indices.size()):
		if offset < remove_offset or offset >= remove_offset + 3:
			result.append(indices[offset])
	return result


static func _fine_neighbor_coordinates(coarse: Vector3i, face: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var axis := 0 if face <= 1 else (1 if face <= 3 else 2)
	var positive := face in [1, 3, 5]
	var fixed := coarse[axis] * 2 + (2 if positive else -1)
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


static func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""


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


static func _vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


static func _vector3i(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() == 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i.ZERO
