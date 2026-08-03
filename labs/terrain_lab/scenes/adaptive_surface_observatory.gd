@tool
extends Node3D

const Harness := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_runtime_harness.gd"
)
const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const SurfaceShader := preload(
	"res://labs/terrain_lab/shaders/adaptive_surface_reference.gdshader"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/adaptive_surface_continuity_standard.json"
)
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/adaptive_surface_observatory"

enum DiagnosticMode {
	LIT,
	MATERIAL,
	PROVENANCE,
	TRIPLANAR,
	NORMAL,
	DECAL,
}

@export_group("Editor Preview")
@export var editor_preview_enabled := true:
	set(value):
		editor_preview_enabled = value
		if is_inside_tree():
			call_deferred("_apply_preview_enabled")
@export var editor_diagnostic_mode: DiagnosticMode = DiagnosticMode.LIT:
	set(value):
		editor_diagnostic_mode = value
		if is_inside_tree():
			call_deferred("_apply_diagnostic_mode")
@export var editor_cycle_lod_now := false:
	set(value):
		editor_cycle_lod_now = false
		if value and is_inside_tree():
			call_deferred("cycle_lod_and_wait")
@export var editor_restart_now := false:
	set(value):
		editor_restart_now = false
		if value and is_inside_tree():
			call_deferred("restart_and_wait")
@export_group("")

@onready var camera: Camera3D = %Camera3D
@onready var status_label: Label = %StatusLabel
@onready var mode_label: Label = %ModeLabel
@onready var payload_label: Label = %PayloadLabel
@onready var pipeline_label: Label = %PipelineLabel
@onready var lit_button: Button = %LitButton
@onready var material_button: Button = %MaterialButton
@onready var provenance_button: Button = %ProvenanceButton
@onready var lod_button: Button = %LodButton
@onready var restart_button: Button = %RestartButton

var _standard := {}
var _profile := {}
var _workload := {}
var _harness: Node
var _terrain: Node
var _material: ShaderMaterial
var _session_root := ""
var _viewer_revision := 0
var _busy := false
var _ready_passed := false
var _last_action := "starting"
var _metrics := {}
var _focus_request: Variant = null


func _ready() -> void:
	_standard = JsonLoader.load_dictionary(STANDARD_PATH)
	_profile = _standard.get("runtime_profile", {})
	_workload = _standard.get("workload", {})
	_session_root = RUNTIME_ROOT + "/%s_%d" % [
		"editor" if Engine.is_editor_hint() else "runtime", OS.get_process_id()
	]
	_connect_interface()
	set_process(true)
	call_deferred("_start_preview")


func _exit_tree() -> void:
	if is_instance_valid(_harness):
		_harness.dispose()
	_harness = null
	_terrain = null


func _process(_delta: float) -> void:
	if is_instance_valid(_terrain):
		_metrics = _terrain.call("get_runtime_metrics")
	_refresh_status()


func consume_editor_camera_focus_request() -> Variant:
	var request: Variant = _focus_request
	_focus_request = null
	return request


func track_editor_camera(_position: Vector3) -> void:
	pass


func wait_until_ready(maximum_frames: int = Harness.MAX_WAIT_FRAMES) -> Dictionary:
	for frame in range(maximum_frames):
		if _ready_passed and not _busy and _is_settled(_metrics):
			return {"status": "PASS", "frames": frame, "snapshot": get_validation_snapshot()}
		if status_label.text.begins_with("FAIL"):
			return {"status": "FAIL", "frames": frame, "snapshot": get_validation_snapshot()}
		await get_tree().process_frame
	return {"status": "FAIL", "frames": maximum_frames, "snapshot": get_validation_snapshot()}


func set_diagnostic_mode(mode: int) -> void:
	editor_diagnostic_mode = clampi(mode, DiagnosticMode.LIT, DiagnosticMode.DECAL)
	_apply_diagnostic_mode()


