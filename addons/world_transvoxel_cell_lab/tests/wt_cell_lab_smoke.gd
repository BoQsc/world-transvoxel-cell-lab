extends SceneTree

const LabScript := preload("res://addons/world_transvoxel_cell_lab/lab/wt_transvoxel_cell_lab.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab := LabScript.new()
	root.add_child(lab)
	lab.cells_x = 6
	lab.cells_y = 6
	lab.cells_z = 6
	lab.field_mode = LabScript.FieldMode.SPHERE
	lab.prefer_native_cell_probe = false
	var report: Dictionary = lab.rebuild()
	if report.get("schema") != "world_transvoxel.cell_lab.report.v1":
		_fail("unexpected report schema")
		return
	if int(report.get("triangles", 0)) <= 0:
		_fail("initial lab mesh has no triangles")
		return
	if str(report.get("render_authority", "")) != "LOCAL_PREVIEW_NOT_EXACT_TRANSVOXEL":
		_fail("local render authority is not explicit")
		return
	if int(report.get("interior_open_edges", -1)) != 0:
		_fail("sphere preview has interior open edges")
		return
	if int(report.get("nonmanifold_edges", -1)) != 0:
		_fail("sphere preview has nonmanifold edges")
		return
	if int(report.get("orientation_conflict_edges", -1)) != 0:
		_fail("sphere preview has orientation conflicts")
		return
	if ClassDB.class_exists("WorldTransvoxelCellProbe"):
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
		lab.prefer_native_cell_probe = true
		report = lab.rebuild()
		if str(report.get("render_authority", "")) != "NATIVE_TRANSVOXEL_BACKEND_AUTHORITATIVE":
			_fail("native render authority was not used")
			return
		if str(report.get("correctness_claim", "")) != "exact_regular_cell_backend_patch_v1":
			_fail("native correctness claim was not explicit")
			return
		if int(report.get("triangles", 0)) <= 0:
			_fail("native exact mesh has no triangles")
			return
		if int(report.get("failed_cells", -1)) != 0:
			_fail("native exact mesh had failed cells")
			return
		if int(report.get("nonmanifold_edges", -1)) != 0:
			_fail("native exact mesh has nonmanifold edges")
			return
		if int(report.get("orientation_conflict_edges", -1)) != 0:
			_fail("native exact mesh has orientation conflicts")
			return
		if str(report.get("transition_status", "")) != "Ok":
			_fail("native exact transition probe did not mesh ok")
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
