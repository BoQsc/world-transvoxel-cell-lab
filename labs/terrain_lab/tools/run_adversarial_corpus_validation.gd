extends SceneTree

const Qualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_adversarial_corpus_qualification.gd"
)
const Evidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_adversarial_corpus_evidence.gd"
)
const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)

const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/adversarial_corpus_standard.json"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_path := _argument_value("--output")
	var case_filter := _argument_value("--case")
	if "--replay-minimized" in OS.get_cmdline_user_args():
		var standard := JsonLoader.load_dictionary(STANDARD_PATH)
		var report := JsonLoader.load_dictionary(str(standard.get("evidence", "")))
		var control: Dictionary = report.get("minimizer_control", {})
		var result := Qualification.replay_minimized_fixture(control.get("fixture", {}))
		print(JSON.stringify(result, "\t", false))
		if str(result.get("status", "")) != "PASS":
			_fail("retained minimized fixture replay failed")
			return
		print("WT_TERRAIN_LAB_ADVERSARIAL_MINIMIZED_REPLAY_PASS")
		quit(0)
		return
	var candidate := "--candidate" in OS.get_cmdline_user_args()
	var result := Qualification.run(case_filter, not candidate)
	if case_filter.is_empty() and not candidate:
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
		_fail("adversarial corpus validation failed: " + str(result.get("failures", [])))
		return
	print("WT_TERRAIN_LAB_ADVERSARIAL_CORPUS_PASS")
	quit(0)


func _argument_value(name: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size() - 1):
		if arguments[index] == name:
			return arguments[index + 1]
	return ""


func _fail(message: String) -> void:
	push_error("WT_TERRAIN_LAB_ADVERSARIAL_CORPUS_FAIL: " + message)
	quit(1)
