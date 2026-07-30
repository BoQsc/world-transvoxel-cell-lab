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
		{
			"id": "overview",
			"mode": LabScript.InspectionMode.PATCH,
			"camera_fov": 55.0,
		},
		{
			"id": "regular_case_42",
			"mode": LabScript.InspectionMode.REGULAR_CASE,
			"regular_case": 42,
			"camera_position": Vector3(4.7, 3.8, 6.4),
			"camera_target": Vector3(0.0, 0.6, 0.0),
			"camera_fov": 68.0,
			"require_full_geometry": true,
		},
		{
			"id": "transition_case_341_negative_z",
			"mode": LabScript.InspectionMode.TRANSITION_CASE,
			"transition_case": 341,
			"orientation": 5,
			"camera_position": Vector3(5.2, 4.7, 7.6),
			"camera_target": Vector3(0.0, 1.0, 0.0),
			"camera_fov": 72.0,
			"require_full_geometry": true,
		},
		{
			"id": "mixed_lod_positive_x",
			"mode": LabScript.InspectionMode.MIXED_LOD,
			"coarse_lod": 1,
			"face": 1,
			"camera_fov": 55.0,
			"caption": (
				"VISUAL REGRESSION / MIXED LOD\n"
				+ "Green coarse / blue fine / orange transition / yellow edges"
			),
			"require_full_geometry": true,
		},
		{
			"id": "reference_terrain",
			"mode": LabScript.InspectionMode.REFERENCE_TERRAIN,
			"reference_view": LabScript.ReferenceViewMode.SURFACE,
			"camera_position": Vector3(9.2, 6.6, 10.0),
			"camera_target": Vector3(0.0, 0.15, 0.0),
			"camera_fov": 55.0,
			"caption": (
				"VISUAL REGRESSION / SURFACE\n"
				+ "Elevation + slope presentation / material identity is separate"
			),
		},
		{
			"id": "reference_terrain_tunnel_closeup",
			"mode": LabScript.InspectionMode.REFERENCE_TERRAIN,
			"reference_view": LabScript.ReferenceViewMode.SURFACE,
			"camera_position": Vector3(-7.0, -0.48, -0.18),
			"camera_target": Vector3(-5.35, -0.58, -0.18),
			"camera_fov": 32.0,
			"caption": (
				"VISUAL REGRESSION / CANONICAL LOD1 TUNNEL MOUTH\n"
				+ "Surface geometry / numeric topology and seams are separate"
			),
			"shadows": false,
			"show_labels": false,
		},
		{
			"id": "reference_terrain_arch_closeup",
			"mode": LabScript.InspectionMode.REFERENCE_TERRAIN,
			"reference_view": LabScript.ReferenceViewMode.SURFACE,
			"camera_position": Vector3(2.4, 2.8, 4.6),
			"camera_target": Vector3(-0.55, 0.48, 0.90),
			"camera_fov": 42.0,
			"caption": (
				"VISUAL REGRESSION / FINE LOD ARCH + THIN FIN\n"
				+ "Feature probes separately validate solid / opening / clearance"
			),
			"shadows": false,
			"show_labels": false,
		},
		{
			"id": "reference_terrain_overhang_cutaway",
			"mode": LabScript.InspectionMode.REFERENCE_TERRAIN,
			"reference_view": LabScript.ReferenceViewMode.DENSITY,
			"slice_axis": 2,
			"slice_position": 6.0,
			"camera_position": Vector3(0.95, 0.38, -6.0),
			"camera_target": Vector3(0.95, 0.38, -1.20),
			"orthographic_size": 3.2,
			"caption": (
				"VISUAL REGRESSION / OVERHANG CUTAWAY / Z=6 / 32x32 CELLS\n"
				+ "Sampled d=0 contour / cell-center blue solid, red air / crosses samples"
			),
			"density_slice_only": true,
			"show_labels": false,
		},
		{
			"id": "reference_terrain_lod",
			"mode": LabScript.InspectionMode.REFERENCE_TERRAIN,
			"reference_view": LabScript.ReferenceViewMode.LOD,
			"caption": (
				"VISUAL REGRESSION / LOD\n"
				+ "Blue LOD0 / green LOD1 / orange transition / yellow selected"
			),
		},
		{
			"id": "reference_terrain_materials",
			"mode": LabScript.InspectionMode.REFERENCE_TERRAIN,
			"reference_view": LabScript.ReferenceViewMode.MATERIAL,
			"caption": (
				"VISUAL REGRESSION / MATERIAL IDS\n"
				+ "Canonical: 1 gray / 2 green / 3 blue\n"
				+ "4 orange / 6 magenta"
			),
		},
		{
			"id": "reference_terrain_triangles",
			"mode": LabScript.InspectionMode.REFERENCE_TERRAIN,
			"reference_view": LabScript.ReferenceViewMode.TRIANGLES,
			"caption": (
				"VISUAL REGRESSION / TRIANGLES\n"
				+ "Yellow native edges / numeric integrity remains the gate"
			),
		},
		{
			"id": "reference_terrain_normals",
			"mode": LabScript.InspectionMode.REFERENCE_TERRAIN,
			"reference_view": LabScript.ReferenceViewMode.NORMALS,
			"caption": (
				"VISUAL REGRESSION / NORMALS\n"
				+ "RGB encodes XYZ / lines sample native normals"
			),
		},
		{
			"id": "reference_terrain_seams",
			"mode": LabScript.InspectionMode.REFERENCE_TERRAIN,
			"reference_view": LabScript.ReferenceViewMode.SEAMS,
			"caption": (
				"VISUAL REGRESSION / SEAMS\n"
				+ "Cyan-green matched / red fail / orange transition / yellow selected"
			),
		},
		{
			"id": "reference_terrain_density",
			"mode": LabScript.InspectionMode.REFERENCE_TERRAIN,
			"reference_view": LabScript.ReferenceViewMode.DENSITY,
			"slice_axis": 2,
			"slice_position": 16.0,
			"caption": (
				"VISUAL REGRESSION / DENSITY SLICE / Z=16\n"
				+ "Sampled d=0 contour / cell-center blue solid, red air / crosses samples"
			),
		},
	]
	for spec in specs:
		lab.inspection_mode = int(spec["mode"])
		lab.selected_regular_case = int(spec.get("regular_case", lab.selected_regular_case))
		lab.selected_transition_case = int(spec.get("transition_case", lab.selected_transition_case))
		lab.selected_transition_orientation = int(spec.get("orientation", lab.selected_transition_orientation))
		lab.selected_chunk_lod = int(spec.get("coarse_lod", lab.selected_chunk_lod))
		lab.selected_chunk_face = int(spec.get("face", lab.selected_chunk_face))
		lab.wireframe = bool(spec.get("wireframe", false))
		lab.reference_view_mode = int(
			spec.get("reference_view", LabScript.ReferenceViewMode.SURFACE)
		)
		lab.show_reference_feature_labels = bool(spec.get("show_features", false))
		lab.show_reference_chunk_bounds = bool(spec.get("show_chunk_bounds", false))
		lab.show_reference_normals = false
		lab.show_reference_seams = false
		lab.show_reference_density_slice = false
		lab.show_reference_sample_grid = false
		lab.reference_slice_axis = int(spec.get("slice_axis", 1))
		lab.reference_slice_position = float(spec.get("slice_position", 10.0))
		lab.rebuild()
		var overlay: CanvasLayer = scene.get_node("Overlay")
		var caption := str(spec.get("caption", ""))
		overlay.visible = (
			int(spec["mode"]) == LabScript.InspectionMode.PATCH
			or not caption.is_empty()
		)
		var label_root := lab.get_node_or_null("CellLabLabels") as Node3D
		if label_root != null:
			label_root.visible = bool(spec.get("show_labels", true))
		if bool(spec.get("density_slice_only", false)):
			var mesh_root := lab.get_node_or_null("CellLabMesh") as Node3D
			if mesh_root != null:
				for child in mesh_root.get_children():
					if child is VisualInstance3D:
						(child as VisualInstance3D).visible = str(child.name).begins_with(
							"reference_terrain_density_"
						)
		var camera: Camera3D = scene.get_node("Camera3D")
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = float(spec.get("camera_fov", 52.0))
		if spec.has("orthographic_size"):
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = float(spec["orthographic_size"])
		if spec.has("camera_position"):
			camera.position = spec["camera_position"]
			camera.look_at(spec.get("camera_target", Vector3.ZERO), Vector3.UP)
		elif int(spec["mode"]) == LabScript.InspectionMode.REFERENCE_TERRAIN:
			camera.position = Vector3(9.2, 6.6, 10.0)
			camera.look_at(Vector3(0.0, 0.15, 0.0), Vector3.UP)
			camera.fov = 55.0
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
		var sun := scene.get_node_or_null("Sun") as DirectionalLight3D
		if sun != null:
			sun.shadow_enabled = bool(spec.get("shadows", true))
		if not caption.is_empty():
			var status_label := scene.get_node("Overlay/StatusLabel") as Label
			status_label.text = caption
		await process_frame
		await process_frame
		await process_frame
		if bool(spec.get("require_full_geometry", false)) \
				and not _visible_geometry_fits(lab, camera, 12.0):
			_fail("capture framing clips visible geometry for %s" % str(spec["id"]))
			return
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


