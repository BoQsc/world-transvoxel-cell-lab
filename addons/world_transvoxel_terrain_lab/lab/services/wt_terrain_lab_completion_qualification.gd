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
	for index in range(53, 65):
		var milestone := "TQP-%02d" % index
		_expect(blocker_by_milestone.has(milestone), "missing fail-closed blocker: " + milestone, failures)
	_expect(
		not ClassDB.class_exists("WtGpuTerrainBackend"),
		"GPU backend exists but blocker catalog still declares it absent",
		failures
	)
	_expect(
		not ClassDB.class_exists("WtTerrainWorld"),
		"production terrain addon exists but blocker catalog still declares it absent",
		failures
	)
	return {
		"schema": "world_transvoxel.terrain_lab.completion_qualification.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"scope_status": {
			"TQP-52": "specified_pending_candidate_benefit_measurement",
			"TQP-53": "blocked",
			"TQP-54": "blocked",
			"TQP-55": "blocked",
			"TQP-56": "blocked",
			"TQP-57": "blocked",
			"TQP-58": "blocked",
			"TQP-59": "blocked",
			"TQP-60": "blocked",
			"TQP-61": "blocked",
			"TQP-62": "blocked",
			"TQP-63": "blocked",
			"TQP-64": "blocked",
		},
		"backend_decision": backend_decision,
		"blockers": blocker_records,
		"specified_scope": [
			"TQP-52 CPU-primary backend architecture decision and candidate promotion boundaries",
		],
		"explicitly_unqualified_scope": [
			"GPU backend milestones TQP-53 through TQP-57",
			"production milestones TQP-58 through TQP-64",
			"TQP-52 measured GPU candidate benefit",
		],
		"failures": failures,
	}


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
