@tool
extends Node
class_name WtTransvoxelTerrainLab

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const ProgramValidator := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_program_validator.gd"
)
const FoundationQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_foundation_qualification.gd"
)
const EditQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_edit_qualification.gd"
)
const MaterialQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_material_qualification.gd"
)
const SystemQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_system_qualification.gd"
)
const NativeAdaptiveQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_adaptive_qualification.gd"
)
const StructuralQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_structural_qualification.gd"
)
const CompletionQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_completion_qualification.gd"
)

const PROGRAM_MANIFEST_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/program_manifest.json"
)
const NATIVE_DEPENDENCY_CLASS := "WorldTransvoxelCellProbe"
const OPTIONAL_TERRAIN_DEPENDENCY_CLASS := "WtTerrainWorld"


func describe_program() -> Dictionary:
	return JsonLoader.load_dictionary(PROGRAM_MANIFEST_PATH)


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
	return ProgramValidator.validate(describe_program(), describe_dependencies())


func qualify_foundation() -> Dictionary:
	return FoundationQualification.run()


func qualify_edit_semantics() -> Dictionary:
	return EditQualification.run()


func qualify_material_surface() -> Dictionary:
	return MaterialQualification.run()


func qualify_terrain_systems() -> Dictionary:
	return SystemQualification.run()


func qualify_native_adaptive_terrain() -> Dictionary:
	return NativeAdaptiveQualification.run()


func qualify_structural_world() -> Dictionary:
	return StructuralQualification.run()


func qualify_program_completion() -> Dictionary:
	return CompletionQualification.run()
