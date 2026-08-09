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


static func run() -> Dictionary:
	var failures: Array[String] = []
	var backend_decision := JsonLoader.load_dictionary(BACKEND_DECISION_PATH)
	var blockers := JsonLoader.load_dictionary(BLOCKERS_PATH)
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
		"TQP-55", "TQP-56", "TQP-57",
		"TQP-59", "TQP-60", "TQP-61", "TQP-62", "TQP-63", "TQP-64", "TQP-71",
	]:
		_expect(blocker_by_milestone.has(milestone), "missing fail-closed blocker: " + milestone, failures)
	_expect(blocker_by_milestone.size() == 10, "blocker catalog contains an unexpected milestone", failures)
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
			"TQP-55": "blocked",
			"TQP-56": "blocked",
			"TQP-57": "blocked",
			"TQP-58": "specified_pending_candidate_benefit_measurement",
			"TQP-59": "blocked",
			"TQP-60": "blocked",
			"TQP-61": "blocked",
			"TQP-62": "blocked",
			"TQP-63": "blocked",
			"TQP-64": "blocked",
			"TQP-71": "blocked",
		},
		"backend_decision": backend_decision,
		"blockers": blocker_records,
		"specified_scope": [
			"TQP-58 CPU-primary backend architecture decision and candidate promotion boundaries",
		],
		"qualified_scope": [
			"TQP-51 pinned standalone candidate-addon boundary without a Terrain Lab runtime dependency",
			"TQP-52 pinned runtime API profiles readiness back-pressure and cancellation contract",
			"TQP-53 bounded production authoring inspection repro and material-payload workflow",
			"TQP-54 exact pinned downstream migration and representative runtime behavior",
		],
		"explicitly_unqualified_scope": [
			"CPU production release matrix certification and release milestones TQP-55 through TQP-57",
			"GPU backend milestones TQP-59 through TQP-64",
			"TQP-58 measured GPU candidate benefit",
			"TQP-71 networking and recovery",
		],
		"failures": failures,
	}


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
