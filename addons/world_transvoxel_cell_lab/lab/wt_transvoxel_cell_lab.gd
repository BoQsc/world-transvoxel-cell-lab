@tool
extends Node3D
class_name WtTransvoxelCellLab

enum FieldMode { PLANE, SPHERE, TUNNEL, SADDLE, WAVES }
enum InspectionMode { PATCH, REGULAR_CASE, TRANSITION_CASE, MIXED_LOD, REFERENCE_TERRAIN }

const Contracts := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_contracts.gd")
const MeshAnalysis := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_mesh_analysis.gd")
const CaseValidator := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_case_validator.gd")
const ChunkValidator := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_chunk_validator.gd")
const EditValidator := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_edit_validator.gd")
const PerformanceService := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_performance.gd")
const ReproStore := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_repro_store.gd")
const ReportBuilder := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_report_builder.gd")
const IntegrationAdapter := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_integration_adapter.gd")
const InspectionPresenter := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_inspection_presenter.gd")
const StandardsRunner := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_standards_runner.gd")
const ReferenceTerrain := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_reference_terrain.gd")

const REPORT_SCHEMA := Contracts.REPORT_SCHEMA
const REPRO_SCHEMA := Contracts.REPRO_SCHEMA
const REGULAR_CASE_CORPUS_SCHEMA := Contracts.REGULAR_CASE_CORPUS_SCHEMA
const TRANSITION_CASE_CORPUS_SCHEMA := Contracts.TRANSITION_CASE_CORPUS_SCHEMA
const CHUNK_LOD_VALIDATION_SCHEMA := Contracts.CHUNK_LOD_VALIDATION_SCHEMA
const EDIT_SEQUENCE_VALIDATION_SCHEMA := Contracts.EDIT_SEQUENCE_VALIDATION_SCHEMA
const PERFORMANCE_BASELINES_SCHEMA := Contracts.PERFORMANCE_BASELINES_SCHEMA
const NATIVE_REGULAR_IMPLEMENTATION := Contracts.NATIVE_REGULAR_IMPLEMENTATION
const NATIVE_AUTHORITY := Contracts.NATIVE_AUTHORITY
const CELL_PROBE_CORRECTNESS_CLAIM := Contracts.CELL_PROBE_CORRECTNESS_CLAIM
const LAB_CORRECTNESS_CLAIM := Contracts.LAB_CORRECTNESS_CLAIM
const LAB_SCOPE := Contracts.LAB_SCOPE
const PRIMARY_VALIDATION_DOMAIN := Contracts.PRIMARY_VALIDATION_DOMAIN
const PRIMITIVE_SCOPE := Contracts.PRIMITIVE_SCOPE
const VALIDATION_STANDARD := Contracts.VALIDATION_STANDARD
const AUTHORITY_MODEL := Contracts.AUTHORITY_MODEL
const UPSTREAM_CORRECTION_POLICY := Contracts.UPSTREAM_CORRECTION_POLICY
const INTEGRATION_GAME_ROLE := Contracts.INTEGRATION_GAME_ROLE
const INTEGRATION_GAME_DIAGNOSTIC_POLICY := Contracts.INTEGRATION_GAME_DIAGNOSTIC_POLICY
const CHUNK_PROBE_IMPLEMENTATION := Contracts.CHUNK_PROBE_IMPLEMENTATION
const CHUNK_PROBE_CELLS_PER_AXIS := Contracts.CHUNK_PROBE_CELLS_PER_AXIS
const CHUNK_FACE_NAMES := Contracts.CHUNK_FACE_NAMES
const CORNER_COUNT := Contracts.REGULAR_CORNER_COUNT
const TRANSITION_SAMPLE_COUNT := Contracts.TRANSITION_SAMPLE_COUNT
const TRANSITION_ORIENTATION_NAMES := Contracts.TRANSITION_ORIENTATION_NAMES
const TRANSITION_ORIENTATION_POSITIVE_Z := Contracts.TRANSITION_ORIENTATION_POSITIVE_Z

@export var inspection_mode: InspectionMode = InspectionMode.PATCH:
	set(value):
		inspection_mode = value
		_request_rebuild()
@export_range(0, 255, 1) var selected_regular_case: int = 1:
	set(value):
		selected_regular_case = clampi(value, 0, 255)
		_request_rebuild()
@export_range(0, 511, 1) var selected_transition_case: int = 1:
	set(value):
		selected_transition_case = clampi(value, 0, 511)
		_request_rebuild()
@export_range(0, 5, 1) var selected_transition_orientation: int = 4:
	set(value):
		selected_transition_orientation = clampi(value, 0, 5)
		_request_rebuild()
@export_range(1, 3, 1) var selected_chunk_lod: int = 1:
	set(value):
		selected_chunk_lod = clampi(value, 1, 3)
		_request_rebuild()
@export_range(0, 5, 1) var selected_chunk_face: int = 1:
	set(value):
		selected_chunk_face = clampi(value, 0, 5)
		_request_rebuild()
@export_range(0, 11, 1) var selected_reference_chunk: int = 8:
	set(value):
		selected_reference_chunk = clampi(value, 0, 11)
		_request_rebuild()
@export var reference_edit_cursor := Vector3(16.0, 12.5, 16.0):
	set(value):
		reference_edit_cursor = value
		_request_rebuild()
@export var show_reference_chunk_bounds: bool = true:
	set(value):
		show_reference_chunk_bounds = value
		_request_rebuild()

@export_range(1, 24, 1) var cells_x: int = 4:
	set(value):
		cells_x = clampi(value, 1, 24)
		_request_rebuild()
@export_range(1, 24, 1) var cells_y: int = 4:
	set(value):
		cells_y = clampi(value, 1, 24)
		_request_rebuild()
@export_range(1, 24, 1) var cells_z: int = 4:
	set(value):
		cells_z = clampi(value, 1, 24)
		_request_rebuild()
@export_range(0.1, 16.0, 0.05) var cell_size: float = 1.0:
	set(value):
		cell_size = maxf(value, 0.05)
		_request_rebuild()
@export var field_mode: FieldMode = FieldMode.PLANE:
	set(value):
		field_mode = value
		_request_rebuild()
@export_range(-64.0, 64.0, 0.01) var isovalue: float = 0.0:
	set(value):
		isovalue = value
		_request_rebuild()
@export_range(-32.0, 32.0, 0.01) var surface_height: float = 0.0:
	set(value):
		surface_height = value
		_request_rebuild()
@export_range(0.1, 64.0, 0.05) var sphere_radius: float = 2.1:
	set(value):
		sphere_radius = maxf(value, 0.05)
		_request_rebuild()
@export_range(0.1, 16.0, 0.05) var edit_radius: float = 1.25
@export_range(1, 65535, 1) var construct_material: int = 4
@export var show_sample_points: bool = true:
	set(value):
		show_sample_points = value
		_request_rebuild()
@export var show_edit_markers: bool = true:
	set(value):
		show_edit_markers = value
		_request_rebuild()
@export var show_transition_frame: bool = true:
	set(value):
		show_transition_frame = value
		_request_rebuild()
@export var show_chunk_probe: bool = true:
	set(value):
		show_chunk_probe = value
		_request_rebuild()
