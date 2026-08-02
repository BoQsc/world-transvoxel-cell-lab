@tool
extends EditorPlugin

const TerrainLabScript := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/wt_transvoxel_terrain_lab.gd"
)
const OBSERVATORY_SCENE := (
	"res://labs/terrain_lab/scenes/terrain_observatory.tscn"
)
const OBSERVATORY_MENU_LABEL := "Open Terrain Observatory"
const SURFACE_REVIEW_SCENE := (
	"res://labs/terrain_lab/scenes/surface_shading_review.tscn"
)
const SURFACE_REVIEW_MENU_LABEL := "Open TQP-23 Surface Review"


func _enter_tree() -> void:
	add_custom_type(
		"WtTransvoxelTerrainLab",
		"Node",
		TerrainLabScript,
		null
	)
	add_tool_menu_item(OBSERVATORY_MENU_LABEL, _open_observatory)
	add_tool_menu_item(SURFACE_REVIEW_MENU_LABEL, _open_surface_review)


func _exit_tree() -> void:
	remove_tool_menu_item(OBSERVATORY_MENU_LABEL)
	remove_tool_menu_item(SURFACE_REVIEW_MENU_LABEL)
	remove_custom_type("WtTransvoxelTerrainLab")


func _open_observatory() -> void:
	get_editor_interface().open_scene_from_path(OBSERVATORY_SCENE)


func _open_surface_review() -> void:
	get_editor_interface().open_scene_from_path(SURFACE_REVIEW_SCENE)
