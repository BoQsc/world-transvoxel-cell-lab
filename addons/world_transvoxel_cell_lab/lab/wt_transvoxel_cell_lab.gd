@tool
extends Node3D
class_name WtTransvoxelCellLab

enum FieldMode { PLANE, SPHERE, TUNNEL, SADDLE, WAVES }

const REPORT_SCHEMA := "world_transvoxel.cell_lab.report.v1"
const REPRO_SCHEMA := "world_transvoxel.cell_lab.repro.v1"
const REGULAR_CASE_CORPUS_SCHEMA := "world_transvoxel.cell_lab.regular_case_corpus.v1"
const TRANSITION_CASE_CORPUS_SCHEMA := "world_transvoxel.cell_lab.transition_case_corpus.v1"
const NATIVE_REGULAR_IMPLEMENTATION := "native_transvoxel_regular_cell_probe_v1"
const NATIVE_AUTHORITY := "NATIVE_TRANSVOXEL_BACKEND_AUTHORITATIVE"
const CELL_PROBE_CORRECTNESS_CLAIM := "exact_regular_and_transition_cell_backend_probe_v1"
const LAB_CORRECTNESS_CLAIM := "exact_regular_transition_and_lod0_chunk_backend_probe_v2"
const LAB_SCOPE := "cell_first_transvoxel_preview_and_validator"
const PRIMARY_VALIDATION_DOMAIN := "volumetric_terrain"
const PRIMITIVE_SCOPE := "transvoxel_scalar_field_cell_unit"
const VALIDATION_STANDARD := "world_transvoxel_native_authoritative_no_fallback"
const AUTHORITY_MODEL := "world_transvoxel_is_implementation_authority_under_test"
const UPSTREAM_CORRECTION_POLICY := "proven_lab_repro_drives_world_transvoxel_fix"
const INTEGRATION_GAME_ROLE := "downstream_proving_ground_not_correctness_authority"
const INTEGRATION_GAME_DIAGNOSTIC_POLICY := "reduce_game_artifact_to_lab_repro_then_classify_fix_layer"
const CHUNK_PROBE_IMPLEMENTATION := "native_transvoxel_lod0_chunk_mesher_probe_v1"
const CHUNK_PROBE_CELLS_PER_AXIS := 16
const CORNER_COUNT := 8
const TRANSITION_SAMPLE_COUNT := 9
const TRANSITION_ORIENTATION_NAMES := [
	"PositiveX",
	"NegativeX",
	"PositiveY",
	"NegativeY",
	"PositiveZ",
	"NegativeZ",
]
const TRANSITION_ORIENTATION_POSITIVE_Z := 4

@export_range(1, 24, 1) var cells_x: int = 4:
	set(value):
		cells_x = clampi(value, 1, 24)
		_request_rebuild()
@export_range(1, 24, 1) var cells_y: int = 4:
	set(value):
		cells_y = clampi(value, 1, 24)
		_request_rebuild()
@export_range(1, 24, 1) var cells_z: int = 4:
	set(value):
		cells_z = clampi(value, 1, 24)
		_request_rebuild()
@export_range(0.1, 16.0, 0.05) var cell_size: float = 1.0:
	set(value):
		cell_size = maxf(value, 0.05)
		_request_rebuild()
@export var field_mode: FieldMode = FieldMode.PLANE:
	set(value):
		field_mode = value
		_request_rebuild()
@export_range(-64.0, 64.0, 0.01) var isovalue: float = 0.0:
	set(value):
		isovalue = value
		_request_rebuild()
@export_range(-32.0, 32.0, 0.01) var surface_height: float = 0.0:
	set(value):
		surface_height = value
		_request_rebuild()
@export_range(0.1, 64.0, 0.05) var sphere_radius: float = 2.1:
	set(value):
		sphere_radius = maxf(value, 0.05)
		_request_rebuild()
@export_range(0.1, 16.0, 0.05) var edit_radius: float = 1.25
@export_range(1, 65535, 1) var construct_material: int = 4
@export var show_sample_points: bool = true:
	set(value):
		show_sample_points = value
		_request_rebuild()
@export var show_edit_markers: bool = true:
	set(value):
		show_edit_markers = value
		_request_rebuild()
@export var show_transition_frame: bool = true:
	set(value):
		show_transition_frame = value
		_request_rebuild()
@export var show_chunk_probe: bool = true:
	set(value):
		show_chunk_probe = value
		_request_rebuild()
@export var show_probe_labels: bool = true:
	set(value):
		show_probe_labels = value
		_request_rebuild()
@export var wireframe: bool = false:
	set(value):
		wireframe = value
		_make_materials()
		_request_rebuild()
@export var auto_rebuild: bool = true
@export var rebuild_now: bool = false:
	set(value):
		rebuild_now = false
		if value:
			call_deferred("rebuild")

var edits: Array[Dictionary] = []
var _last_report: Dictionary = {}
var _native_cell_probe: RefCounted
var _mesh_root: Node3D
var _sample_root: Node3D
var _marker_root: Node3D
var _label_root: Node3D
var _surface_material: StandardMaterial3D
var _wire_material: StandardMaterial3D
var _solid_sample_material: StandardMaterial3D
var _empty_sample_material: StandardMaterial3D
var _dig_marker_material: StandardMaterial3D
var _construct_marker_material: StandardMaterial3D
var _transition_material: StandardMaterial3D
var _transition_surface_material: StandardMaterial3D
var _chunk_surface_material: StandardMaterial3D


func _ready() -> void:
	_make_materials()
	rebuild()


func rebuild() -> Dictionary:
	var start_usec := Time.get_ticks_usec()
	_ensure_roots()
	_clear_children(_mesh_root)
	_clear_children(_sample_root)
	_clear_children(_marker_root)
	_clear_children(_label_root)

	var mesh_data := _build_patch_mesh_data()
	var transition_data := _build_transition_probe_mesh_data()
	var chunk_data := _build_chunk_probe_mesh_data()
	var mesh := _make_array_mesh(mesh_data)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "cell_lab_preview_mesh"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _surface_material
	_mesh_root.add_child(mesh_instance)
	if wireframe:
		var line_instance := MeshInstance3D.new()
		line_instance.name = "cell_lab_wire_edges"
		line_instance.mesh = _make_edge_line_mesh(mesh_data)
		line_instance.material_override = _wire_material
		_mesh_root.add_child(line_instance)
	var transition_mesh := _make_array_mesh(transition_data)
	var transition_instance := MeshInstance3D.new()
	transition_instance.name = "cell_lab_transition_probe_mesh"
	transition_instance.mesh = transition_mesh
	transition_instance.material_override = _transition_surface_material
	_mesh_root.add_child(transition_instance)
	if wireframe:
		var transition_line_instance := MeshInstance3D.new()
		transition_line_instance.name = "cell_lab_transition_probe_wire"
		transition_line_instance.mesh = _make_edge_line_mesh(transition_data)
		transition_line_instance.material_override = _wire_material
		_mesh_root.add_child(transition_line_instance)
	if show_chunk_probe:
		var chunk_instance := MeshInstance3D.new()
		chunk_instance.name = "production_chunk_probe_mesh"
		chunk_instance.mesh = _make_array_mesh(chunk_data)
		chunk_instance.material_override = _chunk_surface_material
		_mesh_root.add_child(chunk_instance)
		if wireframe:
			var chunk_line_instance := MeshInstance3D.new()
			chunk_line_instance.name = "production_chunk_probe_wire"
			chunk_line_instance.mesh = _make_edge_line_mesh(chunk_data)
			chunk_line_instance.material_override = _wire_material
			_mesh_root.add_child(chunk_line_instance)

	if show_sample_points:
		_build_sample_markers()
	if show_edit_markers:
		_build_edit_markers()
	if show_transition_frame:
		_build_transition_frame()
	if show_probe_labels:
		_build_probe_labels(mesh_data, transition_data, chunk_data)

	var elapsed_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
	_last_report = _make_report(mesh_data, transition_data, chunk_data, elapsed_ms)
	return _last_report


func get_last_report() -> Dictionary:
	if _last_report.is_empty():
		rebuild()
	return _last_report


func make_repro_snapshot() -> Dictionary:
	return {
		"schema": REPRO_SCHEMA,
		"created_unix_time": Time.get_unix_time_from_system(),
		"lab_scope": LAB_SCOPE,
		"primary_validation_domain": PRIMARY_VALIDATION_DOMAIN,
		"primitive_scope": PRIMITIVE_SCOPE,
		"validation_standard": VALIDATION_STANDARD,
		"authority_model": AUTHORITY_MODEL,
		"upstream_correction_policy": UPSTREAM_CORRECTION_POLICY,
		"integration_game_role": INTEGRATION_GAME_ROLE,
		"integration_game_diagnostic_policy": INTEGRATION_GAME_DIAGNOSTIC_POLICY,
		"parameters": {
			"cells": Vector3i(cells_x, cells_y, cells_z),
			"cell_size": cell_size,
			"field_mode": FieldMode.keys()[field_mode],
			"isovalue": isovalue,
			"surface_height": surface_height,
			"sphere_radius": sphere_radius,
			"edit_radius": edit_radius,
			"construct_material": construct_material,
			"show_transition_frame": show_transition_frame,
			"show_chunk_probe": show_chunk_probe,
			"show_probe_labels": show_probe_labels,
			"wireframe": wireframe,
		},
		"edits": edits.duplicate(true),
		"report": get_last_report(),
	}


