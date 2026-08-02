@tool
extends Node3D

enum BrushShape { SPHERE, CAPSULE, ROUNDED_BOX }

const EditField := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_edit_field.gd"
)
const TerrainLabScript := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/wt_transvoxel_terrain_lab.gd"
)
const NativeEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_edit_native_evidence.gd"
)
const Observatory := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_observatory.gd"
)
const TerrainShader := preload(
	"res://labs/terrain_lab/shaders/terrain_observatory.gdshader"
)
const SurfaceReferenceShader := preload(
	"res://labs/terrain_lab/shaders/terrain_surface_reference.gdshader"
)

const NATIVE_DEPENDENCY_CLASS := "WorldTransvoxelCellProbe"
const DEFAULT_CHUNK_RANGE_XZ := 1
const DEFAULT_CHUNK_Y_MAX := 1
const CHUNK_CELLS_PER_AXIS := 16.0

@export_group("Editor Preview")
@export var editor_preview_enabled := true:
	set(value):
		editor_preview_enabled = value
		_request_editor_rebuild()
@export var editor_auto_rebuild := true
@export_range(0.125, 1.0, 0.125) var editor_sample_scale_m := 0.5:
	set(value):
		editor_sample_scale_m = value
		_request_editor_reset()
@export_range(1, 3, 1) var editor_chunk_range_xz := DEFAULT_CHUNK_RANGE_XZ:
	set(value):
		editor_chunk_range_xz = value
		_request_editor_rebuild()
@export_range(1, 3, 1) var editor_chunk_y_max := DEFAULT_CHUNK_Y_MAX:
	set(value):
		editor_chunk_y_max = value
		_request_editor_rebuild()
@export var editor_seed_canonical_edits := true:
	set(value):
		editor_seed_canonical_edits = value
		_request_editor_reset()
@export var editor_show_chunk_bounds := true:
	set(value):
		editor_show_chunk_bounds = value
		if is_instance_valid(bounds_root):
			bounds_root.visible = value
@export var editor_rebuild_now := false:
	set(value):
		editor_rebuild_now = false
		if value and is_inside_tree():
			call_deferred("_rebuild")
@export var editor_reset_now := false:
	set(value):
		editor_reset_now = false
		if value and is_inside_tree():
			call_deferred("_reset_field")

@export_group("Editor Diagnostics")
@export var editor_repro_path := "user://terrain_observatory_repro.json"
@export var editor_export_repro_now := false:
	set(value):
		editor_export_repro_now = false
		if value and is_inside_tree():
			call_deferred("_export_observatory_repro", editor_repro_path)

@export_group("Editor Brush")
@export var editor_brush_shape: BrushShape = BrushShape.SPHERE
@export var editor_brush_center := Vector3(4.0, 9.0, 4.0)
@export_range(0.5, 24.0, 0.5) var editor_brush_radius := 4.0
@export var editor_brush_extents := Vector3(4.0, 2.0, 4.0)
@export_range(1, 65535, 1) var editor_construct_material := 7
@export var editor_dig_now := false:
	set(value):
		editor_dig_now = false
		if value and is_inside_tree():
			call_deferred("_apply_editor_operation", "dig")
@export var editor_construct_now := false:
	set(value):
		editor_construct_now = false
		if value and is_inside_tree():
			call_deferred("_apply_editor_operation", "construct")
@export_group("")

@onready var mesh_root: Node3D = %MeshRoot
@onready var bounds_root: Node3D = %BoundsRoot
@onready var camera: Camera3D = %Camera3D
@onready var status_label: Label = %StatusLabel
@onready var metrics_label: Label = %MetricsLabel
@onready var position_x: SpinBox = %PositionX
@onready var position_y: SpinBox = %PositionY
@onready var position_z: SpinBox = %PositionZ
@onready var radius: SpinBox = %Radius
@onready var extent_x: SpinBox = %ExtentX
@onready var extent_y: SpinBox = %ExtentY
@onready var extent_z: SpinBox = %ExtentZ
@onready var shape_option: OptionButton = %ShapeOption
@onready var bounds_toggle: CheckButton = %BoundsToggle

