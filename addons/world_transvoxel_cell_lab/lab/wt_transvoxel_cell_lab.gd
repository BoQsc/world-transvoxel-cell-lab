@tool
extends Node3D
class_name WtTransvoxelCellLab

enum FieldMode { PLANE, SPHERE, TUNNEL, SADDLE, WAVES }

const REPORT_SCHEMA := "world_transvoxel.cell_lab.report.v1"
const NATIVE_REGULAR_IMPLEMENTATION := "native_transvoxel_regular_cell_probe_v1"
const NATIVE_AUTHORITY := "NATIVE_TRANSVOXEL_BACKEND_AUTHORITATIVE"
const CORNER_COUNT := 8
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
var _surface_material: StandardMaterial3D
var _wire_material: StandardMaterial3D
var _solid_sample_material: StandardMaterial3D
var _empty_sample_material: StandardMaterial3D
var _dig_marker_material: StandardMaterial3D
var _construct_marker_material: StandardMaterial3D
var _transition_material: StandardMaterial3D
var _transition_surface_material: StandardMaterial3D


func _ready() -> void:
	_make_materials()
	rebuild()


func rebuild() -> Dictionary:
	var start_usec := Time.get_ticks_usec()
	_ensure_roots()
	_clear_children(_mesh_root)
	_clear_children(_sample_root)
	_clear_children(_marker_root)

	var mesh_data := _build_patch_mesh_data()
	var transition_data := _build_transition_probe_mesh_data()
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

	if show_sample_points:
		_build_sample_markers()
	if show_edit_markers:
		_build_edit_markers()
	if show_transition_frame:
		_build_transition_frame()

	var elapsed_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
	_last_report = _make_report(mesh_data, transition_data, elapsed_ms)
	return _last_report


func get_last_report() -> Dictionary:
	if _last_report.is_empty():
		rebuild()
	return _last_report


func get_status_line() -> String:
	var report := get_last_report()
	return "status=%s authority=%s cells=%s tris=%d interior_open=%d boundary_open=%d nonmanifold=%d orient=%d transition=%s/%d edits=%d %.2fms exact_backend=%s" % [
		str(report.get("status", "UNKNOWN")),
		str(report.get("render_authority", "unknown")),
		str(report.get("cells", Vector3i.ZERO)),
		int(report.get("triangles", 0)),
		int(report.get("interior_open_edges", 0)),
		int(report.get("boundary_open_edges", 0)),
		int(report.get("nonmanifold_edges", 0)),
		int(report.get("orientation_conflict_edges", 0)),
		str(report.get("transition_status", "unavailable")),
		int(report.get("transition_triangles", 0)),
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
		times.append(float(Time.get_ticks_usec() - start_usec) / 1000.0)
		total_triangles += int(data.get("triangles", 0)) + int(transition_data.get("triangles", 0))
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
		"correctness_claim": "exact_regular_and_transition_cell_backend_probe_v1",
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


func _make_report(mesh_data: Dictionary, transition_data: Dictionary, elapsed_ms: float) -> Dictionary:
	var failed_cells := int(mesh_data.get("failed_cells", 0))
	var interior_open_edges := int(mesh_data.get("interior_open_edges", 0))
	var nonmanifold_edges := int(mesh_data.get("nonmanifold_edges", 0))
	var orientation_conflict_edges := int(mesh_data.get("orientation_conflict_edges", 0))
	var transition_available := bool(transition_data.get("available", false))
	var transition_ok := bool(transition_data.get("ok", false))
	var transition_nonmanifold_edges := int(transition_data.get("nonmanifold_edges", 0))
	var transition_orientation_conflict_edges := int(transition_data.get("orientation_conflict_edges", 0))
	var status := "PASS"
	if failed_cells > 0 or interior_open_edges > 0 or nonmanifold_edges > 0 or orientation_conflict_edges > 0:
		status = "FAIL"
	if not transition_available or not transition_ok or transition_nonmanifold_edges > 0 or transition_orientation_conflict_edges > 0:
		status = "FAIL"
	var backend_identity: Dictionary = mesh_data.get("backend_identity", {})
	return {
		"schema": REPORT_SCHEMA,
		"status": status,
		"implementation": str(mesh_data.get("implementation", NATIVE_REGULAR_IMPLEMENTATION)),
		"render_authority": str(mesh_data.get("render_authority", NATIVE_AUTHORITY)),
		"correctness_claim": str(mesh_data.get("correctness_claim", "exact_regular_and_transition_cell_backend_probe_v1")),
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
		"degenerate_triangles": int(mesh_data.get("degenerate_triangles", 0)),
		"field_mode": FieldMode.keys()[field_mode],
		"edit_count": edits.size(),
		"build_ms": elapsed_ms,
		"case_histogram": mesh_data.get("case_histogram", {}),
		"native_status_histogram": mesh_data.get("native_status_histogram", {}),
	}
