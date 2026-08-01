extends SceneTree

const GateBQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_gate_b_qualification.gd"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var result := GateBQualification.run()
	var output_path := _argument_value("--output")
	if not output_path.is_empty():
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file == null:
			push_error("WT_TERRAIN_GATE_B_FAIL could not open output path")
			quit(1)
			return
		file.store_string(JSON.stringify(result, "\t", false) + "\n")
	print("WT_TERRAIN_GATE_B_%s failures=%s" % [
		str(result.get("status", "FAIL")),
		str(result.get("failures", [])),
	])
	quit(0 if str(result.get("status", "")) == "PASS" else 1)


func _argument_value(name: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size() - 1):
		if arguments[index] == name:
			return arguments[index + 1]
	return ""