var _field := EditField.new()
var _diagnostics := Observatory.new()
var _probe: RefCounted
var _surface_material: ShaderMaterial
var _operation_sequence := 0
var _orbit_yaw := -0.65
var _orbit_pitch := -0.42
var _orbit_distance := 42.0
var _orbit_target := Vector3(4.0, 10.0, 4.0)
var _orbiting := false
var _mesh_metrics := {}
var _seam_report := {}
var _topology_report := {}
var _editor_rebuild_queued := false
var _editor_reset_queued := false


func _ready() -> void:
	_field.terrain_profile = "observatory"
	_field.sample_scale_m = editor_sample_scale_m
	_surface_material = ShaderMaterial.new()
	_surface_material.shader = TerrainShader
	_surface_material.set_shader_parameter("terrain_textures", _build_texture_array())
	_surface_material.set_shader_parameter("terrain_normal_textures", _build_normal_texture_array())
	_surface_material.set_shader_parameter("texture_world_origin", Vector3.ZERO)
	mesh_root.scale = Vector3.ONE * _field.sample_scale_m
	bounds_root.scale = Vector3.ONE * _field.sample_scale_m
	shape_option.clear()
	shape_option.add_item("Sphere", BrushShape.SPHERE)
	shape_option.add_item("Capsule", BrushShape.CAPSULE)
	shape_option.add_item("Rounded Box", BrushShape.ROUNDED_BOX)
	%DigButton.pressed.connect(_apply_operation.bind("dig"))
	%ConstructButton.pressed.connect(_apply_operation.bind("construct"))
	%ResetButton.pressed.connect(_reset_field)
	%QualifyButton.pressed.connect(_run_qualification)
	bounds_toggle.toggled.connect(_set_bounds_visible)
	_probe = _create_probe()
	if editor_seed_canonical_edits:
		_seed_initial_edits()
	bounds_root.visible = editor_show_chunk_bounds
	_rebuild()
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_orbit_distance = maxf(_orbit_distance - 6.0, 24.0)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_orbit_distance = minf(_orbit_distance + 6.0, 180.0)
			_update_camera()
	elif event is InputEventMouseMotion and _orbiting:
		_orbit_yaw -= event.relative.x * 0.008
		_orbit_pitch = clampf(_orbit_pitch - event.relative.y * 0.008, -1.35, -0.08)
		_update_camera()
		get_viewport().set_input_as_handled()


func _seed_initial_edits() -> void:
	_field.add_operation({
		"id": "initial-crater",
		"mode": "dig",
		"shape": "sphere",
		"center": Vector3(-1.0, 9.5, 4.0),
		"radius_m": 4.0,
		"smoothing_m": 0.75,
	})
	_field.add_operation({
		"id": "initial-tunnel",
		"mode": "dig",
		"shape": "capsule",
		"segment_a": Vector3(7.0, 9.0, -5.0),
		"segment_b": Vector3(7.0, 9.0, 13.0),
		"radius_m": 2.25,
		"smoothing_m": 0.35,
	})
	_field.add_operation({
		"id": "initial-construct",
		"mode": "construct",
		"shape": "rounded_box",
		"center": Vector3(11.0, 12.5, 5.0),
		"half_extents": Vector3(3.5, 1.4, 2.25),
		"rounding_m": 0.6,
		"material": 7,
	})


func _apply_operation(mode: String) -> void:
	var center := Vector3(position_x.value, position_y.value, position_z.value)
	_apply_brush_operation(
		mode,
		shape_option.get_selected_id(),
		center,
		radius.value,
		Vector3(extent_x.value, extent_y.value, extent_z.value),
		7
	)


func _apply_editor_operation(mode: String) -> void:
	_apply_brush_operation(
		mode,
		editor_brush_shape,
		editor_brush_center,
		editor_brush_radius,
		editor_brush_extents,
		editor_construct_material
	)


func _apply_brush_operation(
	mode: String,
	shape: int,
	center: Vector3,
	brush_radius: float,
	brush_extents: Vector3,
	material_id: int
) -> void:
	var operation := {
		"id": "interactive-%04d" % _operation_sequence,
		"mode": mode,
		"center": center,
		"radius_m": brush_radius,
		"material": material_id,
		"smoothing_m": 0.35,
	}
	match shape:
		BrushShape.CAPSULE:
			operation["shape"] = "capsule"
			operation["segment_a"] = center - brush_extents
			operation["segment_b"] = center + brush_extents
		BrushShape.ROUNDED_BOX:
			operation["shape"] = "rounded_box"
			operation["half_extents"] = brush_extents
			operation["rounding_m"] = minf(brush_radius * 0.25, 1.0)
		_:
			operation["shape"] = "sphere"
	if not _field.add_operation(operation):
		status_label.text = "Operation rejected"
		return
	_operation_sequence += 1
	_rebuild()


