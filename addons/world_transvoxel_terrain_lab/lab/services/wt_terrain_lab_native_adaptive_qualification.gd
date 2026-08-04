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


static func run() -> Dictionary:
	var field_validation := NativeFieldEvidence.validate_retained()
	var adaptive_lod_validation := AdaptiveLodEvidence.validate_retained()
	var transition_validation := TransitionAssemblyEvidence.validate_retained()
	var boundary_validation := BoundaryEnclosureEvidence.validate_retained()
	var oracle_validation := IndependentOracleEvidence.validate_retained()
	var adversarial_validation := AdversarialCorpusEvidence.validate_retained()
	var dynamic_publication_validation := DynamicLodPublicationEvidence.validate_retained()
	var edit_invalidation_validation := EditInvalidationEvidence.validate_retained()
	var adaptive_edit_validation := AdaptiveEditEvidence.validate_retained()
	var adaptive_surface_validation := AdaptiveSurfaceEvidence.validate_retained()
	var adaptive_system_validation := AdaptiveSystemEvidence.validate_retained()
	var adaptive_streaming_validation := AdaptiveStreamingEvidence.validate_retained()
	var adaptive_persistence_validation := AdaptivePersistenceEvidence.validate_retained()
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
		adaptive_edit_validation,
		adaptive_surface_validation,
		adaptive_system_validation,
		adaptive_streaming_validation,
		adaptive_persistence_validation,
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
	var adaptive_edit_passed := str(adaptive_edit_validation.get("status", "")) == "PASS"
	var adaptive_surface_passed := str(adaptive_surface_validation.get("status", "")) == "PASS"
	var adaptive_system_passed := str(adaptive_system_validation.get("status", "")) == "PASS"
	var adaptive_streaming_passed := str(adaptive_streaming_validation.get("status", "")) == "PASS"
	var adaptive_persistence_passed := str(adaptive_persistence_validation.get("status", "")) == "PASS"
	var passed := field_passed and adaptive_lod_passed and transition_passed \
		and boundary_passed and oracle_passed and adversarial_passed \
		and dynamic_publication_passed and edit_invalidation_passed \
		and adaptive_edit_passed and adaptive_surface_passed \
		and adaptive_system_passed and adaptive_streaming_passed \
		and adaptive_persistence_passed
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
			"TQP-37": "qualified_native_adaptive_editing_v1"
				if adaptive_edit_passed else "failed_adaptive_editing",
			"TQP-38": "qualified_native_adaptive_surface_continuity_v1"
				if adaptive_surface_passed else "failed_adaptive_surface_continuity",
			"TQP-39": "qualified_native_adaptive_system_agreement_v1"
				if adaptive_system_passed else "failed_adaptive_system_agreement",
			"TQP-40": "qualified_native_multi_layer_adaptive_streaming_v1"
				if adaptive_streaming_passed else "failed_adaptive_streaming",
			"TQP-41": "qualified_native_adaptive_persistence_replay_v1"
				if adaptive_persistence_passed else "failed_adaptive_persistence",
			"TQP-42": "proposed_pending_sparse_hierarchy_storage_and_large_world_compaction",
			"TQP-43": "proposed_pending_fault_and_order_determinism",
			"TQP-44": "proposed_pending_complex_visual_temporal_corpus",
			"TQP-45": "proposed_pending_complex_adaptive_soak",
			"TQP-46": "proposed_gate_open",
		},
		"audit_status": "ADAPTIVE_STREAMING_AND_PERSISTENCE_QUALIFIED_SPARSE_STORAGE_STILL_OPEN",
		"native_field_evidence": field_validation,
		"adaptive_lod_evidence": adaptive_lod_validation,
		"transition_assembly_evidence": transition_validation,
		"boundary_enclosure_evidence": boundary_validation,
		"independent_oracle_evidence": oracle_validation,
		"adversarial_corpus_evidence": adversarial_validation,
		"dynamic_lod_publication_evidence": dynamic_publication_validation,
		"edit_invalidation_evidence": edit_invalidation_validation,
		"adaptive_edit_evidence": adaptive_edit_validation,
		"adaptive_surface_evidence": adaptive_surface_validation,
		"adaptive_system_evidence": adaptive_system_validation,
		"adaptive_streaming_evidence": adaptive_streaming_validation,
		"adaptive_persistence_evidence": adaptive_persistence_validation,
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
			"TQP-37 bounded Windows native adaptive digging, construction, lifecycle, refinement, retention, and reconstructive-history contract",
			"TQP-38 bounded Windows native adaptive material payload, shared-position continuity, and diagnostic shader contract",
			"TQP-39 bounded Windows native render/collision/query/physics agreement and consumer-derived navigation contract",
			"TQP-40 bounded Windows native LOD2/LOD1/LOD0 multi-layer cave, multi-viewer, prefetch, teleport, and retirement contract",
			"TQP-41 bounded Windows native-baked adaptive edit replay, committed-prefix recovery, compaction, migration, and regenerated-resource contract",
		],
		"explicitly_unqualified_scope": [
			"arbitrary, deeper than LOD1/LOD0, fault-injected, or production adaptive hierarchy arrangements beyond the retained dynamic contract",
			"adaptive digging, construction, materials, system agreement, streaming, and persistence beyond the retained TQP-37 through TQP-41 Windows fixtures",
			"efficient sparse hierarchy storage and large-world compaction required by TQP-42",
			"fault-injected ordering determinism and recovery beyond retained committed-prefix and inherited truncated-tail checks",
			"complex adaptive visual quality and performance",
			"Gate E native adaptive terrain authority",
		],
		"failures": failures,
	}
