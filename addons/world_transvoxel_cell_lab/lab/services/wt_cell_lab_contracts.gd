@tool
extends RefCounted
class_name WtCellLabContracts

const REPORT_SCHEMA := "world_transvoxel.cell_lab.report.v4"
const PREVIOUS_REPORT_SCHEMA := "world_transvoxel.cell_lab.report.v3"
const LEGACY_REPORT_SCHEMA := "world_transvoxel.cell_lab.report.v2"
const ORIGINAL_REPORT_SCHEMA := "world_transvoxel.cell_lab.report.v1"
const REPRO_SCHEMA := "world_transvoxel.cell_lab.repro.v2"
const LEGACY_REPRO_SCHEMA := "world_transvoxel.cell_lab.repro.v1"
const REGULAR_CASE_CORPUS_SCHEMA := "world_transvoxel.cell_lab.regular_case_corpus.v2"
const TRANSITION_CASE_CORPUS_SCHEMA := "world_transvoxel.cell_lab.transition_case_corpus.v2"
const CHUNK_LOD_VALIDATION_SCHEMA := "world_transvoxel.cell_lab.chunk_lod_validation.v2"
const EDIT_SEQUENCE_VALIDATION_SCHEMA := "world_transvoxel.cell_lab.edit_sequence_validation.v2"
const PERFORMANCE_BASELINES_SCHEMA := "world_transvoxel.cell_lab.performance_baselines.v2"
const STANDARDS_CORPUS_SCHEMA := "world_transvoxel.cell_lab.standards_corpus.v1"
const INTEGRATION_IMPORT_SCHEMA := "world_transvoxel.cell_lab.integration_import.v1"
const REFERENCE_TERRAIN_FIXTURE_SCHEMA := "world_transvoxel.cell_lab.reference_terrain_fixture.v2"
const REFERENCE_TERRAIN_VALIDATION_SCHEMA := "world_transvoxel.cell_lab.reference_terrain_validation.v2"
const TERRAIN_OBSERVATORY_SCHEMA := "world_transvoxel.cell_lab.terrain_observatory.v1"
const TERRAIN_OBSERVATORY_VALIDATION_SCHEMA := "world_transvoxel.cell_lab.terrain_observatory_validation.v1"
const NATIVE_DEPENDENCY_VALIDATION_SCHEMA := "world_transvoxel.cell_lab.native_dependency_validation.v1"
const AUTHORITY_STRESS_VALIDATION_SCHEMA := "world_transvoxel.cell_lab.authority_stress_validation.v1"
const QUALIFICATION_SUITE_SCHEMA := "world_transvoxel.cell_lab.qualification_suite.v1"
const QUALIFICATION_STANDARD_SCHEMA := "world_transvoxel.cell_lab.qualification_standard.v1"
const CORRECTNESS_QUALIFICATION_SCHEMA := "world_transvoxel.cell_lab.correctness_qualification.v1"
const CORRECTNESS_QUALIFICATION_STANDARD_SCHEMA := "world_transvoxel.cell_lab.correctness_qualification_standard.v1"
const ADVERSARIAL_CORPUS_SCHEMA := "world_transvoxel.cell_lab.adversarial_scalar_field_corpus.v1"
const FAILURE_REDUCTION_SCHEMA := "world_transvoxel.cell_lab.failure_reduction.v1"
const SPECIFICATION_VALIDATION_SCHEMA := "world_transvoxel.cell_lab.independent_specification_validation.v1"
const RUNTIME_QUALIFICATION_SCHEMA := "world_transvoxel.cell_lab.runtime_qualification.v1"
const RUNTIME_QUALIFICATION_STANDARD_SCHEMA := "world_transvoxel.cell_lab.runtime_qualification_standard.v1"
const EDIT_STRESS_SCHEMA := "world_transvoxel.cell_lab.edit_stress_corpus.v1"
const SCALING_QUALIFICATION_SCHEMA := "world_transvoxel.cell_lab.scaling_qualification.v1"
const MEMORY_QUALIFICATION_SCHEMA := "world_transvoxel.cell_lab.memory_qualification.v1"
const RENDERING_QUALITY_SCHEMA := "world_transvoxel.cell_lab.rendering_quality_qualification.v1"
const COLLISION_QUERY_SCHEMA := "world_transvoxel.cell_lab.collision_query_qualification.v1"
const STREAMING_QUALIFICATION_SCHEMA := "world_transvoxel.cell_lab.streaming_qualification.v1"
const PERSISTENCE_QUALIFICATION_SCHEMA := "world_transvoxel.cell_lab.persistence_qualification.v1"
const PERSISTENCE_ENVELOPE_SCHEMA := "world_transvoxel.cell_lab.persistence_envelope.v1"
const RELEASE_QUALIFICATION_SCHEMA := "world_transvoxel.cell_lab.release_qualification.v1"
const RELEASE_QUALIFICATION_STANDARD_SCHEMA := "world_transvoxel.cell_lab.release_qualification_standard.v1"
const INTEGRATION_PARITY_SCHEMA := "world_transvoxel.cell_lab.integration_parity_corpus.v1"
const PLATFORM_RENDERER_MATRIX_SCHEMA := "world_transvoxel.cell_lab.platform_renderer_matrix.v1"
const RELEASE_BUNDLE_SCHEMA := "world_transvoxel.cell_lab.release_bundle.v1"
const UPSTREAM_GOVERNANCE_SCHEMA := "world_transvoxel.cell_lab.upstream_correction_governance.v1"

