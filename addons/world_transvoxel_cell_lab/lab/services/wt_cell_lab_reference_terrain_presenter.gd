@tool
extends RefCounted
class_name WtCellLabReferenceTerrainPresenter

const MeshAnalysis := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_mesh_analysis.gd")


func render(
	lab: Object,
	mesh_root: Node3D,
	marker_root: Node3D,
	label_root: Node3D,
	materials: Dictionary
) -> Dictionary:
	var fixture: Dictionary = lab.build_reference_terrain()
	var buffers: Array = fixture.get("buffers", [])
	var center := Vector3(16.0, 10.0, 16.0)
	var scale := 0.12
	var buffer_index := 0
	for buffer_value in buffers:
		var buffer: Dictionary = buffer_value
		var mesh_data := _display_mesh_data(buffer, center, scale)
		var material: Material = materials.get("chunk")
		if str(buffer.get("kind", "")) == "transition":
			material = materials.get("transition")
		elif int(buffer.get("lod", 0)) == 0:
			material = materials.get("fine_chunk")
		_add_mesh_instance(
			mesh_root,
			"reference_terrain_buffer_%d" % buffer_index,
			mesh_data,
			material
		)
		if bool(lab.wireframe):
			_add_wire_instance(
				mesh_root,
				"reference_terrain_wire_%d" % buffer_index,
				mesh_data,
				materials.get("wire")
			)
		buffer_index += 1
	var chunks: Array = fixture.get("chunks", [])
	var selected_index := clampi(int(lab.get("selected_reference_chunk")), 0, maxi(chunks.size() - 1, 0))
	if not chunks.is_empty():
		var selected: Dictionary = chunks[selected_index]
		var selected_id := str(selected.get("fixture_chunk_id", ""))
		for selected_buffer_value in buffers:
			var selected_buffer: Dictionary = selected_buffer_value
			if str(selected_buffer.get("chunk_id", "")) != selected_id:
				continue
			var selected_mesh := _display_mesh_data(selected_buffer, center, scale)
			_add_wire_instance(
				mesh_root,
				"reference_terrain_selected_chunk",
				selected_mesh,
				materials.get("edge")
			)
	if bool(lab.get("show_reference_chunk_bounds")):
		_add_chunk_bounds(mesh_root, chunks, center, scale, materials.get("basis"))
	_add_edit_markers(lab, marker_root, center, scale, materials)
	var selected_id := ""
	var selected_lod := -1
	var selected_coordinate := Vector3i.ZERO
	if not chunks.is_empty():
		var selected: Dictionary = chunks[selected_index]
		selected_id = str(selected.get("fixture_chunk_id", ""))
		selected_lod = int(selected.get("lod", -1))
		selected_coordinate = selected.get("chunk_coordinate", Vector3i.ZERO)
	_add_label(
		label_root,
		"Reference Terrain / %s\n%s | %d chunks | %d triangles | %d transitions\nSelected %s LOD%d %s" % [
			str(fixture.get("fixture_id", "")),
			str(fixture.get("status", "Unavailable")),
			int(fixture.get("chunk_count", 0)),
			int(fixture.get("triangle_count", 0)),
			int(fixture.get("transition_triangles", 0)),
			selected_id,
			selected_lod,
			str(selected_coordinate),
		],
		Vector3(0.0, 4.35, 0.0),
		Color(0.94, 0.98, 1.0)
	)
	return {
		"mode": "REFERENCE_TERRAIN",
		"status": str(fixture.get("status", "Unavailable")),
		"fixture_id": str(fixture.get("fixture_id", "")),
		"chunk_count": int(fixture.get("chunk_count", 0)),
		"coarse_chunk_count": int(fixture.get("coarse_chunk_count", 0)),
		"fine_chunk_count": int(fixture.get("fine_chunk_count", 0)),
		"transition_chunk_count": int(fixture.get("transition_chunk_count", 0)),
		"sample_count": int(fixture.get("sample_count", 0)),
		"triangles": int(fixture.get("triangle_count", 0)),
		"transition_triangles": int(fixture.get("transition_triangles", 0)),
		"material_ids": fixture.get("material_ids", []),
		"edit_count": int(fixture.get("edit_count", 0)),
		"selected_chunk": selected_id,
		"selected_chunk_index": selected_index,
		"selected_lod": selected_lod,
		"selected_coordinate": selected_coordinate,
		"geometry_signature": str(fixture.get("geometry_signature", "")),
		"build_ms": float(fixture.get("elapsed_ms", 0.0)),
	}


