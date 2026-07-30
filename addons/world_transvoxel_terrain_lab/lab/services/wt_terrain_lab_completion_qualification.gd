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
	for index in range(35, 47):
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
			"TQP-34": "specified_pending_candidate_benefit_measurement",
			"TQP-35": "blocked",
			"TQP-36": "blocked",
			"TQP-37": "blocked",
			"TQP-38": "blocked",
			"TQP-39": "blocked",
			"TQP-40": "blocked",
			"TQP-41": "blocked",
			"TQP-42": "blocked",
			"TQP-43": "blocked",
			"TQP-44": "blocked",
			"TQP-45": "blocked",
			"TQP-46": "blocked",
		},
		"backend_decision": backend_decision,
		"blockers": blocker_records,
		"specified_scope": [
			"TQP-34 CPU-primary backend architecture decision and candidate promotion boundaries",
		],
		"explicitly_unqualified_scope": [
			"GPU backend milestones TQP-35 through TQP-39",
			"production milestones TQP-40 through TQP-46",
			"TQP-34 measured GPU candidate benefit",
		],
		"failures": failures,
	}


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
