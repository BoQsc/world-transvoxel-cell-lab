@tool
extends RefCounted
class_name WtCellLabReferenceTerrainPresenter

const Contracts := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_contracts.gd")
const MeshAnalysis := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_mesh_analysis.gd")

const DISPLAY_CENTER := Vector3(16.0, 10.0, 16.0)
const DISPLAY_SCALE := 0.12


func render(
	lab: Object,
	mesh_root: Node3D,
	marker_root: Node3D,
	label_root: Node3D,
	materials: Dictionary
) -> Dictionary:
	var fixture: Dictionary = lab.build_reference_terrain()
	var observatory: Dictionary = lab.build_reference_terrain_observatory(fixture)
	var display_buffers: Array = observatory.get("display_buffers", [])
	var force_wireframe := bool(observatory.get("force_wireframe", false))
	var view_name := str(observatory.get("view_name", "SURFACE"))
	var terrain_material: Material = materials.get("observatory_surface")
	if view_name in ["SEAMS", "DENSITY"]:
		terrain_material = materials.get("observatory_overlay_surface")
	elif view_name != "SURFACE":
		terrain_material = materials.get("observatory_diagnostic")
	for buffer_index in range(display_buffers.size()):
		var display_buffer: Dictionary = display_buffers[buffer_index]
		_add_mesh_instance(
			mesh_root,
			"reference_terrain_buffer_%d" % buffer_index,
			display_buffer,
			terrain_material
		)
		if bool(lab.wireframe) or force_wireframe:
			_add_wire_instance(
				mesh_root,
				"reference_terrain_wire_%d" % buffer_index,
				display_buffer,
				materials.get("wire")
			)

	var chunks: Array = fixture.get("chunks", [])
	var selected_index := clampi(
		int(observatory.get("selected_chunk_index", 0)),
		0,
		maxi(chunks.size() - 1, 0)
	)
	var selected_id := str(observatory.get("selected_chunk_id", ""))
	_add_chunk_bounds(
		mesh_root,
		chunks,
		[selected_id],
		materials.get("edge"),
		"reference_terrain_selected_chunk"
	)

	if bool(lab.get("show_reference_chunk_bounds")):
		_add_chunk_bounds(
			mesh_root,
			chunks,
			observatory.get("visible_chunk_ids", []),
			materials.get("basis"),
			"reference_terrain_chunk_bounds"
		)
	_add_observatory_overlays(mesh_root, observatory, materials)
	_add_feature_labels(label_root, observatory)
	_add_edit_markers(lab, marker_root, materials)

	var selected_lod := -1
	var selected_coordinate := Vector3i.ZERO
	if not chunks.is_empty():
		var selected: Dictionary = chunks[selected_index]
		selected_lod = int(selected.get("lod", -1))
		selected_coordinate = selected.get("chunk_coordinate", Vector3i.ZERO)
	var seam_lines: Dictionary = observatory.get("seam_lines", {})
	var slice: Dictionary = observatory.get("density_slice", {})
	var detail_line := "Visible %d chunks | %d triangles | materials %s" % [
		int(observatory.get("visible_chunk_count", 0)),
		int(observatory.get("triangle_count", 0)),
		str(observatory.get("represented_material_ids", [])),
	]
	if bool(slice.get("available", false)):
		detail_line = "%s | %s slice %.2f (%d samples)" % [
			detail_line,
			str(slice.get("axis_name", "")),
			float(slice.get("position", 0.0)),
			int(slice.get("sample_count", 0)),
		]
	if int(seam_lines.get("passing_overlay_count", 0)) > 0:
		detail_line = "%s | seams %d pass / %d fail" % [
			detail_line,
			int(seam_lines.get("passing_overlay_count", 0)),
			int(seam_lines.get("failing_overlay_count", 0)),
		]
	_add_label(
		label_root,
		"Terrain Observatory / %s\n%s | %s\n%s\nSelected %s LOD%d %s" % [
			str(observatory.get("view_name", "SURFACE")),
			str(fixture.get("status", "Unavailable")),
			str(fixture.get("fixture_id", "")),
			detail_line,
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
		"observatory_schema": str(observatory.get("schema", "")),
		"observatory_view": str(observatory.get("view_name", "")),
		"chunk_count": int(fixture.get("chunk_count", 0)),
		"visible_chunk_count": int(observatory.get("visible_chunk_count", 0)),
		"coarse_chunk_count": int(fixture.get("coarse_chunk_count", 0)),
		"fine_chunk_count": int(fixture.get("fine_chunk_count", 0)),
		"transition_chunk_count": int(fixture.get("transition_chunk_count", 0)),
		"sample_count": int(fixture.get("sample_count", 0)),
		"triangles": int(fixture.get("triangle_count", 0)),
		"visible_triangles": int(observatory.get("triangle_count", 0)),
		"transition_triangles": int(fixture.get("transition_triangles", 0)),
		"material_ids": fixture.get("material_ids", []),
		"feature_ids": fixture.get("feature_ids", []),
		"edit_count": int(fixture.get("edit_count", 0)),
		"selected_chunk": selected_id,
		"selected_chunk_index": selected_index,
		"selected_lod": selected_lod,
		"selected_coordinate": selected_coordinate,
		"geometry_signature": str(fixture.get("geometry_signature", "")),
		"build_ms": float(fixture.get("elapsed_ms", 0.0)),
		"observatory_ms": float(observatory.get("elapsed_ms", 0.0)),
	}


func _add_observatory_overlays(
	root: Node3D,
	observatory: Dictionary,
	materials: Dictionary
) -> void:
	_add_colored_lines(
		root,
		"reference_terrain_normals",
		observatory.get("normal_lines", {}),
		materials.get("observatory_line")
	)
	var seams: Dictionary = observatory.get("seam_lines", {})
	for spec in [
		["passing", Color(0.20, 0.94, 0.46), "reference_terrain_passing_seams"],
		["failing", Color(1.0, 0.08, 0.05), "reference_terrain_failing_seams"],
		["transition", Color(1.0, 0.58, 0.08), "reference_terrain_transition_faces"],
	]:
		var prefix := str(spec[0])
		_add_lines(
			root,
			str(spec[2]),
			seams.get("%s_vertices" % prefix, PackedVector3Array()),
			materials.get("observatory_line"),
			seams.get("%s_colors" % prefix, PackedColorArray())
		)
	var slice: Dictionary = observatory.get("density_slice", {})
	if bool(slice.get("available", false)):
		_add_mesh_instance(
			root,
			"reference_terrain_density_slice",
			slice,
			materials.get("observatory_slice")
		)
	_add_colored_lines(
		root,
		"reference_terrain_density_samples",
		observatory.get("sample_grid", {}),
		materials.get("observatory_line")
	)


func _add_colored_lines(
	root: Node3D,
	name_value: String,
	line_data: Dictionary,
	material: Material
) -> void:
	_add_lines(
		root,
		name_value,
		line_data.get("vertices", PackedVector3Array()),
		material,
		line_data.get("colors", PackedColorArray())
	)


func _add_chunk_bounds(
	root: Node3D,
	chunks: Array,
	visible_chunk_ids: Array,
	material: Material,
	name_value: String
) -> void:
	var lines := PackedVector3Array()
	for chunk_value in chunks:
		var chunk: Dictionary = chunk_value
		if str(chunk.get("fixture_chunk_id", "")) not in visible_chunk_ids:
			continue
		var lod := int(chunk.get("lod", 0))
		var extent := float(Contracts.CHUNK_PROBE_CELLS_PER_AXIS * (1 << lod))
		var origin := Vector3(
			float(chunk.get("world_origin_x", 0.0)),
			float(chunk.get("world_origin_y", 0.0)),
			float(chunk.get("world_origin_z", 0.0))
		)
		_append_aabb_lines(lines, AABB(origin, Vector3.ONE * extent))
	_add_lines(root, name_value, lines, material)


func _append_aabb_lines(lines: PackedVector3Array, bounds: AABB) -> void:
	var corners: Array[Vector3] = []
	for z in range(2):
		for y in range(2):
			for x in range(2):
				corners.append(
					(bounds.position + Vector3(x, y, z) * bounds.size - DISPLAY_CENTER)
						* DISPLAY_SCALE
				)
	for pair in [
		[0, 1], [1, 3], [3, 2], [2, 0],
		[4, 5], [5, 7], [7, 6], [6, 4],
		[0, 4], [1, 5], [2, 6], [3, 7],
	]:
		lines.append(corners[int(pair[0])])
		lines.append(corners[int(pair[1])])


func _add_feature_labels(root: Node3D, observatory: Dictionary) -> void:
	for feature_value in observatory.get("feature_labels", []):
		var feature: Dictionary = feature_value
		_add_label(
			root,
			str(feature.get("label", feature.get("id", ""))),
			feature.get("position", Vector3.ZERO),
			Color(0.96, 0.86, 0.38)
		)


func _add_edit_markers(
	lab: Object,
	root: Node3D,
	materials: Dictionary
) -> void:
	for edit_value in lab.get_reference_terrain_edits():
		var edit: Dictionary = edit_value
		var radius := float(edit.get("radius", 1.0)) * DISPLAY_SCALE
		var sphere := SphereMesh.new()
		sphere.radius = radius
		sphere.height = radius * 2.0
		sphere.radial_segments = 20
		sphere.rings = 10
		var instance := MeshInstance3D.new()
		instance.mesh = sphere
		var edit_center: Vector3 = edit.get("center", Vector3.ZERO)
		instance.position = (edit_center - DISPLAY_CENTER) * DISPLAY_SCALE
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
			if pair[0] < 0 or pair[1] < 0 \
					or pair[0] >= vertices.size() or pair[1] >= vertices.size():
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


func _add_lines(
	root: Node3D,
	name_value: String,
	vertices: PackedVector3Array,
	material: Material,
	colors: PackedColorArray = PackedColorArray()
) -> void:
	if vertices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	if colors.size() == vertices.size():
		arrays[Mesh.ARRAY_COLOR] = colors
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
	var colors: PackedColorArray = mesh_data.get("colors", PackedColorArray())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	if normals.size() == vertices.size():
		arrays[Mesh.ARRAY_NORMAL] = normals
	if colors.size() == vertices.size():
		arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	if not vertices.is_empty() and not indices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