func apply_repro_snapshot(snapshot: Dictionary) -> Dictionary:
	if str(snapshot.get("schema", "")) != REPRO_SCHEMA:
		return {
			"ok": false,
			"error": "unexpected_repro_schema",
		}
	var parameters: Dictionary = snapshot.get("parameters", {})
	var previous_auto_rebuild := auto_rebuild
	auto_rebuild = false
	var extent := _variant_to_vector3i(parameters.get("cells", Vector3i(cells_x, cells_y, cells_z)), Vector3i(cells_x, cells_y, cells_z))
	cells_x = extent.x
	cells_y = extent.y
	cells_z = extent.z
	cell_size = float(parameters.get("cell_size", cell_size))
	field_mode = _field_mode_from_variant(parameters.get("field_mode", FieldMode.keys()[field_mode]), field_mode)
	isovalue = float(parameters.get("isovalue", isovalue))
	surface_height = float(parameters.get("surface_height", surface_height))
	sphere_radius = float(parameters.get("sphere_radius", sphere_radius))
	edit_radius = float(parameters.get("edit_radius", edit_radius))
	construct_material = int(parameters.get("construct_material", construct_material))
	show_transition_frame = bool(parameters.get("show_transition_frame", show_transition_frame))
	show_chunk_probe = bool(parameters.get("show_chunk_probe", show_chunk_probe))
	show_probe_labels = bool(parameters.get("show_probe_labels", show_probe_labels))
	wireframe = bool(parameters.get("wireframe", wireframe))
	edits.clear()
	var raw_edits: Array = snapshot.get("edits", [])
	for raw_edit in raw_edits:
		var edit: Dictionary = raw_edit
		edits.append({
			"mode": str(edit.get("mode", "")),
			"center": _variant_to_vector3(edit.get("center", Vector3.ZERO), Vector3.ZERO),
			"radius": float(edit.get("radius", edit_radius)),
			"material": int(edit.get("material", construct_material)),
		})
	auto_rebuild = previous_auto_rebuild
	return rebuild()


func validate_regular_case_corpus() -> Dictionary:
	var start_usec := Time.get_ticks_usec()
	var probe := _get_native_cell_probe()
	var result := {
		"schema": REGULAR_CASE_CORPUS_SCHEMA,
		"available": probe != null,
		"authority": NATIVE_AUTHORITY,
		"case_count": 256,
		"ok_cases": 0,
		"empty_cases": 0,
		"failed_cases": 0,
		"expected_empty_mismatches": 0,
		"determinism_failures": 0,
		"buffer_failures": 0,
		"total_vertices": 0,
		"total_triangles": 0,
		"sample_failures": [],
		"status": "Unavailable" if probe == null else "PASS",
		"elapsed_ms": 0.0,
	}
	if probe == null:
		_attach_validation_result("regular_case_corpus", result)
		return result
	for case_code in range(256):
		var cell_mesh := _mesh_regular_case_code(probe, case_code)
		var repeated_mesh := _mesh_regular_case_code(probe, case_code)
		var status := str(cell_mesh.get("status", "Unknown"))
		var expected_empty := case_code == 0 or case_code == 255
		if status == "Ok":
			result["ok_cases"] = int(result["ok_cases"]) + 1
		elif status == "Empty":
			result["empty_cases"] = int(result["empty_cases"]) + 1
		else:
			result["failed_cases"] = int(result["failed_cases"]) + 1
			_append_sample_failure(result, case_code, -1, "regular status=%s" % status)
		if (status == "Empty") != expected_empty:
			result["expected_empty_mismatches"] = int(result["expected_empty_mismatches"]) + 1
			_append_sample_failure(result, case_code, -1, "regular empty classification mismatch")
		if not _cell_meshes_equivalent(cell_mesh, repeated_mesh):
			result["determinism_failures"] = int(result["determinism_failures"]) + 1
			_append_sample_failure(result, case_code, -1, "regular result is not deterministic")
		var validation := _validate_cell_mesh_buffers(cell_mesh, CORNER_COUNT, CORNER_COUNT)
		if int(validation.get("failures", 0)) > 0:
			result["buffer_failures"] = int(result["buffer_failures"]) + int(validation.get("failures", 0))
			_append_sample_failure(result, case_code, -1, str(validation.get("first_failure", "regular buffer validation failed")))
		var vertices: PackedVector3Array = cell_mesh.get("vertices", PackedVector3Array())
		var indices: PackedInt32Array = cell_mesh.get("indices", PackedInt32Array())
		result["total_vertices"] = int(result["total_vertices"]) + vertices.size()
		result["total_triangles"] = int(result["total_triangles"]) + int(indices.size() / 3)
	result["elapsed_ms"] = float(Time.get_ticks_usec() - start_usec) / 1000.0
	if int(result["failed_cases"]) > 0 or int(result["expected_empty_mismatches"]) > 0 or int(result["determinism_failures"]) > 0 or int(result["buffer_failures"]) > 0:
		result["status"] = "FAIL"
	_attach_validation_result("regular_case_corpus", result)
	return result


func validate_transition_case_corpus() -> Dictionary:
	var start_usec := Time.get_ticks_usec()
	var probe := _get_native_cell_probe()
	var result := {
		"schema": TRANSITION_CASE_CORPUS_SCHEMA,
		"available": probe != null,
		"authority": NATIVE_AUTHORITY,
		"case_count": 512,
		"orientation_count": TRANSITION_ORIENTATION_NAMES.size(),
		"probe_count": 512 * TRANSITION_ORIENTATION_NAMES.size(),
		"ok_cases": 0,
		"empty_cases": 0,
		"failed_cases": 0,
		"expected_empty_mismatches": 0,
		"orientation_status_mismatches": 0,
		"orientation_count_mismatches": 0,
		"determinism_failures": 0,
		"buffer_failures": 0,
		"bounds_failures": 0,
		"total_vertices": 0,
		"total_triangles": 0,
		"sample_failures": [],
		"status": "Unavailable" if probe == null else "PASS",
		"elapsed_ms": 0.0,
	}
	if probe == null:
		_attach_validation_result("transition_case_corpus", result)
		return result
	for case_code in range(512):
		var canonical_mesh := _mesh_transition_case_code(probe, case_code, TRANSITION_ORIENTATION_POSITIVE_Z)
		var canonical_status := str(canonical_mesh.get("status", "Unknown"))
		var expected_empty := case_code == 0 or case_code == 511
		if (canonical_status == "Empty") != expected_empty:
			result["expected_empty_mismatches"] = int(result["expected_empty_mismatches"]) + 1
			_append_sample_failure(result, case_code, TRANSITION_ORIENTATION_POSITIVE_Z, "transition empty classification mismatch")
		for orientation in range(TRANSITION_ORIENTATION_NAMES.size()):
			var cell_mesh := _mesh_transition_case_code(probe, case_code, orientation)
			var repeated_mesh := _mesh_transition_case_code(probe, case_code, orientation)
			var status := str(cell_mesh.get("status", "Unknown"))
			if status == "Ok":
				result["ok_cases"] = int(result["ok_cases"]) + 1
			elif status == "Empty":
				result["empty_cases"] = int(result["empty_cases"]) + 1
			else:
				result["failed_cases"] = int(result["failed_cases"]) + 1
				_append_sample_failure(result, case_code, orientation, "transition status=%s" % status)
			if status != canonical_status:
				result["orientation_status_mismatches"] = int(result["orientation_status_mismatches"]) + 1
				_append_sample_failure(result, case_code, orientation, "orientation changed transition status")
			if status == "Ok":
				var vertices: PackedVector3Array = cell_mesh.get("vertices", PackedVector3Array())
				var indices: PackedInt32Array = cell_mesh.get("indices", PackedInt32Array())
				var canonical_vertices: PackedVector3Array = canonical_mesh.get("vertices", PackedVector3Array())
				var canonical_indices: PackedInt32Array = canonical_mesh.get("indices", PackedInt32Array())
				if vertices.size() != canonical_vertices.size() or indices.size() != canonical_indices.size():
					result["orientation_count_mismatches"] = int(result["orientation_count_mismatches"]) + 1
					_append_sample_failure(result, case_code, orientation, "orientation changed transition counts")
				result["total_vertices"] = int(result["total_vertices"]) + vertices.size()
				result["total_triangles"] = int(result["total_triangles"]) + int(indices.size() / 3)
				var bounds_failures := _transition_bounds_failure_count(vertices, orientation)
				if bounds_failures > 0:
					result["bounds_failures"] = int(result["bounds_failures"]) + bounds_failures
					_append_sample_failure(result, case_code, orientation, "transition vertex outside canonical prism")
			if not _cell_meshes_equivalent(cell_mesh, repeated_mesh):
				result["determinism_failures"] = int(result["determinism_failures"]) + 1
				_append_sample_failure(result, case_code, orientation, "transition result is not deterministic")
			var validation := _validate_cell_mesh_buffers(cell_mesh, TRANSITION_SAMPLE_COUNT, 13)
			if int(validation.get("failures", 0)) > 0:
				result["buffer_failures"] = int(result["buffer_failures"]) + int(validation.get("failures", 0))
				_append_sample_failure(result, case_code, orientation, str(validation.get("first_failure", "transition buffer validation failed")))
	result["elapsed_ms"] = float(Time.get_ticks_usec() - start_usec) / 1000.0
	if int(result["failed_cases"]) > 0 or int(result["expected_empty_mismatches"]) > 0 or int(result["orientation_status_mismatches"]) > 0 or int(result["orientation_count_mismatches"]) > 0 or int(result["determinism_failures"]) > 0 or int(result["buffer_failures"]) > 0 or int(result["bounds_failures"]) > 0:
		result["status"] = "FAIL"
	_attach_validation_result("transition_case_corpus", result)
	return result