func prepare_reference_capture(mode: String = "lit") -> void:
	match mode:
		"material":
			set_diagnostic_mode(DiagnosticMode.MATERIAL)
			camera.position = Vector3(169, 73, 130)
			camera.look_at(Vector3(112, 23, 52), Vector3.UP)
		"provenance":
			set_diagnostic_mode(DiagnosticMode.PROVENANCE)
			camera.position = Vector3(160, 62, 121)
			camera.look_at(Vector3(119, 25, 55), Vector3.UP)
		_:
			set_diagnostic_mode(DiagnosticMode.LIT)
			camera.position = Vector3(173, 82, 142)
			camera.look_at(Vector3(112, 22, 52), Vector3.UP)
	_focus_request = {
		"position": camera.position,
		"target": Vector3(112, 22, 52),
	}


func cycle_lod_and_wait() -> Dictionary:
	if _busy or not is_instance_valid(_terrain):
		return {"status": "FAIL", "error": "adaptive surface observatory is not ready"}
	_busy = true
	_last_action = "LOD cycle"
	_viewer_revision += 1
	var away := bool(_terrain.call(
		"update_viewer", int(_profile.get("viewer_id", 38)), _viewer_revision,
		_vector3(_workload.get("lod_cycle_position", [])),
		int(_profile.get("viewer_radius_chunks", 1)), int(_profile.get("maximum_lod", 1))
	)) and str((await _harness.wait_for_settled(1)).get("status", "")) == "PASS"
	_viewer_revision += 1
	var returned := away and bool(_terrain.call(
		"update_viewer", int(_profile.get("viewer_id", 38)), _viewer_revision,
		_vector3(_workload.get("initial_viewer_position", [])),
		int(_profile.get("viewer_radius_chunks", 1)), int(_profile.get("maximum_lod", 1))
	)) and str((await _harness.wait_for_settled(1)).get("status", "")) == "PASS"
	_busy = false
	_ready_passed = returned
	return {"status": "PASS" if returned else "FAIL", "snapshot": get_validation_snapshot()}


func restart_and_wait() -> Dictionary:
	if _busy:
		return {"status": "FAIL", "error": "adaptive surface observatory is busy"}
	await _stop_preview()
	await _start_preview()
	return await wait_until_ready()


func get_validation_snapshot() -> Dictionary:
	var counts := _payload_counts()
	return {
		"schema": "world_transvoxel.terrain_lab.adaptive_surface_observatory_snapshot.v1",
		"status": "PASS" if _ready_passed and int(counts.get("authored", 0)) > 0 else "FAIL",
		"action": _last_action,
		"diagnostic_mode": int(editor_diagnostic_mode),
		"backend_id": str(_terrain.call("get_backend_id")) if is_instance_valid(_terrain) else "",
		"payload": counts,
		"metrics": _metrics.duplicate(true),
	}


func shutdown_for_validation() -> Dictionary:
	return await _stop_preview()


func _start_preview() -> void:
	if _busy or _ready_passed or not editor_preview_enabled:
		return
	_busy = true
	_ready_passed = false
	_last_action = "native authored surface"
	Harness.remove_tree(_session_root)
	_harness = Harness.new()
	_harness.name = "NativeTqp38Runtime"
	add_child(_harness)
	if not _harness.create_runtime(
		int(_profile.get("worker_count", 2)), _runtime_overrides()
	):
		_fail_preview("native runtime unavailable")
		return
	_terrain = _harness.terrain
	_material = ShaderMaterial.new()
	_material.shader = SurfaceShader
	_material.set_shader_parameter("terrain_textures", _build_texture_array(false))
	_material.set_shader_parameter("terrain_normal_textures", _build_texture_array(true))
	_material.set_shader_parameter("texture_scale_m", float(_profile.get("texture_scale_m", 3.0)))
	_material.set_shader_parameter("triplanar_sharpness", float(_profile.get("triplanar_sharpness", 4.0)))
	_terrain.call("set_render_material_override", _material)
	var volume: Array = _profile.get("volume_chunks", [])
	var started: bool = volume.size() == 3 and await _harness.start_procedural_world_preset(
		_session_root.path_join("source"), int(_profile.get("source_revision", 938001)),
		int(_profile.get("seed", 380038)), str(_profile.get("preset", "rolling_hills_cave")),
		int(volume[0]), int(volume[1]), int(_profile.get("vertical_chunk_origin", -2)), int(volume[2])
	)
	if not started:
		_fail_preview("native world did not start")
		return
	_viewer_revision = 1
	if not bool(_terrain.call(
		"update_viewer", int(_profile.get("viewer_id", 38)), _viewer_revision,
		_vector3(_workload.get("initial_viewer_position", [])),
		int(_profile.get("viewer_radius_chunks", 1)), int(_profile.get("maximum_lod", 1))
	)) or str((await _harness.wait_for_settled(1)).get("status", "")) != "PASS":
		_fail_preview("native publication did not settle")
		return
	if not await _commit_authored_edits():
		_fail_preview("native material edits did not settle")
		return
	_ready_passed = true
	_busy = false
	_apply_diagnostic_mode()
	prepare_reference_capture("lit")


