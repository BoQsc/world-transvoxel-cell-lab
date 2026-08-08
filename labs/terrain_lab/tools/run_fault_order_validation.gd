extends SceneTree

const Qualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_fault_order_qualification.gd"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var qualification := Qualification.new()
	root.add_child(qualification)
	var report: Dictionary = await qualification.run()
	var output_path := _argument_value("--output")
	if not output_path.is_empty():
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file == null:
			_fail("could not write TQP-43 report")
			return
		file.store_string(JSON.stringify(report, "\t", false) + "\n")
	if str(report.get("status", "")) != "PASS":
		_fail("TQP-43 qualification failed: " + str(report.get("failures", [])))
		return
	print("WT_TERRAIN_LAB_FAULT_ORDER_PASS signature=" + str(report.get("semantic_signature", "")))
	quit(0)


func _argument_value(name: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size() - 1):
		if arguments[index] == name:
			return arguments[index + 1]
	return ""


func _fail(message: String) -> void:
	push_error("WT_TERRAIN_LAB_FAULT_ORDER_FAIL " + message)
	quit(1)
