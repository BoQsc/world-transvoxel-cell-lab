extends SceneTree

const TerrainLabScript := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/wt_transvoxel_terrain_lab.gd"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_path := _argument_value("--output")
	var terrain_lab := TerrainLabScript.new()
	root.add_child(terrain_lab)
	var result: Dictionary = terrain_lab.validate_program_boundary()
	var edit_semantics: Dictionary = terrain_lab.qualify_edit_semantics()
	var material_surface: Dictionary = terrain_lab.qualify_material_surface()
	var terrain_systems: Dictionary = terrain_lab.qualify_terrain_systems()
	var structural_world: Dictionary = terrain_lab.qualify_structural_world()
	var completion: Dictionary = terrain_lab.qualify_program_completion()
	var suites := {
		"edit_semantics": edit_semantics,
		"material_surface": material_surface,
		"terrain_systems": terrain_systems,
		"structural_world": structural_world,
		"completion": completion,
	}
	result["qualification_suites"] = suites
	for suite in [
		edit_semantics,
		material_surface,
		terrain_systems,
		structural_world,
		completion,
	]:
		if str(suite.get("status", "")) == "PASS":
			continue
		result["status"] = "FAIL"
		var failures: Array = result.get("failures", [])
		failures.append(str(suite.get("schema", "unknown suite")) + " failed")
		result["failures"] = failures
	var evidence_alignment := _validate_evidence_alignment(
		terrain_lab.describe_program(),
		suites
	)
	result["evidence_alignment"] = evidence_alignment
	if str(evidence_alignment.get("status", "")) != "PASS":
		result["status"] = "FAIL"
		var failures: Array = result.get("failures", [])
		failures.append("suite evidence does not match the program manifest")
		result["failures"] = failures
	print(JSON.stringify(result, "\t", false))
	if not output_path.is_empty():
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file == null:
			_fail("could not open output path: " + output_path)
			return
		file.store_string(JSON.stringify(result, "\t", false) + "\n")
	if str(result.get("status", "")) != "PASS":
		_fail("program validation failed: " + str(result.get("failures", [])))
		return
	print("WT_TERRAIN_LAB_VALIDATION_PASS")
	terrain_lab.free()
	quit(0)


func _argument_value(name: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size() - 1):
		if arguments[index] == name:
			return arguments[index + 1]
	return ""


func _validate_evidence_alignment(
	program: Dictionary,
	suites: Dictionary
) -> Dictionary:
	var manifest_status := {}
	for milestone_value in program.get("milestones", []):
		var milestone: Dictionary = milestone_value
		manifest_status[str(milestone.get("id", ""))] = str(milestone.get("status", ""))
	var observed_status := {}
	for suite_name in suites:
		var suite: Dictionary = suites[suite_name]
		for milestone_id in suite.get("scope_status", {}):
			var raw_status := str(suite["scope_status"][milestone_id]).to_lower()
			var normalized := raw_status
			for allowed in [
				"proposed",
				"specified",
				"implemented",
				"qualified",
				"production",
				"blocked",
			]:
				if raw_status.begins_with(allowed):
					normalized = allowed
					break
			observed_status[str(milestone_id)] = normalized
	var failures: Array[String] = []
	for milestone_id in manifest_status:
		if int(str(milestone_id).trim_prefix("TQP-")) <= 5:
			continue
		if not observed_status.has(milestone_id):
			failures.append("no suite status for " + str(milestone_id))
			continue
		if str(observed_status[milestone_id]) != str(manifest_status[milestone_id]):
			failures.append(
				"%s suite=%s manifest=%s"
				% [
					str(milestone_id),
					str(observed_status[milestone_id]),
					str(manifest_status[milestone_id]),
				]
			)
	return {
		"schema": "world_transvoxel.terrain_lab.evidence_alignment.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"observed_milestone_count": observed_status.size() + 5,
		"failures": failures,
	}


func _fail(message: String) -> void:
	push_error("WT_TERRAIN_LAB_VALIDATION_FAIL: " + message)
	quit(1)
