@tool
extends Node3D

const Harness := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_runtime_harness.gd"
)
const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const TerrainShader := preload(
	"res://labs/terrain_lab/shaders/large_terrain_observatory.gdshader"
)

const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/large_terrain_soak_standard.json"
)
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/large_terrain_observatory"
const SOURCE_REVISION := 87001
const VIEWER_ID := 2701
const SURFACE_VIEWER_Y := 8.0
const TELEPORTS := [
	Vector3(40.0, SURFACE_VIEWER_Y, 40.0),
	Vector3(1024.0, SURFACE_VIEWER_Y, 1024.0),
	Vector3(1992.0, SURFACE_VIEWER_Y, 8.0),
	Vector3(8.0, SURFACE_VIEWER_Y, 1992.0),
	Vector3(1992.0, SURFACE_VIEWER_Y, 1992.0),
]

@export_group("Editor Preview")
@export var editor_preview_enabled := true:
	set(value):
		editor_preview_enabled = value
		if is_inside_tree():
			call_deferred("_apply_preview_enabled")
@export var editor_follow_viewport_camera := true
@export var editor_viewer_position := TELEPORTS[0]:
	set(value):
		editor_viewer_position = value
		if is_inside_tree():
			call_deferred("_teleport_to", value, true)
@export_enum("Origin", "Center", "Far X", "Far Z", "Far Corner") \
	var editor_teleport_preset := 0
@export var editor_teleport_now := false:
	set(value):
		editor_teleport_now = false
		if value and is_inside_tree():
			call_deferred("_apply_editor_teleport")
@export var editor_overview_now := false:
	set(value):
		editor_overview_now = false
		if value and is_inside_tree():
			call_deferred("_focus_world_overview")
@export var editor_restart_now := false:
	set(value):
		editor_restart_now = false
		if value and is_inside_tree():
			call_deferred("_restart_preview")

@export_group("Editor Diagnostics")
@export var editor_show_world_bounds := true:
	set(value):
		editor_show_world_bounds = value
		if is_instance_valid(world_bounds):
			world_bounds.visible = value
@export var editor_show_resident_bounds := false:
	set(value):
		editor_show_resident_bounds = value
		if is_instance_valid(resident_bounds):
			resident_bounds.visible = value
@export_group("")

@onready var camera: Camera3D = %Camera3D
@onready var world_bounds: MeshInstance3D = %WorldBounds
@onready var resident_bounds: MeshInstance3D = %ResidentBounds
@onready var viewer_marker: MeshInstance3D = %ViewerMarker
@onready var status_label: Label = %StatusLabel
@onready var profile_label: Label = %ProfileLabel
@onready var viewer_label: Label = %ViewerLabel
@onready var residency_label: Label = %ResidencyLabel
@onready var pipeline_label: Label = %PipelineLabel
@onready var bounds_toggle: CheckButton = %BoundsToggle
@onready var resident_toggle: CheckButton = %ResidentToggle
@onready var track_toggle: CheckButton = %TrackToggle

var _standard := {}
var _runtime_profile := {}
var _harness: Node
var _terrain: Node
var _terrain_material: ShaderMaterial
var _session_root := ""
var _session_generation := 0
var _viewer_revision := 0
var _viewer_position := TELEPORTS[0]
var _published_viewer_position := Vector3(INF, INF, INF)
var _editor_focus_request: Variant = null
var _editor_overview_camera_position: Variant = null
var _world_started := false
var _starting := false
var _runtime_follow_camera := true
var _metrics_accumulator := 0.0
var _bounds_accumulator := 0.0
var _last_render_signature := ""
var _last_metrics := {}
var _looking := false
var _camera_pitch := -0.42
var _camera_yaw := -0.78


