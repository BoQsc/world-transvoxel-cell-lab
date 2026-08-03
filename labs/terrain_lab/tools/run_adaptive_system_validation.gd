extends SceneTree

const Qualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_adaptive_system_qualification.gd"
)
const Evidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_adaptive_system_evidence.gd"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var qualification := Qualification.new()
	root.add_child(qualification)
	var report: Dictionary = await qualification.run()
	var validation: Dictionary = Evidence.validate_report(report)
	report["standard_validation"] = validation
	if str(validation.get("status", "")) != "PASS":
		report["status"] = "FAIL"
		var failures: Array = report.get("failures", [])
		failures.append_array(validation.get("failures", []))
		report["failures"] = failures
	var output_path := _argument_value("--output")
	if not output_path.is_empty():
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file == null:
			push_error("WT_TERRAIN_LAB_ADAPTIVE_SYSTEM_WRITE_FAIL " + output_path)
			quit(2)
			return
		file.store_string(JSON.stringify(report, "\t", false) + "\n")
		file.close()
	if str(report.get("status", "")) != "PASS":
		push_error("WT_TERRAIN_LAB_ADAPTIVE_SYSTEM_FAIL " + JSON.stringify(report.get("failures", [])))
		quit(1)
		return
	print("WT_TERRAIN_LAB_ADAPTIVE_SYSTEM_PASS signature=" + str(report.get("semantic_signature", "")))
	quit(0)


func _argument_value(name: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size() - 1):
		if arguments[index] == name:
			return arguments[index + 1]
	return ""
