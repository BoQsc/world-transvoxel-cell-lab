extends SceneTree

const Qualification := preload("res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_power_profile_qualification.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var qualification := Qualification.new()
	root.add_child(qualification)
	var report := await qualification.run(
		_argument_value("--profile", "low_power_16w_60fps"),
		int(_argument_value("--warmup-seconds", "300")),
		int(_argument_value("--measurement-seconds", "1800"))
	)
	var output := _argument_value("--output", "")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			push_error("WT_TERRAIN_LAB_POWER_WORKLOAD_FAIL could not write report")
			quit(1)
			return
		file.store_string(JSON.stringify(report, "\t", false) + "\n")
	print("WT_TERRAIN_LAB_POWER_WORKLOAD_" + str(report.get("status", "FAIL")))
	quit(0 if str(report.get("status", "")) == "PASS" else 1)


func _argument_value(name: String, fallback: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size() - 1):
		if arguments[index] == name:
			return arguments[index + 1]
	return fallback
