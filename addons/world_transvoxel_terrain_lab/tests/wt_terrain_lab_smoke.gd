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
	if int(validation.get("milestone_count", 0)) != 46:
		_fail("terrain program milestone count changed")
		return
	if int(validation.get("qualified_milestone_count", 0)) != 27:
		_fail("qualified reference milestone count changed")
		return
	if int(validation.get("specified_milestone_count", 0)) != 1:
		_fail("open specification count changed")
		return
	if int(validation.get("proposed_milestone_count", -1)) != 0:
		_fail("one or more milestones lack a reviewed specification")
		return
	var status_counts: Dictionary = validation.get("status_counts", {})
	if int(status_counts.get("implemented", 0)) != 6:
		_fail("implemented evidence count changed")
		return
	if int(status_counts.get("blocked", 0)) != 12:
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
	for gate_name in ["GATE_E", "GATE_F"]:
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
