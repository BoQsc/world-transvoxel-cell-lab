@tool
extends Node3D

enum ReplayMode {
	COLD_CANONICAL,
	WARM_CANONICAL,
	WORKER_REVERSE,
	WORKER_SEEDED,
}

const Qualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_adversarial_corpus_qualification.gd"
)
const CASE_IDS := [
	"seeded_closed_wave_lod0",
	"seeded_closed_blob_lod2",
	"seeded_exact_isovalue_lod0",
	"seeded_transition_positive_z",
	"regression_tqp_d011_tangent_edit",
	"regression_tqp_d018_large_coordinate",
	"regression_tqp_d019_lod3_positive_x",
]
const CASE_LABELS := [
	"Seeded closed wave / LOD 0",
	"Seeded closed blob / LOD 2",
	"Exact isovalue coincidences",
	"Seeded +Z transition",
	"D011 tangent edit regression",
	"D018 million-grid regression",
	"D019 LOD 3 +X regression",
]
const REPLAY_IDS := [
	"cold_canonical",
	"warm_canonical",
	"worker_reverse",
	"worker_seeded",
]
const REPLAY_LABELS := [
	"Cold canonical",
	"Warm canonical",
	"Reverse completion",
	"Seeded completion",
]

@export_group("Editor Preview")
@export var editor_preview_enabled := true:
	set(value):
		editor_preview_enabled = value
		_queue_rebuild()
@export_range(0, 6, 1) var editor_case_index := 0:
	set(value):
		editor_case_index = clampi(value, 0, CASE_IDS.size() - 1)
		_queue_rebuild()
@export var editor_replay_mode: ReplayMode = ReplayMode.COLD_CANONICAL:
	set(value):
		editor_replay_mode = value
		_queue_rebuild()
@export_range(0, 2147483647, 1) var editor_seed_override := 0:
	set(value):
		editor_seed_override = maxi(value, 0)
		_queue_rebuild()
@export var editor_rebuild_now := false:
	set(value):
		editor_rebuild_now = false
		if value:
			_queue_rebuild()
@export_group("")

@onready var mesh_root: Node3D = %MeshRoot
@onready var camera: Camera3D = %Camera3D
@onready var case_option: OptionButton = %CaseOption
@onready var replay_option: OptionButton = %ReplayOption
@onready var seed_input: SpinBox = %SeedInput
@onready var status_label: Label = %StatusLabel
@onready var metrics_label: Label = %MetricsLabel

var _queued := false
var _focus_pending := true
var _validation_snapshot := {}


func _ready() -> void:
	case_option.clear()
	for index in range(CASE_IDS.size()):
		case_option.add_item(CASE_LABELS[index], index)
	replay_option.clear()
	for index in range(REPLAY_IDS.size()):
		replay_option.add_item(REPLAY_LABELS[index], index)
	case_option.item_selected.connect(_select_case)
	replay_option.item_selected.connect(_select_replay)
	seed_input.value_changed.connect(_select_seed)
	%RebuildButton.pressed.connect(_rebuild)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	_rebuild()


func _select_case(index: int) -> void:
	editor_case_index = case_option.get_item_id(index)


func _select_replay(index: int) -> void:
	editor_replay_mode = replay_option.get_item_id(index)


func _select_seed(value: float) -> void:
	editor_seed_override = roundi(value)


func _queue_rebuild() -> void:
	if not is_inside_tree() or _queued:
		return
	_queued = true
	call_deferred("_rebuild")


