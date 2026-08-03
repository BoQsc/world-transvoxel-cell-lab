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
	"res://addons/world_transvoxel_terrain_lab/standards/dynamic_lod_publication_standard.json"
)
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/dynamic_publication_observatory"

enum Action {
	INITIAL,
	SPLIT,
	MERGE,
	RAPID_SUPERSESSION,
	TELEPORT,
	UNLOAD,
}

@export_group("Editor Preview")
@export var editor_preview_enabled := true:
	set(value):
		editor_preview_enabled = value
		if is_inside_tree():
			call_deferred("_apply_preview_enabled")
@export var editor_action: Action = Action.INITIAL
@export var editor_apply_action_now := false:
	set(value):
		editor_apply_action_now = false
		if value and is_inside_tree():
			call_deferred("_apply_selected_action")
@export var editor_restart_now := false:
	set(value):
		editor_restart_now = false
		if value and is_inside_tree():
			call_deferred("_restart_preview")
@export_group("Diagnostics")
@export var editor_show_resident_bounds := true:
	set(value):
		editor_show_resident_bounds = value
		if is_instance_valid(resident_bounds):
			resident_bounds.visible = value
@export_group("")

@onready var camera: Camera3D = %Camera3D
@onready var viewer_marker: MeshInstance3D = %ViewerMarker
@onready var resident_bounds: MeshInstance3D = %ResidentBounds
@onready var status_label: Label = %StatusLabel
@onready var action_label: Label = %ActionLabel
@onready var ownership_label: Label = %OwnershipLabel
@onready var pipeline_label: Label = %PipelineLabel

var _standard := {}
var _profile := {}
var _workload := {}
var _harness: Node
var _terrain: Node
var _material: ShaderMaterial
var _session_root := ""
var _viewer_id := 35
var _viewer_revision := 0
var _current_action := "starting"
var _busy := false
var _world_started := false
var _metrics := {}
var _last_bounds_signature := ""
var _focus_request: Variant = null


func _ready() -> void:
	_standard = JsonLoader.load_dictionary(STANDARD_PATH)
	_profile = _standard.get("runtime_profile", {})
	_workload = _standard.get("workload", {})
	_viewer_id = int(_workload.get("viewer_id", 35))
	_session_root = RUNTIME_ROOT + "/%s_%d" % [
		"editor" if Engine.is_editor_hint() else "runtime",
		OS.get_process_id(),
	]
	_material = ShaderMaterial.new()
	_material.shader = TerrainShader
	_connect_interface()
	resident_bounds.visible = editor_show_resident_bounds
	set_process(true)
	call_deferred("_start_preview")


func _exit_tree() -> void:
	if is_instance_valid(_harness):
		_harness.dispose()
	_harness = null
	_terrain = null


func _process(_delta: float) -> void:
	if not is_instance_valid(_terrain):
		return
	_metrics = _terrain.call("get_runtime_metrics")
	_refresh_status()
	_refresh_bounds()


func consume_editor_camera_focus_request() -> Variant:
	var request: Variant = _focus_request
	_focus_request = null
	return request


func track_editor_camera(_position: Vector3) -> void:
	pass


func wait_until_ready(maximum_frames: int = Harness.MAX_WAIT_FRAMES) -> Dictionary:
	for frame in range(maximum_frames):
		if _world_started and not _busy and _is_settled(_metrics):
			return {"status": "PASS", "frames": frame, "snapshot": get_validation_snapshot()}
		if status_label.text.begins_with("FAIL"):
			return {"status": "FAIL", "frames": frame, "snapshot": get_validation_snapshot()}
		await get_tree().process_frame
	return {"status": "FAIL", "frames": maximum_frames, "snapshot": get_validation_snapshot()}