@export var show_probe_labels: bool = true:
	set(value):
		show_probe_labels = value
		_request_rebuild()
@export var wireframe: bool = false:
	set(value):
		wireframe = value
		_make_materials()
		_request_rebuild()
@export var auto_rebuild: bool = true
@export var rebuild_now: bool = false:
	set(value):
		rebuild_now = false
		if value:
			call_deferred("rebuild")

var edits: Array[Dictionary] = []
var _last_report: Dictionary = {}
var _validation_results: Dictionary = {}
var _native_cell_probe: RefCounted
var _mesh_root: Node3D
var _sample_root: Node3D
var _marker_root: Node3D
var _label_root: Node3D
var _surface_material: StandardMaterial3D
var _wire_material: StandardMaterial3D
var _solid_sample_material: StandardMaterial3D
var _empty_sample_material: StandardMaterial3D
var _dig_marker_material: StandardMaterial3D
var _construct_marker_material: StandardMaterial3D
var _transition_material: StandardMaterial3D
var _transition_surface_material: StandardMaterial3D
var _chunk_surface_material: StandardMaterial3D
var _inspection_edge_material: StandardMaterial3D
var _inspection_normal_material: StandardMaterial3D
var _inspection_low_sample_material: StandardMaterial3D
var _inspection_fine_chunk_material: StandardMaterial3D
var _inspection_basis_material: StandardMaterial3D
var _chunk_validator := ChunkValidator.new()
var _edit_validator := EditValidator.new()
var _performance_service := PerformanceService.new()
var _inspection_presenter := InspectionPresenter.new()
var _standards_runner := StandardsRunner.new()
var _reference_terrain := ReferenceTerrain.new()


func _ready() -> void:
	_make_materials()
	rebuild()


func rebuild() -> Dictionary:
	var start_usec := Time.get_ticks_usec()
	_ensure_roots()
	_clear_children(_mesh_root)
	_clear_children(_sample_root)
	_clear_children(_marker_root)
	_clear_children(_label_root)

	var mesh_data := _build_patch_mesh_data()
	var transition_data := _build_transition_probe_mesh_data()
	var chunk_data := _build_chunk_probe_mesh_data()
	var inspection_report := {}
	if inspection_mode == InspectionMode.PATCH:
		var mesh := _make_array_mesh(mesh_data)
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "cell_lab_preview_mesh"
		mesh_instance.mesh = mesh
		mesh_instance.material_override = _surface_material
		_mesh_root.add_child(mesh_instance)
		if wireframe:
			var line_instance := MeshInstance3D.new()
			line_instance.name = "cell_lab_wire_edges"
			line_instance.mesh = _make_edge_line_mesh(mesh_data)
			line_instance.material_override = _wire_material
			_mesh_root.add_child(line_instance)
		var transition_mesh := _make_array_mesh(transition_data)
		var transition_instance := MeshInstance3D.new()
		transition_instance.name = "cell_lab_transition_probe_mesh"
		transition_instance.mesh = transition_mesh
		transition_instance.material_override = _transition_surface_material
		_mesh_root.add_child(transition_instance)
		if wireframe:
			var transition_line_instance := MeshInstance3D.new()
			transition_line_instance.name = "cell_lab_transition_probe_wire"
			transition_line_instance.mesh = _make_edge_line_mesh(transition_data)
			transition_line_instance.material_override = _wire_material
			_mesh_root.add_child(transition_line_instance)
		if show_chunk_probe:
			var chunk_instance := MeshInstance3D.new()
			chunk_instance.name = "production_chunk_probe_mesh"
			chunk_instance.mesh = _make_array_mesh(chunk_data)
			chunk_instance.material_override = _chunk_surface_material
			_mesh_root.add_child(chunk_instance)
			if wireframe:
				var chunk_line_instance := MeshInstance3D.new()
				chunk_line_instance.name = "production_chunk_probe_wire"
				chunk_line_instance.mesh = _make_edge_line_mesh(chunk_data)
				chunk_line_instance.material_override = _wire_material
				_mesh_root.add_child(chunk_line_instance)
		if show_sample_points:
			_build_sample_markers()
		if show_edit_markers:
			_build_edit_markers()
		if show_transition_frame:
			_build_transition_frame()
		if show_probe_labels:
			_build_probe_labels(mesh_data, transition_data, chunk_data)
	else:
		inspection_report = _inspection_presenter.render(
			self,
			_mesh_root,
			_sample_root,
			_label_root,
			_inspection_materials()
		)

	var elapsed_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
	_last_report = _make_report(mesh_data, transition_data, chunk_data, elapsed_ms)
	_last_report["inspection"] = inspection_report
	for validation_key in _validation_results.keys():
		ReportBuilder.attach_validation(_last_report, str(validation_key), _validation_results[validation_key])
	return _last_report


func get_last_report() -> Dictionary:
	if _last_report.is_empty():
		rebuild()
	return _last_report


func make_repro_snapshot(metadata: Dictionary = {}) -> Dictionary:
	return ReproStore.make_snapshot(self, metadata)


func apply_repro_snapshot(snapshot: Dictionary) -> Dictionary:
	return ReproStore.apply_snapshot(self, snapshot)


func save_repro_snapshot(metadata: Dictionary = {}) -> Dictionary:
	return ReproStore.save_snapshot(make_repro_snapshot(metadata))


func list_repro_snapshots(include_committed: bool = true) -> Array[Dictionary]:
	return ReproStore.list_repros(include_committed)


func load_repro_snapshot(path: String) -> Dictionary:
	var loaded := ReproStore.load_snapshot(path)
	if not bool(loaded.get("ok", false)):
		return loaded
	var report := apply_repro_snapshot(loaded.get("snapshot", {}))
	return {
		"ok": str(report.get("status", "")) in ["PASS", "FAIL"],
		"path": path,
		"report": report,
	}


func validate_regular_case_corpus() -> Dictionary:
	var result := CaseValidator.validate_regular(_get_native_cell_probe())
	_capture_failed_case_repros(result, "regular")
	_attach_validation_result("regular_case_corpus", result)
	return result


func validate_transition_case_corpus() -> Dictionary:
	var result := CaseValidator.validate_transition(_get_native_cell_probe())
	_capture_failed_case_repros(result, "transition")
	_attach_validation_result("transition_case_corpus", result)
	return result


func validate_chunk_lod_seams() -> Dictionary:
	var result := _chunk_validator.validate(_get_native_cell_probe())
	_attach_validation_result("chunk_lod_validation", result)
	return result


func validate_edit_sequence() -> Dictionary:
	var result := _edit_validator.validate(self)
	_attach_validation_result("edit_sequence_validation", result)
	return result


func validate_edit_corpus() -> Dictionary:
	var result := _edit_validator.validate_corpus(self)
	_attach_validation_result("edit_corpus", result)
	return result


func run_performance_baselines(iterations: int = 3) -> Dictionary:
	var result := _performance_service.run(self, _chunk_validator, _edit_validator, iterations)
	_attach_validation_result("performance_baselines", result)
	return result


func validate_standards_corpus() -> Dictionary:
	var result := _standards_runner.run(self)
	_attach_validation_result("standards_corpus", result)
	return result


