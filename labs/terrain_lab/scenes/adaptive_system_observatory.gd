@tool
extends Node3D

const Harness := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_runtime_harness.gd"
)
const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/adaptive_system_agreement_standard.json"
)
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/adaptive_system_observatory"

enum FocusMode {
	OVERVIEW,
	CAVE,
	THIN_FEATURE,
}

@export_group("Editor Preview")
@export var editor_preview_enabled := true:
	set(value):
		editor_preview_enabled = value
		if is_inside_tree():
			call_deferred("_apply_preview_enabled")
@export var editor_focus_mode: FocusMode = FocusMode.OVERVIEW:
	set(value):
		editor_focus_mode = value
		if is_inside_tree():
			call_deferred("_apply_focus_mode")
@export var editor_show_collision_overlay := true:
	set(value):
		editor_show_collision_overlay = value
		if is_inside_tree():
			call_deferred("_apply_overlay_visibility")
@export var editor_show_navigation_overlay := true:
	set(value):
		editor_show_navigation_overlay = value
		if is_inside_tree():
			call_deferred("_apply_overlay_visibility")
@export var editor_teleport_cycle_now := false:
	set(value):
		editor_teleport_cycle_now = false
		if value and is_inside_tree():
			call_deferred("teleport_and_return")
@export var editor_apply_staged_edit_now := false:
	set(value):
		editor_apply_staged_edit_now = false
		if value and is_inside_tree():
			call_deferred("apply_staged_edit_and_wait")
@export var editor_restart_now := false:
	set(value):
		editor_restart_now = false
		if value and is_inside_tree():
			call_deferred("restart_and_wait")
@export_group("")

@onready var camera: Camera3D = %Camera3D
@onready var collision_overlay: MeshInstance3D = %CollisionOverlay
@onready var navigation_overlay: MeshInstance3D = %NavigationOverlay
@onready var ray_overlay: MeshInstance3D = %RayOverlay
@onready var status_label: Label = %StatusLabel
@onready var focus_label: Label = %FocusLabel
@onready var resource_label: Label = %ResourceLabel
@onready var agreement_label: Label = %AgreementLabel
@onready var overview_button: Button = %OverviewButton
@onready var cave_button: Button = %CaveButton
@onready var thin_button: Button = %ThinButton
@onready var teleport_button: Button = %TeleportButton
@onready var staged_button: Button = %StagedButton
@onready var restart_button: Button = %RestartButton

var _standard := {}
var _profile := {}
var _workload := {}
var _harness: Node
var _terrain: Node
var _session_root := ""
var _viewer_revision := 0
var _collision_revision := 0
var _busy := false
var _ready_passed := false
var _staged_edit_applied := false
var _last_action := "starting"
var _metrics := {}
var _collision_stats := {}
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


func prepare_reference_capture(mode: String = "overview") -> void:
	match mode:
		"cave":
			set_focus_mode(FocusMode.CAVE)
		"thin_feature":
			set_focus_mode(FocusMode.THIN_FEATURE)
		_:
			set_focus_mode(FocusMode.OVERVIEW)


func set_focus_mode(mode: int) -> void:
	editor_focus_mode = clampi(mode, FocusMode.OVERVIEW, FocusMode.THIN_FEATURE)
	_apply_focus_mode()


func teleport_and_return() -> Dictionary:
	if _busy or not is_instance_valid(_terrain):
		return {"status": "FAIL", "error": "adaptive system observatory is not ready"}
	_busy = true
	_last_action = "teleport retirement cycle"
	_viewer_revision += 1
	_collision_revision += 1
	var away := str((await _update_viewers_and_wait(
		_vector3(_workload.get("teleport_position", []))
	)).get("status", "")) == "PASS"
	_viewer_revision += 1
	_collision_revision += 1
	var returned := away and str((await _update_viewers_and_wait(
		_vector3(_workload.get("initial_position", []))
	)).get("status", "")) == "PASS"
	if returned:
		await _rebuild_overlays()
	_busy = false
	_ready_passed = returned
	return {"status": "PASS" if returned else "FAIL", "snapshot": get_validation_snapshot()}


