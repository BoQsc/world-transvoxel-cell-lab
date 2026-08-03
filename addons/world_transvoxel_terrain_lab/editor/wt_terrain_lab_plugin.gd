@tool
extends EditorPlugin

const TerrainLabScript := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/wt_transvoxel_terrain_lab.gd"
)
const OBSERVATORY_SCENE := (
	"res://labs/terrain_lab/scenes/terrain_observatory.tscn"
)
const OBSERVATORY_MENU_LABEL := "Open Terrain Observatory"
const LARGE_TERRAIN_OBSERVATORY_SCENE := (
	"res://labs/terrain_lab/scenes/large_terrain_observatory.tscn"
)
const LARGE_TERRAIN_OBSERVATORY_MENU_LABEL := "Open TQP-27 Large Terrain Observatory"
const SURFACE_REVIEW_SCENE := (
	"res://labs/terrain_lab/scenes/surface_shading_review.tscn"
)
const SURFACE_REVIEW_MENU_LABEL := "Open TQP-23 Surface Review"
const BOUNDARY_ENCLOSURE_OBSERVATORY_SCENE := (
	"res://labs/terrain_lab/scenes/boundary_enclosure_observatory.tscn"
)
const BOUNDARY_ENCLOSURE_OBSERVATORY_MENU_LABEL := (
	"Open TQP-32 Boundary Observatory"
)


func _enter_tree() -> void:
	add_custom_type(
		"WtTransvoxelTerrainLab",
		"Node",
		TerrainLabScript,
		null
	)
	add_tool_menu_item(OBSERVATORY_MENU_LABEL, _open_observatory)
	add_tool_menu_item(
		LARGE_TERRAIN_OBSERVATORY_MENU_LABEL,
		_open_large_terrain_observatory
	)
	add_tool_menu_item(SURFACE_REVIEW_MENU_LABEL, _open_surface_review)
	add_tool_menu_item(
		BOUNDARY_ENCLOSURE_OBSERVATORY_MENU_LABEL,
		_open_boundary_enclosure_observatory
	)
	set_process(true)


func _exit_tree() -> void:
	remove_tool_menu_item(OBSERVATORY_MENU_LABEL)
	remove_tool_menu_item(LARGE_TERRAIN_OBSERVATORY_MENU_LABEL)
	remove_tool_menu_item(SURFACE_REVIEW_MENU_LABEL)
	remove_tool_menu_item(BOUNDARY_ENCLOSURE_OBSERVATORY_MENU_LABEL)
	remove_custom_type("WtTransvoxelTerrainLab")


func _open_observatory() -> void:
	get_editor_interface().open_scene_from_path(OBSERVATORY_SCENE)


func _open_large_terrain_observatory() -> void:
	get_editor_interface().open_scene_from_path(LARGE_TERRAIN_OBSERVATORY_SCENE)


func _open_surface_review() -> void:
	get_editor_interface().open_scene_from_path(SURFACE_REVIEW_SCENE)


func _open_boundary_enclosure_observatory() -> void:
	get_editor_interface().open_scene_from_path(
		BOUNDARY_ENCLOSURE_OBSERVATORY_SCENE
	)


func _process(delta: float) -> void:
	_editor_camera_accumulator += delta
	if _editor_camera_accumulator < 0.2:
		return
	_editor_camera_accumulator = 0.0
	var edited_root := get_editor_interface().get_edited_scene_root()
	if edited_root == null or not edited_root.has_method("track_editor_camera"):
		return
	var editor_viewport := get_editor_interface().get_editor_viewport_3d(0)
	if editor_viewport == null:
		return
	var editor_camera := editor_viewport.get_camera_3d()
	if editor_camera == null:
		return
	if edited_root.has_method("consume_editor_camera_focus_request"):
		var focus_request: Variant = edited_root.call("consume_editor_camera_focus_request")
		if focus_request is Vector3:
			var target := focus_request as Vector3
			editor_camera.global_position = target + Vector3(0.0, 32.0, 0.0)
			editor_camera.look_at(target + Vector3(30.0, 0.0, 30.0), Vector3.UP)
		elif focus_request is Dictionary:
			var focus: Dictionary = focus_request
			var position: Vector3 = focus.get("position", Vector3.ZERO)
			var target: Vector3 = focus.get("target", Vector3.ZERO)
			editor_camera.global_position = position
			editor_camera.look_at(target, Vector3.UP)
	edited_root.call("track_editor_camera", editor_camera.global_position)


var _editor_camera_accumulator := 0.0