func _reset_field() -> void:
	_field = EditField.new()
	_field.terrain_profile = "observatory"
	_field.sample_scale_m = editor_sample_scale_m
	mesh_root.scale = Vector3.ONE * _field.sample_scale_m
	bounds_root.scale = Vector3.ONE * _field.sample_scale_m
	_operation_sequence = 0
	if editor_seed_canonical_edits:
		_seed_initial_edits()
	_rebuild()


func _rebuild() -> void:
	_editor_rebuild_queued = false
	if not is_inside_tree() or not is_instance_valid(mesh_root) or not is_instance_valid(bounds_root):
		return
	if Engine.is_editor_hint() and not editor_preview_enabled:
		_clear_children(mesh_root)
		_clear_children(bounds_root)
		_mesh_metrics = {}
		status_label.text = "Editor preview disabled"
		_update_metrics_label(false)
		return
	if _probe == null:
		status_label.text = "FAIL: world-transvoxel unavailable"
		return
	status_label.text = "Meshing native chunks..."
	_clear_children(mesh_root)
	_clear_children(bounds_root)
	_diagnostics.reset()
	var started := Time.get_ticks_usec()
	var chunk_count := 0
	var vertex_count := 0
	var triangle_count := 0
	var failed_chunks := 0
	var local_bounds_violations := 0
	var chunks_by_coordinate := {}
	for x in range(-editor_chunk_range_xz, editor_chunk_range_xz + 1):
		for y in range(0, editor_chunk_y_max + 1):
			for z in range(-editor_chunk_range_xz, editor_chunk_range_xz + 1):
				var coordinate := Vector3i(x, y, z)
				var chunk_id := "%d:%d:%d:0" % [x, y, z]
				var generation := _operation_sequence + 1
				var edit_dependencies := {
					"edit_count": _field.operations.size(),
					"edit_revision": _operation_sequence,
					"sample_scale_m": _field.sample_scale_m,
				}
				_diagnostics.set_chunk_state(
					chunk_id,
					"requested",
					generation,
					0,
					"",
					{"edit_dependencies": edit_dependencies}
				)
				var job_id := "mesh:" + chunk_id
				_diagnostics.set_job(
					job_id,
					chunk_id,
					generation,
					"running",
					0,
					{"edit_dependencies": edit_dependencies}
				)
				var chunk_started := Time.get_ticks_usec()
				var chunk := _mesh_chunk(coordinate)
				var chunk_elapsed_usec := Time.get_ticks_usec() - chunk_started
				if not bool(chunk.get("ok", false)):
					failed_chunks += 1
					var failed_diagnostics := {
						"edit_dependencies": edit_dependencies,
						"timings_usec": {"mesh": chunk_elapsed_usec, "total": chunk_elapsed_usec},
						"collision_state": "not_requested",
					}
					_diagnostics.set_chunk_state(
						chunk_id,
						"failed",
						generation,
						0,
						"native_meshing_failure",
						failed_diagnostics
					)
					_diagnostics.set_job(
						job_id,
						chunk_id,
						generation,
						"failed",
						0,
						{
							"edit_dependencies": edit_dependencies,
							"timings_usec": failed_diagnostics["timings_usec"],
							"rejection_reason": "native_meshing_failure",
						}
					)
					_diagnostics.record_rejection(
						chunk_id,
						generation,
						"native_meshing_failure"
					)
					continue
				chunks_by_coordinate[coordinate] = chunk
				var regular: Dictionary = chunk.get("regular", {})
				var vertices: PackedVector3Array = regular.get("vertices", PackedVector3Array())
				var indices: PackedInt32Array = regular.get("indices", PackedInt32Array())
				var normals: PackedVector3Array = regular.get("normals", PackedVector3Array())
				var material_ids: PackedInt32Array = regular.get("materials", PackedInt32Array())
				var buffers := {
					"vertex_bytes": vertices.size() * 12,
					"normal_bytes": normals.size() * 12,
					"index_bytes": indices.size() * 4,
					"material_bytes": material_ids.size() * 4,
					"collision_bytes": 0,
				}
				var chunk_diagnostics := {
					"edit_dependencies": edit_dependencies,
					"buffers": buffers,
					"timings_usec": {"mesh": chunk_elapsed_usec, "total": chunk_elapsed_usec},
					"collision_state": "not_requested",
				}
				var mesh := _array_mesh(regular)
				if mesh.get_surface_count() == 0:
					_diagnostics.set_chunk_state(
						chunk_id, "cached", generation, 0, "empty_surface", chunk_diagnostics
					)
					_diagnostics.set_job(
						job_id,
						chunk_id,
						generation,
						"completed",
						0,
						{
							"edit_dependencies": edit_dependencies,
							"timings_usec": chunk_diagnostics["timings_usec"],
						}
					)
					_diagnostics.record_publication(chunk_id, generation)
					continue
				var instance := MeshInstance3D.new()
				instance.name = "Chunk_%d_%d_%d" % [x, y, z]
				instance.mesh = mesh
				instance.material_override = _surface_material
				instance.position = Vector3(
					float(chunk.get("world_origin_x", x * CHUNK_CELLS_PER_AXIS)),
					float(chunk.get("world_origin_y", y * CHUNK_CELLS_PER_AXIS)),
					float(chunk.get("world_origin_z", z * CHUNK_CELLS_PER_AXIS))
				)
				mesh_root.add_child(instance)
				chunk_count += 1
				for vertex in vertices:
					if (
						vertex.x < -0.001 or vertex.x > CHUNK_CELLS_PER_AXIS + 0.001
						or vertex.y < -0.001 or vertex.y > CHUNK_CELLS_PER_AXIS + 0.001
						or vertex.z < -0.001 or vertex.z > CHUNK_CELLS_PER_AXIS + 0.001
					):
						local_bounds_violations += 1
				vertex_count += vertices.size()
				triangle_count += indices.size() / 3
				_add_chunk_bounds(instance.position)
				_diagnostics.set_chunk_state(
					chunk_id, "visible", generation, 0, "", chunk_diagnostics
				)
				_diagnostics.set_job(
					job_id,
					chunk_id,
					generation,
					"completed",
					0,
					{
						"edit_dependencies": edit_dependencies,
						"timings_usec": chunk_diagnostics["timings_usec"],
					}
				)
				_diagnostics.record_publication(chunk_id, generation)
	_seam_report = _validate_chunk_seams(chunks_by_coordinate)
	_topology_report = NativeEvidence.same_lod_window_topology(
		chunks_by_coordinate.values()
	)
	var seam_failures := int(_seam_report.get("failure_count", -1))
	var interior_open_edges := int(_topology_report.get("interior_open_edge_count", -1))
	var nonmanifold_edges := int(_topology_report.get("nonmanifold_edge_count", -1))
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	status_label.text = (
		"PASS"
		if (
			failed_chunks == 0
			and local_bounds_violations == 0
			and seam_failures == 0
			and str(_topology_report.get("status", "")) == "PASS"
		)
		else "FAIL"
	)
	var observatory_snapshot := _diagnostics.snapshot()
	var observatory_resources: Dictionary = observatory_snapshot.get("resources", {})
	_mesh_metrics = {
		"chunk_count": chunk_count,
		"edit_count": _field.operations.size(),
		"vertex_count": vertex_count,
		"triangle_count": triangle_count,
		"bounds_errors": local_bounds_violations,
		"seam_pair_count": int(_seam_report.get("pair_count", 0)),
		"surface_seam_pair_count": int(_seam_report.get("surface_pair_count", 0)),
		"seam_errors": seam_failures,
		"exterior_open_edges": int(
			_topology_report.get("exterior_open_edge_count", 0)
		),
		"interior_open_edges": interior_open_edges,
		"nonmanifold_edges": nonmanifold_edges,
		"elapsed_ms": elapsed_ms,
		"observatory_job_count": int(observatory_resources.get("job_count", 0)),
		"observatory_memory_bytes": int(observatory_resources.get("total_memory_bytes", 0)),
		"observatory_rejection_count": (observatory_snapshot.get("rejections", []) as Array).size(),
		"observatory_collision_states": observatory_resources.get("collision_states", {}),
		"observatory_snapshot_signature": str(observatory_snapshot.get("snapshot_signature", "")),
	}
	_update_metrics_label(true)


