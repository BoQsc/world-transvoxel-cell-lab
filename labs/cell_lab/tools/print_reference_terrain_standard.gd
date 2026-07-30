extends SceneTree

const LabScript := preload("res://addons/world_transvoxel_cell_lab/lab/wt_transvoxel_cell_lab.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab := LabScript.new()
	root.add_child(lab)
	var standard: Dictionary = lab.describe_reference_terrain_standard()
	print("WT_REFERENCE_TERRAIN_STANDARD ", JSON.stringify(standard))
	lab.free()
	quit(0 if str(standard.get("status", "")) == "PASS" else 1)