func _visible_geometry_fits(
	lab: Node3D,
	camera: Camera3D,
	margin: float
) -> bool:
	var viewport_size := root.get_viewport().get_visible_rect().size
	for root_name in ["CellLabMesh", "CellLabSamples", "CellLabMarkers"]:
		var visual_root := lab.get_node_or_null(root_name)
		if visual_root == null:
			continue
		for node in visual_root.find_children("*", "VisualInstance3D", true, false):
			var instance := node as VisualInstance3D
			if instance == null or not instance.is_visible_in_tree():
				continue
			var bounds := instance.get_aabb()
			for x in [0.0, 1.0]:
				for y in [0.0, 1.0]:
					for z in [0.0, 1.0]:
						var local_point := bounds.position + Vector3(
							bounds.size.x * x,
							bounds.size.y * y,
							bounds.size.z * z
						)
						var world_point := instance.global_transform * local_point
						if camera.is_position_behind(world_point):
							return false
						var screen_point := camera.unproject_position(world_point)
						if screen_point.x < margin \
								or screen_point.y < margin \
								or screen_point.x > viewport_size.x - margin \
								or screen_point.y > viewport_size.y - margin:
							return false
	return true


func _fail(message: String) -> void:
	push_error("WT_CELL_LAB_VISUAL_CAPTURE_FAIL: " + message)
	quit(1)
