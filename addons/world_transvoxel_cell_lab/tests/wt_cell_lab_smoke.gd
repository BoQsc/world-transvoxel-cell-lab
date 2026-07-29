extends SceneTree

const LabScript := preload("res://addons/world_transvoxel_cell_lab/lab/wt_transvoxel_cell_lab.gd")
const DockScript := preload("res://addons/world_transvoxel_cell_lab/editor/wt_cell_lab_dock.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ClassDB.class_exists("WorldTransvoxelCellProbe"):
		_fail("WorldTransvoxelCellProbe is required")
		return
	var dock := DockScript.new()
	root.add_child(dock)
	if dock.name != "World Transvoxel Lab":
		_fail("editor dock did not initialize")
		return
	dock.free()
	var lab := LabScript.new()
	root.add_child(lab)
	lab.cells_x = 6
	lab.cells_y = 6
	lab.cells_z = 6
	lab.field_mode = LabScript.FieldMode.SPHERE
	var report: Dictionary = lab.rebuild()
	if report.get("schema") != "world_transvoxel.cell_lab.report.v3":
		_fail("unexpected report schema")
		return
	if str(report.get("status", "")) != "PASS":
		_fail("native-only lab report did not pass")
		return
	if int(report.get("triangles", 0)) <= 0:
		_fail("initial lab mesh has no triangles")
		return
	if str(report.get("render_authority", "")) != "NATIVE_TRANSVOXEL_BACKEND_AUTHORITATIVE":
		_fail("native render authority was not used")
		return
	if str(report.get("correctness_claim", "")) \
			!= "provenance_locked_cell_chunk_terrain_observatory_backend_probe_v6":
		_fail("native correctness claim was not explicit")
		return
	if str(report.get("lab_scope", "")) != "cell_first_transvoxel_preview_and_validator":
		_fail("lab scope contract changed")
		return
	if str(report.get("primary_validation_domain", "")) != "volumetric_terrain":
		_fail("primary validation domain changed")
		return
	if str(report.get("primitive_scope", "")) != "transvoxel_scalar_field_cell_unit":
		_fail("primitive scope contract changed")
		return
	if str(report.get("validation_standard", "")) != "world_transvoxel_native_authoritative_no_fallback":
		_fail("validation standard changed")
		return
	if str(report.get("authority_model", "")) != "world_transvoxel_is_implementation_authority_under_test":
		_fail("authority model changed")
		return
	if str(report.get("upstream_correction_policy", "")) != "proven_lab_repro_drives_world_transvoxel_fix":
		_fail("upstream correction policy changed")
		return
	if str(report.get("integration_game_role", "")) != "downstream_proving_ground_not_correctness_authority":
		_fail("integration game role changed")
		return
	if str(report.get("integration_game_diagnostic_policy", "")) != "reduce_game_artifact_to_lab_repro_then_classify_fix_layer":
		_fail("integration game diagnostic policy changed")
		return
	if str(report.get("reference_terrain_role", "")) != "canonical_deterministic_terrain_standard_not_production_runtime":
		_fail("reference terrain role changed")
		return
	var repro: Dictionary = lab.make_repro_snapshot()
	if str(repro.get("schema", "")) != "world_transvoxel.cell_lab.repro.v2":
		_fail("unexpected repro schema")
		return
	if not repro.has("parameters") or not repro.has("report"):
		_fail("repro snapshot is incomplete")
		return
	report = lab.apply_repro_snapshot(repro)
	if str(report.get("status", "")) != "PASS":
		_fail("repro snapshot did not restore to a passing report")
		return
	if int(report.get("interior_open_edges", -1)) != 0:
		_fail("native exact mesh has interior open edges")
		return
	if int(report.get("nonmanifold_edges", -1)) != 0:
		_fail("native exact mesh has nonmanifold edges")
		return
	if int(report.get("orientation_conflict_edges", -1)) != 0:
		_fail("native exact mesh has orientation conflicts")
		return
	if int(report.get("failed_cells", -1)) != 0:
		_fail("native exact mesh had failed cells")
		return
	if not bool(report.get("transition_available", false)):
		_fail("transition probe was not available")
		return
	if str(report.get("transition_status", "")) != "Ok":
		_fail("transition probe did not mesh ok")
		return
	if int(report.get("transition_triangles", 0)) <= 0:
		_fail("transition probe produced no geometry")
		return
	if int(report.get("transition_nonmanifold_edges", -1)) != 0:
		_fail("transition probe has nonmanifold edges")
		return
	if int(report.get("transition_orientation_conflict_edges", -1)) != 0:
		_fail("transition probe has orientation conflicts")
		return
	if not bool(report.get("chunk_probe_available", false)):
		_fail("production chunk probe was not available")
		return
	if str(report.get("chunk_probe_status", "")) != "Ok":
		_fail("production chunk probe did not mesh ok: %s" % str(report.get("chunk_probe_error", "")))
		return
	if int(report.get("chunk_probe_triangles", 0)) <= 0:
		_fail("production chunk probe produced no geometry")
		return
	if int(report.get("chunk_probe_nonmanifold_edges", -1)) != 0:
		_fail("production chunk probe has nonmanifold edges")
		return
	if int(report.get("chunk_probe_orientation_conflict_edges", -1)) != 0:
		_fail("production chunk probe has orientation conflicts")
		return
	var dependency: Dictionary = lab.validate_native_dependency()
	if str(dependency.get("schema", "")) \
			!= "world_transvoxel.cell_lab.native_dependency_validation.v1":
		_fail("unexpected native dependency validation schema")
		return
	if str(dependency.get("status", "")) != "PASS" \
			or int(dependency.get("artifact_count", 0)) != 2:
		_fail("native dependency provenance did not pass")
		return
	if str(dependency.get("source", {}).get("commit", "")) \
			!= "8313650766b6b901f5b5ecdc8d84e03b6b87fd66":
		_fail("native dependency source commit changed")
		return
	var authority_stress: Dictionary = lab.validate_authority_stress()
	if str(authority_stress.get("schema", "")) \
			!= "world_transvoxel.cell_lab.authority_stress_validation.v1":
		_fail("unexpected authority stress validation schema")
		return
	if str(authority_stress.get("status", "")) != "PASS":
		_fail("authority stress validation did not pass")
		return
	var near_isovalue: Dictionary = authority_stress.get("near_isovalue", {})
	if int(near_isovalue.get("regular_probe_count", 0)) != 768 \
			or int(near_isovalue.get("transition_probe_count", 0)) != 1536:
		_fail("near-isovalue authority coverage changed")
		return
	var vertical_stack: Dictionary = authority_stress.get("vertical_stack", {})
	if int(vertical_stack.get("same_lod_matching_interfaces", 0)) != 2 \
			or int(vertical_stack.get("mixed_lod_matching_interfaces", 0)) != 2:
		_fail("vertical authority seam coverage changed")
		return
	var regular_corpus: Dictionary = lab.validate_regular_case_corpus()
	if str(regular_corpus.get("schema", "")) != "world_transvoxel.cell_lab.regular_case_corpus.v2":
		_fail("unexpected regular case corpus schema")
		return
	if str(regular_corpus.get("status", "")) != "PASS":
		_fail("regular case corpus did not pass: %s" % str(regular_corpus.get("sample_failures", [])))
		return
	if int(regular_corpus.get("ok_cases", 0)) != 254 or int(regular_corpus.get("empty_cases", 0)) != 2:
		_fail("regular case corpus counts changed")
		return
	var transition_corpus: Dictionary = lab.validate_transition_case_corpus()
	if str(transition_corpus.get("schema", "")) != "world_transvoxel.cell_lab.transition_case_corpus.v2":
		_fail("unexpected transition case corpus schema")
		return
	if str(transition_corpus.get("status", "")) != "PASS":
		_fail("transition case corpus did not pass: %s" % str(transition_corpus.get("sample_failures", [])))
		return
	if int(transition_corpus.get("ok_cases", 0)) != 3060 or int(transition_corpus.get("empty_cases", 0)) != 12:
		_fail("transition case corpus counts changed")
		return
	var chunk_lod: Dictionary = lab.validate_chunk_lod_seams()
	if str(chunk_lod.get("schema", "")) != "world_transvoxel.cell_lab.chunk_lod_validation.v2":
		_fail("unexpected chunk LOD validation schema")
		return
	if str(chunk_lod.get("status", "")) != "PASS":
		_fail("chunk LOD validation did not pass: %s" % str(chunk_lod.get("sample_failures", [])))
		return
	if int(chunk_lod.get("same_lod_matching_pairs", 0)) != 9:
		_fail("same LOD chunk seam matching changed")
		return
	if str(chunk_lod.get("lod_transition_probe_status", "")) != "Ok":
		_fail("LOD transition mask probe did not mesh ok")
		return
	if int(chunk_lod.get("mixed_lod_matching_pairs", 0)) != 12:
		_fail("mixed LOD seam matching changed")
		return
	if int(chunk_lod.get("visible_crack_count", -1)) != 0:
		_fail("mixed LOD fixture detected a visible crack")
		return
	var reference_terrain: Dictionary = lab.validate_reference_terrain()
	if str(reference_terrain.get("schema", "")) != "world_transvoxel.cell_lab.reference_terrain_validation.v1":
		_fail("unexpected reference terrain validation schema")
		return
	if str(reference_terrain.get("status", "")) != "PASS":
		_fail("reference terrain validation did not pass: %s" % str(reference_terrain.get("sample_failures", [])))
		return
	if int(reference_terrain.get("chunk_count", 0)) != 12:
		_fail("reference terrain chunk count changed")
		return
	if int(reference_terrain.get("visible_crack_count", -1)) != 0:
		_fail("reference terrain detected a visible crack")
		return
	if int(reference_terrain.get("determinism_failures", -1)) != 0:
		_fail("reference terrain was not deterministic")
		return
	var terrain_buffers: Dictionary = reference_terrain.get("buffer_validation", {})
	if int(terrain_buffers.get("nonfinite_vertices", -1)) != 0 \
			or int(terrain_buffers.get("degenerate_triangles", -1)) != 0 \
			or int(terrain_buffers.get("duplicate_triangles", -1)) != 0 \
			or int(terrain_buffers.get("winding_normal_conflicts", -1)) != 0:
		_fail("reference terrain mesh integrity changed")
		return
	if int(terrain_buffers.get("local_winding_normal_disagreements", -1)) != 8:
		_fail("reference terrain local normal diagnostic changed")
		return
	var feature_validation: Dictionary = reference_terrain.get("feature_validation", {})
	if int(feature_validation.get("passing_probes", 0)) != 15 \
			or int(feature_validation.get("failing_probes", -1)) != 0:
		_fail("reference terrain feature probes did not pass")
		return
	var reference_seams: Dictionary = reference_terrain.get("seam_validation", {})
	if int(reference_seams.get("same_lod_matching_pairs", 0)) != 12:
		_fail("reference terrain same-LOD seams changed")
		return
	if int(reference_seams.get("mixed_lod_matching_interfaces", 0)) != 4:
		_fail("reference terrain mixed-LOD seams changed")
		return
	var reference_edits: Dictionary = reference_terrain.get("edit_validation", {})
	if int(reference_edits.get("passing_steps", 0)) != 8 \
			or int(reference_edits.get("deterministic_failures", -1)) != 0:
		_fail("reference terrain edit workflow changed")
		return
	var observatory: Dictionary = reference_terrain.get("terrain_observatory", {})
	if str(observatory.get("schema", "")) \
			!= "world_transvoxel.cell_lab.terrain_observatory_validation.v1":
		_fail("unexpected terrain observatory validation schema")
		return
	if str(observatory.get("status", "")) != "PASS" \
			or int(observatory.get("passing_views", 0)) != 7:
		_fail("terrain observatory validation did not pass")
		return
	var observatory_standard: Dictionary = observatory.get("standard_signature", {})
	if int(observatory_standard.get("passing_seam_edges", 0)) != 501 \
			or int(observatory_standard.get("failing_seam_edges", -1)) != 0:
		_fail("terrain observatory exact seam edges changed")
		return
	var edit_sequence: Dictionary = lab.validate_edit_sequence()
	if str(edit_sequence.get("schema", "")) != "world_transvoxel.cell_lab.edit_sequence_validation.v2":
		_fail("unexpected edit sequence validation schema")
		return
	if str(edit_sequence.get("status", "")) != "PASS":
		_fail("edit sequence validation did not pass: %s" % str(edit_sequence.get("sample_failures", [])))
		return
	if int(edit_sequence.get("determinism_failures", -1)) != 0:
		_fail("edit sequence replay was not deterministic")
		return
	var edit_corpus: Dictionary = lab.validate_edit_corpus()
	if str(edit_corpus.get("status", "")) != "PASS":
		_fail("edit corpus did not pass: %s" % str(edit_corpus.get("sample_failures", [])))
		return
	if int(edit_corpus.get("passing_fixtures", 0)) != 5:
		_fail("edit corpus fixture count changed")
		return
	var standards: Dictionary = lab.validate_standards_corpus()
	if str(standards.get("schema", "")) != "world_transvoxel.cell_lab.standards_corpus.v1":
		_fail("unexpected standards corpus schema")
		return
	if str(standards.get("status", "")) != "PASS":
		_fail("standards corpus did not pass: %s" % str(standards.get("sample_failures", [])))
		return
	if int(standards.get("passing_repros", 0)) != 3:
		_fail("committed repro standards count changed")
		return
	if int(standards.get("passing_case_standards", 0)) != 12:
		_fail("case standards count changed")
		return
	if int(standards.get("passing_reference_terrain_standards", 0)) != 1:
		_fail("reference terrain standard changed")
		return
	if int(standards.get("passing_visual_standards", 0)) != 11:
		_fail("visual standards count changed")
		return
	lab.inspection_mode = LabScript.InspectionMode.REGULAR_CASE
	lab.selected_regular_case = 42
	report = lab.rebuild()
	var inspection: Dictionary = report.get("inspection", {})
	if str(inspection.get("mode", "")) != "REGULAR_CASE" or int(inspection.get("triangles", 0)) != 3:
		_fail("regular selected-case inspection changed")
		return
	lab.inspection_mode = LabScript.InspectionMode.TRANSITION_CASE
	lab.selected_transition_case = 341
	lab.selected_transition_orientation = 5
	report = lab.rebuild()
	inspection = report.get("inspection", {})
	if str(inspection.get("mode", "")) != "TRANSITION_CASE" or int(inspection.get("triangles", 0)) != 12:
		_fail("transition selected-case inspection changed")
		return
	lab.inspection_mode = LabScript.InspectionMode.MIXED_LOD
	lab.selected_chunk_lod = 1
	lab.selected_chunk_face = 1
	report = lab.rebuild()
	inspection = report.get("inspection", {})
	if str(inspection.get("status", "")) != "Ok":
		_fail("mixed LOD inspection fixture changed")
		return
	lab.inspection_mode = LabScript.InspectionMode.REFERENCE_TERRAIN
	report = lab.rebuild()
	inspection = report.get("inspection", {})
	if str(inspection.get("status", "")) != "PASS" \
		or int(inspection.get("chunk_count", 0)) != 12 \
		or int(inspection.get("triangles", 0)) != 11142 \
		or str(inspection.get("observatory_view", "")) != "SURFACE":
		_fail("reference terrain inspection fixture changed")
		return
	lab.inspection_mode = LabScript.InspectionMode.PATCH
	report = lab.rebuild()
	var integration_import: Dictionary = lab.import_integration_snapshot({
		"center": {"x": 0.0, "y": 0.0, "z": 0.0},
		"radius": 2.0,
		"mode": "watertightness",
		"open_edges": 2,
		"nonmanifold_edges": 0,
		"operation_summaries": [{
			"operation": "carve_sdf_sphere",
			"center": {"x": 0.0, "y": 0.0, "z": 0.0},
			"radius": 0.75,
			"material_id": 1,
		}],
	}, "smoke_fixture")
	if not bool(integration_import.get("ok", false)):
		_fail("integration snapshot import failed")
		return
	var comparison: Dictionary = integration_import.get("comparison", {})
	if str(comparison.get("suspected_fix_layer", "")) != "integration":
		_fail("integration reduction did not classify the source layer")
		return
	report = lab.apply_repro_snapshot(repro)
	var performance: Dictionary = lab.run_performance_baselines(2)
	if str(performance.get("schema", "")) != "world_transvoxel.cell_lab.performance_baselines.v2":
		_fail("unexpected performance baselines schema")
		return
	if str(performance.get("status", "")) != "PASS":
		_fail("performance baselines did not pass")
		return
	if float(performance.get("regular_cell_average_us", 0.0)) <= 0.0:
		_fail("regular cell benchmark did not record time")
		return
	if float(performance.get("samples_per_ms", 0.0)) <= 0.0:
		_fail("chunk sample throughput was not recorded")
		return
	if float(performance.get("reference_terrain_average_ms", 0.0)) <= 0.0:
		_fail("reference terrain benchmark did not record time")
		return
	if float(performance.get("terrain_observatory_average_ms", 0.0)) <= 0.0:
		_fail("terrain observatory benchmark did not record time")
		return
	lab.apply_dig_at(Vector3.ZERO, 1.0)
	report = lab.get_last_report()
	if int(report.get("edit_count", 0)) != 1:
		_fail("dig edit was not recorded")
		return
	var benchmark: Dictionary = lab.benchmark_rebuild(3)
	if float(benchmark.get("average_build_ms", 0.0)) <= 0.0:
		_fail("benchmark did not record build time")
		return
	lab.free()
	print("WT_CELL_LAB_SMOKE_PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error("WT_CELL_LAB_SMOKE_FAIL: " + message)
	quit(1)
