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
	if report.get("schema") != "world_transvoxel.cell_lab.report.v1":
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
	if str(report.get("correctness_claim", "")) != "exact_regular_transition_and_lod0_chunk_backend_probe_v2":
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
	var repro: Dictionary = lab.make_repro_snapshot()
	if str(repro.get("schema", "")) != "world_transvoxel.cell_lab.repro.v1":
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
	var regular_corpus: Dictionary = lab.validate_regular_case_corpus()
	if str(regular_corpus.get("schema", "")) != "world_transvoxel.cell_lab.regular_case_corpus.v1":
		_fail("unexpected regular case corpus schema")
		return
	if str(regular_corpus.get("status", "")) != "PASS":
		_fail("regular case corpus did not pass: %s" % str(regular_corpus.get("sample_failures", [])))
		return
	if int(regular_corpus.get("ok_cases", 0)) != 254 or int(regular_corpus.get("empty_cases", 0)) != 2:
		_fail("regular case corpus counts changed")
		return
	var transition_corpus: Dictionary = lab.validate_transition_case_corpus()
	if str(transition_corpus.get("schema", "")) != "world_transvoxel.cell_lab.transition_case_corpus.v1":
		_fail("unexpected transition case corpus schema")
		return
	if str(transition_corpus.get("status", "")) != "PASS":
		_fail("transition case corpus did not pass: %s" % str(transition_corpus.get("sample_failures", [])))
		return
	if int(transition_corpus.get("ok_cases", 0)) != 3060 or int(transition_corpus.get("empty_cases", 0)) != 12:
		_fail("transition case corpus counts changed")
		return
	var chunk_lod: Dictionary = lab.validate_chunk_lod_seams()
	if str(chunk_lod.get("schema", "")) != "world_transvoxel.cell_lab.chunk_lod_validation.v1":
		_fail("unexpected chunk LOD validation schema")
		return
	if str(chunk_lod.get("status", "")) != "PASS":
		_fail("chunk LOD validation did not pass: %s" % str(chunk_lod.get("sample_failures", [])))
		return
	if int(chunk_lod.get("same_lod_matching_pairs", 0)) != 3:
		_fail("same LOD chunk seam matching changed")
		return
	if str(chunk_lod.get("lod_transition_probe_status", "")) != "Ok":
		_fail("LOD transition mask probe did not mesh ok")
		return
	var edit_sequence: Dictionary = lab.validate_edit_sequence()
	if str(edit_sequence.get("schema", "")) != "world_transvoxel.cell_lab.edit_sequence_validation.v1":
		_fail("unexpected edit sequence validation schema")
		return
	if str(edit_sequence.get("status", "")) != "PASS":
		_fail("edit sequence validation did not pass: %s" % str(edit_sequence.get("sample_failures", [])))
		return
	var performance: Dictionary = lab.run_performance_baselines(2)
	if str(performance.get("schema", "")) != "world_transvoxel.cell_lab.performance_baselines.v1":
		_fail("unexpected performance baselines schema")
		return
	if str(performance.get("status", "")) != "PASS":
		_fail("performance baselines did not pass")
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