func get_mesh_metrics() -> Dictionary:
	return _mesh_metrics.duplicate(true)


func get_seam_report() -> Dictionary:
	return _seam_report.duplicate(true)


func get_topology_report() -> Dictionary:
	return _topology_report.duplicate(true)


func get_observatory_snapshot() -> Dictionary:
	return _diagnostics.snapshot()


func export_observatory_repro(path: String = "user://terrain_observatory_repro.json") -> Error:
	return _diagnostics.export_repro(path, {
		"scene": "terrain_observatory",
		"sample_scale_m": _field.sample_scale_m,
		"chunk_range_xz": editor_chunk_range_xz,
		"chunk_y_max": editor_chunk_y_max,
		"edit_count": _field.operations.size(),
		"mesh_metrics": _mesh_metrics,
	})


func _export_observatory_repro(path: String) -> void:
	var error := export_observatory_repro(path)
	status_label.text = "Repro exported" if error == OK else "Repro export failed: " + error_string(error)


func prepare_reference_capture() -> void:
	_update_metrics_label(false)


func prepare_seam_regression_capture() -> void:
	prepare_reference_capture()
	bounds_root.visible = false
	$Interface.visible = false
	var negative_z_material := StandardMaterial3D.new()
	negative_z_material.albedo_color = Color(0.20, 0.68, 0.67, 1.0)
	negative_z_material.roughness = 0.86
	var positive_z_material := StandardMaterial3D.new()
	positive_z_material.albedo_color = Color(0.92, 0.62, 0.20, 1.0)
	positive_z_material.roughness = 0.86
	for child in mesh_root.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			mesh_instance.visible = child.name in ["Chunk_-1_1_-1", "Chunk_-1_1_0"]
			mesh_instance.material_override = (
				negative_z_material
				if child.name == "Chunk_-1_1_-1"
				else positive_z_material
			)
	camera.near = 0.03
	camera.fov = 46.0
	camera.position = Vector3(-1.0, 10.1, 2.4)
	camera.look_at(Vector3(-1.25, 9.55, 0.0), Vector3.UP)


