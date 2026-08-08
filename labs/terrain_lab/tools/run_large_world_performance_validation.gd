extends SceneTree

const Qualification := preload("res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_large_world_performance_qualification.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var qualification := Qualification.new()
	root.add_child(qualification)
	var report: Dictionary = await qualification.run()
	var output := _argument_value("--output")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			_fail("could not write TQP-47 report")
			return
		file.store_string(JSON.stringify(report, "\t", false) + "\n")
	if str(report.get("status", "")) != "PASS":
		_fail("TQP-47 qualification failed: " + str(report.get("failures", [])))
		return
	print("WT_TERRAIN_LAB_LARGE_WORLD_PERFORMANCE_PASS")
	quit(0)


func _argument_value(name: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size() - 1):
		if arguments[index] == name:
			return arguments[index + 1]
	return ""


func _fail(message: String) -> void:
	push_error("WT_TERRAIN_LAB_LARGE_WORLD_PERFORMANCE_FAIL " + message)
	quit(1)
