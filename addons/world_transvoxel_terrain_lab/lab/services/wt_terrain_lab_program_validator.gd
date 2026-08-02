@tool
extends RefCounted
class_name WtTerrainLabProgramValidator

const FoundationQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_foundation_qualification.gd"
)
const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const TemporalWaveEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_temporal_wave_evidence.gd"
)

const PROGRAM_SCHEMA := "world_transvoxel.terrain_lab.program.v2"
const LAB_SCOPE := "experimental_terrain_qualification"
const VALID_STATUSES := [
	"proposed",
	"specified",
	"implemented",
	"qualified",
	"production",
	"blocked",
]
const TERRAIN_LAB_ROOT := "res://addons/world_transvoxel_terrain_lab"


static func validate(program: Dictionary, dependencies: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	var milestones: Array = program.get("milestones", [])
	var milestone_by_id := {}
	var status_counts := {}
	for status in VALID_STATUSES:
		status_counts[status] = 0

	_expect(str(program.get("schema", "")) == PROGRAM_SCHEMA, "program schema mismatch", failures)
	_expect(str(program.get("lab_scope", "")) == LAB_SCOPE, "terrain lab scope mismatch", failures)
	_expect(
		str(program.get("production_status", "")) == "NOT_PRODUCTION",
		"Terrain Lab must not claim production status",
		failures
	)
	_expect(
		str(program.get("execution_policy", "")) == "dependency_order_fail_closed",
		"program must execute in dependency order and fail closed",
		failures
	)
	_expect(milestones.size() == 46, "program must contain exactly 46 milestones", failures)

	var contract_refs := {}
	for index in range(milestones.size()):
		if not milestones[index] is Dictionary:
			failures.append("milestone %d is not an object" % index)
			continue
		var milestone: Dictionary = milestones[index]
		var expected_id := "TQP-%02d" % (index + 1)
		var milestone_id := str(milestone.get("id", ""))
		var status := str(milestone.get("status", ""))
		var contract_ref := str(milestone.get("contract_ref", ""))
		_expect(milestone_id == expected_id, "milestone sequence mismatch at " + expected_id, failures)
		_expect(not milestone_by_id.has(milestone_id), "duplicate milestone: " + milestone_id, failures)
		milestone_by_id[milestone_id] = milestone
		_expect(status in VALID_STATUSES, milestone_id + " has invalid status", failures)
		if status_counts.has(status):
			status_counts[status] = int(status_counts[status]) + 1
		_expect(not str(milestone.get("title", "")).is_empty(), milestone_id + " title is missing", failures)
		_expect(not str(milestone.get("owner", "")).is_empty(), milestone_id + " owner is missing", failures)
		_expect(not str(milestone.get("domain", "")).is_empty(), milestone_id + " domain is missing", failures)
		_expect(
			program.get("evidence_profiles", {}).has(milestone.get("evidence_profile", "")),
			milestone_id + " evidence profile is unknown",
			failures
		)
		_expect(contract_ref.begins_with("#tqp-"), milestone_id + " contract reference is invalid", failures)
		_expect(not contract_refs.has(contract_ref), "duplicate contract reference: " + contract_ref, failures)
		contract_refs[contract_ref] = true
		_expect(
			not str(milestone.get("claim_scope", "")).is_empty(),
			milestone_id + " claim scope is missing",
			failures
		)

	var gates: Dictionary = program.get("gates", {})
	_validate_gates(gates, milestone_by_id, failures)
	_validate_dependencies(milestones, milestone_by_id, gates, failures)
	_validate_evidence_profiles(program, failures)
	_validate_evidence_files(program, failures)
	_validate_execution_plan(program, milestone_by_id, failures)
	_validate_qualification_state(program, milestone_by_id, failures)
	_validate_edit_gate_b_evidence(program, milestone_by_id, failures)
	_validate_temporal_wave_evidence(program, milestone_by_id, failures)
	_validate_wave_02_first_batch_evidence(program, milestone_by_id, failures)
	_validate_wave_02_second_batch_evidence(program, milestone_by_id, failures)
	_validate_visual_evidence(program, milestone_by_id, failures)
	_validate_dependency_boundary(program, dependencies, failures)
	_validate_source_boundary(failures)

	var foundation := FoundationQualification.run()
	if str(foundation.get("status", "")) != "PASS":
		failures.append("Gate A foundation qualification failed")
	for foundation_id in ["TQP-01", "TQP-02", "TQP-03", "TQP-04", "TQP-05"]:
		var milestone: Dictionary = milestone_by_id.get(foundation_id, {})
		_expect(
			str(milestone.get("status", "")) == "qualified",
			foundation_id + " must match the retained Gate A qualification",
			failures
		)

	var gate_statuses := {}
	for gate_name in gates:
		gate_statuses[gate_name] = _gate_status(gates[gate_name], milestone_by_id)

	return {
		"schema": "world_transvoxel.terrain_lab.program_validation.v2",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"milestone_count": milestones.size(),
		"status_counts": status_counts,
		"proposed_milestone_count": int(status_counts.get("proposed", 0)),
		"specified_milestone_count": int(status_counts.get("specified", 0)),
		"qualified_milestone_count": int(status_counts.get("qualified", 0)),
		"gate_statuses": gate_statuses,
		"foundation": foundation,
		"dependencies": dependencies,
		"failures": failures,
	}


static func _validate_gates(
	gates: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	for required in ["GATE_A", "GATE_B", "GATE_C", "GATE_D", "GATE_E", "GATE_F"]:
		_expect(gates.has(required), "missing program gate: " + required, failures)
	for gate_name in gates:
		var members: Array = gates[gate_name]
		_expect(not members.is_empty(), str(gate_name) + " has no milestones", failures)
		for member in members:
			_expect(
				milestone_by_id.has(str(member)),
				"%s references unknown milestone %s" % [str(gate_name), str(member)],
				failures
			)


static func _validate_dependencies(
	milestones: Array,
	milestone_by_id: Dictionary,
	gates: Dictionary,
	failures: Array[String]
) -> void:
	for milestone_value in milestones:
		var milestone: Dictionary = milestone_value
		var milestone_id := str(milestone.get("id", ""))
		for dependency_value in milestone.get("depends_on", []):
			var dependency := str(dependency_value)
			_expect(
				milestone_by_id.has(dependency) or gates.has(dependency),
				milestone_id + " has unknown dependency " + dependency,
				failures
			)
		if str(milestone.get("status", "")) not in ["qualified", "production"]:
			continue
		for dependency_value in milestone.get("depends_on", []):
			var dependency := str(dependency_value)
			if gates.has(dependency):
				_expect(
					_gate_status(gates[dependency], milestone_by_id) == "QUALIFIED",
					milestone_id + " is qualified before " + dependency,
					failures
				)
				continue
			var dependency_milestone: Dictionary = milestone_by_id.get(dependency, {})
			_expect(
				str(dependency_milestone.get("status", "")) in ["qualified", "production"],
				milestone_id + " is qualified before " + dependency,
				failures
			)


static func _validate_evidence_profiles(program: Dictionary, failures: Array[String]) -> void:
	var evidence_classes: Array = program.get("evidence_classes", [])
	var profiles: Dictionary = program.get("evidence_profiles", {})
	_expect(evidence_classes.size() == 10, "evidence class catalog changed", failures)
	for profile_name in profiles:
		var profile: Array = profiles[profile_name]
		_expect(not profile.is_empty(), str(profile_name) + " evidence profile is empty", failures)
		for evidence_class in profile:
			_expect(
				evidence_class in evidence_classes,
				"%s contains unknown evidence class %s" % [str(profile_name), str(evidence_class)],
				failures
			)


static func _validate_evidence_files(program: Dictionary, failures: Array[String]) -> void:
	for path_value in program.get("foundation_evidence", []):
		var path := str(path_value)
		_expect(FileAccess.file_exists(path), "missing foundation evidence: " + path, failures)
		_expect(not JsonLoader.load_dictionary(path).is_empty(), "invalid foundation evidence: " + path, failures)
	var decision_ids := {}
	for path_value in program.get("decisions", []):
		var path := str(path_value)
		_expect(FileAccess.file_exists(path), "missing decision: " + path, failures)
		var decision := JsonLoader.load_dictionary(path)
		_expect(
			str(decision.get("schema", "")) == "world_transvoxel.terrain_lab.decision.v1",
			"invalid decision: " + path,
			failures
		)
		var decision_id := str(decision.get("id", ""))
		_expect(not decision_id.is_empty(), "decision ID is missing: " + path, failures)
		_expect(not decision_ids.has(decision_id), "duplicate decision ID: " + decision_id, failures)
		decision_ids[decision_id] = true
	for required in [
		"TQP-D001", "TQP-D002", "TQP-D003", "TQP-D004", "TQP-D005",
		"TQP-D006", "TQP-D007", "TQP-D008", "TQP-D009", "TQP-D010",
		"TQP-D011",
	]:
		_expect(decision_ids.has(required), "missing retained decision: " + required, failures)
	for key in [
		"qualification_state",
		"backend_decision",
		"blocker_catalog",
		"visual_evidence",
		"edit_gate_b_evidence",
		"temporal_wave_standard",
		"material_blending_standard",
		"streaming_window_standard",
		"large_world_coordinate_standard",
		"texture_system_standard",
		"visibility_residency_standard",
		"wave_02_first_batch_evidence",
		"wave_02_second_batch_evidence",
		"execution_plan",
	]:
		var path := str(program.get(key, ""))
		_expect(FileAccess.file_exists(path), "missing program evidence: " + key, failures)
		_expect(not JsonLoader.load_dictionary(path).is_empty(), "invalid program evidence: " + key, failures)


static func _validate_execution_plan(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var plan := JsonLoader.load_dictionary(str(program.get("execution_plan", "")))
	_expect(
		str(plan.get("schema", ""))
			== "world_transvoxel.terrain_lab.execution_plan.v1",
		"execution plan schema mismatch",
		failures
	)
	var positions := {}
	var active_wave_count := 0
	var current_wave := str(plan.get("current_wave", ""))
	var active_wave: Dictionary = {}
	var waves: Array = plan.get("waves", [])
	for wave_index in range(waves.size()):
		var wave: Dictionary = waves[wave_index]
		var wave_id := str(wave.get("id", ""))
		var wave_status := str(wave.get("status", ""))
		if wave_status == "active":
			active_wave_count += 1
			active_wave = wave
			_expect(wave_id == current_wave, "active execution wave differs from current_wave", failures)
		for step_index in range((wave.get("steps", []) as Array).size()):
			var step: Array = (wave.get("steps", []) as Array)[step_index]
			_expect(not step.is_empty(), wave_id + " contains an empty step", failures)
			for milestone_value in step:
				var milestone_id := str(milestone_value)
				_expect(milestone_by_id.has(milestone_id), "execution plan has unknown milestone " + milestone_id, failures)
				_expect(not positions.has(milestone_id), "execution plan duplicates " + milestone_id, failures)
				positions[milestone_id] = Vector2i(wave_index, step_index)
				if wave_status == "completed":
					var milestone: Dictionary = milestone_by_id.get(milestone_id, {})
					_expect(
						str(milestone.get("status", "")) in ["qualified", "production"],
						"completed execution wave contains unqualified " + milestone_id,
						failures
					)
	_expect(active_wave_count == 1, "execution plan must have exactly one active wave", failures)
	_expect(positions.size() == 46, "execution plan must cover all 46 milestones", failures)
	for milestone_id in milestone_by_id:
		var milestone: Dictionary = milestone_by_id[milestone_id]
		var milestone_position: Vector2i = positions.get(milestone_id, Vector2i(-1, -1))
		for dependency_value in milestone.get("depends_on", []):
			var dependencies: Array = []
			var dependency_id := str(dependency_value)
			if (program.get("gates", {}) as Dictionary).has(dependency_id):
				dependencies = (program.get("gates", {}) as Dictionary)[dependency_id]
			else:
				dependencies = [dependency_id]
			for expanded_value in dependencies:
				var expanded_id := str(expanded_value)
				var dependency_position: Vector2i = positions.get(expanded_id, Vector2i(-1, -1))
				_expect(
					dependency_position.x < milestone_position.x
						or (
							dependency_position.x == milestone_position.x
							and dependency_position.y < milestone_position.y
						),
					milestone_id + " is not scheduled after " + expanded_id,
					failures
				)
	var expected_next: Array = []
	for step_value in active_wave.get("steps", []):
		var step: Array = step_value
		for milestone_value in step:
			var milestone: Dictionary = milestone_by_id.get(str(milestone_value), {})
			if str(milestone.get("status", "")) not in ["qualified", "production"]:
				expected_next.append(str(milestone_value))
		if not expected_next.is_empty():
			break
	_expect(
		plan.get("recommended_next", []) == expected_next,
		"execution plan recommended_next differs from the first incomplete active step",
		failures
	)


static func _validate_qualification_state(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var state := JsonLoader.load_dictionary(str(program.get("qualification_state", "")))
	_expect(
		str(state.get("schema", "")) == "world_transvoxel.terrain_lab.qualification_state.v1",
		"qualification state schema mismatch",
		failures
	)
	_expect(
		int(state.get("program_revision", -1)) == int(program.get("program_revision", -2)),
		"qualification state program revision mismatch",
		failures
	)
	var status_lists: Dictionary = state.get("statuses", {})
	var seen := {}
	for status in VALID_STATUSES:
		_expect(status_lists.has(status), "qualification state missing status: " + status, failures)
		for milestone_value in status_lists.get(status, []):
			var milestone_id := str(milestone_value)
			_expect(milestone_by_id.has(milestone_id), "qualification state has unknown milestone", failures)
			_expect(not seen.has(milestone_id), "qualification state duplicates " + milestone_id, failures)
			seen[milestone_id] = status
			var milestone: Dictionary = milestone_by_id.get(milestone_id, {})
			_expect(
				str(milestone.get("status", "")) == status,
				milestone_id + " status differs from retained qualification state",
				failures
			)
	_expect(seen.size() == 46, "qualification state must classify all 46 milestones", failures)
	var suite_milestones := {}
	for suite_value in state.get("suites", []):
		var suite: Dictionary = suite_value
		_expect(not str(suite.get("schema", "")).is_empty(), "suite schema is missing", failures)
		for milestone_value in suite.get("milestones", []):
			var milestone_id := str(milestone_value)
			_expect(
				not suite_milestones.has(milestone_id),
				"milestone belongs to multiple suites: " + milestone_id,
				failures
			)
			suite_milestones[milestone_id] = str(suite.get("id", ""))
	_expect(suite_milestones.size() == 46, "qualification suites must cover all milestones", failures)
	var blocker_catalog := JsonLoader.load_dictionary(str(program.get("blocker_catalog", "")))
	var blocker_ids := {}
	for blocker_value in blocker_catalog.get("blockers", []):
		var blocker: Dictionary = blocker_value
		blocker_ids[str(blocker.get("milestone", ""))] = true
	for milestone_id in status_lists.get("blocked", []):
		_expect(
			blocker_ids.has(str(milestone_id)),
			"blocked milestone lacks an exit condition: " + str(milestone_id),
			failures
		)
	var retained_path := str(state.get("retained_report", ""))
	_expect(FileAccess.file_exists(retained_path), "retained qualification report is missing", failures)
	if FileAccess.file_exists(retained_path):
		var retained := JsonLoader.load_dictionary(retained_path)
		_expect(
			str(retained.get("schema", "")) == "world_transvoxel.terrain_lab.program_validation.v2",
			"retained qualification report schema mismatch",
			failures
		)
		if not _is_regenerating_retained_report(retained_path):
			_expect(
				str(retained.get("status", "")) == "PASS",
				"retained qualification report did not pass",
				failures
			)
		_expect(
			int(retained.get("milestone_count", 0)) == 46,
			"retained qualification report milestone count changed",
			failures
		)
static func _validate_edit_gate_b_evidence(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard := JsonLoader.load_dictionary(str(program.get("edit_gate_b_evidence", "")))
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.edit_gate_b_standard.v1",
		"Gate B edit standard schema mismatch",
		failures
	)
	_expect(
		str(standard.get("authority", "")) == "world_transvoxel_cpu_native_chunk_probe",
		"Gate B native authority changed",
		failures
	)
	_expect(
		is_equal_approx(float(standard.get("sample_scale_m", 0.0)), 0.5),
		"Gate B sample-to-meter scale changed",
		failures
	)
	var qualified_lods: Array = standard.get("qualified_lods", [])
	_expect(qualified_lods.size() == 8, "Gate B LOD matrix must cover LOD0-7", failures)
	for lod in range(8):
		var found := false
		for qualified_lod in qualified_lods:
			if int(qualified_lod) == lod:
				found = true
				break
		_expect(found, "Gate B LOD matrix is missing LOD%d" % lod, failures)
	var stable_expected: Dictionary = standard.get("stable_expected", {})
	for index in range(9, 15):
		var milestone_id := "TQP-%02d" % index
		_expect(stable_expected.has(milestone_id), "Gate B standard missing " + milestone_id, failures)
		_expect(
			str((milestone_by_id.get(milestone_id, {}) as Dictionary).get("status", ""))
				== "qualified",
			milestone_id + " must match qualified Gate B evidence",
			failures
		)
	var visual: Dictionary = standard.get("visual_evidence", {})
	var visual_path := str(visual.get("path", ""))
	_expect(FileAccess.file_exists(visual_path), "Gate B diagnostic visual is missing", failures)
	_expect(
		int(visual.get("width", 0)) == 1280 and int(visual.get("height", 0)) == 720,
		"Gate B diagnostic visual dimensions changed",
		failures
	)
	_expect(
		not str(visual.get("pixel_signature", "")).is_empty(),
		"Gate B diagnostic visual signature is missing",
		failures
	)
	_expect(
		(visual.get("shape_panels", []) as Array).size() == 7,
		"Gate B diagnostic shape panel contract changed",
		failures
	)
	_expect(
		(visual.get("sequence_panels", []) as Array).size() == 6,
		"Gate B diagnostic sequence panel contract changed",
		failures
	)


static func _validate_temporal_wave_evidence(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard := JsonLoader.load_dictionary(
		str(program.get("temporal_wave_standard", ""))
	)
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.temporal_wave_standard.v1",
		"temporal wave standard schema mismatch",
		failures
	)
	var validation := TemporalWaveEvidence.validate_retained()
	if str(validation.get("status", "")) != "PASS":
		for failure_value in validation.get("failures", []):
			failures.append("temporal wave: " + str(failure_value))
	for milestone_id in ["TQP-15", "TQP-16", "TQP-17"]:
		var milestone: Dictionary = milestone_by_id.get(milestone_id, {})
		_expect(
			str(milestone.get("status", "")) == "qualified",
			milestone_id + " must match retained native temporal wave evidence",
			failures
		)


static func _validate_wave_02_first_batch_evidence(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard_schemas := {
		"material_blending_standard": "world_transvoxel.terrain_lab.material_blending_standard.v1",
		"streaming_window_standard": "world_transvoxel.terrain_lab.streaming_window_standard.v1",
		"large_world_coordinate_standard": "world_transvoxel.terrain_lab.large_world_coordinate_standard.v1",
	}
	var standards := {}
	for key in standard_schemas:
		var standard := JsonLoader.load_dictionary(str(program.get(key, "")))
		standards[key] = standard
		_expect(
			str(standard.get("schema", "")) == str(standard_schemas[key]),
			"Wave 02 standard schema mismatch: " + str(key),
			failures
		)
	var material: Dictionary = standards.get("material_blending_standard", {})
	var visual: Dictionary = material.get("visual_evidence", {})
	var visual_path := str(visual.get("image", ""))
	_expect(FileAccess.file_exists(visual_path), "TQP-18 visual evidence is missing", failures)
	if FileAccess.file_exists(visual_path):
		_expect(
			FileAccess.get_sha256(visual_path) == str(visual.get("sha256", "")),
			"TQP-18 visual evidence hash changed",
			failures
		)
	_expect(str(visual.get("automated_status", "")) == "PASS", "TQP-18 visual automation failed", failures)
	var human_review := str(visual.get("human_review", ""))
	_expect(human_review in ["PENDING", "ACCEPTED", "REJECTED"], "TQP-18 visual review state is invalid", failures)
	var material_status := str((milestone_by_id.get("TQP-18", {}) as Dictionary).get("status", ""))
	_expect(
		(material_status == "qualified") == (human_review == "ACCEPTED"),
		"TQP-18 status does not match its visual review decision",
		failures
	)
	for milestone_id in ["TQP-19", "TQP-20"]:
		_expect(
			str((milestone_by_id.get(milestone_id, {}) as Dictionary).get("status", "")) == "qualified",
			milestone_id + " must match retained Wave 02 evidence",
			failures
		)
	var report := JsonLoader.load_dictionary(str(program.get("wave_02_first_batch_evidence", "")))
	_expect(
		str(report.get("schema", ""))
			== "world_transvoxel.terrain_lab.wave_02_first_batch_qualification.v1",
		"Wave 02 first-batch report schema mismatch",
		failures
	)
	_expect(str(report.get("status", "")) == "PASS", "Wave 02 first-batch report failed", failures)
	var result_by_id := {}
	for result_value in report.get("milestones", []):
		var result: Dictionary = result_value
		result_by_id[str(result.get("milestone", ""))] = result
	for milestone_id in ["TQP-18", "TQP-19", "TQP-20"]:
		var result: Dictionary = result_by_id.get(milestone_id, {})
		_expect(str(result.get("status", "")) == "PASS", milestone_id + " retained batch evidence failed", failures)
		_expect(
			str((result.get("performance", {}) as Dictionary).get("budget_evaluation", ""))
				== "ENFORCED_FOCUSED_RUN",
			milestone_id + " retained performance budget was not enforced",
			failures
		)
	var material_qualification := str(
		(result_by_id.get("TQP-18", {}) as Dictionary).get("qualification_status", "")
	)
	_expect(
		(material_qualification.begins_with("QUALIFIED")) == (human_review == "ACCEPTED"),
		"TQP-18 retained qualification state does not match visual review",
		failures
	)
	_expect(
		str((result_by_id.get("TQP-19", {}) as Dictionary).get("qualification_status", "")).begins_with("QUALIFIED"),
		"TQP-19 retained evidence is not qualified",
		failures
	)
	_expect(
		str((result_by_id.get("TQP-20", {}) as Dictionary).get("qualification_status", "")).begins_with("QUALIFIED"),
		"TQP-20 retained evidence is not qualified",
		failures
	)


static func _validate_wave_02_second_batch_evidence(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard_schemas := {
		"texture_system_standard": "world_transvoxel.terrain_lab.texture_system_standard.v1",
		"visibility_residency_standard": "world_transvoxel.terrain_lab.visibility_residency_standard.v1",
	}
	for key in standard_schemas:
		var standard := JsonLoader.load_dictionary(str(program.get(key, "")))
		_expect(
			str(standard.get("schema", "")) == str(standard_schemas[key]),
			"Wave 02 second-batch standard schema mismatch: " + str(key),
			failures
		)
	var visual := JsonLoader.load_dictionary(str(program.get("visual_evidence", "")))
	var human_review := str((visual.get("human_review", {}) as Dictionary).get("status", ""))
	var texture_status := str((milestone_by_id.get("TQP-21", {}) as Dictionary).get("status", ""))
	_expect(
		(texture_status == "qualified") == (human_review == "ACCEPTED"),
		"TQP-21 status does not match corrected observatory visual review",
		failures
	)
	_expect(
		str((milestone_by_id.get("TQP-22", {}) as Dictionary).get("status", "")) == "qualified",
		"TQP-22 must match retained horizontal CPU visibility evidence",
		failures
	)
	var report := JsonLoader.load_dictionary(str(program.get("wave_02_second_batch_evidence", "")))
	_expect(
		str(report.get("schema", ""))
			== "world_transvoxel.terrain_lab.wave_02_second_batch_qualification.v1",
		"Wave 02 second-batch report schema mismatch",
		failures
	)
	_expect(str(report.get("status", "")) == "PASS", "Wave 02 second-batch report failed", failures)
	var result_by_id := {}
	for result_value in report.get("milestones", []):
		var result: Dictionary = result_value
		result_by_id[str(result.get("milestone", ""))] = result
	for milestone_id in ["TQP-21", "TQP-22"]:
		var result: Dictionary = result_by_id.get(milestone_id, {})
		_expect(str(result.get("status", "")) == "PASS", milestone_id + " retained batch evidence failed", failures)
		_expect(
			str((result.get("performance", {}) as Dictionary).get("budget_evaluation", ""))
				== "ENFORCED_FOCUSED_RUN",
			milestone_id + " retained performance budget was not enforced",
			failures
		)
	var texture_qualification := str(
		(result_by_id.get("TQP-21", {}) as Dictionary).get("qualification_status", "")
	)
	_expect(
		(texture_qualification.begins_with("QUALIFIED")) == (human_review == "ACCEPTED"),
		"TQP-21 retained qualification state does not match visual review",
		failures
	)
	_expect(
		str((result_by_id.get("TQP-22", {}) as Dictionary).get("qualification_status", "")).begins_with("QUALIFIED"),
		"TQP-22 retained evidence is not qualified",
		failures
	)


static func _validate_visual_evidence(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var evidence := JsonLoader.load_dictionary(str(program.get("visual_evidence", "")))
	_expect(
		str(evidence.get("schema", "")) == "world_transvoxel.terrain_lab.visual_evidence.v1",
		"visual evidence schema mismatch",
		failures
	)
	var image_path := str(evidence.get("image", ""))
	_expect(FileAccess.file_exists(image_path), "visual evidence image is missing", failures)
	if FileAccess.file_exists(image_path):
		_expect(
			FileAccess.get_sha256(image_path) == str(evidence.get("sha256", "")),
			"visual evidence image hash changed",
			failures
		)
	var automated: Dictionary = evidence.get("automated_checks", {})
	_expect(str(automated.get("status", "")) == "PASS", "visual automated checks failed", failures)
	_expect(int(automated.get("requested_chunk_count", 0)) == 18, "visual requested chunk corpus changed", failures)
	_expect(int(automated.get("native_chunk_count", 0)) == 16, "visual rendered chunk corpus changed", failures)
	_expect(int(automated.get("local_bounds_errors", -1)) == 0, "visual bounds errors exist", failures)
	_expect(int(automated.get("adjacent_seam_pair_count", 0)) == 33, "visual seam corpus changed", failures)
	_expect(int(automated.get("surface_seam_pair_count", 0)) == 27, "visual surface seam corpus changed", failures)
	_expect(int(automated.get("surface_seam_errors", -1)) == 0, "visual surface seam errors exist", failures)
	_expect(str(automated.get("tangent_edit_regression", "")) == "PASS", "tangent edit regression failed", failures)
	_expect(str(automated.get("cold_warm_capture_identity", "")) == "PASS", "visual capture is not repeatable", failures)
	var tangent: Dictionary = evidence.get("tangent_seam_regression", {})
	var tangent_image_path := str(tangent.get("image", ""))
	_expect(FileAccess.file_exists(tangent_image_path), "tangent seam evidence image is missing", failures)
	if FileAccess.file_exists(tangent_image_path):
		_expect(
			FileAccess.get_sha256(tangent_image_path) == str(tangent.get("sha256", "")),
			"tangent seam evidence image hash changed",
			failures
		)
	_expect(
		str(tangent.get("cold_warm_capture_identity", "")) == "PASS",
		"tangent seam capture is not repeatable",
		failures
	)
	_expect(
		str(tangent.get("native_upstream_commit", ""))
			== "39572401cc0b0898f70ea6c9dcbe3ca5d6f1138b",
		"tangent seam evidence does not name the corrected native revision",
		failures
	)
	var review: Dictionary = evidence.get("human_review", {})
	_expect(
		str(review.get("status", "")) == "PENDING",
		"visual human review changed without a decision record",
		failures
	)
	for milestone_id in ["TQP-21", "TQP-23"]:
		var milestone: Dictionary = milestone_by_id.get(milestone_id, {})
		_expect(
			str(milestone.get("status", "")) == "implemented",
			milestone_id + " must remain implemented until visual acceptance",
			failures
		)
	var visual_corpus: Dictionary = milestone_by_id.get("TQP-25", {})
	_expect(
		str(visual_corpus.get("status", "")) == "specified",
		"TQP-25 must remain specified until human acceptance",
		failures
	)


static func _validate_dependency_boundary(
	program: Dictionary,
	dependencies: Dictionary,
	failures: Array[String]
) -> void:
	var runtime_dependencies: Array = program.get("runtime_dependencies", [])
	_expect(
		runtime_dependencies == ["world_transvoxel"],
		"runtime dependency boundary must contain only world_transvoxel",
		failures
	)
	_expect(
		"world_transvoxel_cell_lab" in program.get("forbidden_dependencies", []),
		"Cell Lab dependency prohibition is missing",
		failures
	)
	_expect(
		str(dependencies.get("status", "")) == "PASS",
		"pinned world-transvoxel native dependency is unavailable",
		failures
	)


static func _validate_source_boundary(failures: Array[String]) -> void:
	var cell_lab_addon := "world_transvoxel_" + "cell_lab"
	var cell_lab_class := "WtTransvoxel" + "CellLab"
	var forbidden_fragments := [
		"preload(\"res://addons/" + cell_lab_addon + "/",
		"load(\"res://addons/" + cell_lab_addon + "/",
		"extends " + cell_lab_class,
	]
	for path in _gdscript_paths(TERRAIN_LAB_ROOT):
		var source := FileAccess.get_file_as_string(path)
		for fragment in forbidden_fragments:
			if fragment in source:
				failures.append("forbidden Cell Lab code dependency in " + path)


static func _gdscript_paths(root_path: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(root_path)
	if directory == null:
		return result
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry == "." or entry == "..":
			entry = directory.get_next()
			continue
		var path := root_path.path_join(entry)
		if directory.current_is_dir():
			result.append_array(_gdscript_paths(path))
		elif entry.ends_with(".gd"):
			result.append(path)
		entry = directory.get_next()
	directory.list_dir_end()
	return result


static func _is_regenerating_retained_report(retained_path: String) -> bool:
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size() - 1):
		if arguments[index] == "--output" and arguments[index + 1] == retained_path:
			return true
	return false


static func _gate_status(members: Array, milestone_by_id: Dictionary) -> String:
	var all_qualified := true
	var all_specified := true
	for member_value in members:
		var milestone: Dictionary = milestone_by_id.get(str(member_value), {})
		var status := str(milestone.get("status", ""))
		if status not in ["qualified", "production"]:
			all_qualified = false
		if status not in ["specified", "implemented", "qualified", "production"]:
			all_specified = false
	if all_qualified:
		return "QUALIFIED"
	if all_specified:
		return "SPECIFIED"
	return "CLOSED"


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