func _ready() -> void:
	_standard = JsonLoader.load_dictionary(STANDARD_PATH)
	_runtime_profile = _standard.get("runtime_profile", {})
	_session_root = RUNTIME_ROOT + "/%s_%d" % [
		"editor" if Engine.is_editor_hint() else "runtime",
		OS.get_process_id(),
	]
	_configure_material()
	_configure_scene()
	_connect_interface()
	_build_world_bounds()
	_focus_camera(TELEPORTS[0])
	_viewer_position = TELEPORTS[0]
	_editor_focus_request = TELEPORTS[0]
	set_process(true)
	call_deferred("_start_preview")


func _exit_tree() -> void:
	_session_generation += 1
	if is_instance_valid(_harness):
		_harness.dispose()
	_harness = null
	_terrain = null
	_world_started = false


func _process(delta: float) -> void:
	_metrics_accumulator += delta
	_bounds_accumulator += delta
	if not Engine.is_editor_hint():
		_update_runtime_camera(delta)
	if _metrics_accumulator >= 0.2:
		_metrics_accumulator = 0.0
		_refresh_metrics()
	if _bounds_accumulator >= 0.5:
		_bounds_accumulator = 0.0
		_refresh_resident_bounds()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_looking = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _looking:
		_camera_yaw -= event.relative.x * 0.0035
		_camera_pitch = clampf(_camera_pitch - event.relative.y * 0.0035, -1.48, 1.48)
		camera.rotation = Vector3(_camera_pitch, _camera_yaw, 0.0)
		get_viewport().set_input_as_handled()


func track_editor_camera(camera_position: Vector3) -> void:
	if not Engine.is_editor_hint() or not editor_follow_viewport_camera:
		return
	if _editor_overview_camera_position is Vector3:
		if camera_position.distance_to(_editor_overview_camera_position as Vector3) < 8.0:
			return
		_editor_overview_camera_position = null
	var tracked := _clamp_viewer_position(
		Vector3(camera_position.x, SURFACE_VIEWER_Y, camera_position.z)
	)
	if tracked.distance_to(_viewer_position) >= 8.0:
		_request_viewer(tracked)


func consume_editor_camera_focus_request() -> Variant:
	var request: Variant = _editor_focus_request
	_editor_focus_request = null
	return request


func get_profile_contract() -> Dictionary:
	return {
		"schema": str(_standard.get("schema", "")),
		"milestone": str(_standard.get("milestone", "")),
		"standard_id": str(_standard.get("standard_id", "")),
		"authority": str(_standard.get("authority", "")),
		"runtime_profile": _runtime_profile.duplicate(true),
		"source_revision": SOURCE_REVISION,
	}


func get_validation_snapshot() -> Dictionary:
	var state := "stopped"
	if is_instance_valid(_terrain):
		state = str(_terrain.call("get_world_state_name"))
	return {
		"status": _readiness_status(),
		"world_state": state,
		"profile": get_profile_contract(),
		"backend_id": str(_terrain.call("get_backend_id")) if is_instance_valid(_terrain) else "",
		"backend_license": str(_terrain.call("get_backend_license")) if is_instance_valid(_terrain) else "",
		"catalog_page_count": int(_terrain.call("get_world_page_count")) if _world_started else 0,
		"viewer_position": _viewer_position,
		"metrics": _last_metrics.duplicate(true),
	}


func wait_until_ready(maximum_frames: int = Harness.MAX_WAIT_FRAMES) -> Dictionary:
	for frame in range(maximum_frames):
		_refresh_metrics()
		if _readiness_status() == "READY":
			return {"status": "PASS", "frames": frame, "snapshot": get_validation_snapshot()}
		if status_label.text.begins_with("FAIL"):
			return {"status": "FAIL", "frames": frame, "snapshot": get_validation_snapshot()}
		if _starting:
			await get_tree().create_timer(0.01).timeout
		else:
			await get_tree().process_frame
	return {"status": "FAIL", "frames": maximum_frames, "snapshot": get_validation_snapshot()}