func _rebuild() -> void:
	_queued = false
	if not is_instance_valid(mesh_root):
		return
	case_option.select(editor_case_index)
	replay_option.select(int(editor_replay_mode))
	seed_input.set_value_no_signal(editor_seed_override)
	_clear_children(mesh_root)
	if not editor_preview_enabled:
		status_label.text = "Preview disabled"
		metrics_label.text = ""
		return
	status_label.text = "Meshing native corpus case..."
	var result := Qualification.inspect_case(
		CASE_IDS[editor_case_index],
		REPLAY_IDS[int(editor_replay_mode)],
		editor_seed_override
	)
	var mesh: Dictionary = result.get("mesh", {})
	var oracle: Dictionary = result.get("oracle", {})
	var passed := str(result.get("status", "")) == "PASS" \
		and str(oracle.get("status", "")) == "PASS"
	var array_mesh := _array_mesh(mesh)
	if array_mesh.get_surface_count() > 0:
		var instance := MeshInstance3D.new()
		instance.mesh = array_mesh
		instance.material_override = _surface_material(passed)
		_fit_instance(instance, mesh)
		mesh_root.add_child(instance)
	var failed_checks: Array[String] = []
	for check_id in (oracle.get("checks", {}) as Dictionary):
		var check: Dictionary = (oracle.get("checks", {}) as Dictionary).get(check_id, {})
		if str(check.get("status", "")) == "FAIL":
			failed_checks.append(str(check_id))
	var metrics: Dictionary = oracle.get("metrics", {})
	status_label.text = "PASS" if passed else "FAIL"
	status_label.modulate = Color(0.35, 0.88, 0.63) if passed else Color(0.95, 0.42, 0.32)
	metrics_label.text = (
		"%s\nField seed %s / order seed %d\n%s\n%d chunks / %d triangles\n"
		+ "Components %d / Euler %d\nMaterials %s\nFailed checks: %s"
	) % [
		CASE_LABELS[editor_case_index],
		str(int(result.get("seed", 0))) if int(result.get("seed", 0)) != 0 else "fixed",
		int(result.get("traversal_seed", 1)),
		REPLAY_LABELS[int(editor_replay_mode)],
		int(result.get("native_chunk_call_count", 0)),
		int(metrics.get("input_triangle_count", 0)),
		int(metrics.get("component_count", 0)),
		int(metrics.get("euler_characteristic", 0)),
		str(result.get("material_ids", [])),
		"none" if failed_checks.is_empty() else ", ".join(failed_checks),
	]
	_validation_snapshot = {
		"status": "PASS" if passed else "FAIL",
		"case_id": CASE_IDS[editor_case_index],
		"seed": result.get("seed", 0),
		"traversal_seed": result.get("traversal_seed", 1),
		"replay_order": REPLAY_IDS[int(editor_replay_mode)],
		"native_chunk_call_count": result.get("native_chunk_call_count", 0),
		"geometry_signature": result.get("geometry_signature", ""),
		"oracle_status": oracle.get("status", ""),
		"failed_checks": failed_checks,
		"metrics": metrics,
		"failures": result.get("failures", []),
	}
	_focus_pending = true


func get_validation_snapshot() -> Dictionary:
	return _validation_snapshot.duplicate(true)


func consume_editor_camera_focus_request() -> Variant:
	if not _focus_pending:
		return null
	_focus_pending = false
	return {
		"position": Vector3(20.0, 15.0, 23.0),
		"target": Vector3.ZERO,
	}


func track_editor_camera(_position: Vector3) -> void:
	pass


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
		colors[index] = _material_color(
			int(materials[index]) if index < materials.size() else 1
		)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _fit_instance(instance: MeshInstance3D, mesh: Dictionary) -> void:
	var vertices: PackedVector3Array = mesh.get("vertices", PackedVector3Array())
	if vertices.is_empty():
		return
	var minimum := vertices[0]
	var maximum := vertices[0]
	for vertex in vertices:
		minimum = minimum.min(vertex)
		maximum = maximum.max(vertex)
	var size := maximum - minimum
	var scale_value := 14.5 / maxf(size.x, maxf(size.y, size.z))
	instance.scale = Vector3.ONE * scale_value
	instance.position = -(minimum + maximum) * 0.5 * scale_value


func _surface_material(passed: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.roughness = 0.82
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE if passed else Color(0.85, 0.35, 0.28)
	return material


func _material_color(material_id: int) -> Color:
	var palette := [
		Color(0.19, 0.61, 0.48),
		Color(0.24, 0.48, 0.72),
		Color(0.73, 0.57, 0.22),
		Color(0.65, 0.34, 0.42),
		Color(0.43, 0.59, 0.25),
		Color(0.34, 0.66, 0.68),
		Color(0.62, 0.46, 0.72),
		Color(0.72, 0.43, 0.24),
		Color(0.52, 0.68, 0.38),
	]
	return palette[posmod(material_id - 1, palette.size())]


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