func run_action_and_wait(action_id: String) -> Dictionary:
	if _busy:
		return {"status": "FAIL", "error": "another publication action is active"}
	match action_id:
		"initial_load":
			return await _publish_position(action_id, _position("initial_position"))
		"split_approach":
			return await _publish_position(action_id, _position("split_position"))
		"merge_retreat":
			return await _publish_position(action_id, _position("merge_position"))
		"rapid_supersession":
			return await _rapid_supersession()
		"teleport":
			return await _publish_position(action_id, _position("teleport_position"))
		"viewer_unload":
			return await _unload_viewer()
		_:
			return {"status": "FAIL", "error": "unknown action: " + action_id}


func restart_and_wait() -> Dictionary:
	if _busy:
		return {"status": "FAIL", "error": "another publication action is active"}
	await _stop_preview()
	await _start_preview()
	return await wait_until_ready()


func get_validation_snapshot() -> Dictionary:
	var render_keys: Array[String] = []
	var collision_keys: Array[String] = []
	if is_instance_valid(_terrain):
		for child in _terrain.get_children():
			var node_name := str(child.name)
			if child is MeshInstance3D and node_name.begins_with("WT_Render_") and child.visible:
				render_keys.append(node_name.trim_prefix("WT_Render_"))
			elif child is StaticBody3D and node_name.begins_with("WT_Collision_"):
				collision_keys.append(node_name.trim_prefix("WT_Collision_"))
	render_keys.sort()
	collision_keys.sort()
	var overlap_count := _collision_overlap_count(collision_keys)
	return {
		"schema": "world_transvoxel.terrain_lab.dynamic_lod_publication_observatory_snapshot.v1",
		"status": "PASS" if _world_started and overlap_count == 0 else "FAIL",
		"action": _current_action,
		"world_state": str(_terrain.call("get_world_state_name")) if is_instance_valid(_terrain) else "stopped",
		"backend_id": str(_terrain.call("get_backend_id")) if is_instance_valid(_terrain) else "",
		"backend_license": str(_terrain.call("get_backend_license")) if is_instance_valid(_terrain) else "",
		"viewer_revision": _viewer_revision,
		"render_keys": render_keys,
		"collision_keys": collision_keys,
		"render_key_signature": "\n".join(render_keys).sha256_text(),
		"collision_key_signature": "\n".join(collision_keys).sha256_text(),
		"collision_overlap_count": overlap_count,
		"metrics": _metrics.duplicate(true),
	}


func prepare_reference_capture() -> void:
	resident_bounds.visible = true
	camera.position = Vector3(118.0, 96.0, 186.0)
	camera.look_at(Vector3(120.0, 20.0, 112.0), Vector3.UP)
	_focus_request = {
		"position": camera.position,
		"target": Vector3(120.0, 20.0, 112.0),
	}


func shutdown_for_validation() -> Dictionary:
	return await _stop_preview()


func _apply_preview_enabled() -> void:
	if editor_preview_enabled:
		await _start_preview()
	else:
		await _stop_preview()


func _restart_preview() -> void:
	await restart_and_wait()


func _start_preview() -> void:
	if _busy or _world_started or not editor_preview_enabled:
		return
	_busy = true
	_current_action = "starting"
	status_label.text = "STARTING"
	Harness.remove_tree(_session_root)
	_harness = Harness.new()
	_harness.name = "NativeTqp35Runtime"
	add_child(_harness)
	var overrides := {
		"active_chunk_capacity": int(_profile.get("active_chunk_capacity", 512)),
		"demand_capacity_per_viewer": int(_profile.get("demand_capacity_per_viewer", 1024)),
		"lod_refinement_radius_chunks": int(_profile.get("lod_refinement_radius_chunks", 1)),
		"render_transition_frames": int(_profile.get("render_transition_frames", 0)),
		"shader_fade_parameter_enabled": bool(_profile.get("shader_fade_parameter_enabled", false)),
		"global_coarse_lod_coverage": bool(_profile.get("global_coarse_lod_coverage", false)),
	}
	if not _harness.create_runtime(int(_profile.get("worker_count", 2)), overrides):
		_fail("native runtime unavailable")
		return
	_terrain = _harness.terrain
	_terrain.call("set_render_material_override", _material)
	var volume: Array = _profile.get("volume_chunks", [])
	var started: bool = volume.size() == 3 and await _harness.start_procedural_world_preset(
		_session_root + "/source",
		int(_profile.get("source_revision", 0)),
		int(_profile.get("seed", 0)),
		str(_profile.get("preset", "")),
		int(volume[0]), int(volume[1]),
		int(_profile.get("vertical_chunk_origin", 0)), int(volume[2])
	)
	if not started:
		_fail("procedural world did not start")
		return
	_world_started = true
	_busy = false
	var result := await _publish_position("initial_load", _position("initial_position"))
	if str(result.get("status", "")) != "PASS":
		_fail("initial publication did not settle")
		return
	prepare_reference_capture()