func describe_regular_case(case_code: int = selected_regular_case) -> Dictionary:
	return CaseValidator.describe_regular_case(_get_native_cell_probe(), case_code)


func describe_transition_case(
	case_code: int = selected_transition_case,
	orientation: int = selected_transition_orientation
) -> Dictionary:
	return CaseValidator.describe_transition_case(
		_get_native_cell_probe(),
		case_code,
		orientation
	)


func build_mixed_lod_fixture(
	face: int = selected_chunk_face,
	coarse_lod: int = selected_chunk_lod
) -> Dictionary:
	return _chunk_validator.build_mixed_lod_fixture(
		_get_native_cell_probe(),
		face,
		coarse_lod
	)


func build_reference_terrain() -> Dictionary:
	return _reference_terrain.build(_get_native_cell_probe())


func validate_reference_terrain() -> Dictionary:
	var result := _reference_terrain.validate(_get_native_cell_probe())
	_attach_validation_result("reference_terrain_validation", result)
	return result


func describe_reference_terrain_standard() -> Dictionary:
	return _reference_terrain.standard_signature(_get_native_cell_probe())


func benchmark_reference_terrain(iterations: int = 2) -> Dictionary:
	return _reference_terrain.benchmark(_get_native_cell_probe(), iterations)


func get_reference_terrain_edits() -> Array[Dictionary]:
	return _reference_terrain.edits.duplicate(true)


func set_reference_terrain_edits(values: Array) -> void:
	_reference_terrain.set_edits(values)
	if auto_rebuild:
		rebuild()


func get_reference_terrain_dirty_region() -> AABB:
	return _reference_terrain.dirty_region()


func apply_reference_terrain_dig(
	center: Vector3 = reference_edit_cursor,
	radius: float = -1.0
) -> void:
	_apply_reference_terrain_edit("dig", center, radius)


func apply_reference_terrain_construct(
	center: Vector3 = reference_edit_cursor,
	radius: float = -1.0
) -> void:
	_apply_reference_terrain_edit("construct", center, radius)


func clear_reference_terrain_edits() -> void:
	_reference_terrain.clear_edits()
	rebuild()


func import_integration_snapshot(snapshot: Dictionary, source_reference: String = "") -> Dictionary:
	var result := IntegrationAdapter.import_snapshot(snapshot, self, source_reference)
	if bool(result.get("ok", false)):
		_attach_validation_result("integration_comparison", result.get("comparison", {}))
	return result


func import_integration_snapshot_file(path: String) -> Dictionary:
	var result := IntegrationAdapter.import_file(path, self)
	if bool(result.get("ok", false)):
		_attach_validation_result("integration_comparison", result.get("comparison", {}))
	return result


func get_native_probe() -> RefCounted:
	return _get_native_cell_probe()


func get_affected_cells() -> Array[Vector3i]:
	var affected: Dictionary = {}
	var origin := _patch_origin()
	for edit_value in edits:
		var edit: Dictionary = edit_value
		var center: Vector3 = edit.get("center", Vector3.ZERO)
		var radius := maxf(float(edit.get("radius", edit_radius)), 0.0)
		var local_min := (center - Vector3.ONE * radius - origin) / cell_size
		var local_max := (center + Vector3.ONE * radius - origin) / cell_size
		var minimum := Vector3i(
			clampi(floori(local_min.x), 0, cells_x - 1),
			clampi(floori(local_min.y), 0, cells_y - 1),
			clampi(floori(local_min.z), 0, cells_z - 1)
		)
		var maximum := Vector3i(
			clampi(floori(local_max.x), 0, cells_x - 1),
			clampi(floori(local_max.y), 0, cells_y - 1),
			clampi(floori(local_max.z), 0, cells_z - 1)
		)
		for z in range(minimum.z, maximum.z + 1):
			for y in range(minimum.y, maximum.y + 1):
				for x in range(minimum.x, maximum.x + 1):
					var coordinate := Vector3i(x, y, z)
					var cell_box := AABB(
						origin + Vector3(coordinate) * cell_size,
						Vector3.ONE * cell_size
					)
					if _sphere_intersects_aabb(center, radius, cell_box):
						affected[coordinate] = true
	var result: Array[Vector3i] = []
	for coordinate in affected.keys():
		result.append(coordinate)
	result.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return Vector3i(a.z, a.y, a.x) < Vector3i(b.z, b.y, b.x)
	)
	return result


func get_dirty_region() -> AABB:
	if edits.is_empty():
		return AABB()
	var patch_bounds := AABB(
		_patch_origin(),
		Vector3(cells_x, cells_y, cells_z) * cell_size
	)
	var dirty := AABB()
	var has_dirty := false
	for edit_value in edits:
		var edit: Dictionary = edit_value
		var center: Vector3 = edit.get("center", Vector3.ZERO)
		var radius := maxf(float(edit.get("radius", edit_radius)), 0.0)
		var bounds := AABB(center - Vector3.ONE * radius, Vector3.ONE * radius * 2.0)
		bounds = bounds.intersection(patch_bounds)
		if bounds.size == Vector3.ZERO:
			continue
		dirty = bounds if not has_dirty else dirty.merge(bounds)
		has_dirty = true
	return dirty


func _sphere_intersects_aabb(center: Vector3, radius: float, bounds: AABB) -> bool:
	var closest := Vector3(
		clampf(center.x, bounds.position.x, bounds.end.x),
		clampf(center.y, bounds.position.y, bounds.end.y),
		clampf(center.z, bounds.position.z, bounds.end.z)
	)
	return closest.distance_squared_to(center) <= radius * radius


func _attach_validation_result(key: String, result: Dictionary) -> void:
	_validation_results[key] = result
	if _last_report.is_empty():
		rebuild()
	ReportBuilder.attach_validation(_last_report, key, result)


func _capture_failed_case_repros(result: Dictionary, cell_type: String) -> void:
	if str(result.get("status", "")) != "FAIL":
		result["saved_failure_repros"] = []
		return
	var previous_auto_rebuild := auto_rebuild
	var previous_mode := inspection_mode
	var previous_regular_case := selected_regular_case
	var previous_transition_case := selected_transition_case
	var previous_orientation := selected_transition_orientation
	auto_rebuild = false
	var saved_paths: Array[String] = []
	var seen := {}
	for failure_value in result.get("sample_failures", []):
		var failure: Dictionary = failure_value
		var case_code := int(failure.get("case", -1))
		if case_code < 0:
			continue
		var orientation_name := str(failure.get("orientation", ""))
		var orientation := Contracts.TRANSITION_ORIENTATION_NAMES.find(orientation_name)
		var key := "%s:%d:%d" % [cell_type, case_code, orientation]
		if seen.has(key):
			continue
		seen[key] = true
		if cell_type == "regular":
			inspection_mode = InspectionMode.REGULAR_CASE
			selected_regular_case = case_code
		else:
			inspection_mode = InspectionMode.TRANSITION_CASE
			selected_transition_case = case_code
			selected_transition_orientation = maxi(orientation, 0)
		var snapshot := make_repro_snapshot({
			"name": "%s_case_%d_failure" % [cell_type, case_code],
			"notes": str(failure.get("message", "case corpus failure")),
			"expected_label": "known_failure",
			"source_layer": "world_transvoxel",
			"source_reference": str(result.get("schema", "")),
		})
		snapshot["case_failure"] = failure.duplicate(true)
		var saved := ReproStore.save_snapshot(snapshot)
		if bool(saved.get("ok", false)):
			saved_paths.append(str(saved.get("absolute_path", saved.get("path", ""))))
	auto_rebuild = false
	inspection_mode = previous_mode
	selected_regular_case = previous_regular_case
	selected_transition_case = previous_transition_case
	selected_transition_orientation = previous_orientation
	auto_rebuild = previous_auto_rebuild
	result["saved_failure_repros"] = saved_paths


