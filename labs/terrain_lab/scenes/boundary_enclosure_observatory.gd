@tool
extends Node3D

enum FixtureMode { CLOSED_VOLUME, CLOSED_TERRAIN, INTENTIONAL_OPEN }

const BoundaryField := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_boundary_field.gd"
)
const NativeEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_edit_native_evidence.gd"
)

@export_group("Editor Preview")
@export var editor_preview_enabled := true:
	set(value):
		editor_preview_enabled = value
		_queue_rebuild()
@export var editor_fixture_mode: FixtureMode = FixtureMode.CLOSED_TERRAIN:
	set(value):
		editor_fixture_mode = value
		_queue_rebuild()
@export var editor_show_chunk_bounds := true:
	set(value):
		editor_show_chunk_bounds = value
		if is_instance_valid(bounds_root):
			bounds_root.visible = value
@export var editor_rebuild_now := false:
	set(value):
		editor_rebuild_now = false
		if value:
			_queue_rebuild()
@export_group("")

@onready var mesh_root: Node3D = %MeshRoot
@onready var bounds_root: Node3D = %BoundsRoot
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
	mode_option.add_item("Closed volume", FixtureMode.CLOSED_VOLUME)
	mode_option.add_item("Closed terrain", FixtureMode.CLOSED_TERRAIN)
	mode_option.add_item("Intentional open", FixtureMode.INTENTIONAL_OPEN)
	mode_option.select(editor_fixture_mode)
	mode_option.item_selected.connect(_select_mode)
	%BoundsToggle.button_pressed = editor_show_chunk_bounds
	%BoundsToggle.toggled.connect(_set_bounds_visible)
	%RebuildButton.pressed.connect(_rebuild)
	_probe = NativeEvidence.create_probe()
	camera.look_at(Vector3(0.0, 7.0, 0.0), Vector3.UP)
	_rebuild()


func _select_mode(index: int) -> void:
	editor_fixture_mode = mode_option.get_item_id(index)


func _set_bounds_visible(visible: bool) -> void:
	editor_show_chunk_bounds = visible
	bounds_root.visible = visible


func _queue_rebuild() -> void:
	if not is_inside_tree() or _queued:
		return
	_queued = true
	call_deferred("_rebuild")


func _rebuild() -> void:
	_queued = false
	if is_instance_valid(mode_option):
		mode_option.select(editor_fixture_mode)
	_clear_children(mesh_root)
	_clear_children(bounds_root)
	if not editor_preview_enabled:
		status_label.text = "Preview disabled"
		metrics_label.text = ""
		return
	if _probe == null:
		status_label.text = "FAIL: native probe unavailable"
		metrics_label.text = "Fallback geometry is forbidden"
		return
	var definition := _fixture_definition(editor_fixture_mode)
	var field := BoundaryField.new()
	if not field.configure(definition):
		status_label.text = "FAIL: invalid fixture"
		return
	var chunk_extent: int = BoundaryField.CHUNK_CELLS_PER_AXIS * (1 << int(field.lod))
	var domain_origin := Vector3(field.chunk_base * chunk_extent)
	var chunks: Array[Dictionary] = []
	var triangle_count := 0
	var failed_chunks := 0
	var material := _surface_material(editor_fixture_mode)
	for z in range(field.window_chunks.z):
		for y in range(field.window_chunks.y):
			for x in range(field.window_chunks.x):
				var coordinate: Vector3i = field.chunk_base + Vector3i(x, y, z)
				var chunk := NativeEvidence.mesh_chunk(
					_probe, field, coordinate, field.lod, 0
				)
				chunks.append(chunk)
				var validation := NativeEvidence.validate_chunk(chunk)
				if str(validation.get("status", "")) != "PASS":
					failed_chunks += 1
					continue
				triangle_count += int(validation.get("triangle_count", 0))
				var regular: Dictionary = chunk.get("regular", {})
				var mesh := _array_mesh(regular)
				if mesh.get_surface_count() == 0:
					continue
				var instance := MeshInstance3D.new()
				instance.name = "Chunk_%d_%d_%d" % [x, y, z]
				instance.mesh = mesh
				instance.material_override = material
				instance.position = (
					NativeEvidence.chunk_origin(chunk) - domain_origin
				) * BoundaryField.SAMPLE_SCALE_M
				instance.scale = Vector3.ONE * BoundaryField.SAMPLE_SCALE_M
				mesh_root.add_child(instance)
				_add_chunk_bounds(Vector3(x, y, z) * 8.0)
	var topology := NativeEvidence.same_lod_window_topology(chunks)
	var exterior_open := int(topology.get("exterior_open_edge_count", -1))
	var expected_open := editor_fixture_mode == FixtureMode.INTENTIONAL_OPEN
	var passed := failed_chunks == 0 \
		and str(topology.get("status", "")) == "PASS" \
		and ((exterior_open > 0) if expected_open else (exterior_open == 0))
	status_label.text = "PASS" if passed else "FAIL"
	_validation_snapshot = {
		"status": "PASS" if passed else "FAIL",
		"fixture_id": definition.get("id", ""),
		"native_chunk_count": chunks.size(),
		"triangle_count": triangle_count,
		"topology": topology,
		"sample_audit": field.sample_audit(),
	}
	metrics_label.text = (
		"%s\n8 native chunks / %d triangles\n%d exterior open edges\n%d interior open / %d nonmanifold\n%d outside-field halo samples"
		% [
			str(definition.get("label", "")),
			triangle_count,
			exterior_open,
			int(topology.get("interior_open_edge_count", -1)),
			int(topology.get("nonmanifold_edge_count", -1)),
			int(field.sample_audit().get("outside_sample_count", 0)),
		]
	)
	bounds_root.visible = editor_show_chunk_bounds
	_focus_pending = true


