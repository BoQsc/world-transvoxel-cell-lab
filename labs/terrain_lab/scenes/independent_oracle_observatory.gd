@tool
extends Node3D

enum DefectMode {
	CLEAN,
	MISSING_TRIANGLE,
	DUPLICATE_TRIANGLE,
	FLIPPED_TRIANGLE,
	DISCONNECTED_COMPONENT,
}

const BoundaryField := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_boundary_field.gd"
)
const NativeAdapter := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_mesh_adapter.gd"
)
const Oracle := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_independent_oracle.gd"
)

@export_group("Editor Preview")
@export var editor_preview_enabled := true:
	set(value):
		editor_preview_enabled = value
		_queue_rebuild()
@export var editor_defect_mode: DefectMode = DefectMode.CLEAN:
	set(value):
		editor_defect_mode = value
		_queue_rebuild()
@export var editor_rebuild_now := false:
	set(value):
		editor_rebuild_now = false
		if value:
			_queue_rebuild()
@export_group("")

@onready var mesh_root: Node3D = %MeshRoot
@onready var status_label: Label = %StatusLabel
@onready var metrics_label: Label = %MetricsLabel
@onready var mode_option: OptionButton = %ModeOption
@onready var camera: Camera3D = %Camera3D

var _probe: RefCounted
var _queued := false
var _focus_pending := true
var _validation_snapshot := {}


func _ready() -> void:
	mode_option.clear()
	mode_option.add_item("Clean native assembly", DefectMode.CLEAN)
	mode_option.add_item("Missing triangle", DefectMode.MISSING_TRIANGLE)
	mode_option.add_item("Duplicate triangle", DefectMode.DUPLICATE_TRIANGLE)
	mode_option.add_item("Flipped triangle", DefectMode.FLIPPED_TRIANGLE)
	mode_option.add_item("Disconnected component", DefectMode.DISCONNECTED_COMPONENT)
	mode_option.select(editor_defect_mode)
	mode_option.item_selected.connect(_select_mode)
	%RebuildButton.pressed.connect(_rebuild)
	_probe = NativeAdapter.create_probe()
	camera.look_at(Vector3(0.0, 7.5, 0.0), Vector3.UP)
	_rebuild()


func _select_mode(index: int) -> void:
	editor_defect_mode = mode_option.get_item_id(index)


func _queue_rebuild() -> void:
	if not is_inside_tree() or _queued:
		return
	_queued = true
	call_deferred("_rebuild")


func _rebuild() -> void:
	_queued = false
	if is_instance_valid(mode_option):
		mode_option.select(editor_defect_mode)
	_clear_children(mesh_root)
	if not editor_preview_enabled:
		status_label.text = "Preview disabled"
		metrics_label.text = ""
		return
	if _probe == null:
		status_label.text = "FAIL: native probe unavailable"
		metrics_label.text = "Fallback geometry is forbidden"
		return
	var field := BoundaryField.new()
	field.configure({
		"id": "closed_volume_lod0",
		"kind": "closed_volume",
		"chunk_base": [0, 0, 0],
		"window_chunks": [2, 2, 2],
		"lod": 0,
		"enclosure_inset_samples": 1.75,
	})
	var chunks: Array[Dictionary] = []
	for z in range(2):
		for y in range(2):
			for x in range(2):
				chunks.append(NativeAdapter.mesh_chunk(
					_probe, field, Vector3i(x, y, z), 0, 0
				))
	var mesh := NativeAdapter.assemble(chunks, false)
	mesh = _inject_display_defect(mesh, editor_defect_mode)
	var contract := {
		"bounds_min": Vector3.ZERO,
		"bounds_max": Vector3(32.0, 32.0, 32.0),
		"closed": true,
		"allowed_open_faces": [],
		"expected_component_count": 1,
		"expected_euler_characteristic": 2,
		"expected_signed_volume_sign": -1,
		"minimum_abs_signed_volume": 1000.0,
		"field_tolerance": 0.0313,
		"field_sampler": Callable(field, "sample"),
		"ray_tests": [
			{"id": "outside_crossing", "origin": Vector3(-4.0, 15.31, 15.53), "direction": Vector3.RIGHT, "expected_parity": 0, "minimum_hit_count": 2},
			{"id": "inside_exit", "origin": Vector3(16.0, 15.31, 15.53), "direction": Vector3.RIGHT, "expected_parity": 1, "minimum_hit_count": 1},
		],
	}
	var oracle_result := Oracle.analyze(mesh, contract)
	var array_mesh := _array_mesh(mesh)
	if array_mesh.get_surface_count() > 0:
		var instance := MeshInstance3D.new()
		instance.mesh = array_mesh
		instance.scale = Vector3.ONE * 0.5
		instance.material_override = _surface_material(
			str(oracle_result.get("status", "")) == "PASS"
		)
		mesh_root.add_child(instance)
	var expected_pass := editor_defect_mode == DefectMode.CLEAN
	var observed_pass := str(oracle_result.get("status", "")) == "PASS"
	var observatory_pass := expected_pass == observed_pass
	status_label.text = "PASS" if observatory_pass else "FAIL"
	var failed_checks: Array[String] = []
	for check_id in Oracle.CHECK_IDS:
		var check: Dictionary = (oracle_result.get("checks", {}) as Dictionary).get(check_id, {})
		if str(check.get("status", "")) == "FAIL":
			failed_checks.append(check_id)
	_validation_snapshot = {
		"status": "PASS" if observatory_pass else "FAIL",
		"oracle_status": oracle_result.get("status", ""),
		"defect_mode": editor_defect_mode,
		"failed_checks": failed_checks,
		"geometry_signature": NativeAdapter.mesh_signature(
			mesh.get("vertices", PackedVector3Array()),
			mesh.get("indices", PackedInt32Array()),
			mesh.get("materials", PackedInt32Array())
		),
		"oracle": oracle_result,
	}
	var metrics: Dictionary = oracle_result.get("metrics", {})
	metrics_label.text = (
		"%s\n%d triangles / %d unique edges\n%d components / Euler %d\nFailed checks: %s"
		% [
			_mode_label(editor_defect_mode),
			int(metrics.get("input_triangle_count", 0)),
			int(metrics.get("unique_edge_count", 0)),
			int(metrics.get("component_count", 0)),
			int(metrics.get("euler_characteristic", 0)),
			"none" if failed_checks.is_empty() else ", ".join(failed_checks),
		]
	)
	_focus_pending = true


