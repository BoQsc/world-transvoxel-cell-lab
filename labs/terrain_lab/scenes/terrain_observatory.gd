extends Node3D

const EditField := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_edit_field.gd"
)
const TerrainLabScript := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/wt_transvoxel_terrain_lab.gd"
)
const TerrainShader := preload(
	"res://labs/terrain_lab/shaders/terrain_observatory.gdshader"
)

const NATIVE_DEPENDENCY_CLASS := "WorldTransvoxelCellProbe"
const CHUNK_RANGE := 1
const CHUNK_SIZE := 32.0

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
var _probe: RefCounted
var _surface_material: ShaderMaterial
var _operation_sequence := 0
var _orbit_yaw := -0.65
var _orbit_pitch := -0.42
var _orbit_distance := 92.0
var _orbit_target := Vector3(16.0, 7.0, 16.0)
var _orbiting := false


func _ready() -> void:
	_field.terrain_profile = "observatory"
	_surface_material = ShaderMaterial.new()
	_surface_material.shader = TerrainShader
	_surface_material.set_shader_parameter("terrain_textures", _build_texture_array())
	shape_option.add_item("Sphere", 0)
	shape_option.add_item("Capsule", 1)
	shape_option.add_item("Rounded Box", 2)
	%DigButton.pressed.connect(_apply_operation.bind("dig"))
	%ConstructButton.pressed.connect(_apply_operation.bind("construct"))
	%ResetButton.pressed.connect(_reset_field)
	%QualifyButton.pressed.connect(_run_qualification)
	bounds_toggle.toggled.connect(_set_bounds_visible)
	_probe = _create_probe()
	_seed_initial_edits()
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
		"center": Vector3(2.0, 8.5, 7.0),
		"radius_m": 6.0,
		"smoothing_m": 0.75,
	})
	_field.add_operation({
		"id": "initial-tunnel",
		"mode": "dig",
		"shape": "capsule",
		"segment_a": Vector3(15.0, 6.0, -8.0),
		"segment_b": Vector3(15.0, 6.0, 17.0),
		"radius_m": 3.0,
		"smoothing_m": 0.35,
	})
	_field.add_operation({
		"id": "initial-construct",
		"mode": "construct",
		"shape": "rounded_box",
		"center": Vector3(27.0, 12.0, 13.0),
		"half_extents": Vector3(7.0, 1.4, 3.0),
		"rounding_m": 0.6,
		"material": 7,
	})


func _apply_operation(mode: String) -> void:
	var center := Vector3(position_x.value, position_y.value, position_z.value)
	var operation := {
		"id": "interactive-%04d" % _operation_sequence,
		"mode": mode,
		"center": center,
		"radius_m": radius.value,
		"material": 7,
		"smoothing_m": 0.35,
	}
	match shape_option.get_selected_id():
		1:
			operation["shape"] = "capsule"
			operation["segment_a"] = center - Vector3(extent_x.value, extent_y.value, extent_z.value)
			operation["segment_b"] = center + Vector3(extent_x.value, extent_y.value, extent_z.value)
		2:
			operation["shape"] = "rounded_box"
			operation["half_extents"] = Vector3(extent_x.value, extent_y.value, extent_z.value)
			operation["rounding_m"] = minf(radius.value * 0.25, 1.0)
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
	_operation_sequence = 0
	_seed_initial_edits()
	_rebuild()


func _rebuild() -> void:
	if _probe == null:
		status_label.text = "FAIL: world-transvoxel unavailable"
		return
	status_label.text = "Meshing native chunks..."
	_clear_children(mesh_root)
	_clear_children(bounds_root)
	var started := Time.get_ticks_usec()
	var chunk_count := 0
	var vertex_count := 0
	var triangle_count := 0
	var failed_chunks := 0
	var local_bounds_violations := 0
	for x in range(-CHUNK_RANGE, CHUNK_RANGE + 1):
		for z in range(-CHUNK_RANGE, CHUNK_RANGE + 1):
			var coordinate := Vector3i(x, 0, z)
			var chunk := _mesh_chunk(coordinate)
			if not bool(chunk.get("ok", false)):
				failed_chunks += 1
				continue
			var regular: Dictionary = chunk.get("regular", {})
			var mesh := _array_mesh(regular)
			if mesh.get_surface_count() == 0:
				continue
			var instance := MeshInstance3D.new()
			instance.name = "Chunk_%d_0_%d" % [x, z]
			instance.mesh = mesh
			instance.material_override = _surface_material
			instance.position = Vector3(
				float(chunk.get("world_origin_x", x * CHUNK_SIZE)),
				float(chunk.get("world_origin_y", 0.0)),
				float(chunk.get("world_origin_z", z * CHUNK_SIZE))
			)
			mesh_root.add_child(instance)
			chunk_count += 1
			var vertices: PackedVector3Array = regular.get("vertices", PackedVector3Array())
			var indices: PackedInt32Array = regular.get("indices", PackedInt32Array())
			for vertex in vertices:
				if (
					vertex.x < -0.001 or vertex.x > CHUNK_SIZE + 0.001
					or vertex.y < -0.001 or vertex.y > CHUNK_SIZE + 0.001
					or vertex.z < -0.001 or vertex.z > CHUNK_SIZE + 0.001
				):
					local_bounds_violations += 1
			vertex_count += vertices.size()
			triangle_count += indices.size() / 3
			_add_chunk_bounds(instance.position)
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	status_label.text = (
		"PASS"
		if failed_chunks == 0 and local_bounds_violations == 0
		else "FAIL"
	)
	metrics_label.text = (
		"%d chunks / %d edits\n%d vertices / %d triangles\n%d bounds errors / %.1f ms"
		% [
			chunk_count,
			_field.operations.size(),
			vertex_count,
			triangle_count,
			local_bounds_violations,
			elapsed_ms,
		]
	)


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
		origin + Vector3(CHUNK_SIZE, 0.05, 0.0),
		origin + Vector3(CHUNK_SIZE, 0.05, CHUNK_SIZE),
		origin + Vector3(0.0, 0.05, CHUNK_SIZE),
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
				var grain := (
					sin(float(x * 13 + y * 7 + layer * 19) * 0.17) * 0.5
					+ sin(float(x * 3 - y * 11 + layer * 5) * 0.11) * 0.5
				)
				var grid := 0.08 if (x % 32 == 0 or y % 32 == 0) else 0.0
				var color := base_colors[layer].lightened(clampf(grain * 0.08 + grid, -0.08, 0.14))
				image.set_pixel(x, y, color)
		image.generate_mipmaps()
		images.append(image)
	var texture := Texture2DArray.new()
	texture.create_from_images(images)
	return texture


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