func get_validation_snapshot() -> Dictionary:
	return _validation_snapshot.duplicate(true)


func consume_editor_camera_focus_request() -> Variant:
	if not _focus_pending:
		return null
	_focus_pending = false
	return {
		"position": Vector3(20.0, 17.0, 22.0),
		"target": Vector3(0.0, 7.0, 0.0),
	}


func track_editor_camera(_position: Vector3) -> void:
	pass


func _fixture_definition(mode: FixtureMode) -> Dictionary:
	match mode:
		FixtureMode.CLOSED_VOLUME:
			return {
				"id": "closed_volume_all_faces",
				"label": "Closed volume: six field-owned enclosure faces",
				"kind": "closed_volume",
				"chunk_base": [0, 0, 0],
				"window_chunks": [2, 2, 2],
				"enclosure_inset_samples": 1.75,
			}
		FixtureMode.INTENTIONAL_OPEN:
			return {
				"id": "intentional_open_terrain",
				"label": "Open terrain: declared exterior contour",
				"kind": "open_terrain",
				"chunk_base": [3, -2, 2],
				"window_chunks": [2, 2, 2],
				"enclosure_inset_samples": 1.75,
			}
	return {
		"id": "closed_terrain_side_bottom_caps",
		"label": "Closed terrain: field-owned side and bottom caps",
		"kind": "closed_terrain",
		"chunk_base": [-2, 1, -1],
		"window_chunks": [2, 2, 2],
		"enclosure_inset_samples": 1.75,
	}


func _array_mesh(mesh_data: Dictionary) -> ArrayMesh:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	var mesh := ArrayMesh.new()
	if vertices.is_empty() or indices.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _surface_material(mode: FixtureMode) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.roughness = 0.82
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	match mode:
		FixtureMode.CLOSED_VOLUME:
			material.albedo_color = Color(0.16, 0.53, 0.58)
		FixtureMode.INTENTIONAL_OPEN:
			material.albedo_color = Color(0.72, 0.48, 0.16)
		_:
			material.albedo_color = Color(0.22, 0.47, 0.29)
	return material


func _add_chunk_bounds(origin: Vector3) -> void:
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	var corners: Array[Vector3] = []
	for z in [0.0, 8.0]:
		for y in [0.0, 8.0]:
			for x in [0.0, 8.0]:
				corners.append(origin + Vector3(x, y, z))
	for edge in [
		[0, 1], [2, 3], [4, 5], [6, 7],
		[0, 2], [1, 3], [4, 6], [5, 7],
		[0, 4], [1, 5], [2, 6], [3, 7],
	]:
		immediate.surface_add_vertex(corners[edge[0]])
		immediate.surface_add_vertex(corners[edge[1]])
	immediate.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = immediate
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.12, 0.72, 0.78, 0.82)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	instance.material_override = material
	bounds_root.add_child(instance)


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
