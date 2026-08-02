extends SceneTree

const Qualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_observatory_qualification.gd"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_path := _argument_value("--output")
	var milestone := Qualification.run()
	var report := {
		"schema": "world_transvoxel.terrain_lab.terrain_observatory_qualification.v1",
		"status": str(milestone.get("status", "")),
		"milestone": milestone,
		"failures": milestone.get("failures", []),
	}
	print(JSON.stringify(report, "\t", false))
	if not output_path.is_empty():
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file == null:
			_fail("could not open output path: " + output_path)
			return
		file.store_string(JSON.stringify(report, "\t", false) + "\n")
	if str(report.get("status", "")) != "PASS":
		_fail("terrain observatory qualification failed: " + str(report.get("failures", [])))
		return
	print("WT_TERRAIN_OBSERVATORY_QUALIFICATION_PASS")
	quit(0)


func _argument_value(name: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size() - 1):
		if arguments[index] == name:
			return arguments[index + 1]
	return ""


func _fail(message: String) -> void:
	push_error("WT_TERRAIN_OBSERVATORY_QUALIFICATION_FAIL: " + message)
	quit(1)