func move_viewer_and_wait(position: Vector3) -> Dictionary:
	var target := _clamp_viewer_position(position)
	if not Engine.is_editor_hint():
		_focus_camera(target)
	if not is_instance_valid(_harness):
		return {"status": "FAIL", "error": "native runtime is unavailable"}
	var viewer_updates_before := int(
		(_terrain.call("get_runtime_metrics") as Dictionary).get("viewer_updates", 0)
	)
	if not _request_viewer(target, true):
		return {"status": "FAIL", "error": "native viewer update was rejected"}
	var viewer_update_consumed := false
	for frame in range(600):
		await get_tree().process_frame
		var metrics: Dictionary = _terrain.call("get_runtime_metrics")
		if int(metrics.get("viewer_updates", 0)) > viewer_updates_before:
			viewer_update_consumed = true
			break
		if frame % 8 == 0:
			await get_tree().create_timer(0.001).timeout
	if not viewer_update_consumed:
		return {"status": "FAIL", "error": "native viewer update was not consumed"}
	var settlement: Dictionary = await _harness.wait_for_settled(1)
	settlement["viewer_update_consumed"] = true
	_refresh_metrics()
	_refresh_resident_bounds(true)
	return settlement


func shutdown_for_validation() -> Dictionary:
	return await _stop_preview(true)


func prepare_reference_capture() -> void:
	_runtime_follow_camera = false
	track_toggle.button_pressed = false
	_focus_camera(TELEPORTS[0])
	world_bounds.visible = false
	resident_bounds.visible = false


func prepare_world_overview_capture() -> void:
	_focus_world_overview()
	world_bounds.visible = true
	resident_bounds.visible = false


func _apply_preview_enabled() -> void:
	if editor_preview_enabled:
		await _start_preview()
	else:
		await _stop_preview(true)


func _restart_preview() -> void:
	await _stop_preview(true)
	if editor_preview_enabled:
		await _start_preview()


func _start_preview() -> void:
	if _starting or _world_started or not editor_preview_enabled:
		return
	_starting = true
	_session_generation += 1
	var generation := _session_generation
	status_label.text = "STARTING"
	Harness.remove_tree(_session_root)
	_harness = Harness.new()
	_harness.name = "NativeTqp27Runtime"
	add_child(_harness)
	if not _harness.create_runtime(int(_runtime_profile.get("worker_count", 0))):
		_fail_preview("native world-transvoxel runtime unavailable")
		return
	_terrain = _harness.terrain
	_terrain.call("set_render_material_override", _terrain_material)
	var volume_chunks: Array = _runtime_profile.get("volume_chunks", [])
	if volume_chunks.size() != 3:
		_fail_preview("TQP-27 volume profile is invalid")
		return
	var started: bool = await _harness.start_flat_world(
		_session_root,
		SOURCE_REVISION,
		int(volume_chunks[0]),
		int(volume_chunks[1]),
		int(_runtime_profile.get("vertical_chunk_origin", 0)),
		int(volume_chunks[2])
	)
	if generation != _session_generation:
		return
	if not started:
		_fail_preview("native 2K world did not enter running state")
		return
	_world_started = true
	_update_profile_label(int(_terrain.call("get_world_page_count")))
	_request_viewer(_viewer_position, true)
	var initial_settlement: Dictionary = await _harness.wait_for_settled(1)
	if generation != _session_generation:
		return
	if str(initial_settlement.get("status", "")) != "PASS":
		_fail_preview("initial native window did not settle")
		return
	_starting = false
	_refresh_metrics()


func _stop_preview(cleanup: bool) -> Dictionary:
	_session_generation += 1
	_starting = false
	var stopped := true
	var resources_empty := true
	if is_instance_valid(_terrain) and str(_terrain.call("get_world_state_name")) != "stopped":
		_viewer_revision += 1
		_terrain.call("remove_viewer", VIEWER_ID, _viewer_revision)
		if is_instance_valid(_harness):
			stopped = await _harness.stop_world()
	if is_instance_valid(_terrain):
		resources_empty = (
			int(_terrain.call("get_render_resource_count")) == 0
			and int(_terrain.call("get_collision_resource_count")) == 0
			and int(_terrain.call("get_queued_render_count")) == 0
			and int(_terrain.call("get_queued_collision_count")) == 0
		)
	if is_instance_valid(_harness):
		_harness.dispose()
		_harness.queue_free()
	_harness = null
	_terrain = null
	_world_started = false
	_last_metrics = {}
	_clear_resident_bounds()
	if cleanup:
		Harness.remove_tree(_session_root)
	var passed := stopped and resources_empty
	status_label.text = "STOPPED" if passed else "FAIL: shutdown"
	return {"status": "PASS" if passed else "FAIL", "resources_empty": resources_empty}


