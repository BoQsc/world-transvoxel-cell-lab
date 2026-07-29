@tool
extends RefCounted
class_name WtCellLabInspectionPresenter

const Contracts := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_contracts.gd")
const MeshAnalysis := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_mesh_analysis.gd")
const ReferenceTerrainPresenter := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_reference_terrain_presenter.gd")
const INSPECTION_MODE_NAMES := ["PATCH", "REGULAR_CASE", "TRANSITION_CASE", "MIXED_LOD", "REFERENCE_TERRAIN"]

var _reference_terrain_presenter := ReferenceTerrainPresenter.new()


func render(
	lab: Object,
	mesh_root: Node3D,
	sample_root: Node3D,
	label_root: Node3D,
	materials: Dictionary
) -> Dictionary:
	match int(lab.inspection_mode):
		1:
			return _render_regular_case(lab, mesh_root, sample_root, label_root, materials)
		2:
			return _render_transition_case(lab, mesh_root, sample_root, label_root, materials)
		3:
			return _render_mixed_lod(lab, mesh_root, label_root, materials)
		4:
			return _reference_terrain_presenter.render(
				lab,
				mesh_root,
				sample_root,
				label_root,
				materials
			)
	return {
		"mode": INSPECTION_MODE_NAMES[0],
		"status": "PASS",
	}


func _render_regular_case(
	lab: Object,
	mesh_root: Node3D,
	sample_root: Node3D,
	label_root: Node3D,
	materials: Dictionary
) -> Dictionary:
	var description: Dictionary = lab.describe_regular_case()
	var mesh_data: Dictionary = description.get("mesh", {})
	var transform := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 4.0), Vector3(-2.0, -2.0, -2.0))
	_add_mesh_instance(
		mesh_root,
		"selected_regular_case_mesh",
		mesh_data,
		transform,
		materials.get("surface")
	)
	_add_wire_instance(
		mesh_root,
		"selected_regular_case_wire",
		mesh_data,
		transform,
		materials.get("wire")
	)
	var densities: PackedFloat32Array = description.get("densities", PackedFloat32Array())
	var positions: PackedVector3Array = description.get("corner_positions", PackedVector3Array())
	for index in range(positions.size()):
		_add_sample_marker(
			sample_root,
			transform * positions[index],
			float(densities[index]) < 0.0,
			materials
		)
	var edge_lines := PackedVector3Array()
	var endpoint_a: PackedInt32Array = mesh_data.get("endpoint_a", PackedInt32Array())
	var endpoint_b: PackedInt32Array = mesh_data.get("endpoint_b", PackedInt32Array())
	for vertex_index in range(mini(endpoint_a.size(), endpoint_b.size())):
		var a := int(endpoint_a[vertex_index])
		var b := int(endpoint_b[vertex_index])
		if a >= 0 and b >= 0 and a < positions.size() and b < positions.size():
			edge_lines.append(transform * positions[a])
			edge_lines.append(transform * positions[b])
	_add_lines(mesh_root, "regular_backend_endpoint_edges", edge_lines, materials.get("edge"))
	_add_normal_lines(mesh_root, mesh_data, transform, materials.get("normal"))
	_add_label(
		label_root,
		"Regular case %d / %s\n%s, vertices %d, triangles %d" % [
			int(description.get("case_code", 0)),
			str(description.get("case_code_binary", "")),
			str(mesh_data.get("status", "Unavailable")),
			int(mesh_data.get("vertex_count", 0)),
			int(mesh_data.get("triangle_count", 0)),
		],
		Vector3(0.0, 3.0, 0.0),
		Color(0.95, 0.97, 1.0)
	)
	return {
		"mode": INSPECTION_MODE_NAMES[1],
		"status": str(mesh_data.get("status", "Unavailable")),
		"case_code": int(description.get("case_code", 0)),
		"case_code_binary": str(description.get("case_code_binary", "")),
		"densities": densities,
		"materials": description.get("materials", PackedInt32Array()),
		"edge_intersections": description.get("edge_intersections", []),
		"backend_endpoint_provenance": description.get("backend_endpoint_provenance", []),
		"vertices": int(mesh_data.get("vertex_count", 0)),
		"triangles": int(mesh_data.get("triangle_count", 0)),
	}


