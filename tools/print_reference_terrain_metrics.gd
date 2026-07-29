extends SceneTree

const LabScript := preload("res://addons/world_transvoxel_cell_lab/lab/wt_transvoxel_cell_lab.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab := LabScript.new()
	root.add_child(lab)
	var standard: Dictionary = lab.describe_reference_terrain_standard()
	print("WT_REFERENCE_TERRAIN_STANDARD ", JSON.stringify(standard))
	var validation: Dictionary = lab.validate_reference_terrain()
	print("WT_REFERENCE_TERRAIN_VALIDATION ", JSON.stringify(_summary(validation)))
	lab.free()
	quit(0 if str(validation.get("status", "")) == "PASS" else 1)


func _summary(validation: Dictionary) -> Dictionary:
	return {
		"status": validation.get("status", ""),
		"sample_failures": validation.get("sample_failures", []),
		"chunk_count": validation.get("chunk_count", 0),
		"triangle_count": validation.get("triangle_count", 0),
		"visible_crack_count": validation.get("visible_crack_count", -1),
		"determinism_failures": validation.get("determinism_failures", -1),
		"buffer_validation": validation.get("buffer_validation", {}),
		"seam_validation": validation.get("seam_validation", {}),
		"feature_validation": validation.get("feature_validation", {}),
		"edit_validation": validation.get("edit_validation", {}),
		"elapsed_ms": validation.get("elapsed_ms", 0.0),
	}