func _request_viewer(position: Vector3, force: bool = false) -> bool:
	var clamped := _clamp_viewer_position(position)
	_viewer_position = clamped
	viewer_marker.position = clamped
	if not _world_started or not is_instance_valid(_terrain):
		return false
	if not force and clamped.distance_to(_published_viewer_position) < 1.0:
		return true
	_viewer_revision += 1
	var accepted := bool(_terrain.call(
		"update_viewer",
		VIEWER_ID,
		_viewer_revision,
		clamped,
		int(_runtime_profile.get("viewer_radius_chunks", 0)),
		int(_runtime_profile.get("maximum_lod", 0))
	))
	if accepted:
		_published_viewer_position = clamped
	else:
		status_label.text = "FAIL: viewer update"
	return accepted


func _teleport_to(position: Vector3, focus_editor_camera: bool = false) -> void:
	var target := _clamp_viewer_position(position)
	_editor_overview_camera_position = null
	_request_viewer(target, true)
	if Engine.is_editor_hint():
		if focus_editor_camera:
			_editor_focus_request = target
	else:
		_focus_camera(target)


func _apply_editor_teleport() -> void:
	var index := clampi(editor_teleport_preset, 0, TELEPORTS.size() - 1)
	_teleport_to(TELEPORTS[index], true)


func _focus_world_overview() -> void:
	var volume_cells: Array = _runtime_profile.get("volume_cells", [2048, 256, 2048])
	var target := Vector3(
		float(volume_cells[0]) * 0.5,
		0.0,
		float(volume_cells[2]) * 0.5
	)
	var overview_position := target + Vector3(0.0, 2400.0, 900.0)
	if Engine.is_editor_hint():
		_editor_overview_camera_position = overview_position
		_editor_focus_request = {
			"position": overview_position,
			"target": target,
		}
	else:
		_runtime_follow_camera = false
		track_toggle.button_pressed = false
		camera.position = overview_position
		camera.look_at(target, Vector3.UP)


func _refresh_metrics() -> void:
	if not _world_started or not is_instance_valid(_terrain):
		return
	_last_metrics = _terrain.call("get_runtime_metrics")
	var active := int(_last_metrics.get("active_chunk_records", 0))
	var non_retiring := int(_last_metrics.get("non_retiring_chunk_records", active))
	var ready := int(_last_metrics.get("non_retiring_fully_ready_chunk_records", 0))
	var render_count := int(_last_metrics.get("render_resources", 0))
	var collision_count := int(_last_metrics.get("collision_resources", 0))
	var queued_jobs := int(_last_metrics.get("scheduler_queued_jobs", 0))
	var queued_storage := int(_last_metrics.get("storage_queued_requests", 0))
	status_label.text = _readiness_status()
	viewer_label.text = "Viewer  %.1f, %.1f, %.1f\nRevision  %d" % [
		_viewer_position.x,
		_viewer_position.y,
		_viewer_position.z,
		_viewer_revision,
	]
	residency_label.text = "Resident  %d active / %d ready\nRender  %d    Collision  %d" % [
		non_retiring,
		ready,
		render_count,
		collision_count,
	]
	pipeline_label.text = "Queues  %d jobs / %d storage\nWorld revision  %d" % [
		queued_jobs,
		queued_storage,
		int(_last_metrics.get("edit_commits", 0)),
	]