func get_status_line() -> String:
	var report := get_last_report()
	return "scope=%s primary=%s primitive=%s authority_model=%s integration=%s status=%s regular_patch cells=%s tris=%d interior_open=%d boundary_open=%d nonmanifold=%d orient=%d transition_cell=%s tris=%d production_chunk=%s tris=%d edits=%d %.2fms exact_backend=%s" % [
		str(report.get("lab_scope", LAB_SCOPE)),
		str(report.get("primary_validation_domain", PRIMARY_VALIDATION_DOMAIN)),
		str(report.get("primitive_scope", PRIMITIVE_SCOPE)),
		str(report.get("authority_model", AUTHORITY_MODEL)),
		str(report.get("integration_game_role", INTEGRATION_GAME_ROLE)),
		str(report.get("status", "UNKNOWN")),
		str(report.get("cells", Vector3i.ZERO)),
		int(report.get("triangles", 0)),
		int(report.get("interior_open_edges", 0)),
		int(report.get("boundary_open_edges", 0)),
		int(report.get("nonmanifold_edges", 0)),
		int(report.get("orientation_conflict_edges", 0)),
		str(report.get("transition_status", "unavailable")),
		int(report.get("transition_triangles", 0)),
		str(report.get("chunk_probe_status", "unavailable")),
		int(report.get("chunk_probe_triangles", 0)),
		int(report.get("edit_count", 0)),
		float(report.get("build_ms", 0.0)),
		str(report.get("native_cell_probe_available", false)),
	]


func set_extent(extent: Vector3i) -> void:
	cells_x = clampi(extent.x, 1, 24)
	cells_y = clampi(extent.y, 1, 24)
	cells_z = clampi(extent.z, 1, 24)
	rebuild()


func expand_cells(axis: String, delta: int) -> void:
	match axis:
		"x":
			cells_x = clampi(cells_x + delta, 1, 24)
		"y":
			cells_y = clampi(cells_y + delta, 1, 24)
		"z":
			cells_z = clampi(cells_z + delta, 1, 24)
	rebuild()


func apply_dig_at(center: Vector3 = Vector3.ZERO, radius: float = -1.0) -> void:
	_apply_edit("dig", center, radius)


func apply_construct_at(center: Vector3 = Vector3.ZERO, radius: float = -1.0) -> void:
	_apply_edit("construct", center, radius)


func clear_edits() -> void:
	edits.clear()
	rebuild()


func benchmark_rebuild(iterations: int = 24) -> Dictionary:
	iterations = clampi(iterations, 1, 240)
	var times: Array[float] = []
	var total_triangles := 0
	for _i in range(iterations):
		var start_usec := Time.get_ticks_usec()
		var data := _build_patch_mesh_data()
		var transition_data := _build_transition_probe_mesh_data()
		var chunk_data := _build_chunk_probe_mesh_data()
		times.append(float(Time.get_ticks_usec() - start_usec) / 1000.0)
		total_triangles += int(data.get("triangles", 0)) + int(transition_data.get("triangles", 0)) + int(chunk_data.get("triangles", 0))
	var sum := 0.0
	var maximum := 0.0
	for value in times:
		sum += value
		maximum = maxf(maximum, value)
	var result := {
		"schema": "world_transvoxel.cell_lab.benchmark.v1",
		"iterations": iterations,
		"average_build_ms": sum / float(iterations),
		"maximum_build_ms": maximum,
		"average_triangles": int(total_triangles / iterations),
		"cells": Vector3i(cells_x, cells_y, cells_z),
	}
	rebuild()
	_last_report["benchmark"] = result
	return result


func _mesh_regular_case_code(probe: RefCounted, case_code: int) -> Dictionary:
	var densities := PackedFloat32Array()
	var gradients := PackedVector3Array()
	var materials := PackedInt32Array()
	for corner in range(CORNER_COUNT):
		densities.append(-1.0 if (case_code & (1 << corner)) != 0 else 1.0)
		gradients.append(Vector3.RIGHT)
		materials.append(corner + 1)
	return probe.call(
		"mesh_regular_cell",
		densities,
		gradients,
		materials,
		Vector3.ZERO,
		1.0,
		0.0
	)


func _mesh_transition_case_code(probe: RefCounted, case_code: int, orientation: int) -> Dictionary:
	var densities := PackedFloat32Array()
	var gradients := PackedVector3Array()
	var materials := PackedInt32Array()
	for sample_index in range(TRANSITION_SAMPLE_COUNT):
		var bit := _transition_case_bit(sample_index)
		densities.append(-1.0 if (case_code & (1 << bit)) != 0 else 1.0)
		gradients.append(Vector3.RIGHT)
		materials.append(sample_index + 1)
	return probe.call(
		"mesh_transition_cell",
		densities,
		gradients,
		materials,
		orientation,
		Vector3.ZERO,
		1.0,
		0.25,
		0.0
	)


func _validate_cell_mesh_buffers(cell_mesh: Dictionary, sample_count: int, topology_sample_count: int) -> Dictionary:
	var vertices: PackedVector3Array = cell_mesh.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = cell_mesh.get("normals", PackedVector3Array())
	var indices: PackedInt32Array = cell_mesh.get("indices", PackedInt32Array())
	var materials: PackedInt32Array = cell_mesh.get("materials", PackedInt32Array())
	var endpoint_a: PackedInt32Array = cell_mesh.get("endpoint_a", PackedInt32Array())
	var endpoint_b: PackedInt32Array = cell_mesh.get("endpoint_b", PackedInt32Array())
	var failures := 0
	var first_failure := ""
	if (indices.size() % 3) != 0:
		failures += 1
		first_failure = _first_failure(first_failure, "index count is not triangular")
	for index in indices:
		if int(index) < 0 or int(index) >= vertices.size():
			failures += 1
			first_failure = _first_failure(first_failure, "index outside active vertices")
			break
	for index in range(vertices.size()):
		var position := vertices[index]
		if not _vector_is_finite(position):
			failures += 1
			first_failure = _first_failure(first_failure, "position is not finite")
		if index >= normals.size() or not _normal_is_valid(normals[index]):
			failures += 1
			first_failure = _first_failure(first_failure, "normal is not unit length")
		if index >= materials.size() or int(materials[index]) <= 0 or int(materials[index]) > sample_count:
			failures += 1
			first_failure = _first_failure(first_failure, "material is outside sample set")
		if index >= endpoint_a.size() or index >= endpoint_b.size():
			failures += 1
			first_failure = _first_failure(first_failure, "endpoint provenance is missing")
			continue
		var a := int(endpoint_a[index])
		var b := int(endpoint_b[index])
		if a < 0 or a >= topology_sample_count or b < 0 or b >= topology_sample_count:
			failures += 1
			first_failure = _first_failure(first_failure, "endpoint provenance is outside topology samples")
		if a == b:
			failures += 1
			first_failure = _first_failure(first_failure, "endpoint provenance names a zero-length topology edge")
	return {
		"failures": failures,
		"first_failure": first_failure,
	}


func _cell_meshes_equivalent(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("status", "Unknown")) != str(b.get("status", "Unknown")):
		return false
	var a_vertices: PackedVector3Array = a.get("vertices", PackedVector3Array())
	var b_vertices: PackedVector3Array = b.get("vertices", PackedVector3Array())
	var a_normals: PackedVector3Array = a.get("normals", PackedVector3Array())
	var b_normals: PackedVector3Array = b.get("normals", PackedVector3Array())
	var a_indices: PackedInt32Array = a.get("indices", PackedInt32Array())
	var b_indices: PackedInt32Array = b.get("indices", PackedInt32Array())
	var a_materials: PackedInt32Array = a.get("materials", PackedInt32Array())
	var b_materials: PackedInt32Array = b.get("materials", PackedInt32Array())
	if a_vertices.size() != b_vertices.size() or a_normals.size() != b_normals.size() or a_indices.size() != b_indices.size() or a_materials.size() != b_materials.size():
		return false
	for index in range(a_vertices.size()):
		if not _vectors_nearly_equal(a_vertices[index], b_vertices[index]):
			return false
		if not _vectors_nearly_equal(a_normals[index], b_normals[index]):
			return false
		if int(a_materials[index]) != int(b_materials[index]):
			return false
	for index in range(a_indices.size()):
		if int(a_indices[index]) != int(b_indices[index]):
			return false
	return true


