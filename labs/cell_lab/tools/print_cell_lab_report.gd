extends SceneTree

const LabScript := preload("res://addons/world_transvoxel_cell_lab/lab/wt_transvoxel_cell_lab.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab := LabScript.new()
	root.add_child(lab)
	lab.cells_x = 6
	lab.cells_y = 6
	lab.cells_z = 6
	lab.field_mode = LabScript.FieldMode.SPHERE
	var report: Dictionary = lab.rebuild()
	print("CELL_LAB_REPORT status=%s authority=%s claim=%s backend=%s tris=%d transition=%s/%d transition_nonmanifold=%d transition_orient=%d interior_open=%d nonmanifold=%d orient=%d failed_cells=%d" % [
		str(report.get("status", "UNKNOWN")),
		str(report.get("render_authority", "unknown")),
		str(report.get("correctness_claim", "unknown")),
		str(report.get("backend_id", "")),
		int(report.get("triangles", 0)),
		str(report.get("transition_status", "Unavailable")),
		int(report.get("transition_triangles", 0)),
		int(report.get("transition_nonmanifold_edges", 0)),
		int(report.get("transition_orientation_conflict_edges", 0)),
		int(report.get("interior_open_edges", 0)),
		int(report.get("nonmanifold_edges", 0)),
		int(report.get("orientation_conflict_edges", 0)),
		int(report.get("failed_cells", 0)),
	])
	lab.free()
	quit(0)
