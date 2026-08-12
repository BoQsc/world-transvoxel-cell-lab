extends SceneTree

const TerrainLabScript := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/wt_transvoxel_terrain_lab.gd"
)
const TerrainObservatoryScene := preload(
	"res://labs/terrain_lab/scenes/terrain_observatory.tscn"
)
const SurfaceShadingReviewScene := preload(
	"res://labs/terrain_lab/scenes/surface_shading_review.tscn"
)
const LargeTerrainObservatoryScene := preload(
	"res://labs/terrain_lab/scenes/large_terrain_observatory.tscn"
)
const BoundaryEnclosureObservatoryScene := preload(
	"res://labs/terrain_lab/scenes/boundary_enclosure_observatory.tscn"
)
const IndependentOracleObservatoryScene := preload(
	"res://labs/terrain_lab/scenes/independent_oracle_observatory.tscn"
)
const AdversarialCorpusObservatoryScene := preload(
	"res://labs/terrain_lab/scenes/adversarial_corpus_observatory.tscn"
)
const DynamicLodPublicationObservatoryScene := preload(
	"res://labs/terrain_lab/scenes/dynamic_lod_publication_observatory.tscn"
)
const EditInvalidationObservatoryScene := preload(
	"res://labs/terrain_lab/scenes/edit_invalidation_observatory.tscn"
)
const AdaptiveEditObservatoryScene := preload(
	"res://labs/terrain_lab/scenes/adaptive_edit_observatory.tscn"
)
const AdaptiveSurfaceObservatoryScene := preload(
	"res://labs/terrain_lab/scenes/adaptive_surface_observatory.tscn"
)
const AdaptiveSystemObservatoryScene := preload(
	"res://labs/terrain_lab/scenes/adaptive_system_observatory.tscn"
)
const AdaptiveStreamingObservatoryScene := preload(
	"res://labs/terrain_lab/scenes/adaptive_streaming_observatory.tscn"
)
const AdaptivePersistenceObservatoryScene := preload(
	"res://labs/terrain_lab/scenes/adaptive_persistence_observatory.tscn"
)
const SparseHierarchyObservatoryScene := preload(
	"res://labs/terrain_lab/scenes/sparse_hierarchy_observatory.tscn"
)
const FaultOrderObservatoryScene := preload(
	"res://labs/terrain_lab/scenes/fault_order_observatory.tscn"
)
const NativeEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_edit_native_evidence.gd"
)
const ObservatoryDiagnostics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_observatory.gd"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ClassDB.class_exists("WorldTransvoxelCellProbe"):
		_fail("pinned world-transvoxel dependency is unavailable")
		return
	var observatory_script := load(
		"res://labs/terrain_lab/scenes/terrain_observatory.gd"
	) as Script
	if observatory_script == null or not observatory_script.is_tool():
		_fail("Terrain Observatory must execute as an editor tool")
		return
	var large_observatory_script := load(
		"res://labs/terrain_lab/scenes/large_terrain_observatory.gd"
	) as Script
	if large_observatory_script == null or not large_observatory_script.is_tool():
		_fail("TQP-27 Large Terrain Observatory must execute as an editor tool")
		return
	var large_method_names := PackedStringArray()
	for method in large_observatory_script.get_script_method_list():
		large_method_names.append(str(method.get("name", "")))
	for required_method in [
		"track_editor_camera",
		"get_profile_contract",
		"get_validation_snapshot",
		"move_viewer_and_wait",
		"shutdown_for_validation",
	]:
		if required_method not in large_method_names:
			_fail("TQP-27 Large Terrain Observatory lacks " + required_method)
			return
	if LargeTerrainObservatoryScene == null:
		_fail("TQP-27 Large Terrain Observatory scene is unavailable")
		return
	var boundary_script := load(
		"res://labs/terrain_lab/scenes/boundary_enclosure_observatory.gd"
	) as Script
	if boundary_script == null or not boundary_script.is_tool():
		_fail("TQP-32 Boundary Observatory must execute as an editor tool")
		return
	var boundary := BoundaryEnclosureObservatoryScene.instantiate()
	root.add_child(boundary)
	for mode in range(3):
		boundary.editor_fixture_mode = mode
		boundary.call("_rebuild")
		var boundary_snapshot: Dictionary = boundary.get_validation_snapshot()
		if str(boundary_snapshot.get("status", "")) != "PASS":
			_fail("TQP-32 Boundary Observatory fixture failed")
			return
		if int(boundary_snapshot.get("native_chunk_count", 0)) != 8:
			_fail("TQP-32 Boundary Observatory native chunk count changed")
			return
		var boundary_topology: Dictionary = boundary_snapshot.get("topology", {})
		var exterior_open := int(boundary_topology.get("exterior_open_edge_count", -1))
		if (mode == 2 and exterior_open <= 0) or (mode != 2 and exterior_open != 0):
			_fail("TQP-32 Boundary Observatory contour ownership changed")
			return
		if int(boundary_topology.get("interior_open_edge_count", -1)) != 0 \
				or int(boundary_topology.get("nonmanifold_edge_count", -1)) != 0:
			_fail("TQP-32 Boundary Observatory topology failed")
			return
		if int((boundary_snapshot.get("sample_audit", {}) as Dictionary).get("outside_sample_count", 0)) <= 0:
			_fail("TQP-32 Boundary Observatory lacks outside-field halo samples")
			return
	boundary.free()
	var oracle_script := load(
		"res://labs/terrain_lab/scenes/independent_oracle_observatory.gd"
	) as Script
	if oracle_script == null or not oracle_script.is_tool():
		_fail("TQP-33 Independent Oracle Observatory must execute as an editor tool")
		return
	var oracle_observatory := IndependentOracleObservatoryScene.instantiate()
	root.add_child(oracle_observatory)
	var expected_failed_checks := {
		1: "edge_multiplicity",
		2: "duplicate_overlap",
		3: "orientation",
		4: "component",
	}
	for mode in range(5):
		oracle_observatory.editor_defect_mode = mode
		oracle_observatory.call("_rebuild")
		var oracle_snapshot: Dictionary = oracle_observatory.get_validation_snapshot()
		if str(oracle_snapshot.get("status", "")) != "PASS":
			_fail("TQP-33 Independent Oracle Observatory mode failed")
			return
		var oracle_status := str(oracle_snapshot.get("oracle_status", ""))
		if (mode == 0 and oracle_status != "PASS") or (mode != 0 and oracle_status != "FAIL"):
			_fail("TQP-33 Independent Oracle Observatory detection changed")
			return
		if mode != 0 and str(expected_failed_checks.get(mode, "")) not in oracle_snapshot.get("failed_checks", []):
			_fail("TQP-33 Independent Oracle Observatory designated check did not fail")
			return
	oracle_observatory.free()
	var corpus_script := load(
		"res://labs/terrain_lab/scenes/adversarial_corpus_observatory.gd"
	) as Script
	if corpus_script == null or not corpus_script.is_tool():
		_fail("TQP-34 Adversarial Corpus Observatory must execute as an editor tool")
		return
	var corpus_observatory := AdversarialCorpusObservatoryScene.instantiate()
	root.add_child(corpus_observatory)
	var corpus_canonical: Dictionary = corpus_observatory.get_validation_snapshot()
	if str(corpus_canonical.get("status", "")) != "PASS" \
			or int(corpus_canonical.get("native_chunk_call_count", 0)) != 8 \
			or not (corpus_canonical.get("failed_checks", []) as Array).is_empty():
		_fail("TQP-34 Adversarial Corpus Observatory default case failed")
		return
	var canonical_corpus_signature := str(corpus_canonical.get("geometry_signature", ""))
	corpus_observatory.editor_replay_mode = 2
	corpus_observatory.call("_rebuild")
	var corpus_reverse: Dictionary = corpus_observatory.get_validation_snapshot()
	if str(corpus_reverse.get("status", "")) != "PASS" \
			or str(corpus_reverse.get("geometry_signature", "")) != canonical_corpus_signature:
		_fail("TQP-34 completion-order observatory replay differs")
		return
	corpus_observatory.editor_case_index = 2
	corpus_observatory.call("_rebuild")
	var corpus_exact: Dictionary = corpus_observatory.get_validation_snapshot()
	if str(corpus_exact.get("status", "")) != "PASS" \
			or str(corpus_exact.get("case_id", "")) != "seeded_exact_isovalue_lod0":
		_fail("TQP-34 exact-isovalue observatory case failed")
		return
	corpus_observatory.free()
	var publication_script := load(
		"res://labs/terrain_lab/scenes/dynamic_lod_publication_observatory.gd"
	) as Script
	if publication_script == null or not publication_script.is_tool():
		_fail("TQP-35 Dynamic Publication Observatory must execute as an editor tool")
		return
	var publication_method_names := PackedStringArray()
	for method in publication_script.get_script_method_list():
		publication_method_names.append(str(method.get("name", "")))
	for required_method in [
		"wait_until_ready", "run_action_and_wait", "get_validation_snapshot",
		"restart_and_wait", "shutdown_for_validation",
	]:
		if required_method not in publication_method_names:
			_fail("TQP-35 Dynamic Publication Observatory lacks " + required_method)
			return
	var publication_observatory := DynamicLodPublicationObservatoryScene.instantiate()
	root.add_child(publication_observatory)
	var publication_ready: Dictionary = await publication_observatory.wait_until_ready()
	if str(publication_ready.get("status", "")) != "PASS":
		_fail("TQP-35 Dynamic Publication Observatory did not become ready")
		return
	var initial_publication: Dictionary = publication_observatory.get_validation_snapshot()
	if str(initial_publication.get("status", "")) != "PASS" \
			or int(initial_publication.get("collision_overlap_count", -1)) != 0 \
			or (initial_publication.get("render_keys", []) as Array).is_empty() \
			or initial_publication.get("render_keys", []) != initial_publication.get("collision_keys", []):
		_fail("TQP-35 initial render/collision ownership failed")
		return
	var initial_publication_signature := str(initial_publication.get("render_key_signature", ""))
	var split_publication: Dictionary = await publication_observatory.run_action_and_wait("split_approach")
	if str(split_publication.get("status", "")) != "PASS":
		_fail("TQP-35 split observatory action failed")
		return
	var split_snapshot: Dictionary = split_publication.get("snapshot", {})
	if int(split_snapshot.get("collision_overlap_count", -1)) != 0 \
			or str(split_snapshot.get("render_key_signature", "")) == initial_publication_signature:
		_fail("TQP-35 split did not change ownership cleanly")
		return
	var merge_publication: Dictionary = await publication_observatory.run_action_and_wait("merge_retreat")
	if str(merge_publication.get("status", "")) != "PASS" \
			or int((merge_publication.get("snapshot", {}) as Dictionary).get("collision_overlap_count", -1)) != 0:
		_fail("TQP-35 merge observatory action failed")
		return
	var rapid_publication: Dictionary = await publication_observatory.run_action_and_wait("rapid_supersession")
	var rapid_metrics: Dictionary = (rapid_publication.get("snapshot", {}) as Dictionary).get("metrics", {})
	if str(rapid_publication.get("status", "")) != "PASS" \
			or int(rapid_metrics.get("coalesced_viewer_events", 0)) <= 0 \
			or int(rapid_metrics.get("application_stale_render", 0)) \
				+ int(rapid_metrics.get("application_stale_collision", 0)) <= 0:
		_fail("TQP-35 rapid supersession controls were not exercised")
		return
	if str((await publication_observatory.shutdown_for_validation()).get("status", "")) != "PASS":
		_fail("TQP-35 observatory did not shut down cleanly")
		return
	publication_observatory.free()
	var invalidation_script := load(
		"res://labs/terrain_lab/scenes/edit_invalidation_observatory.gd"
	) as Script
	if invalidation_script == null or not invalidation_script.is_tool():
		_fail("TQP-36 Edit Invalidation Observatory must execute as an editor tool")
		return
	var invalidation_method_names := PackedStringArray()
	for method in invalidation_script.get_script_method_list():
		invalidation_method_names.append(str(method.get("name", "")))
	for required_method in [
		"wait_until_ready", "run_action_and_wait", "get_validation_snapshot",
		"restart_and_wait", "shutdown_for_validation",
	]:
		if required_method not in invalidation_method_names:
			_fail("TQP-36 Edit Invalidation Observatory lacks " + required_method)
			return
	var invalidation_observatory := EditInvalidationObservatoryScene.instantiate()
	root.add_child(invalidation_observatory)
	var invalidation_ready: Dictionary = await invalidation_observatory.wait_until_ready()
	if str(invalidation_ready.get("status", "")) != "PASS":
		_fail("TQP-36 Edit Invalidation Observatory did not become ready")
		return
	for action in [
		"mixed_lod_transition_dependency", "disjoint_batch_union",
		"unloaded_noop", "rapid_supersession",
	]:
		var invalidation_result: Dictionary = await invalidation_observatory.run_action_and_wait(action)
		if str(invalidation_result.get("status", "")) != "PASS" \
				or invalidation_result.get("expected_ids", []) \
				!= invalidation_result.get("changed_ids", []):
			_fail("TQP-36 Edit Invalidation Observatory action failed: " + action)
			return
	var invalidation_snapshot: Dictionary = invalidation_observatory.get_validation_snapshot()
	if str(invalidation_snapshot.get("status", "")) != "PASS" \
			or int(invalidation_snapshot.get("collision_overlap_count", -1)) != 0:
		_fail("TQP-36 Edit Invalidation Observatory ownership failed")
		return
	if str((await invalidation_observatory.shutdown_for_validation()).get("status", "")) != "PASS":
		_fail("TQP-36 Edit Invalidation Observatory did not shut down cleanly")
		return
	invalidation_observatory.free()
	var adaptive_edit_script := load(
		"res://labs/terrain_lab/scenes/adaptive_edit_observatory.gd"
	) as Script
	if adaptive_edit_script == null or not adaptive_edit_script.is_tool():
		_fail("TQP-37 Adaptive Edit Observatory must execute as an editor tool")
		return
	var adaptive_edit_method_names := PackedStringArray()
	for method in adaptive_edit_script.get_script_method_list():
		adaptive_edit_method_names.append(str(method.get("name", "")))
	for required_method in [
		"wait_until_ready", "run_action_and_wait", "get_validation_snapshot",
		"restart_and_wait", "shutdown_for_validation",
	]:
		if required_method not in adaptive_edit_method_names:
			_fail("TQP-37 Adaptive Edit Observatory lacks " + required_method)
			return
	var adaptive_edit_observatory := AdaptiveEditObservatoryScene.instantiate()
	root.add_child(adaptive_edit_observatory)
	var adaptive_ready: Dictionary = await adaptive_edit_observatory.wait_until_ready()
	if str(adaptive_ready.get("status", "")) != "PASS":
		_fail("TQP-37 Adaptive Edit Observatory did not become ready")
		return
	var carve_result: Dictionary = await adaptive_edit_observatory.run_action_and_wait(
		"transition_face_carve"
	)
	if str(carve_result.get("status", "")) != "PASS" \
			or int(carve_result.get("local_triangle_count", 0)) <= 0:
		_fail("TQP-37 transition carve observatory action failed")
		return
	var coarse_result: Dictionary = await adaptive_edit_observatory.run_action_and_wait(
		"under_resolved_coarse"
	)
	if str(coarse_result.get("status", "")) != "PASS" \
			or int(coarse_result.get("local_triangle_count", -1)) != 0:
		_fail("TQP-37 under-resolved coarse control failed")
		return
	var refined_result: Dictionary = await adaptive_edit_observatory.run_action_and_wait(
		"under_resolved_refined"
	)
	if str(refined_result.get("status", "")) != "PASS" \
			or int(refined_result.get("local_triangle_count", 0)) != 8 \
			or int(refined_result.get("edit_lod_retention_zones", 0)) <= 0:
		_fail("TQP-37 under-resolved refinement observatory action failed")
		return
	var adaptive_snapshot: Dictionary = adaptive_edit_observatory.get_validation_snapshot()
	var collision_profile: Dictionary = adaptive_snapshot.get("collision_profile", {})
	if str(adaptive_snapshot.get("status", "")) != "PASS" \
			or int(adaptive_snapshot.get("collision_overlap_count", -1)) != 0 \
			or str(collision_profile.get("production_policy_qualification", "")) \
				!= "UNQUALIFIED_OWNED_BY_LATER_TQP":
		_fail("TQP-37 Adaptive Edit Observatory ownership scope failed")
		return
	if str((await adaptive_edit_observatory.shutdown_for_validation()).get("status", "")) != "PASS":
		_fail("TQP-37 Adaptive Edit Observatory did not shut down cleanly")
		return
	adaptive_edit_observatory.free()
	var adaptive_surface_script := load(
		"res://labs/terrain_lab/scenes/adaptive_surface_observatory.gd"
	) as Script
	if adaptive_surface_script == null or not adaptive_surface_script.is_tool():
		_fail("TQP-38 Adaptive Surface Observatory must execute as an editor tool")
		return
	var adaptive_surface_method_names := PackedStringArray()
	for method in adaptive_surface_script.get_script_method_list():
		adaptive_surface_method_names.append(str(method.get("name", "")))
	for required_method in [
		"wait_until_ready", "set_diagnostic_mode", "cycle_lod_and_wait",
		"get_validation_snapshot", "restart_and_wait", "shutdown_for_validation",
	]:
		if required_method not in adaptive_surface_method_names:
			_fail("TQP-38 Adaptive Surface Observatory lacks " + required_method)
			return
	var adaptive_surface_observatory := AdaptiveSurfaceObservatoryScene.instantiate()
	root.add_child(adaptive_surface_observatory)
	var surface_ready: Dictionary = await adaptive_surface_observatory.wait_until_ready()
	var surface_snapshot: Dictionary = adaptive_surface_observatory.get_validation_snapshot()
	var surface_payload: Dictionary = surface_snapshot.get("payload", {})
	if str(surface_ready.get("status", "")) != "PASS" \
			or str(surface_snapshot.get("status", "")) != "PASS" \
			or int(surface_payload.get("authored", 0)) <= 0:
		_fail("TQP-38 Adaptive Surface Observatory payload failed")
		return
	if str((await adaptive_surface_observatory.shutdown_for_validation()).get("status", "")) != "PASS":
		_fail("TQP-38 Adaptive Surface Observatory did not shut down cleanly")
		return
	adaptive_surface_observatory.free()
	var adaptive_system_script := load(
		"res://labs/terrain_lab/scenes/adaptive_system_observatory.gd"
	) as Script
	if adaptive_system_script == null or not adaptive_system_script.is_tool():
		_fail("TQP-39 Adaptive System Observatory must execute as an editor tool")
		return
	var adaptive_system_method_names := PackedStringArray()
	for method in adaptive_system_script.get_script_method_list():
		adaptive_system_method_names.append(str(method.get("name", "")))
	for required_method in [
		"wait_until_ready", "set_focus_mode", "teleport_and_return",
		"apply_staged_edit_and_wait", "get_validation_snapshot",
		"restart_and_wait", "shutdown_for_validation",
	]:
		if required_method not in adaptive_system_method_names:
			_fail("TQP-39 Adaptive System Observatory lacks " + required_method)
			return
	var adaptive_system_observatory := AdaptiveSystemObservatoryScene.instantiate()
	root.add_child(adaptive_system_observatory)
	var system_ready: Dictionary = await adaptive_system_observatory.wait_until_ready()
	var system_snapshot: Dictionary = adaptive_system_observatory.get_validation_snapshot()
	var system_collision: Dictionary = system_snapshot.get("collision", {})
	var system_metrics: Dictionary = system_snapshot.get("metrics", {})
	if str(system_ready.get("status", "")) != "PASS" \
			or str(system_snapshot.get("status", "")) != "PASS" \
			or int(system_collision.get("triangles", 0)) <= 0 \
			or int(system_metrics.get("collision_required_chunk_records", 0)) \
				>= int(system_metrics.get("active_chunk_records", 0)):
		_fail("TQP-39 Adaptive System Observatory agreement failed")
		return
	if str((await adaptive_system_observatory.shutdown_for_validation()).get("status", "")) != "PASS":
		_fail("TQP-39 Adaptive System Observatory did not shut down cleanly")
		return
	adaptive_system_observatory.free()
	var adaptive_streaming_script := load(
		"res://labs/terrain_lab/scenes/adaptive_streaming_observatory.gd"
	) as Script
	if adaptive_streaming_script == null or not adaptive_streaming_script.is_tool():
		_fail("TQP-40 Adaptive Streaming Observatory must execute as an editor tool")
		return
	var adaptive_streaming_method_names := PackedStringArray()
	for method in adaptive_streaming_script.get_script_method_list():
		adaptive_streaming_method_names.append(str(method.get("name", "")))
	for required_method in [
		"wait_until_ready", "set_inspection_mode", "run_multi_viewer_and_wait",
		"teleport_and_wait", "restart_and_wait", "get_validation_snapshot",
		"shutdown_for_validation",
	]:
		if required_method not in adaptive_streaming_method_names:
			_fail("TQP-40 Adaptive Streaming Observatory lacks " + required_method)
			return
	var adaptive_streaming_observatory := AdaptiveStreamingObservatoryScene.instantiate()
	root.add_child(adaptive_streaming_observatory)
	var streaming_ready: Dictionary = await adaptive_streaming_observatory.wait_until_ready()
	var streaming_snapshot: Dictionary = adaptive_streaming_observatory.get_validation_snapshot()
	if str(streaming_ready.get("status", "")) != "PASS" \
			or str(streaming_snapshot.get("status", "")) != "PASS" \
			or str(streaming_snapshot.get("backend_id", "")) != "transvoxel_mit_official":
		_fail(
			"TQP-40 Adaptive Streaming Observatory residency state failed: ready=%s snapshot=%s"
			% [str(streaming_ready), str(streaming_snapshot)]
		)
		return
	if str((await adaptive_streaming_observatory.shutdown_for_validation()).get("status", "")) != "PASS":
		_fail("TQP-40 Adaptive Streaming Observatory did not shut down cleanly")
		return
	adaptive_streaming_observatory.free()
	var adaptive_persistence_script := load(
		"res://labs/terrain_lab/scenes/adaptive_persistence_observatory.gd"
	) as Script
	if adaptive_persistence_script == null or not adaptive_persistence_script.is_tool():
		_fail("TQP-41 Adaptive Persistence Observatory must execute as an editor tool")
		return
	var adaptive_persistence_method_names := PackedStringArray()
	for method in adaptive_persistence_script.get_script_method_list():
		adaptive_persistence_method_names.append(str(method.get("name", "")))
	for required_method in [
		"wait_until_ready", "set_inspection_mode", "replay_and_wait",
		"show_distant_and_wait", "restart_and_wait", "get_validation_snapshot",
		"shutdown_for_validation",
	]:
		if required_method not in adaptive_persistence_method_names:
			_fail("TQP-41 Adaptive Persistence Observatory lacks " + required_method)
			return
	var adaptive_persistence_observatory := AdaptivePersistenceObservatoryScene.instantiate()
	root.add_child(adaptive_persistence_observatory)
	var persistence_ready: Dictionary = await adaptive_persistence_observatory.wait_until_ready()
	var persistence_snapshot: Dictionary = adaptive_persistence_observatory.get_validation_snapshot()
	if str(persistence_ready.get("status", "")) != "PASS" \
			or str(persistence_snapshot.get("status", "")) != "PASS" \
			or int(persistence_snapshot.get("world_revision", -1)) != 2 \
			or int(persistence_snapshot.get("cave_triangle_count", 0)) <= 0:
		_fail("TQP-41 Adaptive Persistence Observatory restored state failed")
		return
	if str((await adaptive_persistence_observatory.shutdown_for_validation()).get("status", "")) != "PASS":
		_fail("TQP-41 Adaptive Persistence Observatory did not shut down cleanly")
		return
	adaptive_persistence_observatory.free()
	var sparse_hierarchy_script := load(
		"res://labs/terrain_lab/scenes/sparse_hierarchy_observatory.gd"
	) as Script
	if sparse_hierarchy_script == null or not sparse_hierarchy_script.is_tool():
		_fail("TQP-42 Sparse Hierarchy Observatory must execute as an editor tool")
		return
	var sparse_hierarchy_method_names := PackedStringArray()
	for method in sparse_hierarchy_script.get_script_method_list():
		sparse_hierarchy_method_names.append(str(method.get("name", "")))
	for required_method in [
		"wait_until_ready", "apply_localized_edit", "compact_and_reopen",
		"restart_source", "get_validation_snapshot", "shutdown_for_validation",
	]:
		if required_method not in sparse_hierarchy_method_names:
			_fail("TQP-42 Sparse Hierarchy Observatory lacks " + required_method)
			return
	var sparse_hierarchy_observatory := SparseHierarchyObservatoryScene.instantiate()
	root.add_child(sparse_hierarchy_observatory)
	var hierarchy_ready: Dictionary = await sparse_hierarchy_observatory.wait_until_ready()
	var hierarchy_snapshot: Dictionary = sparse_hierarchy_observatory.get_validation_snapshot()
	var hierarchy_metrics: Dictionary = hierarchy_snapshot.get("metrics", {})
	if str(hierarchy_ready.get("status", "")) != "PASS" \
			or str(hierarchy_snapshot.get("status", "")) != "PASS" \
			or int(hierarchy_metrics.get("hierarchy_kind", 0)) != 2 \
			or int(hierarchy_metrics.get("hierarchy_declared_pages", 0)) != 299520 \
			or int(hierarchy_metrics.get("hierarchy_explicit_index_entries", -1)) != 0:
		_fail("TQP-42 Sparse Hierarchy Observatory source state failed")
		return
	if str((await sparse_hierarchy_observatory.shutdown_for_validation()).get("status", "")) != "PASS":
		_fail("TQP-42 Sparse Hierarchy Observatory did not shut down cleanly")
		return
	sparse_hierarchy_observatory.free()
	var fault_order_script := load(
		"res://labs/terrain_lab/scenes/fault_order_observatory.gd"
	) as Script
	if fault_order_script == null or not fault_order_script.is_tool():
		_fail("TQP-43 Fault-Order Observatory must execute as an editor tool")
		return
	var fault_order_method_names := PackedStringArray()
	for method in fault_order_script.get_script_method_list():
		fault_order_method_names.append(str(method.get("name", "")))
	for required_method in [
		"wait_until_ready", "run_motion_storm_and_wait", "compare_reverse_and_wait",
		"restart_and_wait", "get_validation_snapshot", "shutdown_for_validation",
	]:
		if required_method not in fault_order_method_names:
			_fail("TQP-43 Fault-Order Observatory lacks " + required_method)
			return
	var fault_order_observatory := FaultOrderObservatoryScene.instantiate()
	root.add_child(fault_order_observatory)
	var fault_ready: Dictionary = await fault_order_observatory.wait_until_ready()
	var fault_snapshot: Dictionary = fault_order_observatory.get_validation_snapshot()
	if str(fault_ready.get("status", "")) != "PASS" \
			or str(fault_snapshot.get("status", "")) != "PASS" \
			or str(fault_snapshot.get("backend_id", "")) != "transvoxel_mit_official" \
			or int(fault_snapshot.get("native_orders", 0)) != 64 \
			or int(fault_snapshot.get("first_divergence_generation", -1)) != 4 \
			or int(fault_snapshot.get("render_resources", 0)) <= 0:
		_fail("TQP-43 Fault-Order Observatory authority state failed")
		return
	if str((await fault_order_observatory.shutdown_for_validation()).get("status", "")) != "PASS":
		_fail("TQP-43 Fault-Order Observatory did not shut down cleanly")
		return
	fault_order_observatory.free()
	var observatory_property_names := PackedStringArray()
	for property in observatory_script.get_script_property_list():
		observatory_property_names.append(str(property.get("name", "")))
	for required_property in [
		"editor_preview_enabled",
		"editor_auto_rebuild",
		"editor_show_chunk_bounds",
		"editor_rebuild_now",
		"editor_reset_now",
		"editor_repro_path",
		"editor_export_repro_now",
		"editor_dig_now",
		"editor_construct_now",
	]:
		if not observatory_property_names.has(required_property):
			_fail("Terrain Observatory editor contract lacks " + required_property)
			return
	var observatory := TerrainObservatoryScene.instantiate()
	root.add_child(observatory)
	var observatory_metrics: Dictionary = observatory.get_mesh_metrics()
	if int(observatory_metrics.get("chunk_count", 0)) <= 0:
		_fail("Terrain Observatory editor preview generated no native chunks")
		return
	if int(observatory_metrics.get("bounds_errors", -1)) != 0:
		_fail("Terrain Observatory editor preview has local bounds errors")
		return
	if int(observatory_metrics.get("surface_seam_pair_count", 0)) <= 0:
		_fail("Terrain Observatory canonical fixture exercises no surface seams")
		return
	if int(observatory_metrics.get("seam_errors", -1)) != 0:
		_fail(
			"Terrain Observatory canonical fixture has mismatched chunk seams: "
			+ str(observatory.get_seam_report())
		)
		return
	if int(observatory_metrics.get("interior_open_edges", -1)) != 0 \
			or int(observatory_metrics.get("nonmanifold_edges", -1)) != 0:
		_fail(
			"Terrain Observatory canonical fixture has invalid window topology: "
			+ str(observatory.get_topology_report())
		)
		return
	if not _window_topology_negative_control_passes():
		_fail("window topology audit did not detect an injected interior opening")
		return
	var diagnostics: Dictionary = observatory.get_observatory_snapshot()
	if str(diagnostics.get("schema", "")) != ObservatoryDiagnostics.SNAPSHOT_SCHEMA:
		_fail("Terrain Observatory diagnostic snapshot schema changed")
		return
	var resources: Dictionary = diagnostics.get("resources", {})
	if int(resources.get("chunk_count", 0)) <= 0 \
			or int(resources.get("job_count", 0)) <= 0 \
			or int(resources.get("total_memory_bytes", 0)) <= 0:
		_fail("Terrain Observatory diagnostic resource summary is incomplete")
		return
	if (resources.get("collision_states", {}) as Dictionary).is_empty():
		_fail("Terrain Observatory diagnostic collision state is absent")
		return
	var repro_path := "user://terrain_observatory_smoke_repro.json"
	if observatory.export_observatory_repro(repro_path) != OK:
		_fail("Terrain Observatory editor repro export failed")
		return
	var repro_value := JSON.parse_string(FileAccess.get_file_as_string(repro_path))
	if not repro_value is Dictionary \
			or str(ObservatoryDiagnostics.validate_repro(repro_value).get("status", "")) != "PASS":
		_fail("Terrain Observatory editor repro failed validation")
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(repro_path))
	var canonical_edit_count := int(observatory_metrics.get("edit_count", 0))
	observatory.call("_apply_editor_operation", "dig")
	var edited_observatory_metrics: Dictionary = observatory.get_mesh_metrics()
	if int(edited_observatory_metrics.get("edit_count", 0)) != canonical_edit_count + 1:
		_fail("Terrain Observatory editor dig control did not rebuild the fixture")
		return
	observatory.call("_reset_field")
	if int(observatory.get_mesh_metrics().get("edit_count", 0)) != canonical_edit_count:
		_fail("Terrain Observatory editor reset did not restore the canonical fixture")
		return
	observatory.free()
	var review_script := load(
		"res://labs/terrain_lab/scenes/surface_shading_review.gd"
	) as Script
	if review_script == null or not review_script.is_tool():
		_fail("TQP-23 Surface Review must execute as an editor tool")
		return
	var surface_review := SurfaceShadingReviewScene.instantiate()
	var smoke_review_observatory := surface_review.get_node("TerrainObservatory")
	smoke_review_observatory.editor_sample_scale_m = 0.5
	smoke_review_observatory.editor_chunk_range_xz = 1
	smoke_review_observatory.editor_chunk_y_max = 1
	root.add_child(surface_review)
	var review_contract: Dictionary = surface_review.get_review_contract()
	if str(review_contract.get("milestone", "")) != "TQP-23":
		_fail("surface review milestone contract changed")
		return
	if not bool(review_contract.get("formal_decision_required", false)):
		_fail("surface review can bypass the formal decision")
		return
	if int(review_contract.get("diagnostic_mode_count", 0)) != 10:
		_fail("surface review diagnostic catalog changed")
		return
	if int(review_contract.get("minimum_motion_cycles", 0)) != 2:
		_fail("surface review motion-cycle gate changed")
		return
	if int(review_contract.get("required_diagnostic_modes", 0)) != 10:
		_fail("surface review required diagnostic count changed")
		return
	if not bool(review_contract.get("shadow_comparison_required", false)):
		_fail("surface review shadow comparison is not required")
		return
	if (review_contract.get("criterion_ids", []) as Array).size() != 8:
		_fail("surface review criteria changed")
		return
	var review_observatory: Node = smoke_review_observatory
	for diagnostic_mode in range(10):
		surface_review.editor_diagnostic_mode = diagnostic_mode
		surface_review.call("_apply_diagnostic_mode")
		if int(review_observatory.call("get_surface_shading_diagnostic_mode")) != diagnostic_mode:
			_fail("surface review diagnostic mode did not reach the native fixture material")
			return
	for criterion_node in [
		"ProjectionAnchored",
		"NoFlicker",
		"TriplanarCoherent",
		"DetailFadeContinuous",
		"NormalsCoherent",
		"MasksAttached",
		"NoDiscontinuity",
		"ShadowAnchored",
	]:
		(surface_review.get_node("%" + criterion_node) as CheckBox).button_pressed = true
	if bool(surface_review.call("_candidate_pass_ready")):
		_fail("surface review candidate pass bypassed the motion-cycle gate")
		return
	surface_review.set("_motion_cycles", 2)
	if bool(surface_review.call("_candidate_pass_ready")):
		_fail("surface review candidate pass bypassed the shadow comparison")
		return
	surface_review.call("_set_shadows_enabled", false)
	if bool(surface_review.call("_candidate_pass_ready")):
		_fail("surface review candidate pass opened with reference shadows disabled")
		return
	surface_review.call("_set_shadows_enabled", true)
	if not bool(surface_review.call("_candidate_pass_ready")):
		_fail("surface review candidate pass did not open after every required observation")
		return
	surface_review.set_review_camera_progress(0.0, 0.0)
	var near_state: Dictionary = surface_review.get_review_camera_state()
	surface_review.set_review_camera_progress(1.0, 0.0)
	var far_state: Dictionary = surface_review.get_review_camera_state()
	var near_position: Vector3 = near_state.get("position", Vector3.ZERO)
	var far_position: Vector3 = far_state.get("position", Vector3.ZERO)
	if not near_position.is_equal_approx(Vector3(-25.0, 22.0, 3.0)):
		_fail("surface review near endpoint changed")
		return
	if not far_position.is_equal_approx(Vector3(-52.0, 42.0, 3.0)):
		_fail("surface review far endpoint changed")
		return
	surface_review.free()
	var terrain_lab := TerrainLabScript.new()
	root.add_child(terrain_lab)
	var validation: Dictionary = terrain_lab.validate_program_boundary()
	if str(validation.get("status", "")) != "PASS":
		_fail("terrain lab boundary failed: " + str(validation.get("failures", [])))
		return
	if int(validation.get("milestone_count", 0)) != 71:
		_fail("terrain program milestone count changed")
		return
	if int(validation.get("qualified_milestone_count", 0)) != 56:
		_fail("qualified reference milestone count changed")
		return
	if int(validation.get("specified_milestone_count", -1)) != 0:
		_fail("open specification count changed")
		return
	if int(validation.get("proposed_milestone_count", -1)) != 0:
		_fail("proposed milestone count changed")
		return
	var status_counts: Dictionary = validation.get("status_counts", {})
	if int(status_counts.get("implemented", 0)) != 6:
		_fail("implemented evidence count changed")
		return
	if int(status_counts.get("production", 0)) != 1:
		_fail("production release milestone count changed")
		return
	if int(status_counts.get("blocked", 0)) != 8:
		_fail("fail-closed milestone count changed")
		return
	var dependencies: Dictionary = validation.get("dependencies", {})
	if str(dependencies.get("status", "")) != "PASS":
		_fail("terrain lab dependency boundary failed")
		return
	var foundation: Dictionary = validation.get("foundation", {})
	if str(foundation.get("status", "")) != "PASS":
		_fail("Gate A qualification failed: " + str(foundation.get("failures", [])))
		return
	var gates: Dictionary = validation.get("gate_statuses", {})
	if str(gates.get("GATE_A", "")) != "QUALIFIED":
		_fail("Gate A did not close as qualified")
		return
	if str(gates.get("GATE_B", "")) != "QUALIFIED":
		_fail("Gate B did not close as qualified")
		return
	if str(gates.get("GATE_C", "")) != "QUALIFIED":
		_fail("Gate C did not close as qualified")
		return
	if str(gates.get("GATE_D", "")) != "QUALIFIED":
		_fail("Gate D did not close as qualified")
		return
	if str(gates.get("GATE_E", "")) != "QUALIFIED":
		_fail("Gate E did not close as qualified")
		return
	if str(gates.get("GATE_F", "")) != "QUALIFIED":
		_fail("Gate F did not close as qualified")
		return
	for gate_name in ["GATE_G", "GATE_H"]:
		if str(gates.get(gate_name, "")) != "CLOSED":
			_fail(gate_name + " must fail closed while blockers remain")
			return
	print(
		"WT_TERRAIN_LAB_SMOKE_PASS topology="
		+ JSON.stringify(observatory_metrics)
	)
	terrain_lab.free()
	quit(0)


