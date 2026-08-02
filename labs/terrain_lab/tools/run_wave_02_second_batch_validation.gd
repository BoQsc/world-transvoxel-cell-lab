extends SceneTree

const TextureSystemQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_texture_system_qualification.gd"
)
const VisibilityResidencyQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_visibility_residency_qualification.gd"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_path := _argument_value("--output")
	var results: Array[Dictionary] = [
		TextureSystemQualification.run(),
		VisibilityResidencyQualification.run(),
	]
	var failures: Array[String] = []
	for result in results:
		if str(result.get("status", "")) == "PASS":
			continue
		for failure_value in result.get("failures", []):
			failures.append("%s: %s" % [str(result.get("milestone", "UNKNOWN")), str(failure_value)])
	var report := {
		"schema": "world_transvoxel.terrain_lab.wave_02_second_batch_qualification.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"milestones": results,
		"failures": failures,
	}
	print(JSON.stringify(report, "\t", false))
	if not output_path.is_empty():
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file == null:
			_fail("could not open output path: " + output_path)
			return
		file.store_string(JSON.stringify(report, "\t", false) + "\n")
	if not failures.is_empty():
		_fail("Wave 02 second batch failed: " + str(failures))
		return
	print("WT_TQP_WAVE_02_SECOND_BATCH_PASS")
	quit(0)


func _argument_value(name: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size() - 1):
		if arguments[index] == name:
			return arguments[index + 1]
	return ""


func _fail(message: String) -> void:
	push_error("WT_TQP_WAVE_02_SECOND_BATCH_FAIL: " + message)
	quit(1)