func prepare_tangent_pole_capture() -> void:
	prepare_reference_capture()
	bounds_root.visible = false
	$Interface.visible = false
	camera.near = 0.01
	camera.fov = 48.0
	camera.position = Vector3(-1.0, 8.2, 6.8)
	camera.look_at(Vector3(-1.0, 5.5, 4.0), Vector3.UP)


func prepare_surface_shading_capture(distance_mode: String) -> void:
	prepare_reference_capture()
	bounds_root.visible = false
	$Interface.visible = false
	_apply_capture_shader(SurfaceReferenceShader)
	if distance_mode == "far":
		camera.fov = 26.0
		camera.position = Vector3(-52.0, 42.0, 3.0)
		camera.look_at(Vector3(3.0, 8.0, 3.0), Vector3.UP)
	else:
		camera.fov = 48.0
		camera.position = Vector3(-25.0, 22.0, 3.0)
		camera.look_at(Vector3(3.0, 8.0, 3.0), Vector3.UP)


func prepare_surface_shading_review() -> void:
	prepare_surface_shading_capture("near")
	camera.near = 0.1


func set_surface_shading_diagnostic_mode(mode: int) -> void:
	if _surface_material == null or _surface_material.shader != SurfaceReferenceShader:
		_apply_capture_shader(SurfaceReferenceShader)
	_surface_material.set_shader_parameter("diagnostic_mode", clampi(mode, 0, 9))


func get_surface_shading_diagnostic_mode() -> int:
	if _surface_material == null or _surface_material.shader != SurfaceReferenceShader:
		return -1
	return int(_surface_material.get_shader_parameter("diagnostic_mode"))


func _apply_capture_shader(shader: Shader) -> void:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("terrain_textures", _build_texture_array())
	material.set_shader_parameter("terrain_normal_textures", _build_normal_texture_array())
	material.set_shader_parameter("texture_world_origin", Vector3.ZERO)
	_surface_material = material
	for child in mesh_root.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = material