func apply_staged_edit_and_wait() -> Dictionary:
	if _busy or not is_instance_valid(_terrain):
		return {"status": "FAIL", "error": "adaptive system observatory is not ready"}
	if _staged_edit_applied:
		return {"status": "PASS", "snapshot": get_validation_snapshot()}
	_busy = true
	_last_action = "staged crater replacement"
	var expected_revision := int(_terrain.call("get_world_revision")) + 1
	var edit: RefCounted = _terrain.call("begin_edit_transaction", 3992)
	var accepted := edit != null and _append_feature_edit(
		edit, _workload.get("staged_edit", {})
	)
	if accepted:
		accepted = bool(_terrain.call("commit_edit_transaction", edit))
	accepted = accepted and await _harness.wait_for_commit(expected_revision)
	if accepted:
		accepted = str((await _harness.wait_for_settled(1)).get("status", "")) == "PASS"
	if accepted:
		_staged_edit_applied = true
		await _rebuild_overlays()
	_busy = false
	_ready_passed = accepted
	return {"status": "PASS" if accepted else "FAIL", "snapshot": get_validation_snapshot()}


func restart_and_wait() -> Dictionary:
	if _busy:
		return {"status": "FAIL", "error": "adaptive system observatory is busy"}
	await _stop_preview()
	await _start_preview()
	return await wait_until_ready()


func get_validation_snapshot() -> Dictionary:
	return {
		"schema": "world_transvoxel.terrain_lab.adaptive_system_observatory_snapshot.v1",
		"status": "PASS" if _ready_passed and int(_collision_stats.get("triangles", 0)) > 0 else "FAIL",
		"action": _last_action,
		"focus_mode": int(editor_focus_mode),
		"backend_id": str(_terrain.call("get_backend_id")) if is_instance_valid(_terrain) else "",
		"world_revision": int(_terrain.call("get_world_revision")) if is_instance_valid(_terrain) else -1,
		"collision": _collision_stats.duplicate(true),
		"metrics": _metrics.duplicate(true),
	}


func shutdown_for_validation() -> Dictionary:
	return await _stop_preview()


func _start_preview() -> void:
	if _busy or _ready_passed or not editor_preview_enabled:
		return
	_busy = true
	_ready_passed = false
	_staged_edit_applied = false
	_last_action = "native collision and feature publication"
	Harness.remove_tree(_session_root)
	_harness = Harness.new()
	_harness.name = "NativeTqp39Runtime"
	add_child(_harness)
	if not _harness.create_runtime(
		int(_profile.get("worker_count", 2)), _runtime_overrides()
	):
		_fail_preview("native runtime unavailable")
		return
	_terrain = _harness.terrain
	_terrain.call("set_render_material_override", _terrain_material())
	var volume: Array = _profile.get("volume_chunks", [])
	var started: bool = volume.size() == 3 and await _harness.start_flat_world(
		_session_root.path_join("source"), int(_profile.get("source_revision", 939001)),
		int(volume[0]), int(volume[1]), int(_profile.get("vertical_chunk_origin", -2)),
		int(volume[2])
	)
	if not started:
		_fail_preview("native flat world did not start")
		return
	_viewer_revision = 1
	_collision_revision = 1
	if str((await _update_viewers_and_wait(
		_vector3(_workload.get("initial_position", []))
	)).get("status", "")) != "PASS":
		_fail_preview("native render/collision publication did not settle")
		return
	if not await _commit_feature_edits():
		_fail_preview("native feature edits did not settle")
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	await _rebuild_overlays()
	_ready_passed = int(_collision_stats.get("triangles", 0)) > 0
	_busy = false
	_apply_focus_mode()


func _commit_feature_edits() -> bool:
	var edit: RefCounted = _terrain.call("begin_edit_transaction", 3991)
	if edit == null:
		return false
	for feature_value in _workload.get("feature_edits", []):
		if not _append_feature_edit(edit, feature_value):
			return false
	return bool(_terrain.call("commit_edit_transaction", edit)) \
		and await _harness.wait_for_commit(1) \
		and str((await _harness.wait_for_settled(1)).get("status", "")) == "PASS"


func _update_viewers_and_wait(position: Vector3) -> Dictionary:
	var before: Dictionary = _terrain.call("get_runtime_metrics")
	var accepted := bool(_terrain.call(
		"update_viewer", int(_profile.get("viewer_id", 39)), _viewer_revision,
		position, int(_profile.get("viewer_radius_chunks", 1)),
		int(_profile.get("maximum_lod", 1))
	)) and bool(_terrain.call(
		"update_collision_viewer", int(_profile.get("collision_viewer_id", 390)),
		_collision_revision, position, int(_profile.get("collision_radius_chunks", 2))
	))
	if not accepted:
		return {"status": "FAIL"}
	for frame in range(Harness.MAX_WAIT_FRAMES):
		var metrics: Dictionary = _terrain.call("get_runtime_metrics")
		if int(metrics.get("viewer_updates", 0)) > int(before.get("viewer_updates", 0)) \
				and int(metrics.get("collision_viewer_updates", 0)) \
					> int(before.get("collision_viewer_updates", 0)):
			var settlement: Dictionary = await _harness.wait_for_settled(1)
			settlement["event_frames"] = frame
			return settlement
		await get_tree().process_frame
	return {"status": "FAIL"}


