extends SceneTree

const Qualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_field_qualification.gd"
)
const Evidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_field_evidence.gd"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_path := _argument_value("--output")
	var fixture_filter := _argument_value("--fixture")
	var result := Qualification.run(fixture_filter)
	if fixture_filter.is_empty():
		var evidence_validation := Evidence.validate_report(result)
		result["standard_validation"] = evidence_validation
		if str(evidence_validation.get("status", "")) != "PASS":
			result["status"] = "FAIL"
			var failures: Array = result.get("failures", [])
			failures.append_array(evidence_validation.get("failures", []))
			result["failures"] = failures
	print(JSON.stringify(result, "\t", false))
	if not output_path.is_empty():
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file == null:
			_fail("could not open output path: " + output_path)
			return
		file.store_string(JSON.stringify(result, "\t", false) + "\n")
	if str(result.get("status", "")) != "PASS":
		_fail("native field validation failed: " + str(result.get("failures", [])))
		return
	print("WT_TERRAIN_LAB_NATIVE_FIELD_PASS")
	quit(0)


func _argument_value(name: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size() - 1):
		if arguments[index] == name:
			return arguments[index + 1]
	return ""


func _fail(message: String) -> void:
	push_error("WT_TERRAIN_LAB_NATIVE_FIELD_FAIL: " + message)
	quit(1)
