@tool
extends RefCounted
class_name WtTerrainLabCompletionQualification

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)

const BACKEND_DECISION_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/backend_architecture_decision.json"
)
const BLOCKERS_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/program_blockers.json"
)
const CPU_FINALIZATION_PATH := (
	"res://labs/terrain_lab/results/cpu_finalization_readiness_windows.json"
)


static func run() -> Dictionary:
	var failures: Array[String] = []
	var backend_decision := JsonLoader.load_dictionary(BACKEND_DECISION_PATH)
	var blockers := JsonLoader.load_dictionary(BLOCKERS_PATH)
	var cpu_finalization := JsonLoader.load_dictionary(CPU_FINALIZATION_PATH)
	_expect(
		str(backend_decision.get("schema", ""))
			== "world_transvoxel.terrain_lab.backend_architecture_decision.v1",
		"backend decision is missing or invalid",
		failures
	)
	_expect(
		str(backend_decision.get("reference_backend", "")) == "world_transvoxel_cpu",
		"CPU authority changed without differential qualification",
		failures
	)
	var decisions: Dictionary = backend_decision.get("decisions", {})
	for key in ["field_evaluation", "meshing", "buffer_residency", "collision"]:
		_expect(decisions.has(key), "backend decision missing: " + key, failures)
	_expect(
		str(blockers.get("schema", "")) == "world_transvoxel.terrain_lab.program_blockers.v1",
		"program blockers are missing or invalid",
		failures
	)
	_expect(
		str(cpu_finalization.get("schema", ""))
			== "world_transvoxel.terrain_lab.cpu_finalization_readiness.v1",
		"CPU finalization evidence is missing or invalid",
		failures
	)
	var cpu_finalization_passed := (
		str(cpu_finalization.get("status", "")) == "PASS"
		and bool(cpu_finalization.get("retained_complete", false))
		and bool(cpu_finalization.get("tqp58_eligible", false))
		and (cpu_finalization.get("consistency_failures", []) as Array).is_empty()
	)
	var blocker_records: Array = blockers.get("blockers", [])
	var blocker_by_milestone := {}
	for record_value in blocker_records:
		var record: Dictionary = record_value
		var milestone := str(record.get("milestone", ""))
		_expect(not blocker_by_milestone.has(milestone), "duplicate blocker: " + milestone, failures)
		_expect(not str(record.get("code", "")).is_empty(), milestone + " blocker code missing", failures)
		_expect(not str(record.get("owner", "")).is_empty(), milestone + " blocker owner missing", failures)
		_expect(not str(record.get("exit", "")).is_empty(), milestone + " blocker exit missing", failures)
		blocker_by_milestone[milestone] = record
	for milestone in [
		"TQP-58", "TQP-59", "TQP-60", "TQP-61", "TQP-62", "TQP-63", "TQP-64", "TQP-71",
	]:
		_expect(blocker_by_milestone.has(milestone), "missing fail-closed blocker: " + milestone, failures)
	_expect(blocker_by_milestone.size() == 8, "blocker catalog contains an unexpected milestone", failures)
	_expect(
		not cpu_finalization_passed,
		"CPU finalization passed but the TQP-58 blocker was not retired",
		failures
	)
	_expect(
		not ClassDB.class_exists("WtGpuTerrainBackend"),
		"GPU backend exists but blocker catalog still declares it absent",
		failures
	)
	_expect(
		not ClassDB.class_exists("WtTerrainWorld"),
		"production terrain addon leaked into the Terrain Lab runtime dependency boundary",
		failures
	)
	return {
		"schema": "world_transvoxel.terrain_lab.completion_qualification.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"scope_status": {
			"TQP-51": "qualified_candidate_production_addon_boundary_v1",
			"TQP-52": "qualified_production_runtime_contract_v1",
			"TQP-53": "qualified_production_authoring_workflow_v1",
			"TQP-54": "qualified_downstream_migration_v1",
			"TQP-55": "qualified_windows_cpu_release_matrix_v1",
			"TQP-56": "qualified_windows_cpu_wrapper_and_retained_long_haul_v1",
			"TQP-57": "production_cpu_terrain_standard_1_0_limited_windows_reference_release",
			"TQP-58": "blocked_cpu_finalization_incomplete",
			"TQP-59": "blocked",
			"TQP-60": "blocked",
			"TQP-61": "blocked",
			"TQP-62": "blocked",
			"TQP-63": "blocked",
			"TQP-64": "blocked",
			"TQP-71": "blocked",
		},
		"backend_decision": backend_decision,
		"cpu_finalization": cpu_finalization,
		"blockers": blocker_records,
		"specified_scope": [],
		"qualified_scope": [
			"TQP-51 pinned standalone candidate-addon boundary without a Terrain Lab runtime dependency",
			"TQP-52 pinned runtime API profiles readiness back-pressure and cancellation contract",
			"TQP-53 bounded production authoring inspection repro and material-payload workflow",
			"TQP-54 exact pinned downstream migration and representative runtime behavior",
			"TQP-55 pinned Windows CPU production release matrix and deterministic package",
			"TQP-56 bounded production-wrapper plus retained 1800-second long-haul evidence",
			"TQP-57 CPU Terrain Standard 1.0 standalone limited Windows reference release",
		],
		"explicitly_unqualified_scope": [
			"CPU finalization and CPU architecture exhaustion",
			"GPU backend milestones TQP-58 through TQP-64",
			"TQP-71 networking and recovery",
		],
		"failures": failures,
	}


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