const NATIVE_REGULAR_IMPLEMENTATION := "native_transvoxel_regular_cell_probe_v1"
const NATIVE_AUTHORITY := "NATIVE_TRANSVOXEL_BACKEND_AUTHORITATIVE"
const CELL_PROBE_CORRECTNESS_CLAIM := "exact_regular_and_transition_cell_backend_probe_v2"
const LAB_CORRECTNESS_CLAIM := "release_qualified_transvoxel_terrain_authority_probe_v7"
const LAB_SCOPE := "cell_first_transvoxel_preview_and_validator"
const PRIMARY_VALIDATION_DOMAIN := "volumetric_terrain"
const PRIMITIVE_SCOPE := "transvoxel_scalar_field_cell_unit"
const VALIDATION_STANDARD := "world_transvoxel_native_authoritative_no_fallback"
const AUTHORITY_MODEL := "world_transvoxel_is_implementation_authority_under_test"
const UPSTREAM_CORRECTION_POLICY := "proven_lab_repro_drives_world_transvoxel_fix"
const INTEGRATION_GAME_ROLE := "downstream_proving_ground_not_correctness_authority"
const INTEGRATION_GAME_DIAGNOSTIC_POLICY := "reduce_game_artifact_to_lab_repro_then_classify_fix_layer"
const CHUNK_PROBE_IMPLEMENTATION := "native_transvoxel_multilod_chunk_mesher_probe_v2"
const CHUNK_PROBE_CELLS_PER_AXIS := 16
const REFERENCE_TERRAIN_IMPLEMENTATION := "native_transvoxel_canonical_multichunk_terrain_v2"
const REFERENCE_TERRAIN_ROLE := "canonical_deterministic_terrain_standard_not_production_runtime"
const TERRAIN_OBSERVATORY_ROLE := "derived_inspection_and_measurement_of_authoritative_reference_terrain"

const SOURCE_LAYERS := [
	"unknown",
	"world_transvoxel",
	"integration",
	"runtime",
	"gameplay",
]
const EXPECTED_LABELS := [
	"passing_standard",
	"known_failure",
	"fixed_bug",
	"investigation",
]
const CHUNK_FACE_NAMES := [
	"NegativeX",
	"PositiveX",
	"NegativeY",
	"PositiveY",
	"NegativeZ",
	"PositiveZ",
]
const TRANSITION_ORIENTATION_NAMES := [
	"PositiveX",
	"NegativeX",
	"PositiveY",
	"NegativeY",
	"PositiveZ",
	"NegativeZ",
]
const REGULAR_CORNER_COUNT := 8
const TRANSITION_SAMPLE_COUNT := 9
const TRANSITION_TOPOLOGY_SAMPLE_COUNT := 13
const TRANSITION_ORIENTATION_POSITIVE_Z := 4


static func authority_metadata() -> Dictionary:
	return {
		"lab_scope": LAB_SCOPE,
		"primary_validation_domain": PRIMARY_VALIDATION_DOMAIN,
		"primitive_scope": PRIMITIVE_SCOPE,
		"validation_standard": VALIDATION_STANDARD,
		"authority_model": AUTHORITY_MODEL,
		"upstream_correction_policy": UPSTREAM_CORRECTION_POLICY,
		"integration_game_role": INTEGRATION_GAME_ROLE,
		"integration_game_diagnostic_policy": INTEGRATION_GAME_DIAGNOSTIC_POLICY,
		"reference_terrain_role": REFERENCE_TERRAIN_ROLE,
		"terrain_observatory_role": TERRAIN_OBSERVATORY_ROLE,
	}
