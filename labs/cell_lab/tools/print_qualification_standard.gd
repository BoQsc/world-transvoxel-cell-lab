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
	var evidence: Dictionary = lab.build_qualification_evidence()
	var signature: Dictionary = evidence.get("standard_signature", {})
	var print_full := "full" in OS.get_cmdline_user_args()
	print(JSON.stringify(
		ReproStore.to_json_safe(evidence if print_full else signature),
		"\t",
		true
	))
	if str(signature.get("status", "")) != "PASS":
		push_error("WT_CELL_LAB_QUALIFICATION_STANDARD_FAIL")
		quit(1)
		return
	print("WT_CELL_LAB_QUALIFICATION_STANDARD_PASS")
	lab.free()
	quit(0)