func _display_mesh_data(buffer: Dictionary, center: Vector3, scale: float) -> Dictionary:
	var origin: Vector3 = buffer.get("origin", Vector3.ZERO)
	var source_vertices: PackedVector3Array = buffer.get("vertices", PackedVector3Array())
	var vertices := PackedVector3Array()
	for vertex in source_vertices:
		vertices.append((vertex + origin - center) * scale)
	return {
		"vertices": vertices,
		"normals": buffer.get("normals", PackedVector3Array()),
		"indices": buffer.get("indices", PackedInt32Array()),
	}


func _add_chunk_bounds(
	root: Node3D,
	chunks: Array,
	center: Vector3,
	scale: float,
	material: Material
) -> void:
	var lines := PackedVector3Array()
	for chunk_value in chunks:
		var chunk: Dictionary = chunk_value
		var lod := int(chunk.get("lod", 0))
		var extent := float(16 * (1 << lod))
		var origin := Vector3(
			float(chunk.get("world_origin_x", 0.0)),
			float(chunk.get("world_origin_y", 0.0)),
			float(chunk.get("world_origin_z", 0.0))
		)
		var bounds := AABB(origin, Vector3.ONE * extent)
		_append_aabb_lines(lines, bounds, center, scale)
	_add_lines(root, "reference_terrain_chunk_bounds", lines, material)


func _append_aabb_lines(
	lines: PackedVector3Array,
	bounds: AABB,
	center: Vector3,
	scale: float
) -> void:
	var corners: Array[Vector3] = []
	for z in range(2):
		for y in range(2):
			for x in range(2):
				corners.append(
					(bounds.position + Vector3(x, y, z) * bounds.size - center) * scale
				)
	for pair in [
		[0, 1], [1, 3], [3, 2], [2, 0],
		[4, 5], [5, 7], [7, 6], [6, 4],
		[0, 4], [1, 5], [2, 6], [3, 7],
	]:
		lines.append(corners[int(pair[0])])
		lines.append(corners[int(pair[1])])


func _add_edit_markers(
	lab: Object,
	root: Node3D,
	center: Vector3,
	scale: float,
	materials: Dictionary
) -> void:
	for edit_value in lab.get_reference_terrain_edits():
		var edit: Dictionary = edit_value
		var radius := float(edit.get("radius", 1.0)) * scale
		var sphere := SphereMesh.new()
		sphere.radius = radius
		sphere.height = radius * 2.0
		sphere.radial_segments = 20
		sphere.rings = 10
		var instance := MeshInstance3D.new()
		instance.mesh = sphere
		var edit_center: Vector3 = edit.get("center", Vector3.ZERO)
		instance.position = (edit_center - center) * scale
		instance.material_override = materials.get("dig_marker") \
			if str(edit.get("mode", "")) == "dig" else materials.get("construct_marker")
		root.add_child(instance)


func _add_mesh_instance(
	root: Node3D,
	name_value: String,
	mesh_data: Dictionary,
	material: Material
) -> void:
	var instance := MeshInstance3D.new()
	instance.name = name_value
	instance.mesh = _make_array_mesh(mesh_data)
	instance.material_override = material
	root.add_child(instance)


func _add_wire_instance(
	root: Node3D,
	name_value: String,
	mesh_data: Dictionary,
	material: Material
) -> void:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	var lines := PackedVector3Array()
	var seen := {}
	for index in range(0, indices.size(), 3):
		if index + 2 >= indices.size():
			break
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
			lines.append(a)
			lines.append(b)
	_add_lines(root, name_value, lines, material)


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


func _add_label(root: Node3D, text_value: String, position: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.text = text_value
	label.position = position
	label.modulate = color
	label.font_size = 42
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	root.add_child(label)


func _make_array_mesh(mesh_data: Dictionary) -> ArrayMesh:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
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