func get_status_line() -> String:
	var report := get_last_report()
	return "scope=%s primary=%s primitive=%s authority_model=%s integration=%s status=%s regular_patch cells=%s tris=%d interior_open=%d boundary_open=%d nonmanifold=%d orient=%d transition_cell=%s tris=%d production_chunk=%s tris=%d edits=%d %.2fms exact_backend=%s" % [
		str(report.get("lab_scope", LAB_SCOPE)),
		str(report.get("primary_validation_domain", PRIMARY_VALIDATION_DOMAIN)),
		str(report.get("primitive_scope", PRIMITIVE_SCOPE)),
		str(report.get("authority_model", AUTHORITY_MODEL)),
		str(report.get("integration_game_role", INTEGRATION_GAME_ROLE)),
		str(report.get("status", "UNKNOWN")),
		str(report.get("cells", Vector3i.ZERO)),
		int(report.get("triangles", 0)),
		int(report.get("interior_open_edges", 0)),
		int(report.get("boundary_open_edges", 0)),
		int(report.get("nonmanifold_edges", 0)),
		int(report.get("orientation_conflict_edges", 0)),
		str(report.get("transition_status", "unavailable")),
		int(report.get("transition_triangles", 0)),
		str(report.get("chunk_probe_status", "unavailable")),
		int(report.get("chunk_probe_triangles", 0)),
		int(report.get("edit_count", 0)),
		float(report.get("build_ms", 0.0)),
		str(report.get("native_cell_probe_available", false)),
	]


func set_extent(extent: Vector3i) -> void:
	cells_x = clampi(extent.x, 1, 24)
	cells_y = clampi(extent.y, 1, 24)
	cells_z = clampi(extent.z, 1, 24)
	rebuild()


func expand_cells(axis: String, delta: int) -> void:
	match axis:
		"x":
			cells_x = clampi(cells_x + delta, 1, 24)
		"y":
			cells_y = clampi(cells_y + delta, 1, 24)
		"z":
			cells_z = clampi(cells_z + delta, 1, 24)
	rebuild()


func apply_dig_at(center: Vector3 = Vector3.ZERO, radius: float = -1.0) -> void:
	_apply_edit("dig", center, radius)


func apply_construct_at(center: Vector3 = Vector3.ZERO, radius: float = -1.0) -> void:
	_apply_edit("construct", center, radius)


func clear_edits() -> void:
	edits.clear()
	rebuild()


func benchmark_rebuild(iterations: int = 24) -> Dictionary:
	iterations = clampi(iterations, 1, 240)
	var times: Array[float] = []
	var total_triangles := 0
	for _i in range(iterations):
		var start_usec := Time.get_ticks_usec()
		var data := _build_patch_mesh_data()
		var transition_data := _build_transition_probe_mesh_data()
		var chunk_data := _build_chunk_probe_mesh_data()
		times.append(float(Time.get_ticks_usec() - start_usec) / 1000.0)
		total_triangles += int(data.get("triangles", 0)) + int(transition_data.get("triangles", 0)) + int(chunk_data.get("triangles", 0))
	var sum := 0.0
	var maximum := 0.0
	for value in times:
		sum += value
		maximum = maxf(maximum, value)
	var result := {
		"schema": "world_transvoxel.cell_lab.benchmark.v1",
		"iterations": iterations,
		"average_build_ms": sum / float(iterations),
		"maximum_build_ms": maximum,
		"average_triangles": int(total_triangles / iterations),
		"cells": Vector3i(cells_x, cells_y, cells_z),
	}
	rebuild()
	_last_report["benchmark"] = result
	return result


func _apply_edit(mode: String, center: Vector3, radius: float) -> void:
	if radius <= 0.0:
		radius = edit_radius
	edits.append({
		"mode": mode,
		"center": center,
		"radius": radius,
		"material": construct_material,
	})
	rebuild()


func _apply_reference_terrain_edit(mode: String, center: Vector3, radius: float) -> void:
	if radius <= 0.0:
		radius = edit_radius
	_reference_terrain.apply_edit(mode, center, radius, construct_material)
	rebuild()


func _request_rebuild() -> void:
	if not auto_rebuild or not is_inside_tree():
		return
	call_deferred("rebuild")


func _ensure_roots() -> void:
	if _mesh_root == null or not is_instance_valid(_mesh_root):
		_mesh_root = _get_or_make_root("CellLabMesh")
	if _sample_root == null or not is_instance_valid(_sample_root):
		_sample_root = _get_or_make_root("CellLabSamples")
	if _marker_root == null or not is_instance_valid(_marker_root):
		_marker_root = _get_or_make_root("CellLabEdits")
	if _label_root == null or not is_instance_valid(_label_root):
		_label_root = _get_or_make_root("CellLabLabels")


func _get_or_make_root(root_name: String) -> Node3D:
	var existing := get_node_or_null(root_name)
	if existing is Node3D:
		return existing
	var root := Node3D.new()
	root.name = root_name
	add_child(root)
	root.owner = owner
	return root


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func _make_materials() -> void:
	_surface_material = _material(Color(0.16, 0.55, 0.82, 1.0), false)
	_wire_material = _material(Color(0.95, 0.66, 0.12, 1.0), true)
	_solid_sample_material = _material(Color(0.95, 0.18, 0.14, 1.0), false)
	_empty_sample_material = _material(Color(0.16, 0.72, 0.42, 1.0), false)
	_dig_marker_material = _material(Color(1.0, 0.08, 0.06, 0.35), false)
	_construct_marker_material = _material(Color(0.20, 0.60, 1.0, 0.35), false)
	_transition_material = _material(Color(1.0, 0.78, 0.20, 0.45), true)
	_transition_surface_material = _material(Color(0.92, 0.36, 0.16, 0.82), false)
	_chunk_surface_material = _material(Color(0.25, 0.82, 0.52, 0.68), false)
	_inspection_edge_material = _material(Color(1.0, 0.72, 0.12, 0.92), true)
	_inspection_normal_material = _material(Color(0.18, 0.88, 1.0, 0.90), true)
	_inspection_low_sample_material = _material(Color(0.78, 0.42, 1.0, 1.0), false)
	_inspection_fine_chunk_material = _material(Color(0.18, 0.68, 0.92, 0.74), false)
	_inspection_basis_material = _material(Color(1.0, 0.96, 0.36, 1.0), true)