func _readiness_status() -> String:
	if not _world_started:
		return "STARTING" if _starting else "STOPPED"
	var active := int(_last_metrics.get("active_chunk_records", 0))
	var non_retiring := int(_last_metrics.get("non_retiring_chunk_records", active))
	var ready := int(_last_metrics.get("non_retiring_fully_ready_chunk_records", 0))
	var queues_empty := (
		int(_last_metrics.get("scheduler_queued_jobs", 1)) == 0
		and int(_last_metrics.get("storage_queued_requests", 1)) == 0
		and int(_last_metrics.get("queued_render", 1)) == 0
		and int(_last_metrics.get("queued_collision", 1)) == 0
	)
	return "READY" if active > 0 and ready == non_retiring and queues_empty else "STREAMING"


func _refresh_resident_bounds(force: bool = false) -> void:
	if not _world_started or not is_instance_valid(_terrain):
		return
	var render_nodes: Array[Node] = []
	var names: Array[String] = []
	for child in _terrain.get_children():
		if child is MeshInstance3D and str(child.name).begins_with("WT_Render_"):
			render_nodes.append(child)
			names.append(str(child.name))
	names.sort()
	var signature := "\n".join(names).sha256_text()
	if not force and signature == _last_render_signature:
		return
	_last_render_signature = signature
	if render_nodes.is_empty():
		resident_bounds.mesh = null
		return
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	for node in render_nodes:
		var lod := _lod_from_render_name(str(node.name))
		var size := 16.0 * pow(2.0, float(lod))
		_add_box_lines(immediate, node.position, node.position + Vector3.ONE * size)
		(node as MeshInstance3D).set_instance_shader_parameter(
			"lod_tint",
			Vector3(0.72, 1.0, 0.76) if lod == 0 else Vector3(1.0, 0.82, 0.52)
		)
	immediate.surface_end()
	resident_bounds.mesh = immediate


func _clear_resident_bounds() -> void:
	_last_render_signature = ""
	if is_instance_valid(resident_bounds):
		resident_bounds.mesh = null


func _build_world_bounds() -> void:
	var volume_cells: Array = _runtime_profile.get("volume_cells", [2048, 256, 2048])
	var origin_y := float(int(_runtime_profile.get("vertical_chunk_origin", -8)) * 16)
	var minimum := Vector3(0.0, origin_y, 0.0)
	var maximum := minimum + Vector3(
		float(volume_cells[0]),
		float(volume_cells[1]),
		float(volume_cells[2])
	)
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	_add_box_lines(immediate, minimum, maximum)
	for target in TELEPORTS:
		immediate.surface_add_vertex(Vector3(target.x, 0.0, target.z))
		immediate.surface_add_vertex(Vector3(target.x, 28.0, target.z))
	immediate.surface_end()
	world_bounds.mesh = immediate
	world_bounds.visible = editor_show_world_bounds
	resident_bounds.visible = editor_show_resident_bounds


func _configure_material() -> void:
	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = TerrainShader


func _configure_scene() -> void:
	_update_profile_label(0)
	viewer_marker.position = _viewer_position
	bounds_toggle.button_pressed = editor_show_world_bounds
	resident_toggle.button_pressed = editor_show_resident_bounds
	track_toggle.button_pressed = true


func _update_profile_label(catalog_page_count: int) -> void:
	var volume_cells: Array = _runtime_profile.get("volume_cells", [2048, 256, 2048])
	var volume_chunks: Array = _runtime_profile.get("volume_chunks", [128, 16, 128])
	var catalog_text := (
		_format_integer(catalog_page_count) + " catalog pages"
		if catalog_page_count > 0
		else "Catalog pending"
	)
	profile_label.text = "%dx%dx%d cells\n%dx%dx%d chunks\n%s" % [
		int(volume_cells[0]), int(volume_cells[1]), int(volume_cells[2]),
		int(volume_chunks[0]), int(volume_chunks[1]), int(volume_chunks[2]),
		catalog_text,
	]