func _rebuild_overlays() -> void:
	_collision_stats = _build_collision_overlay()
	_build_navigation_overlay()
	_build_ray_overlay()
	_apply_overlay_visibility()
	await get_tree().process_frame


func _build_collision_overlay() -> Dictionary:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _line_material(Color(0.12, 0.88, 0.92, 0.64)))
	var bodies := 0
	var triangles := 0
	for child in _terrain.get_children():
		if not child is StaticBody3D or not str(child.name).begins_with("WT_Collision_"):
			continue
		var body := child as StaticBody3D
		var shape := _collision_shape(body)
		if shape == null:
			continue
		bodies += 1
		var faces := shape.get_faces()
		triangles += faces.size() / 3
		for triangle in range(0, faces.size(), 3):
			var a := body.global_transform * faces[triangle]
			var b := body.global_transform * faces[triangle + 1]
			var c := body.global_transform * faces[triangle + 2]
			_add_triangle_lines(mesh, a, b, c)
	mesh.surface_end()
	collision_overlay.mesh = mesh
	return {"bodies": bodies, "triangles": triangles}


func _build_navigation_overlay() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _line_material(Color(0.95, 0.76, 0.16, 0.72)))
	for child in _terrain.get_children():
		if not child is StaticBody3D or not str(child.name).begins_with("WT_Collision_"):
			continue
		var body := child as StaticBody3D
		var shape := _collision_shape(body)
		if shape == null:
			continue
		var faces := shape.get_faces()
		for triangle in range(0, faces.size(), 3):
			var a := body.global_transform * faces[triangle]
			var b := body.global_transform * faces[triangle + 1]
			var c := body.global_transform * faces[triangle + 2]
			var cross := (b - a).cross(c - a)
			if cross.length_squared() > 0.000001 and cross.normalized().y <= -0.55:
				_add_triangle_lines(mesh, a + Vector3.UP * 0.025, b + Vector3.UP * 0.025, c + Vector3.UP * 0.025)
	mesh.surface_end()
	navigation_overlay.mesh = mesh


func _build_ray_overlay() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _line_material(Color(1.0, 0.24, 0.12, 0.92)))
	for fixture_value in _workload.get("ray_fixtures", []):
		var fixture: Dictionary = fixture_value
		mesh.surface_add_vertex(_vector3(fixture.get("from", [])))
		mesh.surface_add_vertex(_vector3(fixture.get("to", [])))
	mesh.surface_end()
	ray_overlay.mesh = mesh


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
	_collision_stats = {}
	collision_overlay.mesh = null
	navigation_overlay.mesh = null
	ray_overlay.mesh = null
	Harness.remove_tree(_session_root)
	_busy = false
	status_label.text = "STOPPED" if stopped else "FAIL: shutdown"
	return {"status": "PASS" if stopped else "FAIL"}


func _apply_preview_enabled() -> void:
	if editor_preview_enabled:
		await _start_preview()
	else:
		await _stop_preview()


func _apply_focus_mode() -> void:
	match editor_focus_mode:
		FocusMode.CAVE:
			camera.position = Vector3(105, 19, 86)
			camera.look_at(Vector3(87, 4, 68), Vector3.UP)
		FocusMode.THIN_FEATURE:
			camera.position = Vector3(132, 34, 91)
			camera.look_at(Vector3(112, 12, 64), Vector3.UP)
		_:
			camera.position = Vector3(157, 67, 139)
			camera.look_at(Vector3(94, 7, 66), Vector3.UP)
	focus_label.text = "FOCUS  " + FocusMode.keys()[int(editor_focus_mode)]
	_focus_request = {"position": camera.position, "target": _focus_target()}


func _apply_overlay_visibility() -> void:
	if is_instance_valid(collision_overlay):
		collision_overlay.visible = editor_show_collision_overlay
	if is_instance_valid(navigation_overlay):
		navigation_overlay.visible = editor_show_navigation_overlay


