@tool
extends RefCounted
class_name WtTerrainLabNativeAdaptiveQualification

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


static func run() -> Dictionary:
	var field_validation := NativeFieldEvidence.validate_retained()
	var adaptive_lod_validation := AdaptiveLodEvidence.validate_retained()
	var transition_validation := TransitionAssemblyEvidence.validate_retained()
	var boundary_validation := BoundaryEnclosureEvidence.validate_retained()
	var oracle_validation := IndependentOracleEvidence.validate_retained()
	var adversarial_validation := AdversarialCorpusEvidence.validate_retained()
	var dynamic_publication_validation := DynamicLodPublicationEvidence.validate_retained()
	var edit_invalidation_validation := EditInvalidationEvidence.validate_retained()
	var failures: Array = []
	for validation in [
		field_validation,
		adaptive_lod_validation,
		transition_validation,
		boundary_validation,
		oracle_validation,
		adversarial_validation,
		dynamic_publication_validation,
		edit_invalidation_validation,
	]:
		failures.append_array(validation.get("failures", []))
	var field_passed := str(field_validation.get("status", "")) == "PASS"
	var adaptive_lod_passed := str(adaptive_lod_validation.get("status", "")) == "PASS"
	var transition_passed := str(transition_validation.get("status", "")) == "PASS"
	var boundary_passed := str(boundary_validation.get("status", "")) == "PASS"
	var oracle_passed := str(oracle_validation.get("status", "")) == "PASS"
	var adversarial_passed := str(adversarial_validation.get("status", "")) == "PASS"
	var dynamic_publication_passed := str(dynamic_publication_validation.get("status", "")) == "PASS"
	var edit_invalidation_passed := str(edit_invalidation_validation.get("status", "")) == "PASS"
	var passed := field_passed and adaptive_lod_passed and transition_passed \
		and boundary_passed and oracle_passed and adversarial_passed \
		and dynamic_publication_passed and edit_invalidation_passed
	return {
		"schema": "world_transvoxel.terrain_lab.native_adaptive_terrain_qualification.v1",
		"status": "PASS" if passed else "FAIL",
		"scope_status": {
			"TQP-28": "qualified_native_field_generation_and_sampling_contract_v1"
				if field_passed else "failed_native_field_contract",
			"TQP-29": "qualified_complex_native_lod0_field_corpus_v1"
				if field_passed else "failed_complex_native_field_corpus",
			"TQP-30": "qualified_bounded_adaptive_lod_selection_and_neighbor_contract_v1"
				if adaptive_lod_passed else "failed_adaptive_lod_contract",
			"TQP-31": "qualified_native_regular_transition_assembly_matrix_v1"
				if transition_passed else "failed_regular_transition_assembly_matrix",
			"TQP-32": "qualified_native_boundary_enclosure_policy_v1"
				if boundary_passed else "failed_boundary_enclosure_policy",
			"TQP-33": "qualified_independent_geometry_topology_oracles_v1"
				if oracle_passed else "failed_independent_oracles",
			"TQP-34": "qualified_seeded_adversarial_minimized_corpus_v1"
				if adversarial_passed else "failed_adversarial_corpus",
			"TQP-35": "qualified_native_dynamic_lod_publication_v1"
				if dynamic_publication_passed else "failed_dynamic_lod_publication",
			"TQP-36": "qualified_native_edit_invalidation_v1"
				if edit_invalidation_passed else "failed_edit_invalidation",
			"TQP-37": "proposed_pending_cross_lod_edit_corpus",
			"TQP-38": "proposed_pending_adaptive_surface_continuity",
			"TQP-39": "proposed_pending_adaptive_system_agreement",
			"TQP-40": "proposed_pending_multilayer_adaptive_streaming",
			"TQP-41": "proposed_pending_adaptive_persistence_replay",
			"TQP-42": "proposed_pending_fault_and_order_determinism",
			"TQP-43": "proposed_pending_complex_visual_temporal_corpus",
			"TQP-44": "proposed_pending_complex_adaptive_soak",
			"TQP-45": "proposed_gate_open",
		},
		"audit_status": "EDIT_INVALIDATION_QUALIFIED_ADAPTIVE_EDIT_SEMANTICS_STILL_OPEN",
		"native_field_evidence": field_validation,
		"adaptive_lod_evidence": adaptive_lod_validation,
		"transition_assembly_evidence": transition_validation,
		"boundary_enclosure_evidence": boundary_validation,
		"independent_oracle_evidence": oracle_validation,
		"adversarial_corpus_evidence": adversarial_validation,
		"dynamic_lod_publication_evidence": dynamic_publication_validation,
		"edit_invalidation_evidence": edit_invalidation_validation,
		"preserved_qualified_scope": [
			"TQP-01 through TQP-27 declared bounded scopes",
			"TQP-28 deterministic native field-generation and sampling contract",
			"TQP-29 bounded Windows LOD0 same-resolution complex native field corpus",
			"TQP-30 bounded deterministic adaptive LOD selector and structural contract",
			"TQP-31 bounded Windows native regular/transition assembly matrix",
			"TQP-32 bounded Windows native chunk/world boundary and enclosure policy",
			"TQP-33 bounded Windows independent native geometry and topology oracles",
			"TQP-34 bounded Windows seeded adversarial, replay, minimization, and corrected-regression corpus",
			"TQP-35 bounded Windows native dynamic LOD publication and temporal ownership contract",
			"TQP-36 bounded Windows native exact edit invalidation and incremental remeshing contract",
		],
		"explicitly_unqualified_scope": [
			"arbitrary, deeper than LOD1/LOD0, fault-injected, or production adaptive hierarchy arrangements beyond the retained dynamic contract",
			"dynamic cross-LOD digging and construction",
			"multi-layer adaptive streaming and persistence",
			"complex adaptive visual quality and performance",
			"Gate E native adaptive terrain authority",
		],
		"failures": failures,
	}