func _stop_preview() -> Dictionary:
	_busy = true
	var stopped := true
	if is_instance_valid(_harness) and is_instance_valid(_terrain):
		stopped = await _harness.stop_world()
		_harness.dispose()
		_harness.queue_free()
	_harness = null
	_terrain = null
	_world_started = false
	_busy = false
	_metrics = {}
	_last_bounds_signature = ""
	resident_bounds.mesh = null
	Harness.remove_tree(_session_root)
	status_label.text = "STOPPED" if stopped else "FAIL: shutdown"
	return {"status": "PASS" if stopped else "FAIL"}


func _publish_position(action_id: String, position: Vector3) -> Dictionary:
	if not _world_started or not is_instance_valid(_terrain):
		return {"status": "FAIL", "error": "native world is unavailable"}
	_busy = true
	_current_action = action_id
	var before: Dictionary = _terrain.call("get_runtime_metrics")
	_viewer_revision += 1
	viewer_marker.position = position
	var accepted := bool(_terrain.call(
		"update_viewer", _viewer_id, _viewer_revision, position,
		int(_profile.get("viewer_radius_chunks", 1)),
		int(_profile.get("maximum_lod", 1))
	))
	if not accepted:
		_busy = false
		return {"status": "FAIL", "error": "viewer update was rejected"}
	var result := await _wait_for_publication(before)
	_busy = false
	return result


func _rapid_supersession() -> Dictionary:
	if not _world_started or not is_instance_valid(_terrain):
		return {"status": "FAIL", "error": "native world is unavailable"}
	_busy = true
	_current_action = "rapid_supersession"
	var before: Dictionary = _terrain.call("get_runtime_metrics")
	_terrain.call("set_render_apply_budget", 0)
	_terrain.call("set_collision_apply_budget", 0)
	for position_value in _workload.get("supersession_positions", []):
		_viewer_revision += 1
		var position := _vector3(position_value)
		viewer_marker.position = position
		if not bool(_terrain.call(
			"update_viewer", _viewer_id, _viewer_revision, position,
			int(_profile.get("viewer_radius_chunks", 1)),
			int(_profile.get("maximum_lod", 1))
		)):
			_terrain.call("set_render_apply_budget", 2)
			_terrain.call("set_collision_apply_budget", 2)
			_busy = false
			return {"status": "FAIL", "error": "superseding update was rejected"}
	_terrain.call("set_render_apply_budget", 2)
	_terrain.call("set_collision_apply_budget", 2)
	var result := await _wait_for_publication(before)
	_busy = false
	return result


func _unload_viewer() -> Dictionary:
	if not _world_started or not is_instance_valid(_terrain):
		return {"status": "FAIL", "error": "native world is unavailable"}
	_busy = true
	_current_action = "viewer_unload"
	_viewer_revision += 1
	if not bool(_terrain.call("remove_viewer", _viewer_id, _viewer_revision)):
		_busy = false
		return {"status": "FAIL", "error": "viewer removal was rejected"}
	for frame in range(Harness.MAX_WAIT_FRAMES):
		_metrics = _terrain.call("get_runtime_metrics")
		if int(_metrics.get("active_chunk_records", -1)) == 0 \
				and int(_metrics.get("render_resources", -1)) == 0 \
				and int(_metrics.get("collision_resources", -1)) == 0:
			_busy = false
			return {"status": "PASS", "frames": frame, "snapshot": get_validation_snapshot()}
		await get_tree().process_frame
	_busy = false
	return {"status": "FAIL", "error": "viewer unload did not drain"}