func _render_transition_case(
	lab: Object,
	mesh_root: Node3D,
	sample_root: Node3D,
	label_root: Node3D,
	materials: Dictionary
) -> Dictionary:
	var description: Dictionary = lab.describe_transition_case()
	var mesh_data: Dictionary = description.get("mesh", {})
	var basis_data: Dictionary = description.get("orientation_basis", {})
	var u: Vector3 = basis_data.get("u", Vector3.RIGHT)
	var v: Vector3 = basis_data.get("v", Vector3.UP)
	var w: Vector3 = basis_data.get("w", Vector3.FORWARD)
	var transform := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 2.5), -Vector3.ONE * 0.5)
	_add_mesh_instance(
		mesh_root,
		"selected_transition_case_mesh",
		mesh_data,
		transform,
		materials.get("transition")
	)
	_add_wire_instance(
		mesh_root,
		"selected_transition_case_wire",
		mesh_data,
		transform,
		materials.get("wire")
	)
	var densities: PackedFloat32Array = description.get("densities", PackedFloat32Array())
	var topology_positions := _transition_topology_positions(u, v, w)
	for index in range(9):
		_add_sample_marker(
			sample_root,
			transform * topology_positions[index],
			float(densities[index]) < 0.0,
			materials
		)
	for index in range(9, topology_positions.size()):
		_add_sample_marker(
			sample_root,
			transform * topology_positions[index],
			false,
			{"solid_sample": materials.get("low_sample"), "empty_sample": materials.get("low_sample")}
		)
	var edge_lines := PackedVector3Array()
	var endpoint_a: PackedInt32Array = mesh_data.get("endpoint_a", PackedInt32Array())
	var endpoint_b: PackedInt32Array = mesh_data.get("endpoint_b", PackedInt32Array())
	for vertex_index in range(mini(endpoint_a.size(), endpoint_b.size())):
		var a := int(endpoint_a[vertex_index])
		var b := int(endpoint_b[vertex_index])
		if a >= 0 and b >= 0 and a < topology_positions.size() and b < topology_positions.size():
			edge_lines.append(transform * topology_positions[a])
			edge_lines.append(transform * topology_positions[b])
	_add_lines(mesh_root, "transition_stitching_edges", edge_lines, materials.get("edge"))
	_add_normal_lines(mesh_root, mesh_data, transform, materials.get("normal"))
	var axis_lines := PackedVector3Array([
		Vector3.ZERO, u * 2.5,
		Vector3.ZERO, v * 2.5,
		Vector3.ZERO, w * 2.5,
	])
	_add_lines(mesh_root, "transition_orientation_basis", axis_lines, materials.get("basis"))
	_add_label(
		label_root,
		"Transition case %d / %s\n%s, %s, vertices %d, triangles %d" % [
			int(description.get("case_code", 0)),
			str(description.get("case_code_binary", "")),
			str(description.get("orientation", "")),
			str(mesh_data.get("status", "Unavailable")),
			int(mesh_data.get("vertex_count", 0)),
			int(mesh_data.get("triangle_count", 0)),
		],
		Vector3(0.0, 3.5, 0.0),
		Color(0.90, 1.0, 0.96)
	)
	return {
		"mode": INSPECTION_MODE_NAMES[2],
		"status": str(mesh_data.get("status", "Unavailable")),
		"case_code": int(description.get("case_code", 0)),
		"case_code_binary": str(description.get("case_code_binary", "")),
		"orientation": str(description.get("orientation", "")),
		"orientation_index": int(description.get("orientation_index", 0)),
		"orientation_basis": basis_data,
		"densities": densities,
		"materials": description.get("materials", PackedInt32Array()),
		"high_resolution_samples": description.get("high_resolution_samples", []),
		"low_resolution_alias_samples": description.get("low_resolution_alias_samples", []),
		"stitching_edges": description.get("stitching_edges", []),
		"backend_endpoint_provenance": description.get("backend_endpoint_provenance", []),
		"vertices": int(mesh_data.get("vertex_count", 0)),
		"triangles": int(mesh_data.get("triangle_count", 0)),
	}


func _render_mixed_lod(
	lab: Object,
	mesh_root: Node3D,
	label_root: Node3D,
	materials: Dictionary
) -> Dictionary:
	var fixture: Dictionary = lab.build_mixed_lod_fixture()
	var buffers: Array = fixture.get("buffers", [])
	var coarse_lod := int(fixture.get("coarse_lod", 1))
	var bounds := _world_buffer_bounds(buffers)
	var maximum_dimension := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var scale := 7.0 / maxf(maximum_dimension, 0.001)
	var center := bounds.get_center()
	var buffer_index := 0
	for buffer_value in buffers:
		var buffer: Dictionary = buffer_value
		var origin: Vector3 = buffer.get("origin", Vector3.ZERO)
		var vertices: PackedVector3Array = buffer.get("vertices", PackedVector3Array())
		var transformed := PackedVector3Array()
		for vertex in vertices:
			transformed.append((vertex + origin - center) * scale)
		var mesh_data := {
			"vertices": transformed,
			"indices": buffer.get("indices", PackedInt32Array()),
		}
		var material: Material = materials.get("chunk")
		if str(buffer.get("kind", "")) == "transition":
			material = materials.get("transition")
		elif buffer_index > 1:
			material = materials.get("fine_chunk")
		_add_mesh_instance(
			mesh_root,
			"mixed_lod_buffer_%d" % buffer_index,
			mesh_data,
			Transform3D.IDENTITY,
			material
		)
		_add_wire_instance(
			mesh_root,
			"mixed_lod_wire_%d" % buffer_index,
			mesh_data,
			Transform3D.IDENTITY,
			materials.get("wire")
		)
		buffer_index += 1
	var comparison: Dictionary = fixture.get("comparison", {})
	_add_label(
		label_root,
		"Mixed LOD %d -> %d, %s\n%s, coarse-only %d, fine-only %d" % [
			coarse_lod,
			coarse_lod - 1,
			str(fixture.get("face", "")),
			str(fixture.get("status", "Unavailable")),
			int(comparison.get("coarse_only", 0)),
			int(comparison.get("fine_only", 0)),
		],
		Vector3(0.0, 4.0, 0.0),
		Color(1.0, 0.95, 0.80)
	)
	return {
		"mode": INSPECTION_MODE_NAMES[3],
		"status": str(fixture.get("status", "Unavailable")),
		"face": str(fixture.get("face", "")),
		"face_index": int(fixture.get("face_index", 0)),
		"coarse_lod": coarse_lod,
		"fine_lod": coarse_lod - 1,
		"comparison": comparison,
		"buffer_count": buffers.size(),
	}


