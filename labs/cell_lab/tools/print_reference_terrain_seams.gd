extends SceneTree

const LabScript := preload("res://addons/world_transvoxel_cell_lab/lab/wt_transvoxel_cell_lab.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab := LabScript.new()
	root.add_child(lab)
	var fixture: Dictionary = lab.build_reference_terrain()
	var seams: Dictionary = fixture.get("seam_validation", {})
	print("WT_REFERENCE_TERRAIN_SEAMS ", JSON.stringify(seams))
	lab.free()
	quit(0 if str(seams.get("status", "")) == "PASS" else 1)