func _transition_bounds_failure_count(vertices: PackedVector3Array, orientation: int) -> int:
	var basis := _transition_basis(orientation)
	var u: Vector3 = basis.get("u", Vector3.RIGHT)
	var v: Vector3 = basis.get("v", Vector3.UP)
	var w: Vector3 = basis.get("w", Vector3.FORWARD)
	var failures := 0
	for vertex in vertices:
		var local := Vector3(vertex.dot(u), vertex.dot(v), vertex.dot(w))
		if local.x < -0.0001 or local.x > 2.0001 or local.y < -0.0001 or local.y > 2.0001 or local.z < -0.0001 or local.z > 0.2501:
			failures += 1
	return failures


func _transition_basis(orientation: int) -> Dictionary:
	match orientation:
		0:
			return {"u": Vector3(0.0, 1.0, 0.0), "v": Vector3(0.0, 0.0, 1.0), "w": Vector3(1.0, 0.0, 0.0)}
		1:
			return {"u": Vector3(0.0, 1.0, 0.0), "v": Vector3(0.0, 0.0, -1.0), "w": Vector3(-1.0, 0.0, 0.0)}
		2:
			return {"u": Vector3(0.0, 0.0, 1.0), "v": Vector3(1.0, 0.0, 0.0), "w": Vector3(0.0, 1.0, 0.0)}
		3:
			return {"u": Vector3(0.0, 0.0, 1.0), "v": Vector3(-1.0, 0.0, 0.0), "w": Vector3(0.0, -1.0, 0.0)}
		4:
			return {"u": Vector3(1.0, 0.0, 0.0), "v": Vector3(0.0, 1.0, 0.0), "w": Vector3(0.0, 0.0, 1.0)}
		5:
			return {"u": Vector3(1.0, 0.0, 0.0), "v": Vector3(0.0, -1.0, 0.0), "w": Vector3(0.0, 0.0, -1.0)}
	return {"u": Vector3(1.0, 0.0, 0.0), "v": Vector3(0.0, 1.0, 0.0), "w": Vector3(0.0, 0.0, 1.0)}


func _attach_validation_result(key: String, result: Dictionary) -> void:
	if _last_report.is_empty():
		rebuild()
	_last_report[key] = result


func _append_sample_failure(result: Dictionary, case_code: int, orientation: int, message: String) -> void:
	var failures: Array = result.get("sample_failures", [])
	if failures.size() >= 16:
		return
	var entry := {
		"case": case_code,
		"message": message,
	}
	if orientation >= 0:
		entry["orientation"] = TRANSITION_ORIENTATION_NAMES[orientation] if orientation < TRANSITION_ORIENTATION_NAMES.size() else str(orientation)
	failures.append(entry)
	result["sample_failures"] = failures


func _first_failure(existing: String, candidate: String) -> String:
	return candidate if existing.is_empty() else existing


func _vector_is_finite(value: Vector3) -> bool:
	return _float_is_finite(value.x) and _float_is_finite(value.y) and _float_is_finite(value.z)


func _float_is_finite(value: float) -> bool:
	return value == value and absf(value) < 100000000000000000000.0


func _normal_is_valid(value: Vector3) -> bool:
	if not _vector_is_finite(value):
		return false
	var length_squared := value.length_squared()
	return length_squared >= 0.999 and length_squared <= 1.001


func _vectors_nearly_equal(a: Vector3, b: Vector3, tolerance: float = 0.00001) -> bool:
	return absf(a.x - b.x) <= tolerance and absf(a.y - b.y) <= tolerance and absf(a.z - b.z) <= tolerance


func _field_mode_from_variant(value: Variant, default_value: int) -> int:
	if typeof(value) == TYPE_INT:
		return clampi(int(value), 0, FieldMode.keys().size() - 1)
	var index := FieldMode.keys().find(str(value))
	if index < 0:
		return default_value
	return index


func _variant_to_vector3i(value: Variant, default_value: Vector3i) -> Vector3i:
	match typeof(value):
		TYPE_VECTOR3I:
			return value
		TYPE_VECTOR3:
			var vector3: Vector3 = value
			return Vector3i(roundi(vector3.x), roundi(vector3.y), roundi(vector3.z))
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value
			return Vector3i(
				int(dictionary.get("x", default_value.x)),
				int(dictionary.get("y", default_value.y)),
				int(dictionary.get("z", default_value.z))
			)
	return default_value


func _variant_to_vector3(value: Variant, default_value: Vector3) -> Vector3:
	match typeof(value):
		TYPE_VECTOR3:
			return value
		TYPE_VECTOR3I:
			var vector3i: Vector3i = value
			return Vector3(float(vector3i.x), float(vector3i.y), float(vector3i.z))
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value
			return Vector3(
				float(dictionary.get("x", default_value.x)),
				float(dictionary.get("y", default_value.y)),
				float(dictionary.get("z", default_value.z))
			)
	return default_value


func _apply_edit(mode: String, center: Vector3, radius: float) -> void:
	if radius <= 0.0:
		radius = edit_radius
	edits.append({
		"mode": mode,
		"center": center,
		"radius": radius,
		"material": construct_material,
	})
	rebuild()


func _request_rebuild() -> void:
	if not auto_rebuild or not is_inside_tree():
		return
	call_deferred("rebuild")


func _ensure_roots() -> void:
	if _mesh_root == null or not is_instance_valid(_mesh_root):
		_mesh_root = _get_or_make_root("CellLabMesh")
	if _sample_root == null or not is_instance_valid(_sample_root):
		_sample_root = _get_or_make_root("CellLabSamples")
	if _marker_root == null or not is_instance_valid(_marker_root):
		_marker_root = _get_or_make_root("CellLabEdits")
	if _label_root == null or not is_instance_valid(_label_root):
		_label_root = _get_or_make_root("CellLabLabels")


func _get_or_make_root(root_name: String) -> Node3D:
	var existing := get_node_or_null(root_name)
	if existing is Node3D:
		return existing
	var root := Node3D.new()
	root.name = root_name
	add_child(root)
	root.owner = owner
	return root


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func _make_materials() -> void:
	_surface_material = _material(Color(0.16, 0.55, 0.82, 1.0), false)
	_wire_material = _material(Color(0.95, 0.66, 0.12, 1.0), true)
	_solid_sample_material = _material(Color(0.95, 0.18, 0.14, 1.0), false)
	_empty_sample_material = _material(Color(0.16, 0.72, 0.42, 1.0), false)
	_dig_marker_material = _material(Color(1.0, 0.08, 0.06, 0.35), false)
	_construct_marker_material = _material(Color(0.20, 0.60, 1.0, 0.35), false)
	_transition_material = _material(Color(1.0, 0.78, 0.20, 0.45), true)
	_transition_surface_material = _material(Color(0.92, 0.36, 0.16, 0.82), false)
	_chunk_surface_material = _material(Color(0.25, 0.82, 0.52, 0.68), false)