func _connect_interface() -> void:
	overview_button.pressed.connect(func() -> void: set_focus_mode(FocusMode.OVERVIEW))
	cave_button.pressed.connect(func() -> void: set_focus_mode(FocusMode.CAVE))
	thin_button.pressed.connect(func() -> void: set_focus_mode(FocusMode.THIN_FEATURE))
	teleport_button.pressed.connect(func() -> void: teleport_and_return())
	staged_button.pressed.connect(func() -> void: apply_staged_edit_and_wait())
	restart_button.pressed.connect(func() -> void: restart_and_wait())


func _refresh_status() -> void:
	if _busy:
		status_label.text = "WORKING"
	elif _ready_passed:
		status_label.text = "PASS  SAME-GENERATION SYSTEM"
	resource_label.text = "Active %d   render %d\nCollision %d / required %d" % [
		int(_metrics.get("active_chunk_records", 0)), int(_metrics.get("render_resources", 0)),
		int(_metrics.get("collision_resources", 0)),
		int(_metrics.get("collision_required_chunk_records", 0)),
	]
	agreement_label.text = "Collision bodies %d   triangles %d\nWorld revision %d   staged %s" % [
		int(_collision_stats.get("bodies", 0)), int(_collision_stats.get("triangles", 0)),
		int(_terrain.call("get_world_revision")) if is_instance_valid(_terrain) else -1,
		"applied" if _staged_edit_applied else "pending",
	]


func _runtime_overrides() -> Dictionary:
	var capacity := int(_profile.get("pipeline_capacity", 2048))
	return {
		"active_chunk_capacity": int(_profile.get("active_chunk_capacity", 512)),
		"viewer_capacity": 8,
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
		"collision_apply_budget": 8,
		"collision_activation_distance": float(_profile.get("collision_activation_distance", 0.0)),
		"collision_deactivation_distance": float(_profile.get("collision_deactivation_distance", 0.0)),
	}


func _terrain_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.39, 0.25)
	material.roughness = 0.84
	material.metallic = 0.0
	return material


func _line_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	return material


func _focus_target() -> Vector3:
	match editor_focus_mode:
		FocusMode.CAVE:
			return Vector3(87, 4, 68)
		FocusMode.THIN_FEATURE:
			return Vector3(112, 12, 64)
	return Vector3(94, 7, 66)


func _fail_preview(message: String) -> void:
	status_label.text = "FAIL: " + message
	_busy = false
	_ready_passed = false


static func _collision_shape(body: StaticBody3D) -> ConcavePolygonShape3D:
	for child in body.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is ConcavePolygonShape3D:
			return (child as CollisionShape3D).shape as ConcavePolygonShape3D
	return null


static func _add_triangle_lines(mesh: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3) -> void:
	mesh.surface_add_vertex(a)
	mesh.surface_add_vertex(b)
	mesh.surface_add_vertex(b)
	mesh.surface_add_vertex(c)
	mesh.surface_add_vertex(c)
	mesh.surface_add_vertex(a)


static func _append_feature_edit(edit: RefCounted, feature: Dictionary) -> bool:
	match str(feature.get("operation", "")):
		"carve_smooth_sdf_sphere":
			return bool(edit.call(
				"carve_smooth_sdf_sphere", _vector3(feature.get("center", [])),
				float(feature.get("radius", 0.0)), float(feature.get("strength", 1.0)),
				float(feature.get("smooth_radius", 0.0))
			))
		"set_density_box":
			var accepted := bool(edit.call(
				"set_density_box", _vector3(feature.get("minimum", [])),
				_vector3(feature.get("maximum", [])), float(feature.get("value", -1.0))
			))
			if accepted and feature.has("material"):
				accepted = bool(edit.call(
					"paint_material_box", _vector3(feature.get("minimum", [])),
					_vector3(feature.get("maximum", [])), int(feature.get("material", 7))
				))
			return accepted
	return false


static func _is_settled(metrics: Dictionary) -> bool:
	return int(metrics.get("active_chunk_records", 0)) > 0 \
		and int(metrics.get("non_retiring_fully_ready_chunk_records", 0)) \
			== int(metrics.get("non_retiring_chunk_records", -1)) \
		and int(metrics.get("queued_render", -1)) == 0 \
		and int(metrics.get("queued_collision", -1)) == 0 \
		and int(metrics.get("pending_chunk_retirements", -1)) == 0 \
		and int(metrics.get("blocked_pending_chunk_replacements", -1)) == 0


static func _vector3(value: Variant) -> Vector3:
	var array: Array = value
	return Vector3(float(array[0]), float(array[1]), float(array[2])) \
		if array.size() == 3 else Vector3.ZERO