func _wait_for_publication(before: Dictionary) -> Dictionary:
	var minimum_updates := int(before.get("viewer_updates", 0)) + 1
	var minimum_demands := int(before.get("planned_demands", 0)) + 1
	for frame in range(Harness.MAX_WAIT_FRAMES):
		_metrics = _terrain.call("get_runtime_metrics")
		if int(_metrics.get("viewer_updates", 0)) >= minimum_updates \
				and int(_metrics.get("planned_demands", 0)) >= minimum_demands \
				and _is_settled(_metrics):
			return {"status": "PASS", "frames": frame, "snapshot": get_validation_snapshot()}
		await get_tree().process_frame
	return {"status": "FAIL", "error": "publication did not settle", "metrics": _metrics}


func _is_settled(metrics: Dictionary) -> bool:
	var active := int(metrics.get("active_chunk_records", 0))
	return active > 0 \
		and int(metrics.get("non_retiring_fully_ready_chunk_records", -1)) \
			== int(metrics.get("non_retiring_chunk_records", -2)) \
		and int(metrics.get("scheduler_queued_jobs", -1)) == 0 \
		and int(metrics.get("scheduler_queued_completions", -1)) == 0 \
		and int(metrics.get("storage_queued_requests", -1)) == 0 \
		and int(metrics.get("storage_queued_completions", -1)) == 0 \
		and int(metrics.get("queued_render", -1)) == 0 \
		and int(metrics.get("queued_collision", -1)) == 0 \
		and int(metrics.get("pending_chunk_replacements", -1)) == 0 \
		and int(metrics.get("pending_chunk_retirements", -1)) == 0 \
		and int(metrics.get("staged_render_resources", -1)) == 0 \
		and int(metrics.get("staged_collision_resources", -1)) == 0


func _refresh_status() -> void:
	if _metrics.is_empty():
		return
	status_label.text = "PUBLISHING" if _busy else "SETTLED"
	status_label.modulate = Color(0.96, 0.72, 0.24) if _busy else Color(0.35, 0.9, 0.65)
	action_label.text = "%s  /  viewer revision %d" % [_current_action, _viewer_revision]
	ownership_label.text = "Active %d   ready %d\nRender %d + %d staged\nCollision %d + %d staged" % [
		int(_metrics.get("active_chunk_records", 0)),
		int(_metrics.get("non_retiring_fully_ready_chunk_records", 0)),
		int(_metrics.get("render_resources", 0)),
		int(_metrics.get("staged_render_resources", 0)),
		int(_metrics.get("collision_resources", 0)),
		int(_metrics.get("staged_collision_resources", 0)),
	]
	pipeline_label.text = "Replacements %d   retirements %d\nStale applications %d   coalesced %d\nTransition completions %d" % [
		int(_metrics.get("pending_chunk_replacements", 0)),
		int(_metrics.get("pending_chunk_retirements", 0)),
		int(_metrics.get("application_stale_render", 0))
			+ int(_metrics.get("application_stale_collision", 0)),
		int(_metrics.get("coalesced_viewer_events", 0)),
		int(_metrics.get("transition_mesh_completions", 0)),
	]


func _refresh_bounds() -> void:
	var records: Array[Dictionary] = []
	var names: Array[String] = []
	for child in _terrain.get_children():
		if not child is MeshInstance3D or not str(child.name).begins_with("WT_Render_") or not child.visible:
			continue
		var parsed := _parse_key(str(child.name), "WT_Render_")
		if parsed.is_empty():
			continue
		records.append(parsed)
		names.append(str(child.name))
	names.sort()
	var signature := "\n".join(names).sha256_text()
	if signature == _last_bounds_signature:
		return
	_last_bounds_signature = signature
	if records.is_empty():
		resident_bounds.mesh = null
		return
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	for record in records:
		var size := 16.0 * float(1 << int(record.get("lod", 0)))
		var minimum: Vector3 = record.get("origin", Vector3.ZERO)
		_add_box_lines(immediate, minimum, minimum + Vector3.ONE * size)
	immediate.surface_end()
	resident_bounds.mesh = immediate