func _update_metrics_label(include_timing: bool) -> void:
	var final_line := "%d bounds errors" % int(_mesh_metrics.get("bounds_errors", 0))
	if include_timing:
		final_line += " / %.1f ms" % float(_mesh_metrics.get("elapsed_ms", 0.0))
	metrics_label.text = (
		"%d chunks / %d edits\n%d vertices / %d triangles\n%d surface seams / %d seam errors\n%d interior openings / %d nonmanifold\n%d jobs / %.2f MiB / %d rejections\n%s"
		% [
			int(_mesh_metrics.get("chunk_count", 0)),
			int(_mesh_metrics.get("edit_count", 0)),
			int(_mesh_metrics.get("vertex_count", 0)),
			int(_mesh_metrics.get("triangle_count", 0)),
			int(_mesh_metrics.get("surface_seam_pair_count", 0)),
			int(_mesh_metrics.get("seam_errors", 0)),
			int(_mesh_metrics.get("interior_open_edges", 0)),
			int(_mesh_metrics.get("nonmanifold_edges", 0)),
			int(_mesh_metrics.get("observatory_job_count", 0)),
			float(_mesh_metrics.get("observatory_memory_bytes", 0)) / 1048576.0,
			int(_mesh_metrics.get("observatory_rejection_count", 0)),
			final_line,
		]
	)


func _validate_chunk_seams(chunks_by_coordinate: Dictionary) -> Dictionary:
	var records: Array[Dictionary] = []
	var failure_count := 0
	var surface_pair_count := 0
	var checked_axes := [Vector3i.RIGHT, Vector3i.UP, Vector3i.BACK]
	for coordinate_value in chunks_by_coordinate:
		var coordinate: Vector3i = coordinate_value
		var left: Dictionary = chunks_by_coordinate[coordinate]
		for axis in range(checked_axes.size()):
			var right_coordinate: Vector3i = coordinate + checked_axes[axis]
			if not chunks_by_coordinate.has(right_coordinate):
				continue
			var right: Dictionary = chunks_by_coordinate[right_coordinate]
			var seam := NativeEvidence.same_lod_seam(left, right, axis)
			seam["left_coordinate"] = coordinate
			seam["right_coordinate"] = right_coordinate
			if (
				int(seam.get("left_edge_count", 0)) > 0
				or int(seam.get("right_edge_count", 0)) > 0
			):
				surface_pair_count += 1
			if str(seam.get("status", "")) != "PASS":
				failure_count += 1
			records.append(seam)
	return {
		"status": "PASS" if failure_count == 0 else "FAIL",
		"pair_count": records.size(),
		"surface_pair_count": surface_pair_count,
		"failure_count": failure_count,
		"records": records,
	}


func _mesh_chunk(coordinate: Vector3i) -> Dictionary:
	return _probe.call(
		"mesh_chunk_with_callable",
		Callable(_field, "sample"),
		coordinate,
		0,
		0,
		0,
		0.0,
		0.25
	)


func _array_mesh(mesh_data: Dictionary) -> ArrayMesh:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	var materials: PackedInt32Array = mesh_data.get("materials", PackedInt32Array())
	var mesh := ArrayMesh.new()
	if vertices.is_empty() or indices.is_empty():
		return mesh
	var colors := PackedColorArray()
	colors.resize(vertices.size())
	for index in range(vertices.size()):
		var material_id := materials[index] if index < materials.size() else 1
		colors[index] = Color(float(material_id) / 255.0, 0.0, 0.0, 1.0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_chunk_bounds(origin: Vector3) -> void:
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	var corners: Array[Vector3] = [
		origin + Vector3(0.0, 0.05, 0.0),
		origin + Vector3(CHUNK_CELLS_PER_AXIS, 0.05, 0.0),
		origin + Vector3(CHUNK_CELLS_PER_AXIS, 0.05, CHUNK_CELLS_PER_AXIS),
		origin + Vector3(0.0, 0.05, CHUNK_CELLS_PER_AXIS),
	]
	for edge in [[0, 1], [1, 2], [2, 3], [3, 0]]:
		immediate.surface_add_vertex(corners[edge[0]])
		immediate.surface_add_vertex(corners[edge[1]])
	immediate.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = immediate
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.12, 0.78, 0.82, 0.82)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	instance.material_override = material
	bounds_root.add_child(instance)


