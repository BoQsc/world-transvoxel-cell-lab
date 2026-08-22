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
const Phase03SystemEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_phase_03_system_evidence.gd"
)
const ObservatoryDiagnostics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_observatory.gd"
)
const VisualQualityQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_visual_quality_qualification.gd"
)
const LargeTerrainSoakEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_large_terrain_soak_evidence.gd"
)
const NativeFieldEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_field_evidence.gd"
)
const AdaptiveLodEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_adaptive_lod_evidence.gd"
)
const TransitionAssemblyEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_transition_assembly_evidence.gd"
)
const BoundaryEnclosureEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_boundary_enclosure_evidence.gd"
)
const IndependentOracleEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_independent_oracle_evidence.gd"
)
const AdversarialCorpusEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_adversarial_corpus_evidence.gd"
)
const DynamicLodPublicationEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_dynamic_lod_publication_evidence.gd"
)
const EditInvalidationEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_edit_invalidation_evidence.gd"
)
const AdaptiveEditEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_adaptive_edit_evidence.gd"
)
const AdaptiveSurfaceEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_adaptive_surface_evidence.gd"
)
const AdaptiveSystemEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_adaptive_system_evidence.gd"
)
const AdaptiveStreamingEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_adaptive_streaming_evidence.gd"
)
const AdaptivePersistenceEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_adaptive_persistence_evidence.gd"
)
const ComplexVisualEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_complex_visual_evidence.gd"
)
const FastArrivalEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_fast_arrival_evidence.gd"
)
const TargetedCollisionEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_targeted_collision_evidence.gd"
)
const LargeWorldPerformanceEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_large_world_performance_evidence.gd"
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
	_expect(
		str(program.get("program_goal", ""))
			== "authoritative_correct_efficient_large_volumetric_smooth_terrain",
		"program goal changed",
		failures
	)
	_expect(
		program.get("release_sequence", []) == [
			"native_cpu_authority",
			"standalone_cpu_production_release",
			"gpu_backend_release",
			"post_release_game_systems",
		],
		"program release sequence changed",
		failures
	)
	_expect(
		str(program.get("optimization_policy", ""))
			== "standard_widely_accepted_measured_no_correctness_tradeoff",
		"program optimization policy changed",
		failures
	)
	var engine_policy: Dictionary = program.get("engine_policy", {})
	_expect(str(engine_policy.get("minimum_version", "")) == "4.7", "minimum Godot version changed", failures)
	_expect(
		engine_policy.get("current_qualification_matrix", []) == ["4.7"],
		"Godot qualification matrix must contain only 4.7",
		failures
	)
	_expect(
		str(engine_policy.get("newer_versions", ""))
			== "require_explicit_qualification_before_promotion",
		"newer Godot admission policy changed",
		failures
	)
	var operating_envelope := JsonLoader.load_dictionary(str(program.get("operating_envelope", "")))
	var operating_targets: Dictionary = operating_envelope.get("targets", {})
	_expect(
		str(operating_targets.get("godot_minimum_version", ""))
			== str(engine_policy.get("minimum_version", "")),
		"operating-envelope minimum Godot version differs from the program",
		failures
	)
	_expect(
		operating_targets.get("godot_qualification_matrix", [])
			== engine_policy.get("current_qualification_matrix", []),
		"operating-envelope Godot matrix differs from the program",
		failures
	)
	_expect(milestones.size() == 71, "program must contain exactly 71 milestones", failures)

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
	_validate_surface_shading_evidence(program, milestone_by_id, failures)
	_validate_visual_quality_corpus(program, milestone_by_id, failures)
	_validate_phase_03_system_evidence(program, milestone_by_id, failures)
	_validate_terrain_observatory_evidence(program, milestone_by_id, failures)
	_validate_large_terrain_soak_evidence(program, milestone_by_id, failures)
	_validate_native_field_evidence(program, milestone_by_id, failures)
	_validate_adaptive_lod_evidence(program, milestone_by_id, failures)
	_validate_transition_assembly_evidence(program, milestone_by_id, failures)
	_validate_boundary_enclosure_evidence(program, milestone_by_id, failures)
	_validate_independent_oracle_evidence(program, milestone_by_id, failures)
	_validate_adversarial_corpus_evidence(program, milestone_by_id, failures)
	_validate_dynamic_lod_publication_evidence(program, milestone_by_id, failures)
	_validate_edit_invalidation_evidence(program, milestone_by_id, failures)
	_validate_adaptive_edit_evidence(program, milestone_by_id, failures)
	_validate_adaptive_surface_evidence(program, milestone_by_id, failures)
	_validate_adaptive_system_evidence(program, milestone_by_id, failures)
	_validate_adaptive_streaming_evidence(program, milestone_by_id, failures)
	_validate_adaptive_persistence_evidence(program, milestone_by_id, failures)
	_validate_sparse_hierarchy_evidence(program, milestone_by_id, failures)
	_validate_fault_order_evidence(program, milestone_by_id, failures)
	_validate_cpu_closure_implementation(program, milestone_by_id, failures)
	_validate_production_addon_boundary(program, milestone_by_id, failures)
	_validate_cpu_production_first_batch(program, milestone_by_id, failures)
	_validate_cpu_production_release(program, milestone_by_id, failures)
	_validate_cpu_finalization(program, milestone_by_id, failures)
	_validate_cpu_production_closure(program, milestone_by_id, failures)
	_validate_cpu_human_baseline_trace(program, milestone_by_id, failures)
	_validate_low_power_performance_profile(program, failures)
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
	var expected := {
		"GATE_A": ["TQP-01", "TQP-02", "TQP-03", "TQP-04", "TQP-05"],
		"GATE_B": ["TQP-07", "TQP-09", "TQP-10", "TQP-11", "TQP-12", "TQP-13"],
		"GATE_C": ["TQP-08", "TQP-18", "TQP-21", "TQP-23"],
		"GATE_D": ["TQP-06", "TQP-15", "TQP-16", "TQP-19", "TQP-20", "TQP-22", "TQP-24", "TQP-26", "TQP-27"],
		"GATE_E": ["TQP-28", "TQP-29", "TQP-30", "TQP-31", "TQP-32", "TQP-33", "TQP-34", "TQP-35", "TQP-36", "TQP-37", "TQP-38", "TQP-39", "TQP-40", "TQP-41", "TQP-42", "TQP-43", "TQP-44", "TQP-45", "TQP-46", "TQP-47", "TQP-48", "TQP-49", "TQP-50"],
		"GATE_F": ["TQP-51", "TQP-52", "TQP-53", "TQP-54", "TQP-55", "TQP-56", "TQP-57"],
		"GATE_G": ["TQP-58", "TQP-59", "TQP-60", "TQP-61", "TQP-62", "TQP-63", "TQP-64"],
		"GATE_H": ["TQP-65", "TQP-66", "TQP-67", "TQP-68", "TQP-69", "TQP-70", "TQP-71"],
	}
	for required in expected:
		_expect(gates.has(required), "missing program gate: " + required, failures)
		_expect(gates.get(required, []) == expected[required], required + " membership changed", failures)
	_expect(gates.size() == expected.size(), "program has an undeclared gate", failures)
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
		"TQP-D011", "TQP-D012", "TQP-D013", "TQP-D014", "TQP-D015",
		"TQP-D016", "TQP-D017", "TQP-D018", "TQP-D019", "TQP-D020",
		"TQP-D021", "TQP-D022", "TQP-D023", "TQP-D024", "TQP-D025",
		"TQP-D026", "TQP-D027", "TQP-D028", "TQP-D029", "TQP-D030",
		"TQP-D031", "TQP-D032", "TQP-D033", "TQP-D034", "TQP-D035",
		"TQP-D036", "TQP-D037", "TQP-D038", "TQP-D039", "TQP-D040",
		"TQP-D041", "TQP-D042", "TQP-D043", "TQP-D044", "TQP-D045",
		"TQP-D046", "TQP-D047", "TQP-D048", "TQP-D049", "TQP-D050",
		"TQP-D051", "TQP-D052",
	]:
		_expect(decision_ids.has(required), "missing retained decision: " + required, failures)
	for key in [
		"operating_envelope",
		"qualification_state",
		"backend_decision",
		"blocker_catalog",
		"visual_evidence",
		"visual_quality_corpus_standard",
		"visual_quality_corpus_evidence",
		"low_power_performance_profile",
		"edit_gate_b_evidence",
		"temporal_wave_standard",
		"material_blending_standard",
		"streaming_window_standard",
		"large_world_coordinate_standard",
		"texture_system_standard",
		"surface_shading_standard",
		"surface_shading_review_protocol",
		"surface_shading_review_evidence",
		"surface_shadow_resolution_finding",
		"surface_shadow_resolution_evidence",
		"surface_shading_evidence",
		"surface_shading_contract_evidence",
		"visibility_residency_standard",
		"phase_03_system_standard",
		"phase_03_system_evidence",
		"terrain_observatory_standard",
		"terrain_observatory_evidence",
		"large_terrain_soak_standard",
		"large_terrain_soak_evidence",
		"large_volume_snapshot_finding",
		"native_field_standard",
		"native_field_evidence",
		"adaptive_lod_standard",
		"adaptive_lod_evidence",
		"transition_assembly_standard",
		"transition_assembly_evidence",
		"boundary_enclosure_standard",
		"boundary_enclosure_evidence",
		"independent_oracle_standard",
		"independent_oracle_evidence",
		"adversarial_corpus_standard",
		"adversarial_corpus_evidence",
		"dynamic_lod_publication_standard",
		"dynamic_lod_publication_evidence",
		"dynamic_lod_publication_motion_evidence",
		"edit_invalidation_standard",
		"edit_invalidation_evidence",
		"edit_invalidation_motion_evidence",
		"adaptive_edit_standard",
		"adaptive_edit_evidence",
		"adaptive_edit_motion_evidence",
		"complex_visual_temporal_corpus_standard",
		"complex_visual_temporal_corpus_automation",
		"complex_visual_temporal_corpus_human_review",
		"fast_arrival_responsiveness_standard",
		"fast_arrival_responsiveness_evidence",
		"targeted_collision_residency_standard",
		"targeted_collision_residency_evidence",
		"large_world_performance_standard",
		"large_world_performance_evidence",
		"low_power_qualification_standard",
		"low_power_qualification_evidence",
		"complex_adaptive_soak_recovery_standard",
		"complex_adaptive_soak_recovery_evidence",
		"native_adaptive_authority_gate_standard",
		"native_adaptive_authority_gate_evidence",
		"production_addon_boundary_standard",
		"production_addon_boundary_evidence",
		"production_runtime_contract_standard",
		"production_authoring_workflow_standard",
		"downstream_migration_standard",
		"cpu_production_first_batch_evidence",
		"cpu_production_release_matrix_standard",
		"cpu_production_long_haul_standard",
		"cpu_production_release_standard",
		"cpu_production_release_evidence",
		"cpu_finalization_standard",
		"cpu_finalization_evidence",
		"cpu_production_closure_standard",
		"cpu_production_closure_evidence",
		"cpu_human_baseline_trace_standard",
		"cpu_human_baseline_trace_evidence",
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
	_expect(positions.size() == 71, "execution plan must cover all 71 milestones", failures)
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
	var cpu_human_trace := JsonLoader.load_dictionary(
		str(program.get("cpu_human_baseline_trace_evidence", ""))
	)
	var cpu_human_eligible := (
		str(cpu_human_trace.get("status", "")) == "PASS"
		and bool(cpu_human_trace.get("retained_complete", false))
		and bool(cpu_human_trace.get("tqp58_eligible", false))
	)
	if not cpu_human_eligible:
		expected_next = []
	_expect(
		plan.get("recommended_next", []) == expected_next,
		"execution plan recommended_next differs from the first incomplete active step",
		failures
	)
	var required_preconditions := [
		"CPU_FINALIZATION_PRECONDITION",
		"CPU_PRODUCTION_CLOSURE_PRECONDITION",
		"CPU_HUMAN_BASELINE_TRACE_PRECONDITION",
	]
	_expect(
		plan.get("completed_preconditions", []) == required_preconditions,
		"execution plan completed CPU preconditions are missing or out of order",
		failures
	)
	_expect(
		plan.get("completed_precondition_steps", []) == ["CPU-B1", "CPU-B2", "CPU-B3"],
		"execution plan completed CPU human steps are missing or out of order",
		failures
	)
	_expect(
		(plan.get("recommended_precondition_steps", []) as Array).is_empty(),
		"execution plan CPU human next steps are missing or out of order",
		failures
	)
	_expect(
		active_wave.get("entry_conditions", []) == required_preconditions,
		"active GPU wave CPU entry conditions are missing or out of order",
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
	_expect(seen.size() == 71, "qualification state must classify all 71 milestones", failures)
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
	_expect(suite_milestones.size() == 71, "qualification suites must cover all milestones", failures)
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
	var preconditions: Dictionary = state.get("preconditions", {})
	var cpu_finalization: Dictionary = preconditions.get(
		"CPU_FINALIZATION_PRECONDITION", {}
	)
	_expect(
		str(cpu_finalization.get("status", "")) == "qualified"
			and (cpu_finalization.get("blocks", []) as Array).is_empty()
			and cpu_finalization.get("admits", []) == ["TQP-58"],
		"CPU finalization precondition state is inconsistent",
		failures
	)
	var cpu_production_closure: Dictionary = preconditions.get(
		"CPU_PRODUCTION_CLOSURE_PRECONDITION", {}
	)
	_expect(
		str(cpu_production_closure.get("status", "")) == "qualified"
			and (cpu_production_closure.get("blocks", []) as Array).is_empty()
			and cpu_production_closure.get("admits", []) == ["TQP-58"],
		"CPU production closure precondition state is inconsistent",
		failures
	)
	var cpu_human_trace: Dictionary = preconditions.get(
		"CPU_HUMAN_BASELINE_TRACE_PRECONDITION", {}
	)
	_expect(
		str(cpu_human_trace.get("status", "")) == "qualified"
			and (cpu_human_trace.get("blocks", []) as Array).is_empty()
			and cpu_human_trace.get("admits", []) == ["TQP-58"],
		"CPU human baseline/trace precondition state is inconsistent",
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
				int(retained.get("milestone_count", 0)) == 71,
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
	_expect(str(automated.get("assembled_window_topology", "")) == "PASS", "assembled visual topology failed", failures)
	_expect(int(automated.get("window_unique_edge_count", 0)) == 15504, "assembled visual edge corpus changed", failures)
	_expect(int(automated.get("exterior_open_edge_count", 0)) == 216, "assembled visual exterior contour changed", failures)
	_expect(int(automated.get("interior_open_edge_count", -1)) == 0, "assembled visual terrain has interior openings", failures)
	_expect(int(automated.get("nonmanifold_edge_count", -1)) == 0, "assembled visual terrain has nonmanifold edges", failures)
	_expect(str(automated.get("topology_negative_control", "")) == "PASS", "assembled topology negative control failed", failures)
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
			== "7e4f6946eaeb36728ac466f06b8da75e67e30fa8",
		"tangent seam evidence does not name the corrected native revision",
		failures
	)
	var pole: Dictionary = evidence.get("tangent_pole_regression", {})
	var pole_image_path := str(pole.get("image", ""))
	_expect(FileAccess.file_exists(pole_image_path), "tangent pole evidence image is missing", failures)
	if FileAccess.file_exists(pole_image_path):
		_expect(
			FileAccess.get_sha256(pole_image_path) == str(pole.get("sha256", "")),
			"tangent pole evidence image hash changed",
			failures
		)
	_expect(str(pole.get("cold_warm_capture_identity", "")) == "PASS", "tangent pole capture is not repeatable", failures)
	_expect(str(pole.get("native_upstream_commit", "")) == "7e4f6946eaeb36728ac466f06b8da75e67e30fa8", "tangent pole evidence does not name the corrected native revision", failures)
	var review: Dictionary = evidence.get("human_review", {})
	_expect(str(review.get("status", "")) == "ACCEPTED", "TQP-21 visual is not accepted", failures)
	_expect(str(review.get("decision", "")).ends_with("TQP-D013.json"), "TQP-21 visual acceptance decision is missing", failures)
	_expect("TQP-21" in review.get("accepted_for", []), "TQP-21 is absent from accepted visual scope", failures)
	_expect("TQP-23" not in review.get("pending_for", []), "TQP-23 remains incorrectly pending in observatory evidence", failures)
	_expect("TQP-25" not in review.get("pending_for", []), "TQP-25 remains incorrectly pending in observatory evidence", failures)
	_expect(
		str((milestone_by_id.get("TQP-21", {}) as Dictionary).get("status", "")) == "qualified",
		"TQP-21 must match its accepted visual evidence",
		failures
	)
	_expect(
		str((milestone_by_id.get("TQP-23", {}) as Dictionary).get("status", "")) == "qualified",
		"TQP-23 must match its accepted bounded surface-shading evidence",
		failures
	)
	var visual_corpus: Dictionary = milestone_by_id.get("TQP-25", {})
	_expect(
		str(visual_corpus.get("status", "")) == "qualified",
		"TQP-25 must match its accepted bounded visual evidence",
		failures
	)


static func _validate_visual_quality_corpus(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard := JsonLoader.load_dictionary(
		str(program.get("visual_quality_corpus_standard", ""))
	)
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.visual_quality_corpus_standard.v1",
		"visual quality corpus standard schema mismatch",
		failures
	)
	_expect(
		str(standard.get("automated_evidence", ""))
			== str(program.get("visual_quality_corpus_evidence", "")),
		"visual quality corpus evidence path changed",
		failures
	)
	var result := VisualQualityQualification.run()
	_expect(str(result.get("status", "")) == "PASS", "TQP-25 visual corpus implementation failed", failures)
	var human_review := str(result.get("formal_human_review", ""))
	var milestone_status := str(
		(milestone_by_id.get("TQP-25", {}) as Dictionary).get("status", "")
	)
	_expect(
		milestone_status == ("qualified" if human_review == "ACCEPTED" else "implemented"),
		"TQP-25 status does not match formal visual review",
		failures
	)
	var expected_finding_status := (
		"CLOSED_BOUNDED_TQP25_ACCEPTANCE"
		if human_review == "ACCEPTED"
		else "OPEN_PENDING_HUMAN_VISUAL_REVIEW"
	)
	_expect(
		str((result.get("finding", {}) as Dictionary).get("status", ""))
			== expected_finding_status,
		"TQP-F001 status does not match formal TQP-25 review",
		failures
	)


static func _validate_phase_03_system_evidence(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard := JsonLoader.load_dictionary(str(program.get("phase_03_system_standard", "")))
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.phase_03_system_standard.v1",
		"Phase 3 system standard schema mismatch",
		failures
	)
	var validation := Phase03SystemEvidence.validate_retained()
	if str(validation.get("status", "")) != "PASS":
		for failure_value in validation.get("failures", []):
			failures.append("Phase 3 system: " + str(failure_value))
	_expect(
		str((milestone_by_id.get("TQP-24", {}) as Dictionary).get("status", "")) == "qualified",
		"TQP-24 must match retained native Godot system evidence",
		failures
	)


static func _validate_large_terrain_soak_evidence(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard := JsonLoader.load_dictionary(str(program.get("large_terrain_soak_standard", "")))
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.large_terrain_soak_standard.v1",
		"TQP-27 large-terrain soak standard schema mismatch",
		failures
	)
	var validation := LargeTerrainSoakEvidence.validate_retained()
	if str(validation.get("status", "")) != "PASS":
		for failure_value in validation.get("failures", []):
			failures.append("TQP-27 large-terrain soak: " + str(failure_value))
	_expect(
		str((milestone_by_id.get("TQP-27", {}) as Dictionary).get("status", ""))
			== "qualified",
		"TQP-27 must match retained native large-terrain soak evidence",
		failures
	)
	var finding := JsonLoader.load_dictionary(
		str(program.get("large_volume_snapshot_finding", ""))
	)
	_expect(str(finding.get("id", "")) == "TQP-F002", "large-volume snapshot finding ID changed", failures)
	_expect(
		str(finding.get("status", ""))
			== "CLOSED_BY_TQP42_SPARSE_PROCEDURAL_SNAPSHOT",
		"large-volume snapshot finding does not match TQP-42 disposition",
		failures
	)
	_expect(
		str((validation.get("persistence", {}) as Dictionary).get("large_volume_compaction_status", ""))
			== "EXPECTED_CAPACITY_REJECTION",
		"TQP-F002 negative control did not fail closed",
		failures
	)


static func _validate_native_field_evidence(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard := JsonLoader.load_dictionary(str(program.get("native_field_standard", "")))
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.native_field_standard.v1",
		"TQP-28/29 native field standard schema mismatch",
		failures
	)
	var validation := NativeFieldEvidence.validate_retained()
	if str(validation.get("status", "")) != "PASS":
		for failure_value in validation.get("failures", []):
			failures.append("TQP-28/29 native field: " + str(failure_value))
	for milestone_id in ["TQP-28", "TQP-29"]:
		_expect(
			str((milestone_by_id.get(milestone_id, {}) as Dictionary).get("status", ""))
				== "qualified",
			milestone_id + " must match retained native field evidence",
			failures
		)


static func _validate_adaptive_lod_evidence(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard := JsonLoader.load_dictionary(str(program.get("adaptive_lod_standard", "")))
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.adaptive_lod_standard.v1",
		"TQP-30 adaptive LOD standard schema mismatch",
		failures
	)
	var validation := AdaptiveLodEvidence.validate_retained()
	if str(validation.get("status", "")) != "PASS":
		for failure_value in validation.get("failures", []):
			failures.append("TQP-30 adaptive LOD: " + str(failure_value))
	_expect(
		str((milestone_by_id.get("TQP-30", {}) as Dictionary).get("status", ""))
			== "qualified",
		"TQP-30 must match retained adaptive LOD evidence",
		failures
	)


static func _validate_transition_assembly_evidence(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard := JsonLoader.load_dictionary(
		str(program.get("transition_assembly_standard", ""))
	)
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.transition_assembly_standard.v1",
		"TQP-31 transition assembly standard schema mismatch",
		failures
	)
	var validation := TransitionAssemblyEvidence.validate_retained()
	if str(validation.get("status", "")) != "PASS":
		for failure_value in validation.get("failures", []):
			failures.append("TQP-31 transition assembly: " + str(failure_value))
	_expect(
		str((milestone_by_id.get("TQP-31", {}) as Dictionary).get("status", ""))
			== "qualified",
		"TQP-31 must match retained transition assembly evidence",
		failures
	)


static func _validate_boundary_enclosure_evidence(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard := JsonLoader.load_dictionary(
		str(program.get("boundary_enclosure_standard", ""))
	)
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.boundary_enclosure_standard.v1",
		"TQP-32 boundary/enclosure standard schema mismatch",
		failures
	)
	var validation := BoundaryEnclosureEvidence.validate_retained()
	if str(validation.get("status", "")) != "PASS":
		for failure_value in validation.get("failures", []):
			failures.append("TQP-32 boundary/enclosure: " + str(failure_value))
	_expect(
		str((milestone_by_id.get("TQP-32", {}) as Dictionary).get("status", ""))
			== "qualified",
		"TQP-32 must match retained boundary/enclosure evidence",
		failures
	)


static func _validate_independent_oracle_evidence(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard := JsonLoader.load_dictionary(
		str(program.get("independent_oracle_standard", ""))
	)
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.independent_oracle_standard.v1",
		"TQP-33 independent-oracle standard schema mismatch",
		failures
	)
	var validation := IndependentOracleEvidence.validate_retained()
	if str(validation.get("status", "")) != "PASS":
		for failure_value in validation.get("failures", []):
			failures.append("TQP-33 independent oracle: " + str(failure_value))
	_expect(
		str((milestone_by_id.get("TQP-33", {}) as Dictionary).get("status", ""))
			== "qualified",
		"TQP-33 must match retained independent-oracle evidence",
		failures
	)


static func _validate_adversarial_corpus_evidence(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard := JsonLoader.load_dictionary(
		str(program.get("adversarial_corpus_standard", ""))
	)
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.adversarial_corpus_standard.v1",
		"TQP-34 adversarial corpus standard schema mismatch",
		failures
	)
	var validation := AdversarialCorpusEvidence.validate_retained()
	if str(validation.get("status", "")) != "PASS":
		for failure_value in validation.get("failures", []):
			failures.append("TQP-34 adversarial corpus: " + str(failure_value))
	_expect(
		str((milestone_by_id.get("TQP-34", {}) as Dictionary).get("status", ""))
			== "qualified",
		"TQP-34 must match retained adversarial corpus evidence",
		failures
	)


static func _validate_dynamic_lod_publication_evidence(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard := JsonLoader.load_dictionary(
		str(program.get("dynamic_lod_publication_standard", ""))
	)
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.dynamic_lod_publication_standard.v1",
		"TQP-35 dynamic LOD publication standard schema mismatch",
		failures
	)
	var validation := DynamicLodPublicationEvidence.validate_retained()
	if str(validation.get("status", "")) != "PASS":
		for failure_value in validation.get("failures", []):
			failures.append("TQP-35 dynamic publication: " + str(failure_value))
	_expect(
		str((milestone_by_id.get("TQP-35", {}) as Dictionary).get("status", ""))
			== "qualified",
		"TQP-35 must match retained dynamic LOD publication evidence",
		failures
	)


static func _validate_edit_invalidation_evidence(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard := JsonLoader.load_dictionary(
		str(program.get("edit_invalidation_standard", ""))
	)
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.edit_invalidation_standard.v1",
		"TQP-36 edit invalidation standard schema mismatch",
		failures
	)
	var validation := EditInvalidationEvidence.validate_retained()
	if str(validation.get("status", "")) != "PASS":
		for failure_value in validation.get("failures", []):
			failures.append("TQP-36 edit invalidation: " + str(failure_value))
	_expect(
		str((milestone_by_id.get("TQP-36", {}) as Dictionary).get("status", ""))
			== "qualified",
		"TQP-36 must match retained edit invalidation evidence",
		failures
	)


static func _validate_adaptive_edit_evidence(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard := JsonLoader.load_dictionary(
		str(program.get("adaptive_edit_standard", ""))
	)
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.adaptive_edit_standard.v1",
		"TQP-37 adaptive edit standard schema mismatch",
		failures
	)
	var validation := AdaptiveEditEvidence.validate_retained()
	if str(validation.get("status", "")) != "PASS":
		for failure_value in validation.get("failures", []):
			failures.append("TQP-37 adaptive edit: " + str(failure_value))
	_expect(
		str((milestone_by_id.get("TQP-37", {}) as Dictionary).get("status", ""))
			== "qualified",
		"TQP-37 must match retained adaptive edit evidence",
		failures
	)


static func _validate_adaptive_surface_evidence(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard := JsonLoader.load_dictionary(
		str(program.get("adaptive_surface_continuity_standard", ""))
	)
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.adaptive_surface_continuity_standard.v1",
		"TQP-38 adaptive surface standard schema mismatch", failures
	)
	var validation := AdaptiveSurfaceEvidence.validate_retained()
	if str(validation.get("status", "")) != "PASS":
		for failure_value in validation.get("failures", []):
			failures.append("TQP-38 adaptive surface: " + str(failure_value))
	_expect(
		str((milestone_by_id.get("TQP-38", {}) as Dictionary).get("status", ""))
			== "qualified",
		"TQP-38 must match retained adaptive surface evidence", failures
	)


static func _validate_adaptive_system_evidence(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard := JsonLoader.load_dictionary(
		str(program.get("adaptive_system_agreement_standard", ""))
	)
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.adaptive_system_agreement_standard.v1",
		"TQP-39 adaptive system standard schema mismatch", failures
	)
	var validation := AdaptiveSystemEvidence.validate_retained()
	if str(validation.get("status", "")) != "PASS":
		for failure_value in validation.get("failures", []):
			failures.append("TQP-39 adaptive system: " + str(failure_value))
	_expect(
		str((milestone_by_id.get("TQP-39", {}) as Dictionary).get("status", ""))
			== "qualified",
		"TQP-39 must match retained adaptive system evidence", failures
	)


static func _validate_adaptive_streaming_evidence(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard := JsonLoader.load_dictionary(
		str(program.get("adaptive_streaming_residency_standard", ""))
	)
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.adaptive_streaming_residency_standard.v1",
		"TQP-40 adaptive streaming standard schema mismatch", failures
	)
	var validation := AdaptiveStreamingEvidence.validate_retained()
	if str(validation.get("status", "")) != "PASS":
		for failure_value in validation.get("failures", []):
			failures.append("TQP-40 adaptive streaming: " + str(failure_value))
	_expect(
		str((milestone_by_id.get("TQP-40", {}) as Dictionary).get("status", ""))
			== "qualified",
		"TQP-40 must match retained adaptive streaming evidence", failures
	)


static func _validate_adaptive_persistence_evidence(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard := JsonLoader.load_dictionary(
		str(program.get("adaptive_persistence_standard", ""))
	)
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.adaptive_persistence_standard.v1",
		"TQP-41 adaptive persistence standard schema mismatch", failures
	)
	var validation := AdaptivePersistenceEvidence.validate_retained()
	if str(validation.get("status", "")) != "PASS":
		for failure_value in validation.get("failures", []):
			failures.append("TQP-41 adaptive persistence: " + str(failure_value))
	_expect(
		str((milestone_by_id.get("TQP-41", {}) as Dictionary).get("status", ""))
			== "qualified",
		"TQP-41 must match retained adaptive persistence evidence", failures
	)


static func _validate_sparse_hierarchy_evidence(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard_path := str(program.get("sparse_hierarchy_storage_standard", ""))
	var evidence_path := str(program.get("sparse_hierarchy_storage_evidence", ""))
	var native_path := str(program.get("sparse_hierarchy_native_benchmark_evidence", ""))
	var observatory_path := str(program.get("sparse_hierarchy_observatory_evidence", ""))
	var standard := JsonLoader.load_dictionary(standard_path)
	var evidence := JsonLoader.load_dictionary(evidence_path)
	var native := JsonLoader.load_dictionary(native_path)
	var observatory := JsonLoader.load_dictionary(observatory_path)
	var expected: Dictionary = standard.get("stable_expected", {})
	var native_authority: Dictionary = native.get("authority", {})
	var native_summary: Dictionary = native.get("summary", {})
	var counters: Dictionary = native_summary.get("fixed_counters", {})
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.sparse_hierarchy_storage_standard.v1",
		"TQP-42 sparse hierarchy standard schema mismatch",
		failures
	)
	_expect(
		str(standard.get("evidence", "")) == evidence_path
			and str(standard.get("native_benchmark_evidence", "")) == native_path,
		"TQP-42 sparse hierarchy evidence paths changed",
		failures
	)
	_expect(
		str(evidence.get("schema", ""))
			== "world_transvoxel.terrain_lab.sparse_hierarchy_qualification.v1"
			and str(evidence.get("milestone", "")) == "TQP-42"
			and str(evidence.get("status", "")) == "PASS"
			and bool(evidence.get("retained_complete", false))
			and (evidence.get("failures", []) as Array).is_empty(),
		"TQP-42 retained qualification is absent or failed",
		failures
	)
	_expect(
		str(evidence.get("semantic_signature", ""))
			== str(expected.get("semantic_signature", "")),
		"TQP-42 semantic signature changed",
		failures
	)
	var actions: Dictionary = evidence.get("actions", {})
	for action in (standard.get("workload", {}) as Dictionary).get("required_actions", []):
		_expect(
			str(actions.get(str(action), "")) == "PASS",
			"TQP-42 required action failed: " + str(action),
			failures
		)
	_expect(
		str(native.get("schema", ""))
			== "world_transvoxel.sparse_hierarchy_benchmark.v1"
			and str(native.get("status", "")) == "PASS"
			and int((native.get("method", {}) as Dictionary).get("measured_runs", 0)) >= 7
			and str((native.get("method", {}) as Dictionary).get("memory_metric", ""))
				== str(expected.get("memory_metric", ""))
			and str(native_authority.get("git_commit", ""))
				== str(expected.get("upstream_commit", ""))
			and str(native_authority.get("executable_sha256", ""))
				== str(expected.get("executable_sha256", ""))
			and str(native_authority.get("native_contract_hash", ""))
				== str(expected.get("native_contract_hash", "")),
		"TQP-42 pinned native benchmark authority changed",
		failures
	)
	_expect(
		int(counters.get("declared_pages", -1)) == int(expected.get("declared_pages", -2))
			and int(counters.get("hierarchy_index_bytes", -1))
				== int(expected.get("hierarchy_index_bytes", -2))
			and int(counters.get("overlay_pages", -1))
				== int(expected.get("native_overlay_pages", -2))
			and int((native_summary.get("peak_working_set_bytes", {}) as Dictionary).get("worst", 0)) > 0,
		"TQP-42 native hierarchy counters or memory evidence changed",
		failures
	)
	_expect(
		str(observatory.get("schema", ""))
			== "world_transvoxel.terrain_lab.sparse_hierarchy_observatory_validation.v1"
			and str(observatory.get("status", "")) == "PASS"
			and (observatory.get("failures", []) as Array).is_empty(),
		"TQP-42 observatory workflow evidence is absent or failed",
		failures
	)
	var source: Dictionary = observatory.get("source_snapshot", {})
	var sparse: Dictionary = observatory.get("sparse_snapshot", {})
	_expect(
		int(source.get("declared_pages", -1)) == int(expected.get("declared_pages", -2))
			and int(source.get("explicit_index_entries", -1)) == 0
			and int(sparse.get("overlay_pages", 0)) > 0,
		"TQP-42 observatory hierarchy or overlay counters changed",
		failures
	)
	var finding := JsonLoader.load_dictionary(
		str(program.get("large_volume_snapshot_finding", ""))
	)
	_expect(
		str(finding.get("status", ""))
			== "CLOSED_BY_TQP42_SPARSE_PROCEDURAL_SNAPSHOT"
			and str(finding.get("upstream_commit", ""))
				== str(expected.get("upstream_commit", ""))
			and str(evidence.get("finding_disposition", ""))
				== "TQP-F002_CLOSED_BY_TQP42_SPARSE_PROCEDURAL_SNAPSHOT",
		"TQP-F002 closure lacks matching TQP-42 evidence",
		failures
	)
	_expect(
		str((milestone_by_id.get("TQP-42", {}) as Dictionary).get("status", ""))
			== "qualified",
		"TQP-42 must match retained sparse hierarchy evidence",
		failures
	)


static func _validate_fault_order_evidence(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard_path := str(program.get("fault_order_determinism_standard", ""))
	var evidence_path := str(program.get("fault_order_determinism_evidence", ""))
	var native_path := str(program.get("fault_order_native_benchmark_evidence", ""))
	var observatory_path := str(program.get("fault_order_observatory_evidence", ""))
	var standard := JsonLoader.load_dictionary(standard_path)
	var evidence := JsonLoader.load_dictionary(evidence_path)
	var native := JsonLoader.load_dictionary(native_path)
	var observatory := JsonLoader.load_dictionary(observatory_path)
	var expected: Dictionary = standard.get("stable_expected", {})
	var native_authority: Dictionary = native.get("authority", {})
	var native_summary: Dictionary = native.get("summary", {})
	var counters: Dictionary = native_summary.get("fixed_counters", {})
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.fault_order_determinism_standard.v1",
		"TQP-43 fault-order standard schema mismatch",
		failures
	)
	_expect(
		str(standard.get("evidence", "")) == evidence_path
			and str(standard.get("native_benchmark_evidence", "")) == native_path
			and str(standard.get("observatory_evidence", "")) == observatory_path,
		"TQP-43 retained evidence paths changed",
		failures
	)
	_expect(
		str(evidence.get("schema", ""))
			== "world_transvoxel.terrain_lab.fault_order_qualification.v1"
			and str(evidence.get("milestone", "")) == "TQP-43"
			and str(evidence.get("status", "")) == "PASS"
			and bool(evidence.get("retained_complete", false))
			and bool(evidence.get("cross_order_converged", false))
			and (evidence.get("failures", []) as Array).is_empty(),
		"TQP-43 retained qualification is absent or failed",
		failures
	)
	_expect(
		str(evidence.get("semantic_signature", ""))
			== str(expected.get("semantic_signature", "")),
		"TQP-43 semantic signature changed",
		failures
	)
	var actions: Dictionary = evidence.get("actions", {})
	for action in (standard.get("workload", {}) as Dictionary).get("required_actions", []):
		_expect(
			str(actions.get(str(action), "")) == "PASS",
			"TQP-43 required action failed: " + str(action),
			failures
		)
	_expect(
		str(native.get("schema", ""))
			== "world_transvoxel.terrain_lab.fault_order_native_benchmark.v1"
			and str(native.get("status", "")) == "PASS"
			and int((native.get("method", {}) as Dictionary).get("measured_runs", 0)) >= 15
			and str((native.get("method", {}) as Dictionary).get("memory_metric", ""))
				== str(expected.get("memory_metric", ""))
			and str(native_authority.get("git_commit", ""))
				== str(expected.get("upstream_commit", ""))
			and str(native_authority.get("executable_sha256", ""))
				== str(expected.get("executable_sha256", ""))
			and str(native_authority.get("release_executable_sha256", ""))
				== str(expected.get("release_executable_sha256", ""))
			and str(native_authority.get("native_contract_hash", ""))
				== str(expected.get("native_contract_hash", "")),
		"TQP-43 pinned native fault-order authority changed",
		failures
	)
	var build_matrix: Dictionary = native.get("build_matrix", {})
	_expect(
		str((build_matrix.get("template_debug", {}) as Dictionary).get("status", "")) == "PASS"
			and str((build_matrix.get("template_release", {}) as Dictionary).get("status", "")) == "PASS"
			and str((build_matrix.get("template_debug", {}) as Dictionary).get("native_hash", ""))
				== str(expected.get("native_contract_hash", ""))
			and str((build_matrix.get("template_release", {}) as Dictionary).get("native_hash", ""))
				== str(expected.get("native_contract_hash", "")),
		"TQP-43 debug/release native authority matrix changed",
		failures
	)
	for key in [
		"orders", "records", "stale", "cancellations", "allocation_faults",
		"interruption", "malformed", "first_divergence_generation",
	]:
		_expect(
			int(counters.get(key, -1)) == int(expected.get(key, -2)),
			"TQP-43 native counter changed: " + key,
			failures
		)
	_expect(
		str(counters.get("shutdown", "")) == str(expected.get("shutdown", ""))
			and int((native_summary.get("peak_working_set_bytes", {}) as Dictionary).get("worst", 0)) > 0,
		"TQP-43 native shutdown or memory evidence changed",
		failures
	)
	var replays: Array = evidence.get("replays", [])
	_expect(replays.size() == 3, "TQP-43 retained motion-order count changed", failures)
	var state_signature := ""
	var geometry_signature := ""
	for replay_value in replays:
		var replay: Dictionary = replay_value
		var snapshot: Dictionary = replay.get("snapshot", {})
		if state_signature.is_empty():
			state_signature = str(snapshot.get("state_signature", ""))
			geometry_signature = str(snapshot.get("geometry_signature", ""))
		_expect(
			str(replay.get("status", "")) == "PASS"
				and bool(replay.get("viewer_drain_completed", false))
				and bool(replay.get("stale_revision_rejected", false))
				and int(snapshot.get("active_count", 0)) > 0
				and int((snapshot.get("metrics", {}) as Dictionary).get("render_resources", 0)) > 0
				and str(snapshot.get("state_signature", "")) == state_signature
				and str(snapshot.get("geometry_signature", "")) == geometry_signature,
			"TQP-43 live replay changed or became empty",
			failures
		)
	_expect(
		str(observatory.get("schema", ""))
			== "world_transvoxel.terrain_lab.fault_order_observatory_validation.v1"
			and str(observatory.get("status", "")) == "PASS"
			and str((observatory.get("comparison", {}) as Dictionary).get("status", "")) == "PASS"
			and (observatory.get("failures", []) as Array).is_empty(),
		"TQP-43 observatory workflow evidence is absent or failed",
		failures
	)
	var observed: Dictionary = observatory.get("comparison_snapshot", {})
	_expect(
		str(observed.get("backend_id", "")) == "transvoxel_mit_official"
			and int(observed.get("native_orders", 0)) == int(expected.get("orders", -1))
			and int(observed.get("first_divergence_generation", -1))
				== int(expected.get("first_divergence_generation", -2))
			and int(observed.get("render_resources", 0)) > 0
			and int(observed.get("coalesced_viewer_events", 0)) > 0
			and int(observed.get("rejected_events", 0)) > 0,
		"TQP-43 observatory authority, geometry, or event counters changed",
		failures
	)
	_expect(
		str((milestone_by_id.get("TQP-43", {}) as Dictionary).get("status", ""))
			== "qualified",
		"TQP-43 must match retained fault-order evidence",
		failures
	)


static func _validate_low_power_performance_profile(
	program: Dictionary,
	failures: Array[String]
) -> void:
	var profile := JsonLoader.load_dictionary(
		str(program.get("low_power_performance_profile", ""))
	)
	_expect(
		str(profile.get("schema", ""))
			== "world_transvoxel.terrain_lab.low_power_performance_profile.v2",
		"low-power performance profile schema mismatch",
		failures
	)
	_expect(
		str(profile.get("status", "")) == "SPECIFIED_UNQUALIFIED",
		"low-power target profile must remain unqualified until the full target pass is measured",
		failures
	)
	var measurement: Dictionary = profile.get("measurement_contract", {})
	_expect(
		is_equal_approx(float(measurement.get("target_fps", 0.0)), 60.0)
			and str(measurement.get("primary_metric", "")) == "gpu_board_wpf60"
			and str(measurement.get("primary_power_boundary", "")) == "gpu_board"
			and is_equal_approx(float(measurement.get("target_wpf60", 0.0)), 16.0),
		"low-power 60 FPS / 16 GPU-board WPF60 target changed",
		failures
	)
	var collision: Dictionary = profile.get("collision_residency_contract", {})
	_expect(
		bool(collision.get("render_and_collision_demand_are_independent", false))
			and bool(collision.get("all_visible_chunks_may_not_receive_collision_by_default", false))
			and bool(collision.get("collision_is_requested_by_bounded_physics_invokers", false))
			and bool(collision.get("collision_generation_and_application_are_budgeted", false)),
		"low-power targeted collision contract is incomplete",
		failures
	)


static func _validate_cpu_closure_implementation(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var visual := ComplexVisualEvidence.validate_retained()
	_expect(
		str(visual.get("automation_status", "")) == "PASS"
			and str(visual.get("status", "")) in ["PENDING_HUMAN_REVIEW", "PASS"],
		"TQP-44 retained corpus is invalid",
		failures
	)
	var fast_arrival := FastArrivalEvidence.validate_retained()
	var targeted_collision := TargetedCollisionEvidence.validate_retained()
	var large_world := LargeWorldPerformanceEvidence.validate_retained()
	for validation in [fast_arrival, targeted_collision, large_world]:
		_expect(
			str((validation as Dictionary).get("status", "")) == "PASS",
			"focused CPU closure candidate evidence failed: %s %s" % [
				str((validation as Dictionary).get("schema", "unknown")),
				str((validation as Dictionary).get("failures", [])),
			],
			failures
		)
	var power := JsonLoader.load_dictionary(str(program.get("low_power_qualification_evidence", "")))
	var power_complete := (
		str(power.get("schema", ""))
		== "world_transvoxel.terrain_lab.low_power_profiles_qualification.v2"
		and str(power.get("status", "")) in ["MEASURED_TARGET_MISS", "PASS"]
		and str(power.get("primary_metric", "")) == "gpu_board_wpf60"
		and bool(power.get("retained_complete", false))
	)
	_expect(power_complete, "TQP-48 retained exact power report is incomplete", failures)
	var soak := JsonLoader.load_dictionary(str(program.get("complex_adaptive_soak_recovery_evidence", "")))
	var soak_passed := (
		str(soak.get("schema", ""))
		== "world_transvoxel.terrain_lab.complex_adaptive_soak_recovery_qualification.v1"
		and str(soak.get("status", "")) == "PASS"
		and bool(soak.get("retained_complete", false))
	)
	_expect(soak_passed, "TQP-49 fail-closed soak report has not passed", failures)
	var gate := JsonLoader.load_dictionary(str(program.get("native_adaptive_authority_gate_evidence", "")))
	var gate_passed := (
		str(gate.get("schema", ""))
		== "world_transvoxel.terrain_lab.native_adaptive_terrain_authority_gate.v1"
		and str(gate.get("status", "")) == "PASS"
		and bool(gate.get("gate_promoted", false))
		and bool(gate.get("retained_complete", false))
	)
	_expect(gate_passed, "TQP-50 fail-closed authority gate has not passed", failures)
	_expect(
		str((milestone_by_id.get("TQP-44", {}) as Dictionary).get("status", ""))
			== ("qualified" if str(visual.get("status", "")) == "PASS" else "implemented"),
		"TQP-44 manifest status differs from retained human review",
		failures
	)
	for milestone_id in ["TQP-45", "TQP-46", "TQP-47"]:
		_expect(
			str((milestone_by_id.get(milestone_id, {}) as Dictionary).get("status", ""))
				== "qualified",
			milestone_id + " must match retained focused PASS evidence",
			failures
		)
	var closure_statuses := {
		"TQP-48": [power_complete, "TQP-48 must match retained exact low-power baseline evidence"],
		"TQP-49": [soak_passed, "TQP-49 must match retained complex adaptive soak evidence"],
		"TQP-50": [gate_passed, "TQP-50 must match retained Gate E authority evidence"],
	}
	for milestone_id in closure_statuses:
		var record: Array = closure_statuses[milestone_id]
		_expect(
			str((milestone_by_id.get(milestone_id, {}) as Dictionary).get("status", ""))
				== ("qualified" if bool(record[0]) else "implemented"),
			str(record[1]),
			failures
		)


static func _validate_surface_shading_evidence(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard := JsonLoader.load_dictionary(str(program.get("surface_shading_standard", "")))
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.surface_shading_standard.v1",
		"surface shading standard schema mismatch",
		failures
	)
	var review_protocol := JsonLoader.load_dictionary(
		str(program.get("surface_shading_review_protocol", ""))
	)
	_expect(
		str(review_protocol.get("schema", ""))
			== "world_transvoxel.terrain_lab.surface_shading_review_protocol.v1",
		"surface shading review protocol schema mismatch",
		failures
	)
	_expect(
		str(review_protocol.get("milestone", "")) == "TQP-23",
		"surface shading review protocol milestone changed",
		failures
	)
	_expect(
		bool(review_protocol.get("formal_decision_required", false)),
		"surface shading review must require a formal decision",
		failures
	)
	_expect(
		int(review_protocol.get("minimum_motion_cycles", 0)) == 2,
		"surface shading review motion-cycle gate changed",
		failures
	)
	var review_fixture: Dictionary = review_protocol.get("fixture", {})
	_expect(
		is_equal_approx(float(review_fixture.get("sample_scale_m", 0.0)), 0.25),
		"surface shading review fixture resolution changed",
		failures
	)
	_expect(
		bool(review_fixture.get("native_dependency_only", false)),
		"surface shading review fixture permits a fallback",
		failures
	)
	_expect(
		(review_protocol.get("diagnostic_modes", []) as Array).size() == 10,
		"surface shading review diagnostic catalog changed",
		failures
	)
	_expect(
		(review_protocol.get("criteria", []) as Array).size() == 8,
		"surface shading review criteria changed",
		failures
	)
	var decision_policy: Dictionary = review_protocol.get("decision_policy", {})
	for required_policy in [
		"candidate_pass_requires_all_criteria",
		"candidate_pass_requires_motion_cycles",
		"candidate_pass_requires_all_diagnostic_modes",
		"candidate_pass_requires_shadow_comparison",
		"candidate_pass_requires_reference_shadows_enabled",
		"any_failed_criterion_blocks_qualification",
		"draft_cannot_promote_milestone",
		"repository_decision_required_for_promotion",
		"uncertain_review_is_pending",
	]:
		_expect(
			bool(decision_policy.get(required_policy, false)),
			"surface shading review policy is not fail-closed: " + required_policy,
			failures
		)
	_expect(
		FileAccess.file_exists(str(review_protocol.get("review_scene", ""))),
		"surface shading guided review scene is missing",
		failures
	)
	var static_evidence := JsonLoader.load_dictionary(
		str(program.get("surface_shading_evidence", ""))
	)
	var static_review: Dictionary = static_evidence.get("human_review", {})
	_expect(
		str(static_review.get("status", "")) == "ACCEPTED",
		"surface shading static evidence is not accepted",
		failures
	)
	_expect(
		str(static_review.get("decision", "")).ends_with("TQP-D014.json"),
		"surface shading static acceptance decision is missing",
		failures
	)
	_expect(
		"TQP-23" in static_review.get("accepted_for", []),
		"TQP-23 is absent from accepted surface-shading scope",
		failures
	)
	var review_evidence := JsonLoader.load_dictionary(
		str(program.get("surface_shading_review_evidence", ""))
	)
	_expect(
		str(review_evidence.get("schema", ""))
			== "world_transvoxel.terrain_lab.surface_shading_review_automation.v1",
		"surface shading guided review evidence schema mismatch",
		failures
	)
	_expect(
		str(review_evidence.get("status", "")) == "PASS",
		"surface shading guided review automation failed",
		failures
	)
	_expect(
		(review_evidence.get("captures", []) as Array).size() == 6,
		"surface shading guided review capture catalog changed",
		failures
	)
	_expect(
		is_equal_approx(
			float((review_evidence.get("review_contract", {}) as Dictionary).get(
				"fixture_sample_scale_m",
				0.0
			)),
			0.25
		),
		"surface shading review evidence used the wrong fixture resolution",
		failures
	)
	var review_capture_by_id := {}
	for capture_value in review_evidence.get("captures", []):
		var capture: Dictionary = capture_value
		review_capture_by_id[str(capture.get("id", ""))] = capture
		var capture_path := str(capture.get("image", ""))
		_expect(FileAccess.file_exists(capture_path), "surface shading review capture is missing: " + capture_path, failures)
		if FileAccess.file_exists(capture_path):
			_expect(
				FileAccess.get_sha256(capture_path) == str(capture.get("sha256", "")),
				"surface shading review capture hash changed: " + capture_path,
				failures
			)
	_expect(
		bool((review_capture_by_id.get("shadow_isolation", {}) as Dictionary).get(
			"sun_shadows",
			false
		)),
		"surface shadow isolation capture has shadows disabled",
		failures
	)
	_expect(
		not bool((review_capture_by_id.get("shadow_disabled_control", {}) as Dictionary).get(
			"sun_shadows",
			true
		)),
		"surface shadow disabled control has shadows enabled",
		failures
	)
	_expect(
		str(review_evidence.get("formal_human_review", "")) == "ACCEPTED",
		"surface shading guided review is not formally accepted",
		failures
	)
	_expect(
		str(review_evidence.get("review_decision", "")).ends_with("TQP-D014.json"),
		"surface shading guided review decision is missing",
		failures
	)
	var shadow_finding := JsonLoader.load_dictionary(
		str(program.get("surface_shadow_resolution_finding", ""))
	)
	_expect(
		str(shadow_finding.get("schema", "")) == "world_transvoxel.terrain_lab.finding.v1",
		"surface shadow finding schema mismatch",
		failures
	)
	_expect(
		str(shadow_finding.get("id", "")) == "TQP-F001",
		"surface shadow finding ID changed",
		failures
	)
	_expect(
		str(shadow_finding.get("status", "")) == "CLOSED_BOUNDED_TQP25_ACCEPTANCE",
		"surface shadow finding is not closed for accepted TQP-25 scope",
		failures
	)
	_expect(
		str(shadow_finding.get("closure_decision", "")).ends_with("TQP-D015.json"),
		"surface shadow finding lacks its bounded closure decision",
		failures
	)
	var shadow_evidence := JsonLoader.load_dictionary(
		str(program.get("surface_shadow_resolution_evidence", ""))
	)
	_expect(
		str(shadow_evidence.get("schema", ""))
			== "world_transvoxel.terrain_lab.surface_shadow_resolution_evidence.v1",
		"surface shadow resolution evidence schema mismatch",
		failures
	)
	_expect(
		str(shadow_evidence.get("status", "")) == "PASS",
		"surface shadow resolution evidence failed",
		failures
	)
	_expect(
		str(shadow_evidence.get("finding", "")) == "TQP-F001",
		"surface shadow evidence is detached from its finding",
		failures
	)
	var shadow_profiles: Array = shadow_evidence.get("resolution_profiles", [])
	_expect(shadow_profiles.size() == 2, "surface shadow resolution profile count changed", failures)
	if shadow_profiles.size() == 2:
		var coarse_mesh: Dictionary = (shadow_profiles[0] as Dictionary).get("mesh", {})
		var fine_mesh: Dictionary = (shadow_profiles[1] as Dictionary).get("mesh", {})
		_expect(
			int(fine_mesh.get("triangle_count", 0)) > int(coarse_mesh.get("triangle_count", 0)),
			"fine surface shadow fixture did not increase native mesh resolution",
			failures
		)
		for mesh in [coarse_mesh, fine_mesh]:
			_expect(int(mesh.get("seam_errors", -1)) == 0, "shadow fixture seam error", failures)
			_expect(
				int(mesh.get("interior_open_edges", -1)) == 0,
				"shadow fixture interior opening",
				failures
			)
			_expect(
				int(mesh.get("nonmanifold_edges", -1)) == 0,
				"shadow fixture nonmanifold topology",
				failures
			)
	var report := JsonLoader.load_dictionary(str(program.get("surface_shading_contract_evidence", "")))
	_expect(
		str(report.get("schema", ""))
			== "world_transvoxel.terrain_lab.surface_shading_contract_qualification.v1",
		"surface shading focused report schema mismatch",
		failures
	)
	_expect(str(report.get("status", "")) == "PASS", "surface shading focused report failed", failures)
	var milestone: Dictionary = report.get("milestone", {})
	_expect(str(milestone.get("milestone", "")) == "TQP-23", "surface shading focused milestone changed", failures)
	_expect(str(milestone.get("status", "")) == "PASS", "surface shading focused contract failed", failures)
	_expect(
		str(milestone.get("qualification_status", "")).begins_with("QUALIFIED"),
		"surface shading focused contract is not qualified",
		failures
	)
	var visual: Dictionary = milestone.get("visual_evidence", {})
	_expect(str(visual.get("human_review", "")) == "ACCEPTED", "surface shading focused report lacks accepted review", failures)
	_expect(
		str((milestone.get("performance", {}) as Dictionary).get("budget_evaluation", ""))
			== "ENFORCED_FOCUSED_RUN",
		"surface shading focused performance ceiling was not enforced",
		failures
	)
	_expect(
		str((milestone_by_id.get("TQP-23", {}) as Dictionary).get("status", "")) == "qualified",
		"TQP-23 status does not match its accepted reference evidence",
		failures
	)


static func _validate_terrain_observatory_evidence(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard := JsonLoader.load_dictionary(str(program.get("terrain_observatory_standard", "")))
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.terrain_observatory_standard.v1",
		"terrain observatory standard schema mismatch",
		failures
	)
	_expect(str(standard.get("milestone", "")) == "TQP-26", "terrain observatory standard milestone changed", failures)
	_expect(FileAccess.file_exists(str(standard.get("editor_scene", ""))), "terrain observatory editor scene is missing", failures)
	_expect((standard.get("required_chunk_fields", []) as Array).size() == 10, "terrain observatory chunk contract changed", failures)
	_expect((standard.get("required_job_fields", []) as Array).size() == 7, "terrain observatory job contract changed", failures)
	var report := JsonLoader.load_dictionary(str(program.get("terrain_observatory_evidence", "")))
	_expect(
		str(report.get("schema", ""))
			== "world_transvoxel.terrain_lab.terrain_observatory_qualification.v1",
		"terrain observatory retained report schema mismatch",
		failures
	)
	_expect(str(report.get("status", "")) == "PASS", "terrain observatory retained report failed", failures)
	var milestone: Dictionary = report.get("milestone", {})
	_expect(str(milestone.get("milestone", "")) == "TQP-26", "terrain observatory evidence milestone changed", failures)
	_expect(str(milestone.get("status", "")) == "PASS", "terrain observatory contract failed", failures)
	_expect(
		str(milestone.get("qualification_status", ""))
			== "QUALIFIED_TERRAIN_OBSERVATORY_DIAGNOSTICS_V1",
		"terrain observatory evidence is not qualified",
		failures
	)
	_expect(int(milestone.get("fixture_count", 0)) >= 54, "terrain observatory fixture coverage changed", failures)
	var snapshot: Dictionary = milestone.get("snapshot", {})
	_expect(
		str(ObservatoryDiagnostics.validate_snapshot(snapshot).get("status", "")) == "PASS",
		"terrain observatory retained snapshot signature failed validation",
		failures
	)
	_expect(
		str(snapshot.get("schema", "")) == str(standard.get("snapshot_schema", "")),
		"terrain observatory snapshot schema changed",
		failures
	)
	_expect(str(snapshot.get("snapshot_signature", "")).length() == 64, "terrain observatory snapshot signature is invalid", failures)
	_expect(str(milestone.get("repro_signature", "")).length() == 64, "terrain observatory repro signature is invalid", failures)
	var resources: Dictionary = snapshot.get("resources", {})
	_expect(int(resources.get("total_memory_bytes", 0)) > 0, "terrain observatory memory evidence is absent", failures)
	_expect(not (resources.get("buffer_bytes", {}) as Dictionary).is_empty(), "terrain observatory buffer evidence is absent", failures)
	_expect(not (resources.get("timing_max_usec", {}) as Dictionary).is_empty(), "terrain observatory timing evidence is absent", failures)
	_expect(not (resources.get("collision_states", {}) as Dictionary).is_empty(), "terrain observatory collision evidence is absent", failures)
	var controls: Dictionary = milestone.get("negative_controls", {})
	_expect(bool(controls.get("tampered_repro_rejected", false)), "terrain observatory tamper control failed", failures)
	_expect(bool(controls.get("event_overflow_ordering", false)), "terrain observatory event overflow control failed", failures)
	_expect(
		str((milestone_by_id.get("TQP-26", {}) as Dictionary).get("status", "")) == "qualified",
		"TQP-26 status does not match retained observatory evidence",
		failures
	)


static func _validate_production_addon_boundary(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard := JsonLoader.load_dictionary(
		str(program.get("production_addon_boundary_standard", ""))
	)
	var evidence := JsonLoader.load_dictionary(
		str(program.get("production_addon_boundary_evidence", ""))
	)
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.production_addon_boundary_standard.v1",
		"production addon boundary standard schema mismatch",
		failures
	)
	_expect(str(standard.get("milestone", "")) == "TQP-51", "production addon standard milestone changed", failures)
	_expect(
		str(evidence.get("schema", ""))
			== "world_transvoxel.terrain_lab.production_addon_boundary_qualification.v1",
		"production addon boundary evidence schema mismatch",
		failures
	)
	_expect(str(evidence.get("milestone", "")) == "TQP-51", "production addon evidence milestone changed", failures)
	_expect(str(evidence.get("status", "")) == "PASS", "production addon boundary evidence failed", failures)
	_expect(bool(evidence.get("retained_complete", false)), "production addon boundary evidence is incomplete", failures)
	_expect(
		str(evidence.get("qualification_status", ""))
			== "QUALIFIED_CANDIDATE_PRODUCTION_ADDON_BOUNDARY_V1",
		"production addon boundary is not qualified",
		failures
	)
	var candidate_standard: Dictionary = standard.get("candidate", {})
	var candidate: Dictionary = evidence.get("candidate", {})
	for key in ["revision", "addon_root", "addon_tree", "candidate_id", "boundary_contract_sha256"]:
		_expect(
			str(candidate.get(key, "")) == str(candidate_standard.get(key, "")),
			"production addon candidate pin mismatch: " + key,
			failures
		)
	_expect(bool(candidate.get("tracked_worktree_clean", false)), "production addon candidate evidence was dirty", failures)
	_expect(candidate.get("fallback_mesher", true) == false, "production addon candidate permits a fallback mesher", failures)
	_expect(candidate.get("silent_fallback", true) == false, "production addon candidate permits silent fallback", failures)
	var authority_standard: Dictionary = standard.get("native_authority", {})
	var authority: Dictionary = evidence.get("native_authority", {})
	_expect(
		str(authority.get("revision", "")) == str(authority_standard.get("revision", "")),
		"production addon native authority pin mismatch",
		failures
	)
	_expect(bool(authority.get("tracked_worktree_clean", false)), "production addon native authority evidence was dirty", failures)
	var static_validation: Dictionary = evidence.get("static_validation", {})
	_expect(str(static_validation.get("status", "")) == "PASS", "production addon static validation failed", failures)
	_expect(
		int(static_validation.get("validator_count", 0))
			== int(standard.get("required_static_validator_count", -1)),
		"production addon static validator coverage changed",
		failures
	)
	var runtime: Dictionary = evidence.get("runtime_regression", {})
	var expected_runtime := {
		"a4": {"decision": "a4_complete", "validators": 9, "smokes": 6},
		"a5": {"decision": "a5_complete", "validators": 7, "smokes": 4},
		"a6": {"decision": "approve_validation_game_repository", "validators": 2, "smokes": 0},
	}
	for report_id in expected_runtime:
		var report: Dictionary = runtime.get(report_id, {})
		var expected: Dictionary = expected_runtime[report_id]
		_expect(str(report.get("decision", "")) == str(expected.get("decision", "")), "production addon runtime decision changed: " + report_id, failures)
		_expect(int(report.get("validators", -1)) == int(expected.get("validators", -2)), "production addon runtime validator coverage changed: " + report_id, failures)
		_expect(int(report.get("smokes", -1)) == int(expected.get("smokes", -2)), "production addon runtime smoke coverage changed: " + report_id, failures)
	_expect(
		str((milestone_by_id.get("TQP-51", {}) as Dictionary).get("status", "")) == "qualified",
		"TQP-51 status does not match retained production-addon boundary evidence",
		failures
	)


static func _validate_cpu_production_first_batch(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var runtime_standard := JsonLoader.load_dictionary(
		str(program.get("production_runtime_contract_standard", ""))
	)
	var authoring_standard := JsonLoader.load_dictionary(
		str(program.get("production_authoring_workflow_standard", ""))
	)
	var migration_standard := JsonLoader.load_dictionary(
		str(program.get("downstream_migration_standard", ""))
	)
	var evidence := JsonLoader.load_dictionary(
		str(program.get("cpu_production_first_batch_evidence", ""))
	)
	_expect(
		str(runtime_standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.production_runtime_contract_standard.v1",
		"production runtime standard schema mismatch",
		failures
	)
	_expect(
		str(authoring_standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.production_authoring_workflow_standard.v1",
		"production authoring standard schema mismatch",
		failures
	)
	_expect(
		str(migration_standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.downstream_migration_standard.v1",
		"downstream migration standard schema mismatch",
		failures
	)
	_expect(
		str(evidence.get("schema", ""))
			== "world_transvoxel.terrain_lab.cpu_production_first_batch_qualification.v1",
		"CPU production first-batch evidence schema mismatch",
		failures
	)
	_expect(str(evidence.get("status", "")) == "PASS", "CPU production first-batch evidence failed", failures)
	_expect(bool(evidence.get("retained_complete", false)), "CPU production first-batch evidence is incomplete", failures)
	_expect(str(evidence.get("platform", "")) == "windows-x86_64", "CPU production first-batch platform changed", failures)

	var candidate: Dictionary = evidence.get("candidate", {})
	var runtime_candidate: Dictionary = runtime_standard.get("candidate", {})
	var authoring_candidate: Dictionary = authoring_standard.get("candidate", {})
	for key in ["repository", "revision", "addon_tree"]:
		_expect(
			str(candidate.get(key, "")) == str(runtime_candidate.get(key, "")),
			"TQP-52 candidate pin mismatch: " + key,
			failures
		)
		_expect(
			str(candidate.get(key, "")) == str(authoring_candidate.get(key, "")),
			"TQP-53 candidate pin mismatch: " + key,
			failures
		)
	_expect(bool(candidate.get("tracked_content_clean", false)), "candidate evidence has tracked changes", failures)
	var authority: Dictionary = evidence.get("native_authority", {})
	var authority_standard: Dictionary = runtime_standard.get("native_authority", {})
	_expect(
		str(authority.get("revision", "")) == str(authority_standard.get("revision", "")),
		"native authority pin mismatch in CPU production evidence",
		failures
	)
	_expect(bool(authority.get("tracked_content_clean", false)), "native authority evidence has tracked changes", failures)
	var integration: Dictionary = evidence.get("integration", {})
	var integration_standard: Dictionary = migration_standard.get("integration", {})
	_expect(
		str(integration.get("revision", "")) == str(integration_standard.get("revision", "")),
		"TQP-54 integration revision mismatch",
		failures
	)
	_expect(bool(integration.get("tracked_content_clean", false)), "integration evidence has tracked content changes", failures)
	var migration_candidate: Dictionary = migration_standard.get("candidate", {})
	_expect(
		str(candidate.get("revision", "")) == str(migration_candidate.get("revision", "")),
		"TQP-54 candidate revision differs from TQP-52/TQP-53",
		failures
	)
	_expect(
		str(candidate.get("addon_tree", "")) == str(migration_candidate.get("addon_tree", "")),
		"TQP-54 candidate tree differs from TQP-52/TQP-53",
		failures
	)

	var records: Dictionary = evidence.get("milestones", {})
	var expected := {
		"TQP-52": {
			"standard": runtime_standard,
			"qualification": "QUALIFIED_PRODUCTION_RUNTIME_CONTRACT_V1",
			"scope": "qualified_production_runtime_contract_v1",
		},
		"TQP-53": {
			"standard": authoring_standard,
			"qualification": "QUALIFIED_PRODUCTION_AUTHORING_WORKFLOW_V1",
			"scope": "qualified_production_authoring_workflow_v1",
		},
		"TQP-54": {
			"standard": migration_standard,
			"qualification": "QUALIFIED_DOWNSTREAM_MIGRATION_V1",
			"scope": "qualified_downstream_migration_v1",
		},
	}
	for milestone_id in expected:
		var expected_record: Dictionary = expected[milestone_id]
		var standard: Dictionary = expected_record["standard"]
		var record: Dictionary = records.get(milestone_id, {})
		var milestone: Dictionary = milestone_by_id.get(milestone_id, {})
		_expect(str(standard.get("milestone", "")) == milestone_id, milestone_id + " standard identity mismatch", failures)
		_expect(str(record.get("status", "")) == "PASS", milestone_id + " retained evidence failed", failures)
		_expect(
			str(record.get("qualification_status", "")) == str(expected_record["qualification"]),
			milestone_id + " qualification status mismatch",
			failures
		)
		_expect(
			str(record.get("standard_id", "")) == str(standard.get("standard_id", "")),
			milestone_id + " standard ID mismatch",
			failures
		)
		_expect(str(milestone.get("status", "")) == "qualified", milestone_id + " is not qualified", failures)
		_expect(
			str(milestone.get("claim_scope", "")) == str(expected_record["scope"]),
			milestone_id + " claim scope mismatch",
			failures
		)

	var runtime_record: Dictionary = records.get("TQP-52", {})
	_expect(int(runtime_record.get("api_version", 0)) == 2, "TQP-52 API version changed", failures)
	_expect(int(runtime_record.get("profiles", 0)) == 4, "TQP-52 profile count changed", failures)
	_expect(int(runtime_record.get("readiness_scopes", 0)) == 4, "TQP-52 readiness scope count changed", failures)
	_expect(
		str(runtime_record.get("source_contract_sha256", ""))
			== str((runtime_standard.get("source_contract", {}) as Dictionary).get("sha256", "")),
		"TQP-52 source contract digest changed",
		failures
	)
	_expect(
		str(runtime_record.get("source_report_sha256", ""))
			== str((runtime_standard.get("source_report", {}) as Dictionary).get("sha256", "")),
		"TQP-52 source report digest changed",
		failures
	)
	var runtime_markers: Dictionary = runtime_record.get("engine_markers", {})
	for engine_value in runtime_standard.get("required_engines", []):
		var engine := str(engine_value)
		_expect(
			str(runtime_markers.get(engine, "")).begins_with("WT_TERRAIN_TQP52_GODOT_PASS"),
			"TQP-52 engine marker missing: " + engine,
			failures
		)
	_expect(
		runtime_markers.size() == (runtime_standard.get("required_engines", []) as Array).size(),
		"TQP-52 engine evidence changed",
		failures
	)
	var authoring_record: Dictionary = records.get("TQP-53", {})
	_expect(bool(authoring_record.get("draft_undo_redo", false)), "TQP-53 draft undo/redo evidence missing", failures)
	_expect(authoring_record.get("durable_inverse_claim", true) == false, "TQP-53 makes a durable inverse claim", failures)
	_expect(str(authoring_record.get("repro_schema", "")) == "world_transvoxel_terrain.repro.v1", "TQP-53 repro schema changed", failures)
	_expect(
		str(authoring_record.get("source_contract_sha256", ""))
			== str((authoring_standard.get("source_contract", {}) as Dictionary).get("sha256", "")),
		"TQP-53 source contract digest changed",
		failures
	)
	_expect(
		str(authoring_record.get("source_report_sha256", ""))
			== str((authoring_standard.get("source_report", {}) as Dictionary).get("sha256", "")),
		"TQP-53 source report digest changed",
		failures
	)
	var authoring_markers: Dictionary = authoring_record.get("engine_markers", {})
	for engine_value in authoring_standard.get("required_engines", []):
		var engine := str(engine_value)
		_expect(
			str(authoring_markers.get(engine, "")).begins_with("WT_TERRAIN_TQP53_GODOT_PASS"),
			"TQP-53 engine marker missing: " + engine,
			failures
		)
	_expect(
		authoring_markers.size() == (authoring_standard.get("required_engines", []) as Array).size(),
		"TQP-53 engine evidence changed",
		failures
	)
	var migration_record: Dictionary = records.get("TQP-54", {})
	_expect(
		str(migration_record.get("package_policy", "")) == "EXACT_PINNED_AUTHORITIES_NO_FALLBACKS",
		"TQP-54 exact package policy changed",
		failures
	)
	_expect(migration_record.get("release_claim", true) == false, "TQP-54 makes a release claim", failures)
	var candidate_package: Dictionary = migration_record.get("candidate_package", {})
	var authority_package: Dictionary = migration_record.get("authority_package", {})
	_expect(
		str(candidate_package.get("commit", "")) == str(migration_candidate.get("revision", "")),
		"TQP-54 candidate package revision changed",
		failures
	)
	for key in ["addon_tree", "package_digest_sha256", "files"]:
		_expect(
			candidate_package.get(key) == migration_candidate.get(key),
			"TQP-54 candidate package changed: " + key,
			failures
		)
	var migration_authority: Dictionary = migration_standard.get("native_authority", {})
	_expect(
		str(authority_package.get("commit", "")) == str(migration_authority.get("revision", "")),
		"TQP-54 authority package revision changed",
		failures
	)
	for key in ["addon_tree", "package_digest_sha256", "files"]:
		_expect(
			authority_package.get(key) == migration_authority.get(key),
			"TQP-54 authority package changed: " + key,
			failures
		)
	var migration_markers: Dictionary = migration_record.get("runtime_smoke_markers", {})
	for engine_value in migration_standard.get("required_engines", []):
		var engine := str(engine_value)
		_expect(
			str(migration_markers.get(engine, "")).begins_with("WT_TQP54_MIGRATION_GODOT_PASS"),
			"TQP-54 engine marker missing: " + engine,
			failures
		)
	_expect(
		migration_markers.size() == (migration_standard.get("required_engines", []) as Array).size(),
		"TQP-54 engine evidence changed",
		failures
	)
	_expect(int(migration_record.get("deep_gate_timeout_seconds", 0)) == 1800, "TQP-54 deep gate timeout changed", failures)


static func _validate_cpu_production_release(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var matrix_standard := JsonLoader.load_dictionary(
		str(program.get("cpu_production_release_matrix_standard", ""))
	)
	var long_standard := JsonLoader.load_dictionary(
		str(program.get("cpu_production_long_haul_standard", ""))
	)
	var release_standard := JsonLoader.load_dictionary(
		str(program.get("cpu_production_release_standard", ""))
	)
	var evidence := JsonLoader.load_dictionary(
		str(program.get("cpu_production_release_evidence", ""))
	)
	_expect(
		str(matrix_standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.cpu_production_release_matrix_standard.v1",
		"TQP-55 release-matrix standard schema mismatch",
		failures
	)
	_expect(
		str(long_standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.cpu_production_long_haul_standard.v1",
		"TQP-56 long-haul standard schema mismatch",
		failures
	)
	_expect(
		str(release_standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.cpu_production_release_standard.v1",
		"TQP-57 release standard schema mismatch",
		failures
	)
	_expect(
		str(evidence.get("schema", ""))
			== "world_transvoxel.terrain_lab.cpu_production_release_qualification.v1",
		"CPU production release evidence schema mismatch",
		failures
	)
	_expect(str(evidence.get("status", "")) == "PASS", "CPU production release evidence failed", failures)
	_expect(bool(evidence.get("retained_complete", false)), "CPU production release evidence is incomplete", failures)
	_expect(bool(evidence.get("gate_promoted", false)), "Gate F was not promoted", failures)
	var candidate: Dictionary = evidence.get("candidate", {})
	var expected_candidate: Dictionary = matrix_standard.get("candidate", {})
	_expect(str(candidate.get("revision", "")) == str(expected_candidate.get("revision", "")), "release candidate revision changed", failures)
	_expect(str(candidate.get("addon_tree", "")) == str(expected_candidate.get("addon_tree", "")), "release candidate addon tree changed", failures)
	_expect(bool(candidate.get("tracked_content_clean", false)), "release candidate tracked content is dirty", failures)
	var milestone_evidence: Dictionary = evidence.get("milestones", {})
	for milestone_id in ["TQP-55", "TQP-56", "TQP-57"]:
		_expect(
			str((milestone_evidence.get(milestone_id, {}) as Dictionary).get("status", "")) == "PASS",
			milestone_id + " release evidence failed",
			failures
		)
	_expect(
		str((milestone_by_id.get("TQP-55", {}) as Dictionary).get("status", "")) == "qualified",
		"TQP-55 status differs from release-matrix evidence",
		failures
	)
	_expect(
		str((milestone_by_id.get("TQP-56", {}) as Dictionary).get("status", "")) == "qualified",
		"TQP-56 status differs from long-haul evidence",
		failures
	)
	_expect(
		str((milestone_by_id.get("TQP-57", {}) as Dictionary).get("status", "")) == "production",
		"TQP-57 status differs from release evidence",
		failures
	)
	var matrix: Dictionary = (milestone_evidence.get("TQP-55", {}) as Dictionary).get("matrix", {})
	_expect(matrix.get("engine_versions", []) == ["4.7"], "TQP-55 Godot matrix changed", failures)
	_expect(
		str((milestone_evidence.get("TQP-55", {}) as Dictionary).get("power_target_status", ""))
			== "retained_measured_target_miss",
		"TQP-55 power target miss was hidden",
		failures
	)
	var workload: Dictionary = (milestone_evidence.get("TQP-56", {}) as Dictionary).get("workload", {})
	_expect(float(workload.get("duration_seconds", 0.0)) >= 60.0, "TQP-56 wrapper duration changed", failures)
	_expect(int(workload.get("queue_rejections", -1)) == 0, "TQP-56 queue rejection evidence changed", failures)
	_expect(bool(workload.get("clean_shutdown", false)), "TQP-56 clean shutdown evidence changed", failures)
	var release: Dictionary = milestone_evidence.get("TQP-57", {})
	_expect(str(release.get("version", "")) == "1.0.0", "TQP-57 version changed", failures)
	_expect(
		str(release.get("release_boundary", "")) == "limited_windows_cpu_reference_release",
		"TQP-57 release boundary widened",
		failures
	)
	var package: Dictionary = release.get("package", {})
	_expect(
		str(package.get("package_digest_sha256", ""))
			== str((release_standard.get("package", {}) as Dictionary).get("package_digest_sha256", "")),
		"TQP-57 package digest changed",
		failures
	)


static func _validate_cpu_finalization(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard := JsonLoader.load_dictionary(
		str(program.get("cpu_finalization_standard", ""))
	)
	var evidence := JsonLoader.load_dictionary(
		str(program.get("cpu_finalization_evidence", ""))
	)
	var backend_decision := JsonLoader.load_dictionary(
		str(program.get("backend_decision", ""))
	)
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.cpu_finalization_standard.v2",
		"CPU finalization standard schema mismatch",
		failures
	)
	_expect(
		str(evidence.get("schema", ""))
			== "world_transvoxel.terrain_lab.cpu_finalization_readiness.v2",
		"CPU finalization evidence schema mismatch",
		failures
	)
	_expect(
		str(standard.get("gate_id", "")) == "CPU_FINALIZATION_PRECONDITION",
		"CPU finalization gate identifier changed",
		failures
	)
	_expect(
		str(standard.get("applies_before", "")) == "TQP-58",
		"CPU finalization no longer applies before TQP-58",
		failures
	)
	var boundary: Dictionary = standard.get("qualification_boundary", {})
	var affinity: Array = boundary.get("logical_cpu_affinity", [])
	_expect(
		int(boundary.get("logical_cpu_limit", -1)) == 3
			and affinity.size() == 3
			and int(affinity[0]) == 0
			and int(affinity[1]) == 1
			and int(affinity[2]) == 2
			and int(boundary.get("build_parallelism_limit", -1)) == 3,
		"CPU finalization three-logical-CPU boundary changed",
		failures
	)
	_expect(
		str(standard.get("status", "")) == "qualified",
		"CPU finalization standard is not qualified",
		failures
	)
	var stages: Array = evidence.get("ordered_closure", [])
	var stage_ids: Array[String] = []
	for stage_value in stages:
		var stage: Dictionary = stage_value
		stage_ids.append(str(stage.get("id", "")))
	_expect(
		stage_ids == ["CPU-C1", "CPU-C2", "CPU-C3"],
		"CPU finalization closure order changed",
		failures
	)
	for stage_value in stages:
		var stage: Dictionary = stage_value
		_expect(
			str(stage.get("status", "")) == "qualified",
			"CPU finalization stage is not qualified: " + str(stage.get("id", "")),
			failures
		)
	_expect(
		(evidence.get("consistency_failures", []) as Array).is_empty(),
		"CPU finalization evidence has consistency failures",
		failures
	)
	var eligible := (
		str(evidence.get("status", "")) == "PASS"
		and bool(evidence.get("retained_complete", false))
		and bool(evidence.get("tqp58_eligible", false))
	)
	var tqp58: Dictionary = milestone_by_id.get("TQP-58", {})
	_expect(eligible, "CPU finalization readiness is no longer eligible", failures)
	_expect(
		"CPU_FINALIZATION_PRECONDITION" in tqp58.get("entry_conditions", []),
		"TQP-58 CPU finalization entry condition is missing",
		failures
	)


static func _validate_cpu_production_closure(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard := JsonLoader.load_dictionary(
		str(program.get("cpu_production_closure_standard", ""))
	)
	var evidence := JsonLoader.load_dictionary(
		str(program.get("cpu_production_closure_evidence", ""))
	)
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.cpu_production_closure_standard.v1",
		"CPU production closure standard schema mismatch",
		failures
	)
	_expect(
		str(evidence.get("schema", ""))
			== "world_transvoxel.terrain_lab.cpu_production_closure_evidence.v1",
		"CPU production closure evidence schema mismatch",
		failures
	)
	_expect(
		str(standard.get("precondition", "")) == "CPU_PRODUCTION_CLOSURE_PRECONDITION"
			and str(evidence.get("precondition", "")) == "CPU_PRODUCTION_CLOSURE_PRECONDITION",
		"CPU production closure precondition identifier changed",
		failures
	)
	var admission: Dictionary = standard.get("admission", {})
	_expect(
		str(standard.get("status", "")) == "qualified"
			and admission.get("admits", []) == ["TQP-58"]
			and bool(admission.get("does_not_select_gpu_architecture", false))
			and bool(admission.get("does_not_claim_public_asset_library_acceptance", false)),
		"CPU production closure admission boundary changed",
		failures
	)
	var expected_order := [
		"TQP-R01_CONSTRUCTION_MATERIAL_OWNERSHIP",
		"TQP-R02_TEMPORAL_STREAMING_CONTINUITY",
		"TQP-R03_GLOBAL_COARSE_COVERAGE_LOCAL_REFINEMENT",
		"TQP-R04_CACHE_PREFETCH_TARGETED_COLLISION_READINESS",
		"TQP-R05_BOUNDED_CPU_PRODUCTION_BASELINE",
		"TQP-R06_SELF_CONTAINED_GODOT_4_7_RELEASE_BUNDLE",
	]
	_expect(
		standard.get("execution_order", []) == expected_order,
		"CPU production closure order changed",
		failures
	)
	var subgate_ids: Array[String] = []
	for subgate_value in evidence.get("subgates", []):
		var subgate: Dictionary = subgate_value
		subgate_ids.append(str(subgate.get("id", "")))
		_expect(
			str(subgate.get("status", "")) == "PASS",
			"CPU production closure subgate did not pass: " + str(subgate.get("id", "")),
			failures
		)
	_expect(
		subgate_ids == ["TQP-R01", "TQP-R02", "TQP-R03", "TQP-R04", "TQP-R05", "TQP-R06"],
		"CPU production closure evidence order changed",
		failures
	)
	var authority_policy: Dictionary = standard.get("authority_policy", {})
	_expect(
		str(authority_policy.get("terrain_authority", "")) == "world-transvoxel"
			and not bool(authority_policy.get("fallback_mesher", true))
			and not bool(authority_policy.get("fallback_field", true))
			and int(authority_policy.get("maximum_logical_cpu_count", -1)) == 3
			and int(authority_policy.get("native_build_jobs", -1)) == 3
			and str(authority_policy.get("engine", "")) == "4.7",
		"CPU production closure authority boundary changed",
		failures
	)
	var affinity: Array = evidence.get("logical_cpu_affinity", [])
	_expect(
		affinity.size() == 3
			and int(affinity[0]) == 0
			and int(affinity[1]) == 1
			and int(affinity[2]) == 2
			and int(evidence.get("native_build_jobs", -1)) == 3,
		"CPU production closure three-logical-CPU boundary changed",
		failures
	)
	_expect(
		str(evidence.get("authority_revision", ""))
			== "d73fd37211797b043797d072020a48a2eaed7383"
			and str(evidence.get("terrain_implementation_revision", ""))
				== "81cb3302b134098786aa988d0a69f8c7353ec4cb"
			and str(evidence.get("terrain_evidence_revision", ""))
				== "50c8759d18f0880231cbbb88294cad2b90bc4efe",
		"CPU production closure revisions changed",
		failures
	)
	var acceptance: Dictionary = standard.get("acceptance", {})
	var measurements: Dictionary = evidence.get("measurements", {})
	var volume_cells: Array = acceptance.get("volume_cells", [])
	_expect(
		volume_cells.size() == 3
			and int(volume_cells[0]) == 2048
			and int(volume_cells[1]) == 256
			and int(volume_cells[2]) == 2048,
		"CPU production closure volume changed",
		failures
	)
	_expect(
		int(measurements.get("broad_scenarios", 0)) == 9
			and int(measurements.get("catalog_pages", 0)) == 299520,
		"CPU production closure broad terrain dimensions changed",
		failures
	)
	var lod_counts: Dictionary = measurements.get("observed_lod_counts", {})
	var all_lods_observed := true
	for lod in range(4):
		all_lods_observed = all_lods_observed and int(lod_counts.get(str(lod), 0)) > 0
	_expect(all_lods_observed, "CPU production closure did not observe LOD0 through LOD3", failures)
	_expect(
		int(measurements.get("global_coarse_roots", -1))
			== int(acceptance.get("global_coarse_roots", -2))
			and int(measurements.get("lod0_equivalent_coverage_cells", -1))
				== int(acceptance.get("lod0_equivalent_coverage_cells", -2)),
		"CPU production closure global coverage changed",
		failures
	)
	_expect(
		int(measurements.get("coarse_ready_latency_usec", 0))
			<= int(acceptance.get("maximum_coarse_ready_latency_usec", -1))
			and int(measurements.get("coverage_overlaps", -1))
				<= int(acceptance.get("maximum_coverage_overlaps", -1))
			and int(measurements.get("generation_errors", -1))
				<= int(acceptance.get("maximum_generation_mismatches", -1))
			and int(measurements.get("broad_topology_failures", -1))
				<= int(acceptance.get("maximum_topology_failures", -1)),
		"CPU production closure broad terrain acceptance regressed",
		failures
	)
	_expect(
		int(measurements.get("frame_samples", 0)) >= int(acceptance.get("minimum_frame_samples", 0))
			and int(measurements.get("scenario_p99_ceiling_usec", 0))
				<= int(acceptance.get("maximum_scenario_p99_usec", -1))
			and int(measurements.get("worst_frame_usec", 0))
				<= int(acceptance.get("maximum_worst_frame_usec", -1)),
		"CPU production closure frame baseline is outside its acceptance envelope",
		failures
	)
	_expect(
		is_zero_approx(float(measurements.get("stutter_fraction_over_100ms", -1.0)))
			and float(measurements.get("average_cpu_cores", 4.0)) <= 3.0,
		"CPU production closure stutter or CPU-capacity boundary regressed",
		failures
	)
	_expect(
		int(measurements.get("repainted_existing_solid_samples", -1)) == 0
			and int(measurements.get("temporal_overlaps", -1)) == 0
			and int(measurements.get("temporal_topology_failures", -1)) == 0
			and int(measurements.get("arrival_storage_requests", -1)) == 0
			and int(measurements.get("arrival_mesh_jobs", -1)) == 0,
		"CPU production closure correctness or readiness regression",
		failures
	)
	_expect(
		int(measurements.get("dig_visual_latency_usec", 0))
			<= int(acceptance.get("maximum_edit_visual_latency_usec", -1))
			and int(measurements.get("construct_visual_latency_usec", 0))
				<= int(acceptance.get("maximum_edit_visual_latency_usec", -1))
			and int(measurements.get("dig_collision_latency_usec", 0))
				<= int(acceptance.get("maximum_edit_collision_latency_usec", -1))
			and int(measurements.get("construct_collision_latency_usec", 0))
				<= int(acceptance.get("maximum_edit_collision_latency_usec", -1)),
		"CPU production closure edit latency regressed",
		failures
	)
	_expect(
		int(measurements.get("temporal_monitored_frames", 0))
			>= int(acceptance.get("minimum_temporal_monitored_frames", 0))
			and int(measurements.get("temporal_topology_samples", 0))
				>= int(acceptance.get("minimum_temporal_topology_samples", 0))
			and int(measurements.get("prefetched_visual_lod0_chunks", 0))
				>= int(acceptance.get("minimum_prefetched_visual_lod0_chunks", 0))
			and int(measurements.get("arrival_collision_latency_usec", 0))
				<= int(acceptance.get("maximum_prefetched_arrival_collision_latency_usec", -1)),
		"CPU production closure temporal or prefetch readiness regressed",
		failures
	)
	var release_bundle: Dictionary = evidence.get("release_bundle", {})
	_expect(
		str(release_bundle.get("version", "")) == "1.1.0-rc1"
			and bool(release_bundle.get("self_contained", false))
			and str(release_bundle.get("clean_install_smoke", "")) == "PASS"
			and str(release_bundle.get("authority_version", "")) == "1.0.16-dev"
			and str(release_bundle.get("backend", "")) == "transvoxel_mit_official"
			and not bool(release_bundle.get("fallback", true))
			and int(release_bundle.get("files", 0)) == int(measurements.get("bundle_files", -1))
			and int(release_bundle.get("bytes", 0)) == int(measurements.get("bundle_bytes", -1))
			and str(release_bundle.get("sha256", ""))
				== "8dc0482fe55b3765ed0bdf376141af2cf6d6f07ff78e855942a731b4d4250f57",
		"CPU production closure release bundle evidence changed",
		failures
	)
	var retained_sources: Array = evidence.get("retained_sources", [])
	_expect(retained_sources.size() == 6, "CPU production closure retained source count changed", failures)
	var expected_source_paths := [
		"artifacts/tqp57_large_terrain_acceptance/tqp57_large_terrain_acceptance_report.json",
		"artifacts/cpu_temporal_continuity/cpu_temporal_continuity_report.json",
		"artifacts/cpu_prefetch_readiness/cpu_prefetch_readiness_report.json",
		"artifacts/cpu_production_closure/cpu_production_closure_report.json",
		"artifacts/cpu_release_bundle/cpu_release_bundle_report.json",
		"artifacts/cpu_release_bundle/world-transvoxel-terrain-cpu-1.1.0-rc1.zip",
	]
	var expected_source_digests := [
		"b936fd3557ba9a95d516b2816accab20c82be339054dfde4574e4e6fd0a79963",
		"3aa03c9347ed915b55aa992eae53ed3c71358d49479785f087fb70e8554e3ee7",
		"c9cc67f42eee272e881c31b0d9a6a9bce99798535a566121c535f958033cb2cc",
		"a0bf52cb134bf0a7ed348538bc777a34bd2e7a5f5e6e6afd4a6dad0e0c81aa31",
		"071c19991c6c6116688f5ada25a42d511e462672188a070bb197befaabf900b0",
		"8dc0482fe55b3765ed0bdf376141af2cf6d6f07ff78e855942a731b4d4250f57",
	]
	for index in range(min(retained_sources.size(), expected_source_paths.size())):
		var retained_value = retained_sources[index]
		var retained: Dictionary = retained_value
		_expect(
			str(retained.get("repository", "")) == "world-transvoxel-terrain"
				and str(retained.get("path", "")) == expected_source_paths[index]
				and str(retained.get("sha256", "")) == expected_source_digests[index],
			"CPU production closure retained source is invalid",
			failures
		)
	_expect(
		str(evidence.get("status", "")) == "PASS"
			and bool(evidence.get("retained_complete", false))
			and bool(evidence.get("tqp58_eligible", false))
			and (evidence.get("consistency_failures", []) as Array).is_empty(),
		"CPU production closure is not eligible",
		failures
	)
	var power: Dictionary = evidence.get("power", {})
	_expect(
		str(power.get("status", "")) == "UNQUALIFIED_NO_TRUSTED_ENERGY_PROVIDER"
			and power.get("cpu_package_watts") == null
			and power.get("whole_system_watts") == null
			and power.get("gpu_board_watts") == null,
		"CPU production closure power claim boundary changed",
		failures
	)
	var tqp58: Dictionary = milestone_by_id.get("TQP-58", {})
	var required_preconditions := [
		"CPU_FINALIZATION_PRECONDITION",
		"CPU_PRODUCTION_CLOSURE_PRECONDITION",
		"CPU_HUMAN_BASELINE_TRACE_PRECONDITION",
	]
	_expect(
		tqp58.get("entry_conditions", []) == required_preconditions,
		"TQP-58 CPU production closure entry condition is missing",
		failures
	)
	var backend_decision := JsonLoader.load_dictionary(str(program.get("backend_decision", "")))
	var gpu_eligibility: Dictionary = backend_decision.get(
		"gpu_architecture_decision_eligibility", {}
	)
	_expect(
		gpu_eligibility.get("required_preconditions", []) == required_preconditions,
		"backend architecture decision is missing the CPU production closure",
		failures
	)


static func _validate_cpu_human_baseline_trace(
	program: Dictionary,
	milestone_by_id: Dictionary,
	failures: Array[String]
) -> void:
	var standard := JsonLoader.load_dictionary(
		str(program.get("cpu_human_baseline_trace_standard", ""))
	)
	var evidence := JsonLoader.load_dictionary(
		str(program.get("cpu_human_baseline_trace_evidence", ""))
	)
	var standard_affinity: Array = standard.get("logical_cpu_affinity", [])
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.cpu_human_baseline_trace_standard.v1"
			and str(standard.get("precondition", ""))
				== "CPU_HUMAN_BASELINE_TRACE_PRECONDITION"
			and str(standard.get("applies_before", "")) == "TQP-58"
			and standard_affinity.size() == 3
			and int(standard_affinity[0]) == 0
			and int(standard_affinity[1]) == 1
			and int(standard_affinity[2]) == 2
			and not bool(standard.get("fallback_allowed", true)),
		"CPU human baseline/trace standard changed",
		failures
	)
	var ordered_ids: Array[String] = []
	for step_value in standard.get("ordered_steps", []):
		ordered_ids.append(str((step_value as Dictionary).get("id", "")))
	_expect(
		ordered_ids == ["CPU-B1", "CPU-B2", "CPU-B3"],
		"CPU human baseline/trace order changed",
		failures
	)
	var continuation_ids: Array[String] = []
	for step_value in standard.get("cpu_b3_continuation", []):
		continuation_ids.append(str((step_value as Dictionary).get("id", "")))
	_expect(
		continuation_ids == ["CPU-B3A", "CPU-B3B", "CPU-B3C", "CPU-B3D", "CPU-B3E"],
		"CPU-B3 continuation order changed",
		failures
	)
	var evidence_steps: Array = evidence.get("steps", [])
	var step_states: Array[String] = []
	for step_value in evidence_steps:
		var step: Dictionary = step_value
		step_states.append("%s:%s" % [str(step.get("id", "")), str(step.get("status", ""))])
	var evidence_affinity: Array = evidence.get("logical_cpu_affinity", [])
	_expect(
		str(evidence.get("schema", ""))
			== "world_transvoxel.terrain_lab.cpu_human_baseline_trace_readiness.v1"
			and str(evidence.get("status", "")) == "PASS"
			and bool(evidence.get("retained_complete", false))
			and bool(evidence.get("tqp58_eligible", false))
			and evidence_affinity.size() == 3
			and int(evidence_affinity[0]) == 0
			and int(evidence_affinity[1]) == 1
			and int(evidence_affinity[2]) == 2
			and (evidence.get("consistency_failures", []) as Array).is_empty()
			and ",".join(step_states) == "CPU-B1:PASS,CPU-B2:PASS,CPU-B3:PASS",
		"CPU human baseline/trace readiness changed",
		failures
	)
	if not evidence_steps.is_empty():
		var baseline_step: Dictionary = evidence_steps[0]
		_expect(
			str(baseline_step.get("evidence_commit", ""))
				== "32adc3164b4bbd7b2b13b0fccbfefadd980231d1"
				and str(baseline_step.get("measurement_commit", ""))
					== "413eaa5c9c612bd0ee3bf939b233723d9d2a8080"
				and str(baseline_step.get("authority_commit", ""))
					== "f30818b9ce0f0b3f9ddb75726db5522d97167404"
				and str(baseline_step.get("evidence_sha256", ""))
					== "5f2552537503237572268565f98fd2f7683a6e2ef8097497a1867d0c51fdc34f"
				and str(baseline_step.get("result", "")) == "MEASURED_TARGET_MISS",
			"CPU-B1 evidence identity changed",
			failures
		)
	if evidence_steps.size() >= 3:
		var attribution_step: Dictionary = evidence_steps[1]
		_expect(
			str(attribution_step.get("evidence_commit", ""))
				== "0950e3dfece191b25eb8094fbf6c1217ffe0207f"
				and str(attribution_step.get("measurement_commit", ""))
					== "5c07dc6ea7580533fac79e185f0e20d2659e8af2"
				and str(attribution_step.get("authority_commit", ""))
					== "f7a583d9e22ae39bc4d9e99178da3f782a2abe61"
				and str(attribution_step.get("evidence_sha256", ""))
					== "d5cced62da4a89728027d16d65a2ffb6732fa2f259abbfc857b05bdf4d86ea76"
				and str(attribution_step.get("result", "")) == "CAUSAL_ATTRIBUTION_PASS",
			"CPU-B2 evidence identity changed",
			failures
		)
		var remediation_step: Dictionary = evidence_steps[2]
		var remaining_reviews: Array = remediation_step.get("remaining", [])
		_expect(
			str(remediation_step.get("evidence_commit", ""))
				== "53eb8e6b1c9a7900c26c57f04e5947aada320518"
				and str(remediation_step.get("candidate_commit", ""))
					== "9518d303f895845efce8afea04e763f24dea695c"
				and str(remediation_step.get("authority_commit", ""))
					== "b35491948e126f6f660f64ad89532acbc50895bc"
				and str(remediation_step.get("evidence_sha256", ""))
					== "0c00b7bb64ca2f905a8626ec38832a8ade05f11cdbab5968372cd01ac6ca513b"
				and str(remediation_step.get("result", ""))
					== "AUTHORITATIVE_CPU_BASELINE_FROZEN_PERFORMANCE_TARGET_MISSED"
				and str(remediation_step.get("human_review_commit", ""))
					== "bf59a98f51ada8cd9ef6fe1a71100984b87046c0"
				and str(remediation_step.get("human_review_sha256", ""))
					== "81142cdc1ac5f3ffeaccd5fc8e6d2ca6bf5e984433ed2eae3affcfc86f55da93"
				and str(remediation_step.get("human_review_status", ""))
					== "ACCEPTED_WITH_KNOWN_LIMITATIONS"
				and str(remediation_step.get("exhaustion_review_commit", ""))
					== "53eb8e6b1c9a7900c26c57f04e5947aada320518"
				and str(remediation_step.get("exhaustion_review_sha256", ""))
					== "0c00b7bb64ca2f905a8626ec38832a8ade05f11cdbab5968372cd01ac6ca513b"
				and str(remediation_step.get("exhaustion_review_status", "")) == "COMPLETE"
				and str(remediation_step.get("exhaustion_decision", ""))
					== "EXHAUSTED_STANDARD_CPU_REMEDIES_GPU_DECISION_ELIGIBLE"
				and remaining_reviews.is_empty(),
			"CPU-B3 evidence identity changed",
			failures
		)
		var cpu_b3: Dictionary = evidence.get("cpu_b3", {})
		var cpu_b3_medians: Dictionary = cpu_b3.get("trace_off_medians", {})
		var human_review: Dictionary = cpu_b3.get("human_review", {})
		var exhaustion_review: Dictionary = cpu_b3.get("independent_exhaustion_review", {})
		var cpu_b3a_attempt: Dictionary = cpu_b3.get("cpu_b3a_attempt", {})
		var final_closure: Dictionary = cpu_b3.get("final_closure", {})
		_expect(
			str(cpu_b3.get("status", "")) == "PASS"
				and is_equal_approx(
					float(cpu_b3_medians.get("relocation_to_visual_ready_ms", 0.0)),
					3822.632
				)
				and is_equal_approx(float(cpu_b3_medians.get("frame_p99_ms", 0.0)), 25.397)
				and int(cpu_b3_medians.get("blocked_frames", -1)) == 11
				and bool(
					(cpu_b3.get("rejected_viewer_region_experiment", {}) as Dictionary).get(
						"reverted", false
					)
				)
				and str(human_review.get("status", ""))
					== "ACCEPTED_WITH_KNOWN_LIMITATIONS"
				and not bool(human_review.get("new_rejection_level_correctness_failure", true))
				and human_review.get("release_blocking_limitations", []) == [
					"TEMPORARY_LOD_SEE_THROUGH_SLICE",
					"RESIDUAL_FLIGHT_RESPONSIVENESS",
					"RELOCATION_FIRST_EDIT_DELAY",
				]
				and str(exhaustion_review.get("review_status", "")) == "COMPLETE"
				and str(final_closure.get("status", ""))
					== "PASS_CPU_REFERENCE_FROZEN_PERFORMANCE_TARGET_MISSED"
				and str(final_closure.get("authority_commit", ""))
					== "b35491948e126f6f660f64ad89532acbc50895bc"
				and int(final_closure.get("native_debug_release_executables_passed", 0)) == 62
				and int(final_closure.get("godot_smoke_scripts_passed", 0)) == 10
				and int(final_closure.get("causal_drops_or_gaps", -1)) == 0
				and bool(final_closure.get("standard_cpu_remedies_exhausted", false))
				and bool(final_closure.get("cpu_b3_pass", false))
				and bool(final_closure.get("tqp58_eligible", false))
				and not bool(final_closure.get("gpu_backend_promoted", true)),
			"CPU-B3 retained measurements changed",
			failures
		)
		_expect(
			str(cpu_b3a_attempt.get("status", "")) == "IN_PROGRESS_EVENT_NOT_REPRODUCED"
				and str(cpu_b3a_attempt.get("classification", ""))
					== "BOUNDED_ROAD_FILTERED_ROUTE_NO_EVENT"
				and str(cpu_b3a_attempt.get("evidence_commit", ""))
					== "cb50b7dd1134f1dbbd0ac0d2f0837177ef703141"
				and str(cpu_b3a_attempt.get("measurement_commit", ""))
					== "ca9ce0f42ae4cb411a54d0b6c84b6c9dc52332de"
				and str(cpu_b3a_attempt.get("authority_commit", ""))
					== "a8bba838a8860ba30bdb79887ad66ba17028ad18"
				and str(cpu_b3a_attempt.get("result_sha256", ""))
					== "349f0ee8a62ef154c9544ba79c367175b7a166e5ed2357001406991a87bb9027"
				and int(cpu_b3a_attempt.get("candidate_rays", -1)) == 64
				and int(cpu_b3a_attempt.get("excluded_authored_road_rays", -1)) == 64
				and int(cpu_b3a_attempt.get("road_clear_rendered_rays", -1)) == 0
				and int(cpu_b3a_attempt.get("road_clear_direct_opening_rays", -1)) == 0
				and int(cpu_b3a_attempt.get("native_event_count", -1)) == 72723
				and int(cpu_b3a_attempt.get("native_consumer_gap_event_count", -1)) == 0
				and int(cpu_b3a_attempt.get("native_local_dropped_event_count", -1)) == 0
				and int(cpu_b3a_attempt.get("downstream_dropped_event_count", -1)) == 0
				and not bool(cpu_b3a_attempt.get("screenshots_are_authority", true))
				and not bool(cpu_b3a_attempt.get("aggregate_queue_counts_are_authority", true))
				and not bool(cpu_b3a_attempt.get("performance_baseline_allowed", true))
				and not bool(cpu_b3a_attempt.get("implementation_changed", true))
				and not bool(cpu_b3a_attempt.get("terrain_behavior_changed", true)),
			"CPU-B3A bounded no-event evidence changed",
			failures
		)
	var baseline: Dictionary = evidence.get("baseline", {})
	var exact_ready: Array = baseline.get("relocation_to_exact_visual_ready_ms", [])
	var blocked_frames: Array = baseline.get("maximum_consecutive_blocked_frames", [])
	_expect(
		int(baseline.get("runs", 0)) == 3
			and exact_ready.size() == 3
			and is_equal_approx(float(exact_ready[0]), 14532.785)
			and is_equal_approx(float(exact_ready[1]), 316.719)
			and is_equal_approx(float(exact_ready[2]), 13206.199)
			and blocked_frames.size() == 3
			and int(blocked_frames[0]) == 4
			and int(blocked_frames[1]) == 30
			and int(blocked_frames[2]) == 6,
		"CPU-B1 retained measurements changed",
		failures
	)
	var tqp58: Dictionary = milestone_by_id.get("TQP-58", {})
	_expect(
		str(tqp58.get("status", "")) == "qualified",
		"TQP-58 decision must be qualified after CPU-B1 through CPU-B3 pass",
		failures
	)
	var backend_decision := JsonLoader.load_dictionary(str(program.get("backend_decision", "")))
	var gpu_eligibility: Dictionary = backend_decision.get(
		"gpu_architecture_decision_eligibility", {}
	)
	_expect(
		str(gpu_eligibility.get("status", ""))
			== "QUALIFIED_TQP58_DECISION_COMPLETE",
		"GPU architecture decision eligibility differs from retained TQP-58 evidence",
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