func _collision_overlap_count(names: Array[String]) -> int:
	var bounds: Array[AABB] = []
	for node_name in names:
		var parsed := _parse_key(node_name, "")
		if parsed.is_empty():
			continue
		var size := 16.0 * float(1 << int(parsed.get("lod", 0)))
		bounds.append(AABB(parsed.get("origin", Vector3.ZERO), Vector3.ONE * size))
	var overlaps := 0
	for first in range(bounds.size()):
		for second in range(first + 1, bounds.size()):
			var overlap := bounds[first].intersection(bounds[second])
			if overlap.size.x > 0.0001 and overlap.size.y > 0.0001 and overlap.size.z > 0.0001:
				overlaps += 1
	return overlaps


func _apply_selected_action() -> void:
	var ids := [
		"initial_load", "split_approach", "merge_retreat",
		"rapid_supersession", "teleport", "viewer_unload",
	]
	await run_action_and_wait(ids[int(editor_action)])


func _connect_interface() -> void:
	%InitialButton.pressed.connect(run_action_and_wait.bind("initial_load"))
	%SplitButton.pressed.connect(run_action_and_wait.bind("split_approach"))
	%MergeButton.pressed.connect(run_action_and_wait.bind("merge_retreat"))
	%RapidButton.pressed.connect(run_action_and_wait.bind("rapid_supersession"))
	%TeleportButton.pressed.connect(run_action_and_wait.bind("teleport"))
	%UnloadButton.pressed.connect(run_action_and_wait.bind("viewer_unload"))
	%RestartButton.pressed.connect(restart_and_wait)
	%BoundsToggle.button_pressed = editor_show_resident_bounds
	%BoundsToggle.toggled.connect(func(value: bool) -> void:
		resident_bounds.visible = value
		if Engine.is_editor_hint(): editor_show_resident_bounds = value
	)


func _position(key: String) -> Vector3:
	return _vector3(_workload.get(key, []))


static func _vector3(value: Variant) -> Vector3:
	var coordinates: Array = value if value is Array else []
	if coordinates.size() != 3:
		return Vector3.ZERO
	return Vector3(float(coordinates[0]), float(coordinates[1]), float(coordinates[2]))


static func _parse_key(node_name: String, prefix: String) -> Dictionary:
	var parts := node_name.trim_prefix(prefix).split("_")
	if parts.size() < 4 or not parts[3].begins_with("L"):
		return {}
	var lod := int(parts[3].trim_prefix("L"))
	var size := 16.0 * float(1 << lod)
	return {
		"lod": lod,
		"origin": Vector3(float(parts[0]), float(parts[1]), float(parts[2])) * size,
	}


static func _add_box_lines(immediate: ImmediateMesh, minimum: Vector3, maximum: Vector3) -> void:
	var corners := [
		Vector3(minimum.x, minimum.y, minimum.z), Vector3(maximum.x, minimum.y, minimum.z),
		Vector3(maximum.x, maximum.y, minimum.z), Vector3(minimum.x, maximum.y, minimum.z),
		Vector3(minimum.x, minimum.y, maximum.z), Vector3(maximum.x, minimum.y, maximum.z),
		Vector3(maximum.x, maximum.y, maximum.z), Vector3(minimum.x, maximum.y, maximum.z),
	]
	for edge in [
		[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6],
		[6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7],
	]:
		immediate.surface_add_vertex(corners[edge[0]])
		immediate.surface_add_vertex(corners[edge[1]])


func _fail(message: String) -> void:
	_busy = false
	_world_started = false
	status_label.text = "FAIL: " + message
