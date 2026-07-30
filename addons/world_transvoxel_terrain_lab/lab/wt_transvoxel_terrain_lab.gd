@tool
extends Node
class_name WtTransvoxelTerrainLab

const PROGRAM_MANIFEST_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/program_manifest.json"
)
const PROGRAM_SCHEMA := "world_transvoxel.terrain_lab.program.v1"
const LAB_SCOPE := "experimental_terrain_qualification"
const NATIVE_DEPENDENCY_CLASS := "WorldTransvoxelCellProbe"
const OPTIONAL_TERRAIN_DEPENDENCY_CLASS := "WtTerrainWorld"


func describe_program() -> Dictionary:
	if not FileAccess.file_exists(PROGRAM_MANIFEST_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(PROGRAM_MANIFEST_PATH)
	)
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	return {}


func describe_dependencies() -> Dictionary:
	var native_available := ClassDB.class_exists(NATIVE_DEPENDENCY_CLASS)
	return {
		"schema": "world_transvoxel.terrain_lab.dependencies.v1",
		"status": "PASS" if native_available else "FAIL",
		"required": {
			"world_transvoxel": native_available,
		},
		"optional": {
			"world_transvoxel_terrain": ClassDB.class_exists(
				OPTIONAL_TERRAIN_DEPENDENCY_CLASS
			),
		},
		"forbidden": [
			"world_transvoxel_cell_lab",
		],
	}


func validate_program_boundary() -> Dictionary:
	var program := describe_program()
	var dependencies := describe_dependencies()
	var milestones: Array = program.get("milestones", [])
	var failures: Array[String] = []
	if str(program.get("schema", "")) != PROGRAM_SCHEMA:
		failures.append("program schema mismatch")
	if str(program.get("lab_scope", "")) != LAB_SCOPE:
		failures.append("terrain lab scope mismatch")
	if str(program.get("production_status", "")) != "NOT_PRODUCTION":
		failures.append("terrain lab must not claim production status")
	if milestones.size() != 46:
		failures.append("expected 46 proposed milestones")
	for index in range(milestones.size()):
		var milestone: Dictionary = milestones[index]
		var expected_id := "TQP-%02d" % (index + 1)
		if str(milestone.get("id", "")) != expected_id:
			failures.append("milestone sequence mismatch at " + expected_id)
			break
		if str(milestone.get("status", "")) != "proposed":
			failures.append(expected_id + " advanced without qualification")
			break
	var runtime_dependencies: Array = program.get("runtime_dependencies", [])
	if runtime_dependencies != ["world_transvoxel"]:
		failures.append("current runtime dependency boundary changed")
	if "world_transvoxel_cell_lab" not in program.get(
		"forbidden_dependencies",
		[]
	):
		failures.append("Cell Lab dependency prohibition is missing")
	if str(dependencies.get("status", "")) != "PASS":
		failures.append("pinned native dependency is unavailable")
	return {
		"schema": "world_transvoxel.terrain_lab.boundary_validation.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"milestone_count": milestones.size(),
		"proposed_milestone_count": _count_status(milestones, "proposed"),
		"dependencies": dependencies,
		"failures": failures,
	}


func _count_status(milestones: Array, status_value: String) -> int:
	var count := 0
	for milestone_value in milestones:
		var milestone: Dictionary = milestone_value
		if str(milestone.get("status", "")) == status_value:
			count += 1
	return count