func _world_buffer_bounds(buffers: Array) -> AABB:
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	var has_vertex := false
	for buffer_value in buffers:
		var buffer: Dictionary = buffer_value
		var origin: Vector3 = buffer.get("origin", Vector3.ZERO)
		var vertices: PackedVector3Array = buffer.get("vertices", PackedVector3Array())
		for vertex in vertices:
			var world_vertex := vertex + origin
			minimum = minimum.min(world_vertex)
			maximum = maximum.max(world_vertex)
			has_vertex = true
	return AABB(minimum, maximum - minimum) if has_vertex else AABB(Vector3.ZERO, Vector3.ONE)


func _transition_topology_positions(u: Vector3, v: Vector3, w: Vector3) -> PackedVector3Array:
	var positions := PackedVector3Array()
	for sample_index in range(9):
		positions.append(
			u * float(sample_index % 3) + v * float(int(sample_index / 3))
		)
	for corner_index in [0, 2, 6, 8]:
		positions.append(
			u * float(corner_index % 3) \
				+ v * float(int(corner_index / 3)) \
				+ w * 0.25
		)
	return positions


func _add_mesh_instance(
	root: Node3D,
	name_value: String,
	mesh_data: Dictionary,
	transform: Transform3D,
	material: Material
) -> void:
	var mesh := _make_array_mesh(mesh_data)
	var instance := MeshInstance3D.new()
	instance.name = name_value
	instance.mesh = mesh
	instance.transform = transform
	instance.material_override = material
	root.add_child(instance)


func _add_wire_instance(
	root: Node3D,
	name_value: String,
	mesh_data: Dictionary,
	transform: Transform3D,
	material: Material
) -> void:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	var lines := PackedVector3Array()
	var seen := {}
	for index in range(0, indices.size(), 3):
		for pair in [
			[int(indices[index]), int(indices[index + 1])],
			[int(indices[index + 1]), int(indices[index + 2])],
			[int(indices[index + 2]), int(indices[index])],
		]:
			if pair[0] < 0 or pair[1] < 0 or pair[0] >= vertices.size() or pair[1] >= vertices.size():
				continue
			var a := vertices[pair[0]]
			var b := vertices[pair[1]]
			var key := MeshAnalysis.edge_key(a, b)
			if seen.has(key):
				continue
			seen[key] = true
			lines.append(transform * a)
			lines.append(transform * b)
	_add_lines(root, name_value, lines, material)


func _add_normal_lines(
	root: Node3D,
	mesh_data: Dictionary,
	transform: Transform3D,
	material: Material
) -> void:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
	var lines := PackedVector3Array()
	for index in range(mini(vertices.size(), normals.size())):
		var start := transform * vertices[index]
		var direction := transform.basis * normals[index]
		lines.append(start)
		lines.append(start + direction.normalized() * 0.45)
	_add_lines(root, "backend_vertex_normals", lines, material)


func _add_sample_marker(
	root: Node3D,
	position: Vector3,
	solid: bool,
	materials: Dictionary
) -> void:
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.13
	sphere.height = 0.26
	sphere.radial_segments = 12
	sphere.rings = 6
	marker.mesh = sphere
	marker.position = position
	marker.material_override = materials.get("solid_sample") if solid else materials.get("empty_sample")
	root.add_child(marker)


func _add_lines(root: Node3D, name_value: String, vertices: PackedVector3Array, material: Material) -> void:
	if vertices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = name_value
	instance.mesh = mesh
	instance.material_override = material
	root.add_child(instance)


func _add_label(
	root: Node3D,
	text_value: String,
	position: Vector3,
	color: Color
) -> void:
	var label := Label3D.new()
	label.text = text_value
	label.position = position
	label.modulate = color
	label.font_size = 44
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	root.add_child(label)


func _make_array_mesh(mesh_data: Dictionary) -> ArrayMesh:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	var normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	if normals.size() == vertices.size():
		arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	if not vertices.is_empty() and not indices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