func _window_topology_negative_control_passes() -> bool:
	var vertices := PackedVector3Array([
		Vector3(4.0, 4.0, 4.0),
		Vector3(8.0, 4.0, 4.0),
		Vector3(6.0, 8.0, 4.0),
		Vector3(6.0, 6.0, 8.0),
	])
	var closed_chunk := {
		"ok": true,
		"lod": 0,
		"world_origin_x": 0.0,
		"world_origin_y": 0.0,
		"world_origin_z": 0.0,
		"regular": {
			"vertices": vertices,
			"indices": PackedInt32Array([
				0, 2, 1,
				0, 1, 3,
				1, 2, 3,
				2, 0, 3,
			]),
		},
	}
	var closed_report := NativeEvidence.same_lod_window_topology([closed_chunk])
	var open_chunk: Dictionary = closed_chunk.duplicate(true)
	open_chunk["regular"]["indices"] = PackedInt32Array([
		0, 2, 1,
		0, 1, 3,
		1, 2, 3,
	])
	var open_report := NativeEvidence.same_lod_window_topology([open_chunk])
	return (
		str(closed_report.get("status", "")) == "PASS"
		and str(open_report.get("status", "")) == "FAIL"
		and int(open_report.get("interior_open_edge_count", 0)) == 3
	)


func _fail(message: String) -> void:
	push_error("WT_TERRAIN_LAB_SMOKE_FAIL: " + message)
	quit(1)
