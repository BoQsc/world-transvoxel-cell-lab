extends SceneTree

const LabScript := preload("res://addons/world_transvoxel_cell_lab/lab/wt_transvoxel_cell_lab.gd")
const ReproStore := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_repro_store.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ClassDB.class_exists("WorldTransvoxelCellProbe"):
		push_error("WorldTransvoxelCellProbe is required")
		quit(1)
		return
	var lab := LabScript.new()
	root.add_child(lab)
	var arguments := OS.get_cmdline_user_args()
	var section := arguments[0] if not arguments.is_empty() else "correctness"
	var result: Dictionary
	if section == "runtime":
		result = lab.build_runtime_qualification()
	else:
		result = lab.build_correctness_qualification()
	print(JSON.stringify(ReproStore.to_json_safe(result), "\t", true))
	if str(result.get("status", "")) != "PASS":
		push_error("WT_CELL_LAB_QUALIFICATION_SECTION_FAIL: " + section)
		quit(1)
		return
	print("WT_CELL_LAB_QUALIFICATION_SECTION_PASS: " + section)
	lab.free()
	quit(0)
