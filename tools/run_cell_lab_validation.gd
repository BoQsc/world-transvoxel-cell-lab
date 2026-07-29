extends SceneTree

const LabScript := preload("res://addons/world_transvoxel_cell_lab/lab/wt_transvoxel_cell_lab.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ClassDB.class_exists("WorldTransvoxelCellProbe"):
		_fail("WorldTransvoxelCellProbe is required")
		return
	var lab := LabScript.new()
	root.add_child(lab)
	lab.cells_x = 6
	lab.cells_y = 6
	lab.cells_z = 6
	lab.field_mode = LabScript.FieldMode.SPHERE
	var suites := OS.get_cmdline_user_args()
	var run_all := suites.is_empty() or "all" in suites
	var results := {}
	if run_all or "base" in suites:
		print("WT_CELL_LAB_STAGE base")
		results["base"] = lab.rebuild()
	if run_all or "provenance" in suites:
		print("WT_CELL_LAB_STAGE provenance")
		results["provenance"] = lab.validate_native_dependency()
	if run_all or "regular" in suites:
		print("WT_CELL_LAB_STAGE regular")
		results["regular"] = lab.validate_regular_case_corpus()
	if run_all or "transition" in suites:
		print("WT_CELL_LAB_STAGE transition")
		results["transition"] = lab.validate_transition_case_corpus()
	if run_all or "chunk" in suites:
		print("WT_CELL_LAB_STAGE chunk")
		results["chunk"] = lab.validate_chunk_lod_seams()
	if run_all or "terrain" in suites:
		print("WT_CELL_LAB_STAGE terrain")
		results["terrain"] = lab.validate_reference_terrain()
	if run_all or "authority" in suites:
		print("WT_CELL_LAB_STAGE authority")
		results["authority"] = lab.validate_authority_stress()
	if run_all or "edit" in suites:
		print("WT_CELL_LAB_STAGE edit")
		results["edit"] = lab.validate_edit_sequence()
		results["edit_corpus"] = lab.validate_edit_corpus()
	if run_all or "standards" in suites:
		print("WT_CELL_LAB_STAGE standards")
		results["standards"] = lab.validate_standards_corpus()
	if run_all or "performance" in suites:
		print("WT_CELL_LAB_STAGE performance")
		results["performance"] = lab.run_performance_baselines(2)
	var failures: Array[String] = []
	for key in results.keys():
		var result: Dictionary = results[key]
		if str(result.get("status", "FAIL")) != "PASS":
			failures.append("%s=%s %s" % [
				key,
				str(result.get("status", "UNKNOWN")),
				str(result.get("sample_failures", [])),
			])
	if not failures.is_empty():
		_fail("; ".join(failures))
		return
	print("WT_CELL_LAB_VALIDATION_PASS suites=%s" % str(results.keys()))
	lab.free()
	quit(0)


func _fail(message: String) -> void:
	push_error("WT_CELL_LAB_VALIDATION_FAIL: " + message)
	quit(1)