func _inspection_materials() -> Dictionary:
	return {
		"surface": _surface_material,
		"transition": _transition_surface_material,
		"chunk": _chunk_surface_material,
		"fine_chunk": _inspection_fine_chunk_material,
		"wire": _wire_material,
		"edge": _inspection_edge_material,
		"normal": _inspection_normal_material,
		"basis": _inspection_basis_material,
		"solid_sample": _solid_sample_material,
		"empty_sample": _empty_sample_material,
		"low_sample": _inspection_low_sample_material,
		"dig_marker": _dig_marker_material,
		"construct_marker": _construct_marker_material,
	}


func _material(color: Color, as_wireframe: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if as_wireframe else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _patch_origin() -> Vector3:
	return Vector3(
		-float(cells_x) * cell_size * 0.5,
		-float(cells_y) * cell_size * 0.5,
		-float(cells_z) * cell_size * 0.5
	)


func _corner_position(cell_origin: Vector3, corner: int) -> Vector3:
	return cell_origin + Vector3(
		1.0 if (corner & 1) != 0 else 0.0,
		1.0 if (corner & 2) != 0 else 0.0,
		1.0 if (corner & 4) != 0 else 0.0
	) * cell_size


func _build_patch_mesh_data() -> Dictionary:
	return _build_native_regular_patch_mesh_data()


func _build_native_regular_patch_mesh_data() -> Dictionary:
	var probe := _get_native_cell_probe()
	if probe == null:
		return _missing_world_transvoxel_mesh_data("WorldTransvoxelCellProbe is unavailable")
	var identity: Dictionary = probe.call("get_backend_identity")
	var vertices: PackedVector3Array = PackedVector3Array()
	var normal_array: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var backend_indices: PackedInt32Array = PackedInt32Array()
	var materials: PackedInt32Array = PackedInt32Array()
	var material_authored: PackedInt32Array = PackedInt32Array()
	var endpoint_a: PackedInt32Array = PackedInt32Array()
	var endpoint_b: PackedInt32Array = PackedInt32Array()
	var reuse_data: PackedInt32Array = PackedInt32Array()
	var case_histogram := {}
	var status_histogram := {}
	var active_cells := 0
	var empty_cells := 0
	var failed_cells := 0
	var origin := _patch_origin()
	for z in range(cells_z):
		for y in range(cells_y):
			for x in range(cells_x):
				var cell_origin := origin + Vector3(x, y, z) * cell_size
				var densities := PackedFloat32Array()
				var gradients := PackedVector3Array()
				var cell_materials := PackedInt32Array()
				var case_code := 0
				for corner in range(CORNER_COUNT):
					var p := _corner_position(cell_origin, corner)
					var d := _density(p)
					densities.append(d)
					gradients.append(_gradient(p))
					cell_materials.append(_material_id_at(p, d))
					if d < isovalue:
						case_code |= 1 << corner
				case_histogram[case_code] = int(case_histogram.get(case_code, 0)) + 1
				var cell_mesh: Dictionary = probe.call(
					"mesh_regular_cell",
					densities,
					gradients,
					cell_materials,
					cell_origin,
					cell_size,
					isovalue
				)
				var status := str(cell_mesh.get("status", "Unknown"))
				status_histogram[status] = int(status_histogram.get(status, 0)) + 1
				if bool(cell_mesh.get("empty", false)):
					empty_cells += 1
					continue
				if not bool(cell_mesh.get("ok", false)):
					failed_cells += 1
					continue
				active_cells += 1
				_append_native_cell_mesh(
					cell_mesh,
					vertices,
					normal_array,
					indices,
					backend_indices,
					materials,
					material_authored,
					endpoint_a,
					endpoint_b,
					reuse_data
				)
	var edge_metrics := _edge_metrics(vertices, indices)
	var orientation_metrics := _orientation_metrics(vertices, indices)
	return {
		"implementation": NATIVE_REGULAR_IMPLEMENTATION,
		"render_authority": NATIVE_AUTHORITY,
		"correctness_claim": CELL_PROBE_CORRECTNESS_CLAIM,
		"native_cell_probe_available": true,
		"backend_runtime_available": ClassDB.class_exists("WorldTransvoxelTerrain"),
		"backend_identity": identity,
		"vertices": vertices,
		"normals": normal_array,
		"indices": indices,
		"backend_indices": backend_indices,
		"materials": materials,
		"material_authored": material_authored,
		"endpoint_a": endpoint_a,
		"endpoint_b": endpoint_b,
		"reuse_data": reuse_data,
		"active_cells": active_cells,
		"empty_cells": empty_cells,
		"failed_cells": failed_cells,
		"triangles": int(indices.size() / 3),
		"degenerate_triangles": 0,
		"open_edges": int(edge_metrics.get("open_edges", 0)),
		"boundary_open_edges": int(edge_metrics.get("boundary_open_edges", 0)),
		"interior_open_edges": int(edge_metrics.get("interior_open_edges", 0)),
		"nonmanifold_edges": int(edge_metrics.get("nonmanifold_edges", 0)),
		"orientation_conflict_edges": int(orientation_metrics.get("orientation_conflict_edges", 0)),
		"case_histogram": case_histogram,
		"native_status_histogram": status_histogram,
	}


func _missing_world_transvoxel_mesh_data(error: String) -> Dictionary:
	return {
		"implementation": NATIVE_REGULAR_IMPLEMENTATION,
		"render_authority": NATIVE_AUTHORITY,
		"correctness_claim": "world_transvoxel_required_no_fallback",
		"native_cell_probe_available": false,
		"backend_runtime_available": ClassDB.class_exists("WorldTransvoxelTerrain"),
		"backend_identity": {},
		"dependency_error": error,
		"vertices": PackedVector3Array(),
		"normals": PackedVector3Array(),
		"indices": PackedInt32Array(),
		"backend_indices": PackedInt32Array(),
		"materials": PackedInt32Array(),
		"material_authored": PackedInt32Array(),
		"endpoint_a": PackedInt32Array(),
		"endpoint_b": PackedInt32Array(),
		"reuse_data": PackedInt32Array(),
		"active_cells": 0,
		"empty_cells": 0,
		"failed_cells": cells_x * cells_y * cells_z,
		"triangles": 0,
		"degenerate_triangles": 0,
		"open_edges": 0,
		"boundary_open_edges": 0,
		"interior_open_edges": 0,
		"nonmanifold_edges": 0,
		"orientation_conflict_edges": 0,
		"case_histogram": {},
		"native_status_histogram": { "DependencyMissing": cells_x * cells_y * cells_z },
	}


func _build_transition_probe_mesh_data() -> Dictionary:
	var empty_result := {
		"available": false,
		"ok": false,
		"status": "Unavailable",
		"vertices": PackedVector3Array(),
		"normals": PackedVector3Array(),
		"indices": PackedInt32Array(),
		"backend_indices": PackedInt32Array(),
		"triangles": 0,
		"case_code": -1,
		"orientation": "PositiveZ",
		"orientation_index": TRANSITION_ORIENTATION_POSITIVE_Z,
		"open_edges": 0,
		"nonmanifold_edges": 0,
		"orientation_conflict_edges": 0,
	}
	var probe := _get_native_cell_probe()
	if probe == null:
		return empty_result

	var origin := _transition_probe_origin()
	var spacing := cell_size
	var width := _transition_probe_width()
	var center := _transition_probe_center(origin)
	var densities := PackedFloat32Array()
	var gradients := PackedVector3Array()
	var materials := PackedInt32Array()
	var case_code := 0
	for index in range(9):
		var point := origin + Vector3(
			float(index % 3),
			float(int(index / 3)),
			0.0
		) * spacing
		var density := _transition_probe_density(point, center)
		densities.append(density)
		gradients.append(_transition_probe_gradient(point, center))
		materials.append(1 if density < isovalue else 0)
		if density < isovalue:
			case_code |= 1 << _transition_case_bit(index)

	var cell_mesh: Dictionary = probe.call(
		"mesh_transition_cell",
		densities,
		gradients,
		materials,
		TRANSITION_ORIENTATION_POSITIVE_Z,
		origin,
		spacing,
		width,
		isovalue
	)
	var vertices := PackedVector3Array()
	var normal_array := PackedVector3Array()
	var indices := PackedInt32Array()
	var backend_indices := PackedInt32Array()
	var material_array := PackedInt32Array()
	var material_authored := PackedInt32Array()
	var endpoint_a := PackedInt32Array()
	var endpoint_b := PackedInt32Array()
	var reuse_data := PackedInt32Array()
	if bool(cell_mesh.get("ok", false)):
		_append_native_cell_mesh(
			cell_mesh,
			vertices,
			normal_array,
			indices,
			backend_indices,
			material_array,
			material_authored,
			endpoint_a,
			endpoint_b,
			reuse_data
		)
	var edge_metrics := _isolated_edge_metrics(vertices, indices)
	var orientation_metrics := _orientation_metrics(vertices, indices)
	return {
		"available": true,
		"ok": bool(cell_mesh.get("ok", false)),
		"empty": bool(cell_mesh.get("empty", false)),
		"status": str(cell_mesh.get("status", "Unknown")),
		"vertices": vertices,
		"normals": normal_array,
		"indices": indices,
		"backend_indices": backend_indices,
		"materials": material_array,
		"material_authored": material_authored,
		"endpoint_a": endpoint_a,
		"endpoint_b": endpoint_b,
		"reuse_data": reuse_data,
		"triangles": int(indices.size() / 3),
		"case_code": int(cell_mesh.get("case_code", case_code)),
		"orientation": "PositiveZ",
		"orientation_index": TRANSITION_ORIENTATION_POSITIVE_Z,
		"open_edges": int(edge_metrics.get("open_edges", 0)),
		"nonmanifold_edges": int(edge_metrics.get("nonmanifold_edges", 0)),
		"orientation_conflict_edges": int(orientation_metrics.get("orientation_conflict_edges", 0)),
	}


func _build_chunk_probe_mesh_data() -> Dictionary:
	var probe := _get_native_cell_probe()
	if probe == null:
		return _empty_chunk_probe_mesh_data("DependencyMissing", "WorldTransvoxelCellProbe is unavailable")
	if not probe.has_method("mesh_chunk_with_callable"):
		return _empty_chunk_probe_mesh_data("MethodMissing", "mesh_chunk_with_callable is unavailable")

	var chunk_mesh: Dictionary = probe.call(
		"mesh_chunk_with_callable",
		Callable(self, "_chunk_probe_sample"),
		Vector3i.ZERO,
		0,
		0,
		0,
		isovalue,
		0.25
	)
	var regular: Dictionary = chunk_mesh.get("regular", {})
	var raw_vertices: PackedVector3Array = regular.get("vertices", PackedVector3Array())
	var vertices := PackedVector3Array()
	for vertex in raw_vertices:
		vertices.append(_chunk_probe_vertex_to_lab_space(vertex))
	var normal_array: PackedVector3Array = regular.get("normals", PackedVector3Array())
	if normal_array.size() != vertices.size():
		normal_array = PackedVector3Array()
		for vertex in vertices:
			var normal := _gradient(vertex)
			normal_array.append(normal.normalized() if normal.length_squared() > 0.0 else Vector3.UP)
	var indices: PackedInt32Array = regular.get("indices", PackedInt32Array())
	var edge_metrics := _isolated_edge_metrics(vertices, indices)
	var orientation_metrics := _orientation_metrics(vertices, indices)
	return {
		"implementation": CHUNK_PROBE_IMPLEMENTATION,
		"render_authority": NATIVE_AUTHORITY,
		"correctness_claim": LAB_CORRECTNESS_CLAIM,
		"available": true,
		"ok": bool(chunk_mesh.get("ok", false)),
		"status": str(chunk_mesh.get("status", "Unknown")),
		"error": str(chunk_mesh.get("sample_error", "")),
		"schema": str(chunk_mesh.get("schema", "")),
		"vertices": vertices,
		"normals": normal_array,
		"indices": indices,
		"backend_indices": regular.get("backend_indices", PackedInt32Array()),
		"materials": regular.get("materials", PackedInt32Array()),
		"material_authored": regular.get("material_authored", PackedInt32Array()),
		"endpoint_a": regular.get("endpoint_a", PackedInt32Array()),
		"endpoint_b": regular.get("endpoint_b", PackedInt32Array()),
		"reuse_data": regular.get("reuse_data", PackedInt32Array()),
		"chunk_cells": Vector3i(CHUNK_PROBE_CELLS_PER_AXIS, CHUNK_PROBE_CELLS_PER_AXIS, CHUNK_PROBE_CELLS_PER_AXIS),
		"chunk_lod": int(chunk_mesh.get("lod", 0)),
		"sample_count": int(chunk_mesh.get("sample_count", 0)),
		"vertices_count": vertices.size(),
		"triangles": int(regular.get("triangle_count", int(indices.size() / 3))),
		"open_edges": int(edge_metrics.get("open_edges", 0)),
		"nonmanifold_edges": int(edge_metrics.get("nonmanifold_edges", 0)),
		"orientation_conflict_edges": int(orientation_metrics.get("orientation_conflict_edges", 0)),
	}


func _empty_chunk_probe_mesh_data(status: String, error: String) -> Dictionary:
	return {
		"implementation": CHUNK_PROBE_IMPLEMENTATION,
		"render_authority": NATIVE_AUTHORITY,
		"correctness_claim": "world_transvoxel_required_no_fallback",
		"available": false,
		"ok": false,
		"status": status,
		"error": error,
		"schema": "",
		"vertices": PackedVector3Array(),
		"normals": PackedVector3Array(),
		"indices": PackedInt32Array(),
		"backend_indices": PackedInt32Array(),
		"materials": PackedInt32Array(),
		"material_authored": PackedInt32Array(),
		"endpoint_a": PackedInt32Array(),
		"endpoint_b": PackedInt32Array(),
		"reuse_data": PackedInt32Array(),
		"chunk_cells": Vector3i(CHUNK_PROBE_CELLS_PER_AXIS, CHUNK_PROBE_CELLS_PER_AXIS, CHUNK_PROBE_CELLS_PER_AXIS),
		"chunk_lod": 0,
		"sample_count": 0,
		"vertices_count": 0,
		"triangles": 0,
		"open_edges": 0,
		"nonmanifold_edges": 0,
		"orientation_conflict_edges": 0,
	}


func _chunk_probe_sample(point: Vector3i) -> Dictionary:
	var center := Vector3.ONE * (float(CHUNK_PROBE_CELLS_PER_AXIS) * 0.5)
	var p := (Vector3(float(point.x), float(point.y), float(point.z)) - center) * cell_size
	var density := _density(p)
	return {
		"density": density,
		"material": _material_id_at(p, density),
		"material_authored": true,
	}


func _chunk_probe_vertex_to_lab_space(vertex: Vector3) -> Vector3:
	var center := Vector3.ONE * (float(CHUNK_PROBE_CELLS_PER_AXIS) * 0.5)
	return (vertex - center) * cell_size + _chunk_probe_visual_offset()


func _chunk_probe_visual_offset() -> Vector3:
	var half_patch_x := float(cells_x) * cell_size * 0.5
	return Vector3(half_patch_x + cell_size * 10.0, 0.0, 0.0)


func _transition_case_bit(sample_index: int) -> int:
	match sample_index:
		0:
			return 0
		1:
			return 1
		2:
			return 2
		5:
			return 3
		8:
			return 4
		7:
			return 5
		6:
			return 6
		3:
			return 7
		4:
			return 8
	return 0


func _get_native_cell_probe() -> RefCounted:
	if _native_cell_probe != null and is_instance_valid(_native_cell_probe):
		return _native_cell_probe
	if not ClassDB.class_exists("WorldTransvoxelCellProbe"):
		push_error("World Transvoxel Cell Lab requires WorldTransvoxelCellProbe from res://addons/world_transvoxel; no fallback mesher is available.")
		return null
	var instance := ClassDB.instantiate("WorldTransvoxelCellProbe")
	if instance is RefCounted:
		_native_cell_probe = instance
	return _native_cell_probe


func _append_native_cell_mesh(
	cell_mesh: Dictionary,
	vertices: PackedVector3Array,
	normal_array: PackedVector3Array,
	indices: PackedInt32Array,
	backend_indices: PackedInt32Array,
	materials: PackedInt32Array,
	material_authored: PackedInt32Array,
	endpoint_a: PackedInt32Array,
	endpoint_b: PackedInt32Array,
	reuse_data: PackedInt32Array
) -> void:
	var cell_vertices: PackedVector3Array = cell_mesh.get("vertices", PackedVector3Array())
	var cell_normals: PackedVector3Array = cell_mesh.get("normals", PackedVector3Array())
	var cell_indices: PackedInt32Array = cell_mesh.get("indices", PackedInt32Array())
	var cell_backend_indices: PackedInt32Array = cell_mesh.get("backend_indices", PackedInt32Array())
	var cell_materials: PackedInt32Array = cell_mesh.get("materials", PackedInt32Array())
	var cell_material_authored: PackedInt32Array = cell_mesh.get("material_authored", PackedInt32Array())
	var cell_endpoint_a: PackedInt32Array = cell_mesh.get("endpoint_a", PackedInt32Array())
	var cell_endpoint_b: PackedInt32Array = cell_mesh.get("endpoint_b", PackedInt32Array())
	var cell_reuse_data: PackedInt32Array = cell_mesh.get("reuse_data", PackedInt32Array())
	var vertex_offset := vertices.size()
	for index in range(cell_vertices.size()):
		var position := cell_vertices[index]
		var normal := cell_normals[index] if index < cell_normals.size() else _gradient(position)
		vertices.append(position)
		normal_array.append(normal.normalized() if normal.length_squared() > 0.0 else Vector3.UP)
		materials.append(int(cell_materials[index]) if index < cell_materials.size() else 1)
		material_authored.append(int(cell_material_authored[index]) if index < cell_material_authored.size() else 0)
		endpoint_a.append(int(cell_endpoint_a[index]) if index < cell_endpoint_a.size() else -1)
		endpoint_b.append(int(cell_endpoint_b[index]) if index < cell_endpoint_b.size() else -1)
		reuse_data.append(int(cell_reuse_data[index]) if index < cell_reuse_data.size() else 0)
	for index in range(cell_indices.size()):
		indices.append(int(cell_indices[index]) + vertex_offset)
	for index in range(cell_backend_indices.size()):
		backend_indices.append(int(cell_backend_indices[index]) + vertex_offset)


func _make_array_mesh(mesh_data: Dictionary) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mesh_data.get("vertices", PackedVector3Array())
	arrays[Mesh.ARRAY_NORMAL] = mesh_data.get("normals", PackedVector3Array())
	arrays[Mesh.ARRAY_INDEX] = mesh_data.get("indices", PackedInt32Array())
	var mesh := ArrayMesh.new()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if vertices.size() > 0 and indices.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_edge_line_mesh(mesh_data: Dictionary) -> ArrayMesh:
	var source_vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var source_indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	var line_vertices := PackedVector3Array()
	var line_indices := PackedInt32Array()
	var edge_lookup := {}
	for i in range(0, source_indices.size(), 3):
		for pair in [
			[int(source_indices[i]), int(source_indices[i + 1])],
			[int(source_indices[i + 1]), int(source_indices[i + 2])],
			[int(source_indices[i + 2]), int(source_indices[i])],
		]:
			var a := source_vertices[int(pair[0])]
			var b := source_vertices[int(pair[1])]
			var key := MeshAnalysis.edge_key(a, b)
			if edge_lookup.has(key):
				continue
			edge_lookup[key] = true
			var base := line_vertices.size()
			line_vertices.append(a)
			line_vertices.append(b)
			line_indices.append(base)
			line_indices.append(base + 1)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = line_vertices
	arrays[Mesh.ARRAY_INDEX] = line_indices
	var mesh := ArrayMesh.new()
	if line_vertices.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


func _build_probe_labels(mesh_data: Dictionary, transition_data: Dictionary, chunk_data: Dictionary) -> void:
	_add_probe_label(
		"REGULAR PATCH\nnative regular-cell probe\ncells %s | tris %d" % [
			str(Vector3i(cells_x, cells_y, cells_z)),
			int(mesh_data.get("triangles", 0)),
		],
		Vector3(0.0, float(cells_y) * cell_size * 0.5 + cell_size * 1.6, 0.0),
		Color(0.55, 0.88, 1.0, 1.0)
	)
	_add_probe_label(
		"TRANSITION CELL\n%s | case %d\ntris %d" % [
			str(transition_data.get("orientation", "PositiveZ")),
			int(transition_data.get("case_code", -1)),
			int(transition_data.get("triangles", 0)),
		],
		_transition_probe_label_position(),
		Color(1.0, 0.58, 0.22, 1.0)
	)
	if show_chunk_probe:
		_add_probe_label(
			"PRODUCTION CHUNK\nWtChunkMesher LOD%d\ntris %d | samples %d" % [
				int(chunk_data.get("chunk_lod", 0)),
				int(chunk_data.get("triangles", 0)),
				int(chunk_data.get("sample_count", 0)),
			],
			_chunk_probe_label_position(),
			Color(0.45, 1.0, 0.68, 1.0)
		)


func _add_probe_label(text: String, position: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.name = "probe_label"
	label.text = text
	label.position = position
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = color
	label.outline_modulate = Color(0.02, 0.025, 0.03, 1.0)
	label.outline_size = 5
	label.font_size = 16
	label.pixel_size = 0.006
	label.fixed_size = false
	label.no_depth_test = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label_root.add_child(label)


func _transition_probe_label_position() -> Vector3:
	var origin := _transition_probe_origin()
	return origin + Vector3(cell_size, cell_size * 3.0, _transition_probe_width() * 0.5)


func _chunk_probe_label_position() -> Vector3:
	return _chunk_probe_visual_offset() + Vector3(0.0, sphere_radius + cell_size * 1.4, 0.0)


func _transition_probe_origin() -> Vector3:
	var half := Vector3(float(cells_x), float(cells_y), float(cells_z)) * cell_size * 0.5
	return Vector3(-cell_size, -cell_size, half.z + cell_size * 0.8)


func _transition_probe_width() -> float:
	return maxf(cell_size * 0.75, 0.05)


func _transition_probe_center(origin: Vector3) -> Vector3:
	return origin + Vector3(cell_size, cell_size, _transition_probe_width() * 0.5)


func _transition_probe_density(p: Vector3, center: Vector3) -> float:
	var local := p - center
	match field_mode:
		FieldMode.SPHERE:
			return local.length() - cell_size * 1.15
		FieldMode.TUNNEL:
			return maxf(local.y, cell_size * 0.45 - Vector2(local.x, local.z).length())
		FieldMode.SADDLE:
			return local.y - 0.22 * local.x * local.z
		FieldMode.WAVES:
			return local.y - 0.25 * sin(local.x * 1.8) - 0.20 * cos(local.z * 1.4)
	return local.y


func _transition_probe_gradient(p: Vector3, center: Vector3) -> Vector3:
	var h := maxf(cell_size * 0.05, 0.01)
	return Vector3(
		_transition_probe_density(p + Vector3(h, 0.0, 0.0), center) - _transition_probe_density(p - Vector3(h, 0.0, 0.0), center),
		_transition_probe_density(p + Vector3(0.0, h, 0.0), center) - _transition_probe_density(p - Vector3(0.0, h, 0.0), center),
		_transition_probe_density(p + Vector3(0.0, 0.0, h), center) - _transition_probe_density(p - Vector3(0.0, 0.0, h), center)
	) / (2.0 * h)


func _density(p: Vector3) -> float:
	var value := 0.0
	match field_mode:
		FieldMode.PLANE:
			value = p.y - surface_height
		FieldMode.SPHERE:
			value = p.length() - sphere_radius
		FieldMode.TUNNEL:
			var ground := p.y - surface_height
			var tunnel := 0.85 - Vector2(p.x, p.y - surface_height + 0.65).length()
			value = maxf(ground, tunnel)
		FieldMode.SADDLE:
			value = p.y - (surface_height + 0.18 * p.x * p.z)
		FieldMode.WAVES:
			value = p.y - (surface_height + 0.35 * sin(p.x * 1.2) + 0.25 * cos(p.z * 1.5))
	for edit in edits:
		var center := edit.get("center", Vector3.ZERO) as Vector3
		var radius := float(edit.get("radius", 1.0))
		var influence := radius - p.distance_to(center)
		if influence <= 0.0:
			continue
		if str(edit.get("mode", "")) == "dig":
			value = maxf(value, influence)
		else:
			value = minf(value, -influence)
	return value


func _material_id_at(p: Vector3, density: float) -> int:
	for edit in edits:
		if str(edit.get("mode", "")) != "construct":
			continue
		var center := edit.get("center", Vector3.ZERO) as Vector3
		var radius := float(edit.get("radius", 1.0))
		if p.distance_to(center) <= radius:
			return construct_material
	return 1 if density < isovalue else 0


func _gradient(p: Vector3) -> Vector3:
	var h := maxf(cell_size * 0.05, 0.01)
	return Vector3(
		_density(p + Vector3(h, 0.0, 0.0)) - _density(p - Vector3(h, 0.0, 0.0)),
		_density(p + Vector3(0.0, h, 0.0)) - _density(p - Vector3(0.0, h, 0.0)),
		_density(p + Vector3(0.0, 0.0, h)) - _density(p - Vector3(0.0, 0.0, h))
	) / (2.0 * h)


func _build_sample_markers() -> void:
	var total := (cells_x + 1) * (cells_y + 1) * (cells_z + 1)
	var stride := maxi(1, ceili(pow(float(total) / 512.0, 1.0 / 3.0)))
	var mesh := SphereMesh.new()
	mesh.radius = cell_size * 0.045
	mesh.height = cell_size * 0.09
	var origin := _patch_origin()
	for z in range(0, cells_z + 1, stride):
		for y in range(0, cells_y + 1, stride):
			for x in range(0, cells_x + 1, stride):
				var p := origin + Vector3(x, y, z) * cell_size
				var marker := MeshInstance3D.new()
				marker.name = "sample"
				marker.mesh = mesh
				marker.position = p
				marker.material_override = _solid_sample_material if _density(p) < isovalue else _empty_sample_material
				_sample_root.add_child(marker)


func _build_edit_markers() -> void:
	for edit in edits:
		var sphere := SphereMesh.new()
		var radius := float(edit.get("radius", 1.0))
		sphere.radius = radius
		sphere.height = radius * 2.0
		var marker := MeshInstance3D.new()
		marker.name = "edit_" + str(edit.get("mode", "unknown"))
		marker.mesh = sphere
		marker.position = edit.get("center", Vector3.ZERO) as Vector3
		marker.material_override = _dig_marker_material if str(edit.get("mode", "")) == "dig" else _construct_marker_material
		_marker_root.add_child(marker)


func _build_transition_frame() -> void:
	var arrays: Array = []
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var origin := _transition_probe_origin()
	var spacing := cell_size
	var width := _transition_probe_width()
	var points := [
		origin,
		origin + Vector3(2.0 * spacing, 0.0, 0.0),
		origin + Vector3(2.0 * spacing, 2.0 * spacing, 0.0),
		origin + Vector3(0.0, 2.0 * spacing, 0.0),
		origin + Vector3(0.0, 0.0, width),
		origin + Vector3(2.0 * spacing, 0.0, width),
		origin + Vector3(2.0 * spacing, 2.0 * spacing, width),
		origin + Vector3(0.0, 2.0 * spacing, width),
	]
	for point in points:
		vertices.append(point)
	for pair in [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]:
		indices.append(int(pair[0]))
		indices.append(int(pair[1]))
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = "transition_frame"
	instance.mesh = mesh
	instance.material_override = _transition_material
	_mesh_root.add_child(instance)


func _isolated_edge_metrics(vertices: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	return MeshAnalysis.isolated_edge_metrics(vertices, indices)


func _edge_metrics(vertices: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	return MeshAnalysis.bounded_edge_metrics(
		vertices,
		indices,
		AABB(_patch_origin(), Vector3(cells_x, cells_y, cells_z) * cell_size)
	)


func _orientation_metrics(vertices: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	return MeshAnalysis.orientation_metrics(vertices, indices)


func _make_report(
	mesh_data: Dictionary,
	transition_data: Dictionary,
	chunk_data: Dictionary,
	elapsed_ms: float
) -> Dictionary:
	return ReportBuilder.build(self, mesh_data, transition_data, chunk_data, elapsed_ms)