func _commit_authored_edits() -> bool:
	var paint: Dictionary = _workload.get("paint", {})
	var construction: Dictionary = _workload.get("construction", {})
	var edit: RefCounted = _terrain.call("begin_edit_transaction", 3810)
	if edit == null:
		return false
	if not bool(edit.call(
		"paint_material_sphere", _vector3(paint.get("center", [])),
		float(paint.get("radius", 0.0)), int(paint.get("material", 8))
	)):
		return false
	if not bool(edit.call(
		"construct_material_smooth_sdf_sphere", _vector3(construction.get("center", [])),
		float(construction.get("radius", 0.0)), float(construction.get("strength", 1.0)),
		int(construction.get("material", 7)), float(construction.get("smooth_radius", 1.0))
	)):
		return false
	return bool(_terrain.call("commit_edit_transaction", edit)) \
		and await _harness.wait_for_commit(1) \
		and str((await _harness.wait_for_settled(1)).get("status", "")) == "PASS"


func _stop_preview() -> Dictionary:
	_busy = true
	var stopped := true
	if is_instance_valid(_harness) and is_instance_valid(_terrain):
		stopped = await _harness.stop_world()
		_harness.dispose()
		_harness.queue_free()
		await get_tree().process_frame
	_harness = null
	_terrain = null
	_ready_passed = false
	_metrics = {}
	Harness.remove_tree(_session_root)
	_busy = false
	status_label.text = "STOPPED" if stopped else "FAIL: shutdown"
	return {"status": "PASS" if stopped else "FAIL"}


func _apply_preview_enabled() -> void:
	if editor_preview_enabled:
		await _start_preview()
	else:
		await _stop_preview()


func _apply_diagnostic_mode() -> void:
	if _material != null:
		_material.set_shader_parameter("diagnostic_mode", int(editor_diagnostic_mode))
	mode_label.text = "MODE  " + DiagnosticMode.keys()[int(editor_diagnostic_mode)]


func _connect_interface() -> void:
	lit_button.pressed.connect(func() -> void: set_diagnostic_mode(DiagnosticMode.LIT))
	material_button.pressed.connect(func() -> void: set_diagnostic_mode(DiagnosticMode.MATERIAL))
	provenance_button.pressed.connect(func() -> void: set_diagnostic_mode(DiagnosticMode.PROVENANCE))
	lod_button.pressed.connect(func() -> void: cycle_lod_and_wait())
	restart_button.pressed.connect(func() -> void: restart_and_wait())


func _refresh_status() -> void:
	if _busy:
		status_label.text = "WORKING"
	elif _ready_passed:
		status_label.text = "PASS  NATIVE PAYLOAD"
	var counts := _payload_counts()
	payload_label.text = "Vertices %d   authored %d\nMaterial 7 %d   material 8 %d" % [
		int(counts.get("vertices", 0)), int(counts.get("authored", 0)),
		int(counts.get("material_7", 0)), int(counts.get("material_8", 0)),
	]
	pipeline_label.text = "Active %d   render %d\nTransition completions %d   queued %d" % [
		int(_metrics.get("active_chunk_records", 0)), int(_metrics.get("render_resources", 0)),
		int(_metrics.get("transition_mesh_completions", 0)), int(_metrics.get("queued_render", 0)),
	]


