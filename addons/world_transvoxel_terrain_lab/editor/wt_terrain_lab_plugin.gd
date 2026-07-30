@tool
extends EditorPlugin

const TerrainLabScript := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/wt_transvoxel_terrain_lab.gd"
)


func _enter_tree() -> void:
	add_custom_type(
		"WtTransvoxelTerrainLab",
		"Node",
		TerrainLabScript,
		null
	)


func _exit_tree() -> void:
	remove_custom_type("WtTransvoxelTerrainLab")