func _connect_interface() -> void:
	%OriginButton.pressed.connect(_teleport_to.bind(TELEPORTS[0], false))
	%CenterButton.pressed.connect(_teleport_to.bind(TELEPORTS[1], false))
	%FarXButton.pressed.connect(_teleport_to.bind(TELEPORTS[2], false))
	%FarZButton.pressed.connect(_teleport_to.bind(TELEPORTS[3], false))
	%CornerButton.pressed.connect(_teleport_to.bind(TELEPORTS[4], false))
	%OverviewButton.pressed.connect(_focus_world_overview)
	%RestartButton.pressed.connect(_restart_preview)
	bounds_toggle.toggled.connect(func(value: bool) -> void:
		world_bounds.visible = value
		if Engine.is_editor_hint(): editor_show_world_bounds = value
	)
	resident_toggle.toggled.connect(func(value: bool) -> void:
		resident_bounds.visible = value
		if Engine.is_editor_hint(): editor_show_resident_bounds = value
	)
	track_toggle.toggled.connect(func(value: bool) -> void:
		_runtime_follow_camera = value
	)


func _update_runtime_camera(delta: float) -> void:
	if camera == null:
		return
	var direction := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): direction -= camera.global_basis.z
	if Input.is_key_pressed(KEY_S): direction += camera.global_basis.z
	if Input.is_key_pressed(KEY_A): direction -= camera.global_basis.x
	if Input.is_key_pressed(KEY_D): direction += camera.global_basis.x
	if Input.is_key_pressed(KEY_Q): direction -= Vector3.UP
	if Input.is_key_pressed(KEY_E): direction += Vector3.UP
	if direction.length_squared() > 0.0:
		var speed := 180.0 if Input.is_key_pressed(KEY_SHIFT) else 54.0
		camera.global_position += direction.normalized() * speed * delta
	if _runtime_follow_camera:
		var tracked := Vector3(camera.global_position.x, SURFACE_VIEWER_Y, camera.global_position.z)
		if tracked.distance_to(_viewer_position) >= 8.0:
			_request_viewer(tracked)


func _focus_camera(target: Vector3) -> void:
	camera.position = target + Vector3(0.0, 32.0, 0.0)
	camera.look_at(target + Vector3(30.0, 0.0, 30.0), Vector3.UP)
	_camera_pitch = camera.rotation.x
	_camera_yaw = camera.rotation.y


func _clamp_viewer_position(position: Vector3) -> Vector3:
	var volume_cells: Array = _runtime_profile.get("volume_cells", [2048, 256, 2048])
	return Vector3(
		clampf(position.x, 8.0, float(volume_cells[0]) - 8.0),
		SURFACE_VIEWER_Y,
		clampf(position.z, 8.0, float(volume_cells[2]) - 8.0)
	)


func _fail_preview(message: String) -> void:
	_starting = false
	_world_started = false
	status_label.text = "FAIL: " + message


static func _lod_from_render_name(node_name: String) -> int:
	var marker := node_name.find("_L")
	if marker < 0:
		return 0
	var suffix := node_name.substr(marker + 2)
	return int(suffix.get_slice("_", 0))


static func _format_integer(value: int) -> String:
	var digits := str(absi(value))
	var formatted := ""
	for index in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:
			formatted += ","
		formatted += digits[index]
	return ("-" if value < 0 else "") + formatted


static func _add_box_lines(immediate: ImmediateMesh, minimum: Vector3, maximum: Vector3) -> void:
	var corners := [
		Vector3(minimum.x, minimum.y, minimum.z),
		Vector3(maximum.x, minimum.y, minimum.z),
		Vector3(maximum.x, maximum.y, minimum.z),
		Vector3(minimum.x, maximum.y, minimum.z),
		Vector3(minimum.x, minimum.y, maximum.z),
		Vector3(maximum.x, minimum.y, maximum.z),
		Vector3(maximum.x, maximum.y, maximum.z),
		Vector3(minimum.x, maximum.y, maximum.z),
	]
	for edge in [
		[0, 1], [1, 2], [2, 3], [3, 0],
		[4, 5], [5, 6], [6, 7], [7, 4],
		[0, 4], [1, 5], [2, 6], [3, 7],
	]:
		immediate.surface_add_vertex(corners[edge[0]])
		immediate.surface_add_vertex(corners[edge[1]])