func _material(color: Color, as_wireframe: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if as_wireframe else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _patch_origin() -> Vector3:
	return Vector3(
		-float(cells_x) * cell_size * 0.5,
		-float(cells_y) * cell_size * 0.5,
		-float(cells_z) * cell_size * 0.5
	)


func _corner_position(cell_origin: Vector3, corner: int) -> Vector3:
	return cell_origin + Vector3(
		1.0 if (corner & 1) != 0 else 0.0,
		1.0 if (corner & 2) != 0 else 0.0,
		1.0 if (corner & 4) != 0 else 0.0
	) * cell_size


func _build_patch_mesh_data() -> Dictionary:
	return _build_native_regular_patch_mesh_data()


func _build_native_regular_patch_mesh_data() -> Dictionary:
	var probe := _get_native_cell_probe()
	if probe == null:
		return _missing_world_transvoxel_mesh_data("WorldTransvoxelCellProbe is unavailable")
	var identity: Dictionary = probe.call("get_backend_identity")
	var vertices: PackedVector3Array = PackedVector3Array()
	var normal_array: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var backend_indices: PackedInt32Array = PackedInt32Array()
	var materials: PackedInt32Array = PackedInt32Array()
	var material_authored: PackedInt32Array = PackedInt32Array()
	var endpoint_a: PackedInt32Array = PackedInt32Array()
	var endpoint_b: PackedInt32Array = PackedInt32Array()
	var reuse_data: PackedInt32Array = PackedInt32Array()
	var case_histogram := {}
	var status_histogram := {}
	var active_cells := 0
	var empty_cells := 0
	var failed_cells := 0
	var origin := _patch_origin()
	for z in range(cells_z):
		for y in range(cells_y):
			for x in range(cells_x):
				var cell_origin := origin + Vector3(x, y, z) * cell_size
				var densities := PackedFloat32Array()
				var gradients := PackedVector3Array()
				var cell_materials := PackedInt32Array()
				var case_code := 0
				for corner in range(CORNER_COUNT):
					var p := _corner_position(cell_origin, corner)
					var d := _density(p)
					densities.append(d)
					gradients.append(_gradient(p))
					cell_materials.append(_material_id_at(p, d))
					if d < isovalue:
						case_code |= 1 << corner
				case_histogram[case_code] = int(case_histogram.get(case_code, 0)) + 1
				var cell_mesh: Dictionary = probe.call(
					"mesh_regular_cell",
					densities,
					gradients,
					cell_materials,
					cell_origin,
					cell_size,
					isovalue
				)
				var status := str(cell_mesh.get("status", "Unknown"))
				status_histogram[status] = int(status_histogram.get(status, 0)) + 1
				if bool(cell_mesh.get("empty", false)):
					empty_cells += 1
					continue
				if not bool(cell_mesh.get("ok", false)):
					failed_cells += 1
					continue
				active_cells += 1
				_append_native_cell_mesh(
					cell_mesh,
					vertices,
					normal_array,
					indices,
					backend_indices,
					materials,
					material_authored,
					endpoint_a,
					endpoint_b,
					reuse_data
				)
	var edge_metrics := _edge_metrics(vertices, indices)
	var orientation_metrics := _orientation_metrics(vertices, indices)
	return {
		"implementation": NATIVE_REGULAR_IMPLEMENTATION,
		"render_authority": NATIVE_AUTHORITY,
		"correctness_claim": CELL_PROBE_CORRECTNESS_CLAIM,
		"native_cell_probe_available": true,
		"backend_runtime_available": ClassDB.class_exists("WorldTransvoxelTerrain"),
		"backend_identity": identity,
		"vertices": vertices,
		"normals": normal_array,
		"indices": indices,
		"backend_indices": backend_indices,
		"materials": materials,
		"material_authored": material_authored,
		"endpoint_a": endpoint_a,
		"endpoint_b": endpoint_b,
		"reuse_data": reuse_data,
		"active_cells": active_cells,
		"empty_cells": empty_cells,
		"failed_cells": failed_cells,
		"triangles": int(indices.size() / 3),
		"degenerate_triangles": 0,
		"open_edges": int(edge_metrics.get("open_edges", 0)),
		"boundary_open_edges": int(edge_metrics.get("boundary_open_edges", 0)),
		"interior_open_edges": int(edge_metrics.get("interior_open_edges", 0)),
		"nonmanifold_edges": int(edge_metrics.get("nonmanifold_edges", 0)),
		"orientation_conflict_edges": int(orientation_metrics.get("orientation_conflict_edges", 0)),
		"case_histogram": case_histogram,
		"native_status_histogram": status_histogram,
	}


func _missing_world_transvoxel_mesh_data(error: String) -> Dictionary:
	return {
		"implementation": NATIVE_REGULAR_IMPLEMENTATION,
		"render_authority": NATIVE_AUTHORITY,
		"correctness_claim": "world_transvoxel_required_no_fallback",
		"native_cell_probe_available": false,
		"backend_runtime_available": ClassDB.class_exists("WorldTransvoxelTerrain"),
		"backend_identity": {},
		"dependency_error": error,
		"vertices": PackedVector3Array(),
		"normals": PackedVector3Array(),
		"indices": PackedInt32Array(),
		"backend_indices": PackedInt32Array(),
		"materials": PackedInt32Array(),
		"material_authored": PackedInt32Array(),
		"endpoint_a": PackedInt32Array(),
		"endpoint_b": PackedInt32Array(),
		"reuse_data": PackedInt32Array(),
		"active_cells": 0,
		"empty_cells": 0,
		"failed_cells": cells_x * cells_y * cells_z,
		"triangles": 0,
		"degenerate_triangles": 0,
		"open_edges": 0,
		"boundary_open_edges": 0,
		"interior_open_edges": 0,
		"nonmanifold_edges": 0,
		"orientation_conflict_edges": 0,
		"case_histogram": {},
		"native_status_histogram": { "DependencyMissing": cells_x * cells_y * cells_z },
	}


func _build_transition_probe_mesh_data() -> Dictionary:
	var empty_result := {
		"available": false,
		"ok": false,
		"status": "Unavailable",
		"vertices": PackedVector3Array(),
		"normals": PackedVector3Array(),
		"indices": PackedInt32Array(),
		"backend_indices": PackedInt32Array(),
		"triangles": 0,
		"case_code": -1,
		"orientation": "PositiveZ",
		"orientation_index": TRANSITION_ORIENTATION_POSITIVE_Z,
		"open_edges": 0,
		"nonmanifold_edges": 0,
		"orientation_conflict_edges": 0,
	}
	var probe := _get_native_cell_probe()
	if probe == null:
		return empty_result

	var origin := _transition_probe_origin()
	var spacing := cell_size
	var width := _transition_probe_width()
	var center := _transition_probe_center(origin)
	var densities := PackedFloat32Array()
	var gradients := PackedVector3Array()
	var materials := PackedInt32Array()
	var case_code := 0
	for index in range(9):
		var point := origin + Vector3(
			float(index % 3),
			float(int(index / 3)),
			0.0
		) * spacing
		var density := _transition_probe_density(point, center)
		densities.append(density)
		gradients.append(_transition_probe_gradient(point, center))
		materials.append(1 if density < isovalue else 0)
		if density < isovalue:
			case_code |= 1 << _transition_case_bit(index)

	var cell_mesh: Dictionary = probe.call(
		"mesh_transition_cell",
		densities,
		gradients,
		materials,
		TRANSITION_ORIENTATION_POSITIVE_Z,
		origin,
		spacing,
		width,
		isovalue
	)
	var vertices := PackedVector3Array()
	var normal_array := PackedVector3Array()
	var indices := PackedInt32Array()
	var backend_indices := PackedInt32Array()
	var material_array := PackedInt32Array()
	var material_authored := PackedInt32Array()
	var endpoint_a := PackedInt32Array()
	var endpoint_b := PackedInt32Array()
	var reuse_data := PackedInt32Array()
	if bool(cell_mesh.get("ok", false)):
		_append_native_cell_mesh(
			cell_mesh,
			vertices,
			normal_array,
			indices,
			backend_indices,
			material_array,
			material_authored,
			endpoint_a,
			endpoint_b,
			reuse_data
		)
	var edge_metrics := _isolated_edge_metrics(vertices, indices)
	var orientation_metrics := _orientation_metrics(vertices, indices)
	return {
		"available": true,
		"ok": bool(cell_mesh.get("ok", false)),
		"empty": bool(cell_mesh.get("empty", false)),
		"status": str(cell_mesh.get("status", "Unknown")),
		"vertices": vertices,
		"normals": normal_array,
		"indices": indices,
		"backend_indices": backend_indices,
		"materials": material_array,
		"material_authored": material_authored,
		"endpoint_a": endpoint_a,
		"endpoint_b": endpoint_b,
		"reuse_data": reuse_data,
		"triangles": int(indices.size() / 3),
		"case_code": int(cell_mesh.get("case_code", case_code)),
		"orientation": "PositiveZ",
		"orientation_index": TRANSITION_ORIENTATION_POSITIVE_Z,
		"open_edges": int(edge_metrics.get("open_edges", 0)),
		"nonmanifold_edges": int(edge_metrics.get("nonmanifold_edges", 0)),
		"orientation_conflict_edges": int(orientation_metrics.get("orientation_conflict_edges", 0)),
	}


func _build_chunk_probe_mesh_data() -> Dictionary:
	var probe := _get_native_cell_probe()
	if probe == null:
		return _empty_chunk_probe_mesh_data("DependencyMissing", "WorldTransvoxelCellProbe is unavailable")
	if not probe.has_method("mesh_chunk_with_callable"):
		return _empty_chunk_probe_mesh_data("MethodMissing", "mesh_chunk_with_callable is unavailable")

	var chunk_mesh: Dictionary = probe.call(
		"mesh_chunk_with_callable",
		Callable(self, "_chunk_probe_sample"),
		Vector3i.ZERO,
		0,
		0,
		0,
		isovalue,
		0.25
	)
	var regular: Dictionary = chunk_mesh.get("regular", {})
	var raw_vertices: PackedVector3Array = regular.get("vertices", PackedVector3Array())
	var vertices := PackedVector3Array()
	for vertex in raw_vertices:
		vertices.append(_chunk_probe_vertex_to_lab_space(vertex))
	var normal_array: PackedVector3Array = regular.get("normals", PackedVector3Array())
	if normal_array.size() != vertices.size():
		normal_array = PackedVector3Array()
		for vertex in vertices:
			var normal := _gradient(vertex)
			normal_array.append(normal.normalized() if normal.length_squared() > 0.0 else Vector3.UP)
	var indices: PackedInt32Array = regular.get("indices", PackedInt32Array())
	var edge_metrics := _isolated_edge_metrics(vertices, indices)
	var orientation_metrics := _orientation_metrics(vertices, indices)
	return {
		"implementation": CHUNK_PROBE_IMPLEMENTATION,
		"render_authority": NATIVE_AUTHORITY,
		"correctness_claim": LAB_CORRECTNESS_CLAIM,
		"available": true,
		"ok": bool(chunk_mesh.get("ok", false)),
		"status": str(chunk_mesh.get("status", "Unknown")),
		"error": str(chunk_mesh.get("sample_error", "")),
		"schema": str(chunk_mesh.get("schema", "")),
		"vertices": vertices,
		"normals": normal_array,
		"indices": indices,
		"backend_indices": regular.get("backend_indices", PackedInt32Array()),
		"materials": regular.get("materials", PackedInt32Array()),
		"material_authored": regular.get("material_authored", PackedInt32Array()),
		"endpoint_a": regular.get("endpoint_a", PackedInt32Array()),
		"endpoint_b": regular.get("endpoint_b", PackedInt32Array()),
		"reuse_data": regular.get("reuse_data", PackedInt32Array()),
		"chunk_cells": Vector3i(CHUNK_PROBE_CELLS_PER_AXIS, CHUNK_PROBE_CELLS_PER_AXIS, CHUNK_PROBE_CELLS_PER_AXIS),
		"chunk_lod": int(chunk_mesh.get("lod", 0)),
		"sample_count": int(chunk_mesh.get("sample_count", 0)),
		"vertices_count": vertices.size(),
		"triangles": int(regular.get("triangle_count", int(indices.size() / 3))),
		"open_edges": int(edge_metrics.get("open_edges", 0)),
		"nonmanifold_edges": int(edge_metrics.get("nonmanifold_edges", 0)),
		"orientation_conflict_edges": int(orientation_metrics.get("orientation_conflict_edges", 0)),
	}


func _empty_chunk_probe_mesh_data(status: String, error: String) -> Dictionary:
	return {
		"implementation": CHUNK_PROBE_IMPLEMENTATION,
		"render_authority": NATIVE_AUTHORITY,
		"correctness_claim": "world_transvoxel_required_no_fallback",
		"available": false,
		"ok": false,
		"status": status,
		"error": error,
		"schema": "",
		"vertices": PackedVector3Array(),
		"normals": PackedVector3Array(),
		"indices": PackedInt32Array(),
		"backend_indices": PackedInt32Array(),
		"materials": PackedInt32Array(),
		"material_authored": PackedInt32Array(),
		"endpoint_a": PackedInt32Array(),
		"endpoint_b": PackedInt32Array(),
		"reuse_data": PackedInt32Array(),
		"chunk_cells": Vector3i(CHUNK_PROBE_CELLS_PER_AXIS, CHUNK_PROBE_CELLS_PER_AXIS, CHUNK_PROBE_CELLS_PER_AXIS),
		"chunk_lod": 0,
		"sample_count": 0,
		"vertices_count": 0,
		"triangles": 0,
		"open_edges": 0,
		"nonmanifold_edges": 0,
		"orientation_conflict_edges": 0,
	}


func _chunk_probe_sample(point: Vector3i) -> Dictionary:
	var center := Vector3.ONE * (float(CHUNK_PROBE_CELLS_PER_AXIS) * 0.5)
	var p := (Vector3(float(point.x), float(point.y), float(point.z)) - center) * cell_size
	var density := _density(p)
	return {
		"density": density,
		"material": _material_id_at(p, density),
		"material_authored": true,
	}


func _chunk_probe_vertex_to_lab_space(vertex: Vector3) -> Vector3:
	var center := Vector3.ONE * (float(CHUNK_PROBE_CELLS_PER_AXIS) * 0.5)
	return (vertex - center) * cell_size + _chunk_probe_visual_offset()


func _chunk_probe_visual_offset() -> Vector3:
	var half_patch_x := float(cells_x) * cell_size * 0.5
	return Vector3(half_patch_x + cell_size * 10.0, 0.0, 0.0)


func _transition_case_bit(sample_index: int) -> int:
	match sample_index:
		0:
			return 0
		1:
			return 1
		2:
			return 2
		5:
			return 3
		8:
			return 4
		7:
			return 5
		6:
			return 6
		3:
			return 7
		4:
			return 8
	return 0


func _get_native_cell_probe() -> RefCounted:
	if _native_cell_probe != null and is_instance_valid(_native_cell_probe):
		return _native_cell_probe
	if not ClassDB.class_exists("WorldTransvoxelCellProbe"):
		push_error("World Transvoxel Cell Lab requires WorldTransvoxelCellProbe from res://addons/world_transvoxel; no fallback mesher is available.")
		return null
	var instance := ClassDB.instantiate("WorldTransvoxelCellProbe")
	if instance is RefCounted:
		_native_cell_probe = instance
	return _native_cell_probe


func _append_native_cell_mesh(
	cell_mesh: Dictionary,
	vertices: PackedVector3Array,
	normal_array: PackedVector3Array,
	indices: PackedInt32Array,
	backend_indices: PackedInt32Array,
	materials: PackedInt32Array,
	material_authored: PackedInt32Array,
	endpoint_a: PackedInt32Array,
	endpoint_b: PackedInt32Array,
	reuse_data: PackedInt32Array
) -> void:
	var cell_vertices: PackedVector3Array = cell_mesh.get("vertices", PackedVector3Array())
	var cell_normals: PackedVector3Array = cell_mesh.get("normals", PackedVector3Array())
	var cell_indices: PackedInt32Array = cell_mesh.get("indices", PackedInt32Array())
	var cell_backend_indices: PackedInt32Array = cell_mesh.get("backend_indices", PackedInt32Array())
	var cell_materials: PackedInt32Array = cell_mesh.get("materials", PackedInt32Array())
	var cell_material_authored: PackedInt32Array = cell_mesh.get("material_authored", PackedInt32Array())
	var cell_endpoint_a: PackedInt32Array = cell_mesh.get("endpoint_a", PackedInt32Array())
	var cell_endpoint_b: PackedInt32Array = cell_mesh.get("endpoint_b", PackedInt32Array())
	var cell_reuse_data: PackedInt32Array = cell_mesh.get("reuse_data", PackedInt32Array())
	var vertex_offset := vertices.size()
	for index in range(cell_vertices.size()):
		var position := cell_vertices[index]
		var normal := cell_normals[index] if index < cell_normals.size() else _gradient(position)
		vertices.append(position)
		normal_array.append(normal.normalized() if normal.length_squared() > 0.0 else Vector3.UP)
		materials.append(int(cell_materials[index]) if index < cell_materials.size() else 1)
		material_authored.append(int(cell_material_authored[index]) if index < cell_material_authored.size() else 0)
		endpoint_a.append(int(cell_endpoint_a[index]) if index < cell_endpoint_a.size() else -1)
		endpoint_b.append(int(cell_endpoint_b[index]) if index < cell_endpoint_b.size() else -1)
		reuse_data.append(int(cell_reuse_data[index]) if index < cell_reuse_data.size() else 0)
	for index in range(cell_indices.size()):
		indices.append(int(cell_indices[index]) + vertex_offset)
	for index in range(cell_backend_indices.size()):
		backend_indices.append(int(cell_backend_indices[index]) + vertex_offset)


func _make_array_mesh(mesh_data: Dictionary) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mesh_data.get("vertices", PackedVector3Array())
	arrays[Mesh.ARRAY_NORMAL] = mesh_data.get("normals", PackedVector3Array())
	arrays[Mesh.ARRAY_INDEX] = mesh_data.get("indices", PackedInt32Array())
	var mesh := ArrayMesh.new()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if vertices.size() > 0 and indices.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_edge_line_mesh(mesh_data: Dictionary) -> ArrayMesh:
	var source_vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var source_indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	var line_vertices := PackedVector3Array()
	var line_indices := PackedInt32Array()
	var edge_lookup := {}
	for i in range(0, source_indices.size(), 3):
		for pair in [
			[int(source_indices[i]), int(source_indices[i + 1])],
			[int(source_indices[i + 1]), int(source_indices[i + 2])],
			[int(source_indices[i + 2]), int(source_indices[i])],
		]:
			var a := source_vertices[int(pair[0])]
			var b := source_vertices[int(pair[1])]
			var key := _edge_key(a, b)
			if edge_lookup.has(key):
				continue
			edge_lookup[key] = true
			var base := line_vertices.size()
			line_vertices.append(a)
			line_vertices.append(b)
			line_indices.append(base)
			line_indices.append(base + 1)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = line_vertices
	arrays[Mesh.ARRAY_INDEX] = line_indices
	var mesh := ArrayMesh.new()
	if line_vertices.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


func _build_probe_labels(mesh_data: Dictionary, transition_data: Dictionary, chunk_data: Dictionary) -> void:
	_add_probe_label(
		"REGULAR PATCH\nnative regular-cell probe\ncells %s | tris %d" % [
			str(Vector3i(cells_x, cells_y, cells_z)),
			int(mesh_data.get("triangles", 0)),
		],
		Vector3(0.0, float(cells_y) * cell_size * 0.5 + cell_size * 1.6, 0.0),
		Color(0.55, 0.88, 1.0, 1.0)
	)
	_add_probe_label(
		"TRANSITION CELL\n%s | case %d\ntris %d" % [
			str(transition_data.get("orientation", "PositiveZ")),
			int(transition_data.get("case_code", -1)),
			int(transition_data.get("triangles", 0)),
		],
		_transition_probe_label_position(),
		Color(1.0, 0.58, 0.22, 1.0)
	)
	if show_chunk_probe:
		_add_probe_label(
			"PRODUCTION CHUNK\nWtChunkMesher LOD%d\ntris %d | samples %d" % [
				int(chunk_data.get("chunk_lod", 0)),
				int(chunk_data.get("triangles", 0)),
				int(chunk_data.get("sample_count", 0)),
			],
			_chunk_probe_label_position(),
			Color(0.45, 1.0, 0.68, 1.0)
		)


func _add_probe_label(text: String, position: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.name = "probe_label"
	label.text = text
	label.position = position
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = color
	label.outline_modulate = Color(0.02, 0.025, 0.03, 1.0)
	label.outline_size = 5
	label.font_size = 16
	label.pixel_size = 0.006
	label.fixed_size = false
	label.no_depth_test = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label_root.add_child(label)


func _transition_probe_label_position() -> Vector3:
	var origin := _transition_probe_origin()
	return origin + Vector3(cell_size, cell_size * 3.0, _transition_probe_width() * 0.5)


func _chunk_probe_label_position() -> Vector3:
	return _chunk_probe_visual_offset() + Vector3(0.0, sphere_radius + cell_size * 1.4, 0.0)


func _transition_probe_origin() -> Vector3:
	var half := Vector3(float(cells_x), float(cells_y), float(cells_z)) * cell_size * 0.5
	return Vector3(-cell_size, -cell_size, half.z + cell_size * 0.8)


func _transition_probe_width() -> float:
	return maxf(cell_size * 0.75, 0.05)


func _transition_probe_center(origin: Vector3) -> Vector3:
	return origin + Vector3(cell_size, cell_size, _transition_probe_width() * 0.5)


func _transition_probe_density(p: Vector3, center: Vector3) -> float:
	var local := p - center
	match field_mode:
		FieldMode.SPHERE:
			return local.length() - cell_size * 1.15
		FieldMode.TUNNEL:
			return maxf(local.y, cell_size * 0.45 - Vector2(local.x, local.z).length())
		FieldMode.SADDLE:
			return local.y - 0.22 * local.x * local.z
		FieldMode.WAVES:
			return local.y - 0.25 * sin(local.x * 1.8) - 0.20 * cos(local.z * 1.4)
	return local.y


func _transition_probe_gradient(p: Vector3, center: Vector3) -> Vector3:
	var h := maxf(cell_size * 0.05, 0.01)
	return Vector3(
		_transition_probe_density(p + Vector3(h, 0.0, 0.0), center) - _transition_probe_density(p - Vector3(h, 0.0, 0.0), center),
		_transition_probe_density(p + Vector3(0.0, h, 0.0), center) - _transition_probe_density(p - Vector3(0.0, h, 0.0), center),
		_transition_probe_density(p + Vector3(0.0, 0.0, h), center) - _transition_probe_density(p - Vector3(0.0, 0.0, h), center)
	) / (2.0 * h)


func _density(p: Vector3) -> float:
	var value := 0.0
	match field_mode:
		FieldMode.PLANE:
			value = p.y - surface_height
		FieldMode.SPHERE:
			value = p.length() - sphere_radius
		FieldMode.TUNNEL:
			var ground := p.y - surface_height
			var tunnel := 0.85 - Vector2(p.x, p.y - surface_height + 0.65).length()
			value = maxf(ground, tunnel)
		FieldMode.SADDLE:
			value = p.y - (surface_height + 0.18 * p.x * p.z)
		FieldMode.WAVES:
			value = p.y - (surface_height + 0.35 * sin(p.x * 1.2) + 0.25 * cos(p.z * 1.5))
	for edit in edits:
		var center := edit.get("center", Vector3.ZERO) as Vector3
		var radius := float(edit.get("radius", 1.0))
		var influence := radius - p.distance_to(center)
		if influence <= 0.0:
			continue
		if str(edit.get("mode", "")) == "dig":
			value = maxf(value, influence)
		else:
			value = minf(value, -influence)
	return value


func _material_id_at(p: Vector3, density: float) -> int:
	for edit in edits:
		if str(edit.get("mode", "")) != "construct":
			continue
		var center := edit.get("center", Vector3.ZERO) as Vector3
		var radius := float(edit.get("radius", 1.0))
		if p.distance_to(center) <= radius:
			return construct_material
	return 1 if density < isovalue else 0


func _gradient(p: Vector3) -> Vector3:
	var h := maxf(cell_size * 0.05, 0.01)
	return Vector3(
		_density(p + Vector3(h, 0.0, 0.0)) - _density(p - Vector3(h, 0.0, 0.0)),
		_density(p + Vector3(0.0, h, 0.0)) - _density(p - Vector3(0.0, h, 0.0)),
		_density(p + Vector3(0.0, 0.0, h)) - _density(p - Vector3(0.0, 0.0, h))
	) / (2.0 * h)


func _build_sample_markers() -> void:
	var total := (cells_x + 1) * (cells_y + 1) * (cells_z + 1)
	var stride := maxi(1, ceili(pow(float(total) / 512.0, 1.0 / 3.0)))
	var mesh := SphereMesh.new()
	mesh.radius = cell_size * 0.045
	mesh.height = cell_size * 0.09
	var origin := _patch_origin()
	for z in range(0, cells_z + 1, stride):
		for y in range(0, cells_y + 1, stride):
			for x in range(0, cells_x + 1, stride):
				var p := origin + Vector3(x, y, z) * cell_size
				var marker := MeshInstance3D.new()
				marker.name = "sample"
				marker.mesh = mesh
				marker.position = p
				marker.material_override = _solid_sample_material if _density(p) < isovalue else _empty_sample_material
				_sample_root.add_child(marker)


func _build_edit_markers() -> void:
	for edit in edits:
		var sphere := SphereMesh.new()
		var radius := float(edit.get("radius", 1.0))
		sphere.radius = radius
		sphere.height = radius * 2.0
		var marker := MeshInstance3D.new()
		marker.name = "edit_" + str(edit.get("mode", "unknown"))
		marker.mesh = sphere
		marker.position = edit.get("center", Vector3.ZERO) as Vector3
		marker.material_override = _dig_marker_material if str(edit.get("mode", "")) == "dig" else _construct_marker_material
		_marker_root.add_child(marker)


func _build_transition_frame() -> void:
	var arrays: Array = []
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var origin := _transition_probe_origin()
	var spacing := cell_size
	var width := _transition_probe_width()
	var points := [
		origin,
		origin + Vector3(2.0 * spacing, 0.0, 0.0),
		origin + Vector3(2.0 * spacing, 2.0 * spacing, 0.0),
		origin + Vector3(0.0, 2.0 * spacing, 0.0),
		origin + Vector3(0.0, 0.0, width),
		origin + Vector3(2.0 * spacing, 0.0, width),
		origin + Vector3(2.0 * spacing, 2.0 * spacing, width),
		origin + Vector3(0.0, 2.0 * spacing, width),
	]
	for point in points:
		vertices.append(point)
	for pair in [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]:
		indices.append(int(pair[0]))
		indices.append(int(pair[1]))
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = "transition_frame"
	instance.mesh = mesh
	instance.material_override = _transition_material
	_mesh_root.add_child(instance)


func _isolated_edge_metrics(vertices: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	var counts := {}
	for i in range(0, indices.size(), 3):
		var a := vertices[int(indices[i])]
		var b := vertices[int(indices[i + 1])]
		var c := vertices[int(indices[i + 2])]
		for edge in [[a, b], [b, c], [c, a]]:
			var key := _edge_key(edge[0], edge[1])
			counts[key] = int(counts.get(key, 0)) + 1
	var open_edges := 0
	var nonmanifold_edges := 0
	for key in counts.keys():
		var count := int(counts[key])
		if count == 1:
			open_edges += 1
		elif count > 2:
			nonmanifold_edges += 1
	return {
		"open_edges": open_edges,
		"nonmanifold_edges": nonmanifold_edges,
	}


func _edge_metrics(vertices: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	var counts := {}
	var edge_points := {}
	for i in range(0, indices.size(), 3):
		var a := vertices[int(indices[i])]
		var b := vertices[int(indices[i + 1])]
		var c := vertices[int(indices[i + 2])]
		for edge in [[a, b], [b, c], [c, a]]:
			var key := _edge_key(edge[0], edge[1])
			counts[key] = int(counts.get(key, 0)) + 1
			edge_points[key] = edge
	var open_edges := 0
	var boundary_open_edges := 0
	var interior_open_edges := 0
	var nonmanifold_edges := 0
	for key in counts.keys():
		var count := int(counts[key])
		if count == 1:
			open_edges += 1
			var edge: Array = edge_points[key]
			if _edge_on_patch_boundary(edge[0] as Vector3, edge[1] as Vector3):
				boundary_open_edges += 1
			else:
				interior_open_edges += 1
		elif count > 2:
			nonmanifold_edges += 1
	return {
		"open_edges": open_edges,
		"boundary_open_edges": boundary_open_edges,
		"interior_open_edges": interior_open_edges,
		"nonmanifold_edges": nonmanifold_edges,
	}


func _orientation_metrics(vertices: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	var directed_counts := {}
	var undirected_counts := {}
	for i in range(0, indices.size(), 3):
		var triangle_indices := [
			int(indices[i]),
			int(indices[i + 1]),
			int(indices[i + 2]),
		]
		for pair in [
			[triangle_indices[0], triangle_indices[1]],
			[triangle_indices[1], triangle_indices[2]],
			[triangle_indices[2], triangle_indices[0]],
		]:
			var a := vertices[int(pair[0])]
			var b := vertices[int(pair[1])]
			var directed_key := _point_key(a) + ">" + _point_key(b)
			var undirected_key := _edge_key(a, b)
			directed_counts[directed_key] = int(directed_counts.get(directed_key, 0)) + 1
			undirected_counts[undirected_key] = int(undirected_counts.get(undirected_key, 0)) + 1
	var conflicts := 0
	for raw_key in undirected_counts.keys():
		var key := str(raw_key)
		if int(undirected_counts[key]) != 2:
			continue
		var parts := key.split("|")
		if parts.size() != 2:
			continue
		var forward := int(directed_counts.get(parts[0] + ">" + parts[1], 0))
		var reverse := int(directed_counts.get(parts[1] + ">" + parts[0], 0))
		if forward != 1 or reverse != 1:
			conflicts += 1
	return {
		"orientation_conflict_edges": conflicts,
	}


func _edge_on_patch_boundary(a: Vector3, b: Vector3) -> bool:
	var origin := _patch_origin()
	var maximum := origin + Vector3(cells_x, cells_y, cells_z) * cell_size
	for axis in range(3):
		if _same_boundary_plane(a[axis], b[axis], origin[axis]) or _same_boundary_plane(a[axis], b[axis], maximum[axis]):
			return true
	return false


func _same_boundary_plane(a: float, b: float, plane: float) -> bool:
	return absf(a - plane) <= 0.0001 and absf(b - plane) <= 0.0001


func _edge_key(a: Vector3, b: Vector3) -> String:
	var ka := _point_key(a)
	var kb := _point_key(b)
	if ka < kb:
		return ka + "|" + kb
	return kb + "|" + ka


func _point_key(p: Vector3) -> String:
	return "%d,%d,%d" % [
		roundi(p.x * 10000.0),
		roundi(p.y * 10000.0),
		roundi(p.z * 10000.0),
	]


func _make_report(mesh_data: Dictionary, transition_data: Dictionary, chunk_data: Dictionary, elapsed_ms: float) -> Dictionary:
	var failed_cells := int(mesh_data.get("failed_cells", 0))
	var interior_open_edges := int(mesh_data.get("interior_open_edges", 0))
	var nonmanifold_edges := int(mesh_data.get("nonmanifold_edges", 0))
	var orientation_conflict_edges := int(mesh_data.get("orientation_conflict_edges", 0))
	var transition_available := bool(transition_data.get("available", false))
	var transition_ok := bool(transition_data.get("ok", false))
	var transition_nonmanifold_edges := int(transition_data.get("nonmanifold_edges", 0))
	var transition_orientation_conflict_edges := int(transition_data.get("orientation_conflict_edges", 0))
	var chunk_available := bool(chunk_data.get("available", false))
	var chunk_ok := bool(chunk_data.get("ok", false))
	var chunk_nonmanifold_edges := int(chunk_data.get("nonmanifold_edges", 0))
	var chunk_orientation_conflict_edges := int(chunk_data.get("orientation_conflict_edges", 0))
	var status := "PASS"
	if failed_cells > 0 or interior_open_edges > 0 or nonmanifold_edges > 0 or orientation_conflict_edges > 0:
		status = "FAIL"
	if not transition_available or not transition_ok or transition_nonmanifold_edges > 0 or transition_orientation_conflict_edges > 0:
		status = "FAIL"
	if not chunk_available or not chunk_ok or chunk_nonmanifold_edges > 0 or chunk_orientation_conflict_edges > 0:
		status = "FAIL"
	var backend_identity: Dictionary = mesh_data.get("backend_identity", {})
	var correctness_claim := LAB_CORRECTNESS_CLAIM if bool(mesh_data.get("native_cell_probe_available", false)) else str(mesh_data.get("correctness_claim", "world_transvoxel_required_no_fallback"))
	return {
		"schema": REPORT_SCHEMA,
		"lab_scope": LAB_SCOPE,
		"primary_validation_domain": PRIMARY_VALIDATION_DOMAIN,
		"primitive_scope": PRIMITIVE_SCOPE,
		"validation_standard": VALIDATION_STANDARD,
		"authority_model": AUTHORITY_MODEL,
		"upstream_correction_policy": UPSTREAM_CORRECTION_POLICY,
		"integration_game_role": INTEGRATION_GAME_ROLE,
		"integration_game_diagnostic_policy": INTEGRATION_GAME_DIAGNOSTIC_POLICY,
		"status": status,
		"implementation": str(mesh_data.get("implementation", NATIVE_REGULAR_IMPLEMENTATION)),
		"render_authority": str(mesh_data.get("render_authority", NATIVE_AUTHORITY)),
		"correctness_claim": correctness_claim,
		"native_cell_probe_available": bool(mesh_data.get("native_cell_probe_available", ClassDB.class_exists("WorldTransvoxelCellProbe"))),
		"backend_runtime_available": bool(mesh_data.get("backend_runtime_available", ClassDB.class_exists("WorldTransvoxelTerrain"))),
		"backend_identity": backend_identity,
		"backend_id": str(backend_identity.get("backend_id", "")),
		"cells": Vector3i(cells_x, cells_y, cells_z),
		"cell_count": cells_x * cells_y * cells_z,
		"active_cells": int(mesh_data.get("active_cells", 0)),
		"empty_cells": int(mesh_data.get("empty_cells", 0)),
		"failed_cells": failed_cells,
		"vertices": (mesh_data.get("vertices", PackedVector3Array()) as PackedVector3Array).size(),
		"triangles": int(mesh_data.get("triangles", 0)),
		"open_edges": int(mesh_data.get("open_edges", 0)),
		"boundary_open_edges": int(mesh_data.get("boundary_open_edges", 0)),
		"interior_open_edges": interior_open_edges,
		"nonmanifold_edges": nonmanifold_edges,
		"orientation_conflict_edges": orientation_conflict_edges,
		"transition_available": transition_available,
		"transition_ok": transition_ok,
		"transition_status": str(transition_data.get("status", "Unavailable")),
		"transition_orientation": str(transition_data.get("orientation", "PositiveZ")),
		"transition_orientation_index": int(transition_data.get("orientation_index", TRANSITION_ORIENTATION_POSITIVE_Z)),
		"transition_case_code": int(transition_data.get("case_code", -1)),
		"transition_vertices": (transition_data.get("vertices", PackedVector3Array()) as PackedVector3Array).size(),
		"transition_triangles": int(transition_data.get("triangles", 0)),
		"transition_open_edges": int(transition_data.get("open_edges", 0)),
		"transition_nonmanifold_edges": transition_nonmanifold_edges,
		"transition_orientation_conflict_edges": transition_orientation_conflict_edges,
		"chunk_probe_available": chunk_available,
		"chunk_probe_ok": chunk_ok,
		"chunk_probe_status": str(chunk_data.get("status", "Unavailable")),
		"chunk_probe_error": str(chunk_data.get("error", "")),
		"chunk_probe_implementation": str(chunk_data.get("implementation", CHUNK_PROBE_IMPLEMENTATION)),
		"chunk_probe_cells": chunk_data.get("chunk_cells", Vector3i(CHUNK_PROBE_CELLS_PER_AXIS, CHUNK_PROBE_CELLS_PER_AXIS, CHUNK_PROBE_CELLS_PER_AXIS)),
		"chunk_probe_lod": int(chunk_data.get("chunk_lod", 0)),
		"chunk_probe_samples": int(chunk_data.get("sample_count", 0)),
		"chunk_probe_vertices": int(chunk_data.get("vertices_count", 0)),
		"chunk_probe_triangles": int(chunk_data.get("triangles", 0)),
		"chunk_probe_open_edges": int(chunk_data.get("open_edges", 0)),
		"chunk_probe_nonmanifold_edges": chunk_nonmanifold_edges,
		"chunk_probe_orientation_conflict_edges": chunk_orientation_conflict_edges,
		"degenerate_triangles": int(mesh_data.get("degenerate_triangles", 0)),
		"field_mode": FieldMode.keys()[field_mode],
		"edit_count": edits.size(),
		"build_ms": elapsed_ms,
		"case_histogram": mesh_data.get("case_histogram", {}),
		"native_status_histogram": mesh_data.get("native_status_histogram", {}),
	}