func _payload_counts() -> Dictionary:
	var counts := {"vertices": 0, "authored": 0, "material_7": 0, "material_8": 0}
	if not is_instance_valid(_terrain):
		return counts
	for child in _terrain.get_children():
		if not child is MeshInstance3D or not str(child.name).begins_with("WT_Render_"):
			continue
		var render := child as MeshInstance3D
		if render.mesh == null:
			continue
		for surface in range(render.mesh.get_surface_count()):
			var arrays := render.mesh.surface_get_arrays(surface)
			var payload: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
			counts["vertices"] = int(counts["vertices"]) + payload.size()
			for value in payload:
				counts["authored"] = int(counts["authored"]) + int(value.y > 0.5)
				counts["material_7"] = int(counts["material_7"]) + int(roundi(value.x) == 7)
				counts["material_8"] = int(counts["material_8"]) + int(roundi(value.x) == 8)
	return counts


func _build_texture_array(normal_map: bool) -> Texture2DArray:
	var size := int(_profile.get("texture_layer_size_px", 64))
	var layer_count := int(_profile.get("texture_layer_count", 8))
	var colors: Array[Color] = [
		Color(0.15, 0.42, 0.22), Color(0.42, 0.43, 0.46),
		Color(0.61, 0.45, 0.19), Color(0.71, 0.67, 0.48),
		Color(0.35, 0.25, 0.18), Color(0.70, 0.38, 0.14),
		Color(0.18, 0.47, 0.63), Color(0.48, 0.48, 0.50),
	]
	var images: Array[Image] = []
	for layer in range(layer_count):
		var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
		for y in range(size):
			for x in range(size):
				var height := _texture_height(x, y, layer)
				if normal_map:
					var left := _texture_height((x - 1 + size) % size, y, layer)
					var right := _texture_height((x + 1) % size, y, layer)
					var down := _texture_height(x, (y - 1 + size) % size, layer)
					var up := _texture_height(x, (y + 1) % size, layer)
					var normal := Vector3((left - right) * 0.28, (down - up) * 0.28, 1.0).normalized()
					image.set_pixel(x, y, Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5, 1.0))
				else:
					image.set_pixel(x, y, colors[layer].lightened(clampf(height * 0.1, -0.08, 0.12)))
		image.generate_mipmaps()
		images.append(image)
	var texture := Texture2DArray.new()
	texture.create_from_images(images)
	return texture


static func _texture_height(x: int, y: int, layer: int) -> float:
	return sin(float(x * 11 + y * 7 + layer * 23) * 0.17) * 0.5 \
		+ sin(float(x * 3 - y * 13 + layer * 5) * 0.09) * 0.5


func _runtime_overrides() -> Dictionary:
	var capacity := int(_profile.get("pipeline_capacity", 2048))
	return {
		"active_chunk_capacity": int(_profile.get("active_chunk_capacity", 512)),
		"viewer_capacity": 4,
		"demand_capacity_per_viewer": capacity,
		"lod_refinement_radius_chunks": int(_profile.get("lod_refinement_radius_chunks", 1)),
		"storage_request_capacity": capacity,
		"storage_completion_capacity": capacity,
		"encoded_page_entry_capacity": capacity,
		"decoded_page_entry_capacity": capacity,
		"mesh_entry_capacity": capacity,
		"render_entry_capacity": capacity,
		"collision_entry_capacity": capacity,
		"trace_event_capacity": 65536,
		"render_apply_budget": 8,
		"collision_apply_budget": 4,
		"collision_activation_distance": 0.0,
		"collision_deactivation_distance": 0.0,
	}


func _fail_preview(message: String) -> void:
	status_label.text = "FAIL: " + message
	_busy = false
	_ready_passed = false


static func _is_settled(metrics: Dictionary) -> bool:
	return int(metrics.get("active_chunk_records", 0)) > 0 \
		and int(metrics.get("non_retiring_fully_ready_chunk_records", 0)) \
			== int(metrics.get("non_retiring_chunk_records", -1)) \
		and int(metrics.get("queued_render", -1)) == 0 \
		and int(metrics.get("pending_chunk_retirements", -1)) == 0 \
		and int(metrics.get("blocked_pending_chunk_replacements", -1)) == 0


static func _vector3(value: Variant) -> Vector3:
	var array: Array = value
	return Vector3(float(array[0]), float(array[1]), float(array[2])) if array.size() == 3 else Vector3.ZERO
