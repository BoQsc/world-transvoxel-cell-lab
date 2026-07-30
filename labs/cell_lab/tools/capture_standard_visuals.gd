extends SceneTree

const LabScript := preload("res://addons/world_transvoxel_cell_lab/lab/wt_transvoxel_cell_lab.gd")
const OUTPUT_DIRECTORY := "res://addons/world_transvoxel_cell_lab/standards/visuals"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_directory := OUTPUT_DIRECTORY
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("output="):
			output_directory = argument.trim_prefix("output=")
	var absolute_directory := ProjectSettings.globalize_path(output_directory)
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		_fail("could not create visual standards directory")
		return
	var packed_scene := load("res://labs/cell_lab/scenes/main.tscn")
	if packed_scene == null:
		_fail("main scene could not be loaded")
		return
	var scene: Node = packed_scene.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var lab: WtTransvoxelCellLab = scene.get_node("WtTransvoxelCellLab")
	if lab == null:
		_fail("lab node is missing")
		return
	lab.auto_rebuild = false
	var specs: Array[Dictionary] = [
		{"id": "overview", "mode": LabScript.InspectionMode.PATCH},
		{
			"id": "regular_case_42",
			"mode": LabScript.InspectionMode.REGULAR_CASE,
			"regular_case": 42,
		},
		{
			"id": "transition_case_341_negative_z",
			"mode": LabScript.InspectionMode.TRANSITION_CASE,
			"transition_case": 341,
			"orientation": 5,
		},
		{
			"id": "mixed_lod_positive_x",
			"mode": LabScript.InspectionMode.MIXED_LOD,
			"coarse_lod": 1,
			"face": 1,
		},
		{
			"id": "reference_terrain",
			"mode": LabScript.InspectionMode.REFERENCE_TERRAIN,
			"reference_view": LabScript.ReferenceViewMode.SURFACE,
		},
		{
			"id": "reference_terrain_lod",
			"mode": LabScript.InspectionMode.REFERENCE_TERRAIN,
			"reference_view": LabScript.ReferenceViewMode.LOD,
		},
		{
			"id": "reference_terrain_materials",
			"mode": LabScript.InspectionMode.REFERENCE_TERRAIN,
			"reference_view": LabScript.ReferenceViewMode.MATERIAL,
		},
		{
			"id": "reference_terrain_triangles",
			"mode": LabScript.InspectionMode.REFERENCE_TERRAIN,
			"reference_view": LabScript.ReferenceViewMode.TRIANGLES,
		},
		{
			"id": "reference_terrain_normals",
			"mode": LabScript.InspectionMode.REFERENCE_TERRAIN,
			"reference_view": LabScript.ReferenceViewMode.NORMALS,
		},
		{
			"id": "reference_terrain_seams",
			"mode": LabScript.InspectionMode.REFERENCE_TERRAIN,
			"reference_view": LabScript.ReferenceViewMode.SEAMS,
		},
		{
			"id": "reference_terrain_density",
			"mode": LabScript.InspectionMode.REFERENCE_TERRAIN,
			"reference_view": LabScript.ReferenceViewMode.DENSITY,
			"slice_axis": 2,
			"slice_position": 16.0,
		},
	]
	for spec in specs:
		lab.inspection_mode = int(spec["mode"])
		lab.selected_regular_case = int(spec.get("regular_case", lab.selected_regular_case))
		lab.selected_transition_case = int(spec.get("transition_case", lab.selected_transition_case))
		lab.selected_transition_orientation = int(spec.get("orientation", lab.selected_transition_orientation))
		lab.selected_chunk_lod = int(spec.get("coarse_lod", lab.selected_chunk_lod))
		lab.selected_chunk_face = int(spec.get("face", lab.selected_chunk_face))
		lab.reference_view_mode = int(
			spec.get("reference_view", LabScript.ReferenceViewMode.SURFACE)
		)
		lab.show_reference_feature_labels = bool(spec.get("show_features", false))
		lab.show_reference_chunk_bounds = false
		lab.show_reference_normals = false
		lab.show_reference_seams = false
		lab.show_reference_density_slice = false
		lab.show_reference_sample_grid = false
		lab.reference_slice_axis = int(spec.get("slice_axis", 1))
		lab.reference_slice_position = float(spec.get("slice_position", 10.0))
		lab.rebuild()
		var overlay: CanvasLayer = scene.get_node("Overlay")
		overlay.visible = int(spec["mode"]) == LabScript.InspectionMode.PATCH
		var camera: Camera3D = scene.get_node("Camera3D")
		if int(spec["mode"]) == LabScript.InspectionMode.REFERENCE_TERRAIN:
			camera.position = Vector3(7.5, 6.0, 10.5)
			camera.look_at(Vector3.ZERO, Vector3.UP)
		elif int(spec["mode"]) == LabScript.InspectionMode.MIXED_LOD:
			camera.position = Vector3(7.0, 6.0, 10.0)
			camera.look_at(Vector3.ZERO, Vector3.UP)
		elif int(spec["mode"]) == LabScript.InspectionMode.PATCH:
			camera.position = Vector3(11.0, 6.0, 14.0)
			camera.look_at(Vector3(5.0, 0.0, 0.0), Vector3.UP)
		else:
			camera.position = Vector3(4.5, 3.5, 6.0)
			camera.look_at(Vector3.ZERO, Vector3.UP)
		if scene.has_method("_update_status"):
			scene.call("_update_status")
		await process_frame
		await process_frame
		await process_frame
		var image: Image = root.get_viewport().get_texture().get_image()
		if image == null or image.is_empty():
			_fail("viewport capture requires a graphical rendering driver")
			return
		var path := "%s/%s.png" % [output_directory, str(spec["id"])]
		var error := image.save_png(path)
		if error != OK:
			_fail("could not save %s" % path)
			return
		print("WT_CELL_LAB_VISUAL_CAPTURE path=%s size=%dx%d" % [
			ProjectSettings.globalize_path(path),
			image.get_width(),
			image.get_height(),
		])
	print("WT_CELL_LAB_VISUAL_CAPTURE_PASS count=%d" % specs.size())
	quit(0)


func _fail(message: String) -> void:
	push_error("WT_CELL_LAB_VISUAL_CAPTURE_FAIL: " + message)
	quit(1)