func get_validation_snapshot() -> Dictionary:
	return _validation_snapshot.duplicate(true)


func consume_editor_camera_focus_request() -> Variant:
	if not _focus_pending:
		return null
	_focus_pending = false
	return {
		"position": Vector3(22.0, 18.0, 24.0),
		"target": Vector3(0.0, 7.5, 0.0),
	}


func track_editor_camera(_position: Vector3) -> void:
	pass


func _inject_display_defect(mesh: Dictionary, mode: DefectMode) -> Dictionary:
	var result := NativeAdapter.clone_mesh(mesh)
	var vertices: PackedVector3Array = result.get("vertices", PackedVector3Array())
	var indices: PackedInt32Array = result.get("indices", PackedInt32Array())
	match mode:
		DefectMode.MISSING_TRIANGLE:
			var shortened := PackedInt32Array()
			for index in range(3, indices.size()):
				shortened.append(indices[index])
			indices = shortened
		DefectMode.DUPLICATE_TRIANGLE:
			for corner in range(3):
				indices.append(indices[corner])
		DefectMode.FLIPPED_TRIANGLE:
			var temporary := indices[1]
			indices[1] = indices[2]
			indices[2] = temporary
		DefectMode.DISCONNECTED_COMPONENT:
			var center := Vector3(16.0, 16.0, 16.0)
			var start := vertices.size()
			vertices.append_array(PackedVector3Array([
				center + Vector3(0.5, 0.0, -0.35),
				center + Vector3(-0.5, 0.0, -0.35),
				center + Vector3(0.0, 0.6, 0.35),
				center + Vector3(0.0, -0.6, 0.35),
			]))
			for triangle in [[0, 2, 1], [0, 1, 3], [0, 3, 2], [1, 2, 3]]:
				for corner in triangle:
					indices.append(start + corner)
	result["vertices"] = vertices
	result["indices"] = indices
	return result


func _array_mesh(mesh_data: Dictionary) -> ArrayMesh:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	var mesh := ArrayMesh.new()
	if vertices.is_empty() or indices.is_empty():
		return mesh
	if normals.size() != vertices.size():
		normals.resize(vertices.size())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _surface_material(passed: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.roughness = 0.8
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = (
		Color(0.18, 0.54, 0.46)
		if passed
		else Color(0.72, 0.24, 0.18)
	)
	return material


func _mode_label(mode: DefectMode) -> String:
	match mode:
		DefectMode.MISSING_TRIANGLE:
			return "Injected missing triangle"
		DefectMode.DUPLICATE_TRIANGLE:
			return "Injected coincident duplicate"
		DefectMode.FLIPPED_TRIANGLE:
			return "Injected orientation conflict"
		DefectMode.DISCONNECTED_COMPONENT:
			return "Injected disconnected component"
	return "Clean native closed assembly"


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