func _build_texture_array() -> Texture2DArray:
	var images: Array[Image] = []
	var base_colors: Array[Color] = [
		Color(0.16, 0.42, 0.22),
		Color(0.40, 0.43, 0.46),
		Color(0.62, 0.42, 0.16),
	]
	for layer in range(base_colors.size()):
		var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		for y in range(128):
			for x in range(128):
				var grain := _texture_height(x, y, layer)
				var grid := 0.08 if (x % 32 == 0 or y % 32 == 0) else 0.0
				var color := base_colors[layer].lightened(clampf(grain * 0.08 + grid, -0.08, 0.14))
				image.set_pixel(x, y, color)
		image.generate_mipmaps()
		images.append(image)
	var texture := Texture2DArray.new()
	texture.create_from_images(images)
	return texture


func _build_normal_texture_array() -> Texture2DArray:
	var images: Array[Image] = []
	for layer in range(3):
		var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		for y in range(128):
			for x in range(128):
				var left := _texture_height((x - 1 + 128) % 128, y, layer)
				var right := _texture_height((x + 1) % 128, y, layer)
				var down := _texture_height(x, (y - 1 + 128) % 128, layer)
				var up := _texture_height(x, (y + 1) % 128, layer)
				var normal := Vector3((left - right) * 0.35, (down - up) * 0.35, 1.0).normalized()
				image.set_pixel(x, y, Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5, 1.0))
		image.generate_mipmaps()
		images.append(image)
	var texture := Texture2DArray.new()
	texture.create_from_images(images)
	return texture


func _texture_height(x: int, y: int, layer: int) -> float:
	return (
		sin(float(x * 13 + y * 7 + layer * 19) * 0.17) * 0.5
		+ sin(float(x * 3 - y * 11 + layer * 5) * 0.11) * 0.5
	)


func _run_qualification() -> void:
	status_label.text = "Running qualification..."
	await get_tree().process_frame
	var lab := TerrainLabScript.new()
	add_child(lab)
	var reports := [
		lab.validate_program_boundary(),
		lab.qualify_edit_semantics(),
		lab.qualify_material_surface(),
		lab.qualify_terrain_systems(),
		lab.qualify_structural_world(),
		lab.qualify_program_completion(),
	]
	var failures := 0
	for report in reports:
		if str(report.get("status", "")) != "PASS":
			failures += 1
	status_label.text = "PASS: all suites" if failures == 0 else "FAIL: %d suites" % failures
	lab.queue_free()


func _create_probe() -> RefCounted:
	if not ClassDB.class_exists(NATIVE_DEPENDENCY_CLASS):
		return null
	var instance: Variant = ClassDB.instantiate(NATIVE_DEPENDENCY_CLASS)
	if instance is RefCounted and instance.has_method("mesh_chunk_with_callable"):
		return instance as RefCounted
	return null


func _set_bounds_visible(visible_value: bool) -> void:
	bounds_root.visible = visible_value
	if Engine.is_editor_hint():
		editor_show_chunk_bounds = visible_value


func _request_editor_rebuild() -> void:
	if (
		not Engine.is_editor_hint()
		or not editor_auto_rebuild
		or not is_inside_tree()
		or _editor_rebuild_queued
	):
		return
	_editor_rebuild_queued = true
	call_deferred("_rebuild")


func _request_editor_reset() -> void:
	if (
		not Engine.is_editor_hint()
		or not editor_auto_rebuild
		or not is_inside_tree()
		or _editor_reset_queued
	):
		return
	_editor_reset_queued = true
	call_deferred("_flush_editor_reset")


func _flush_editor_reset() -> void:
	_editor_reset_queued = false
	if is_inside_tree():
		_reset_field()


func _update_camera() -> void:
	var horizontal := cos(_orbit_pitch) * _orbit_distance
	camera.position = _orbit_target + Vector3(
		sin(_orbit_yaw) * horizontal,
		-sin(_orbit_pitch) * _orbit_distance,
		cos(_orbit_yaw) * horizontal
	)
	camera.look_at(_orbit_target, Vector3.UP)


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		child.free()
