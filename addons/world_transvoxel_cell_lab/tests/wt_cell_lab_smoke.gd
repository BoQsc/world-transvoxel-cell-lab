extends SceneTree

const LabScript := preload("res://addons/world_transvoxel_cell_lab/lab/wt_transvoxel_cell_lab.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ClassDB.class_exists("WorldTransvoxelCellProbe"):
		_fail("WorldTransvoxelCellProbe is required")
		return
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
