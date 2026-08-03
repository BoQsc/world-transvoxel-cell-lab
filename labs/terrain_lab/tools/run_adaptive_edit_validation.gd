extends SceneTree

const QUALIFICATION_PATH := (
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_adaptive_edit_qualification.gd"
)
const EVIDENCE_PATH := (
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_adaptive_edit_evidence.gd"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_path := ""
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size() - 1):
		if arguments[index] == "--output":
			output_path = arguments[index + 1]
	var qualification_script := load(QUALIFICATION_PATH) as Script
	var evidence_script := load(EVIDENCE_PATH) as Script
	if qualification_script == null or evidence_script == null:
		push_error("WT_TERRAIN_LAB_ADAPTIVE_EDIT_LOAD_FAIL")
		quit(3)
		return
	var qualification := qualification_script.new() as Node
	root.add_child(qualification)
	var report: Dictionary = await qualification.run()
	var evidence_validation: Dictionary = evidence_script.validate_report(report)
	report["standard_validation"] = evidence_validation
	if str(evidence_validation.get("status", "")) != "PASS":
		report["status"] = "FAIL"
		var failures: Array = report.get("failures", [])
		failures.append_array(evidence_validation.get("failures", []))
		report["failures"] = failures
	if not output_path.is_empty():
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file == null:
			push_error("WT_TERRAIN_LAB_ADAPTIVE_EDIT_WRITE_FAIL " + output_path)
			quit(2)
			return
		file.store_string(JSON.stringify(report, "\t", false) + "\n")
		file.close()
	if str(report.get("status", "")) != "PASS":
		push_error(
			"WT_TERRAIN_LAB_ADAPTIVE_EDIT_FAIL "
			+ JSON.stringify(report.get("failures", []))
		)
		quit(1)
		return
	print(
		"WT_TERRAIN_LAB_ADAPTIVE_EDIT_PASS scenarios=%d frames=%d matrix=%s" % [
			int((report.get("coverage", {}) as Dictionary).get("scenario_count", 0)),
			int((report.get("coverage", {}) as Dictionary).get("audited_frame_count", 0)),
			str(report.get("scenario_matrix_signature", "")),
		]
	)
	quit()
