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
		"seam_validation": _seam_summary(validation.get("seam_validation", {})),
		"feature_validation": validation.get("feature_validation", {}),
		"edit_validation": validation.get("edit_validation", {}),
		"elapsed_ms": validation.get("elapsed_ms", 0.0),
	}


func _seam_summary(validation: Dictionary) -> Dictionary:
	return {
		"status": validation.get("status", "FAIL"),
		"same_lod_pairs": validation.get("same_lod_pairs", 0),
		"same_lod_matching_pairs": validation.get("same_lod_matching_pairs", 0),
		"same_lod_mismatched_pairs": validation.get("same_lod_mismatched_pairs", 0),
		"same_lod_left_only_edges": validation.get("same_lod_left_only_edges", 0),
		"same_lod_right_only_edges": validation.get("same_lod_right_only_edges", 0),
		"mixed_lod_interfaces": validation.get("mixed_lod_interfaces", 0),
		"mixed_lod_matching_interfaces": validation.get(
			"mixed_lod_matching_interfaces",
			0
		),
		"mixed_lod_mismatched_interfaces": validation.get(
			"mixed_lod_mismatched_interfaces",
			0
		),
		"mixed_lod_coarse_only_edges": validation.get(
			"mixed_lod_coarse_only_edges",
			0
		),
		"mixed_lod_fine_only_edges": validation.get("mixed_lod_fine_only_edges", 0),
		"visible_crack_count": validation.get("visible_crack_count", -1),
	}
