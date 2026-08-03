@tool
extends Node3D

const Harness := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_runtime_harness.gd"
)
const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const Qualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_adaptive_streaming_qualification.gd"
)
const ReferenceShader := preload(
	"res://labs/terrain_lab/shaders/adaptive_runtime_reference.gdshader"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/adaptive_streaming_residency_standard.json"
)
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/adaptive_streaming_observatory"

enum InspectionMode { CAVE, MULTI_VIEWER, TELEPORT }

@export_group("Editor Preview")
@export var editor_preview_enabled := true:
	set(value):
		editor_preview_enabled = value
		if is_inside_tree():
			call_deferred("_apply_preview_enabled")
@export var editor_inspection_mode: InspectionMode = InspectionMode.CAVE:
	set(value):
		editor_inspection_mode = value
		if is_inside_tree():
			call_deferred("_apply_selected_mode")
@export var editor_restart_now := false:
	set(value):
		editor_restart_now = false
		if value and is_inside_tree():
			call_deferred("restart_and_wait")
@export_group("")

@onready var camera: Camera3D = %Camera3D
@onready var cave_light: OmniLight3D = %CaveLight
@onready var status_label: Label = %StatusLabel
@onready var mode_label: Label = %ModeLabel
@onready var residency_label: Label = %ResidencyLabel
@onready var pipeline_label: Label = %PipelineLabel

var _standard := {}
var _profile := {}
var _workload := {}
var _harness: Node
var _terrain: Node
var _session_root := ""
var _viewer_revisions := {}
var _metrics := {}
var _mode := "cave"
var _busy := false
var _ready_passed := false
var _failure := ""
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
		if not _failure.is_empty():
			return {"status": "FAIL", "frames": frame, "error": _failure}
		await get_tree().process_frame
	return {"status": "FAIL", "frames": maximum_frames, "error": "preview timed out"}


func set_inspection_mode(mode: String) -> Dictionary:
	match mode:
		"cave":
			if _mode != "cave":
				return await restart_and_wait()
		"multi_viewer":
			return await run_multi_viewer_and_wait()
		"teleport":
			return await teleport_and_wait()
		_:
			return {"status": "FAIL", "error": "unknown inspection mode"}
	prepare_reference_capture(mode)
	return {"status": "PASS", "snapshot": get_validation_snapshot()}


func run_multi_viewer_and_wait() -> Dictionary:
	if _busy or not _ready_passed:
		return {"status": "FAIL", "error": "streaming observatory is not ready"}
	_busy = true
	var viewers: Array = [
		_workload.get("surface_viewer", {}),
		_workload.get("prefetch_viewer", {}),
	]
	var settled := await _update_viewers_and_wait(viewers)
	_mode = "multi_viewer"
	_busy = false
	prepare_reference_capture(_mode)
	return _mode_result(settled)


func teleport_and_wait() -> Dictionary:
	if _busy or not _ready_passed:
		return {"status": "FAIL", "error": "streaming observatory is not ready"}
	_busy = true
	var settled := await _update_viewers_and_wait(_workload.get("teleport_viewers", []))
	_mode = "teleport"
	_busy = false
	prepare_reference_capture(_mode)
	return _mode_result(settled)


func restart_and_wait() -> Dictionary:
	if _busy:
		return {"status": "FAIL", "error": "streaming observatory is busy"}
	await _stop_preview()
	await _start_preview()
	return await wait_until_ready()


func prepare_reference_capture(mode: String = "cave") -> void:
	cave_light.visible = mode == "cave"
	match mode:
		"multi_viewer":
			camera.position = Vector3(1085.0, 185.0, 1235.0)
			camera.look_at(Vector3(990.0, 0.0, 995.0), Vector3.UP)
		"teleport":
			camera.position = Vector3(520.0, 320.0, 600.0)
			camera.look_at(Vector3(320.0, 0.0, 320.0), Vector3.UP)
		_:
			camera.position = Vector3(1020.0, -18.0, 1020.0)
			camera.look_at(Vector3(1029.0, -20.0, 1030.0), Vector3.UP)
	_focus_request = {
		"position": camera.position,
		"target": camera.position - camera.global_basis.z * 16.0,
	}


func get_validation_snapshot() -> Dictionary:
	var state := Qualification._state_snapshot(_terrain) if is_instance_valid(_terrain) else {}
	var expected: Dictionary = _standard.get("stable_expected", {})
	var prefix := "multi_viewer" if _mode == "multi_viewer" else _mode
	var valid := _ready_passed \
		and str(state.get("state_signature", "")) == str(expected.get(prefix + "_state_signature", "")) \
		and int(state.get("generation_mismatch_count", -1)) == 0
	return {
		"schema": "world_transvoxel.terrain_lab.adaptive_streaming_observatory_snapshot.v1",
		"status": "PASS" if valid else "FAIL",
		"mode": _mode,
		"backend_id": str(_terrain.call("get_backend_id")) if is_instance_valid(_terrain) else "",
		"state": state,
		"metrics": _metrics.duplicate(true),
	}


func shutdown_for_validation() -> Dictionary:
	return await _stop_preview()


func _start_preview() -> void:
	if _busy or _ready_passed or not editor_preview_enabled:
		return
	_busy = true
	_failure = ""
	_ready_passed = false
	_mode = "cave"
	_viewer_revisions.clear()
	Harness.remove_tree(_session_root)
	_harness = Harness.new()
	_harness.name = "NativeTqp40Runtime"
	add_child(_harness)
	if not _harness.create_runtime(
		int(_profile.get("worker_count", 2)), Qualification._runtime_overrides(_profile)
	):
		_fail_preview("native runtime unavailable")
		return
	_terrain = _harness.terrain
	_terrain.call("set_render_material_override", _create_material())
	var volume: Array = _profile.get("volume_chunks", [])
	var started: bool = volume.size() == 3 and await _harness.start_procedural_world_preset(
		_session_root.path_join("source"), int(_profile.get("source_revision", 940001)),
		int(_profile.get("seed", 400040)), str(_profile.get("procedural_preset", "rolling_hills_cave")),
		int(volume[0]), int(volume[1]), int(_profile.get("vertical_chunk_origin", -16)), int(volume[2])
	)
	if not started:
		_fail_preview("native procedural world did not start")
		return
	var settled := await _update_viewers_and_wait([_workload.get("cave_viewer", {})])
	if str(settled.get("status", "")) != "PASS":
		_fail_preview("cave residency did not settle")
		return
	_ready_passed = true
	_busy = false
	prepare_reference_capture("cave")
	var snapshot := get_validation_snapshot()
	if str(snapshot.get("status", "")) != "PASS":
		_fail_preview("cave residency does not match the pinned native state")


func _update_viewers_and_wait(viewers_value: Variant) -> Dictionary:
	var viewers: Array = viewers_value
	var before := int((_terrain.call("get_runtime_metrics") as Dictionary).get("viewer_updates", 0))
	for viewer_value in viewers:
		var viewer: Dictionary = viewer_value
		var id := int(viewer.get("id", 0))
		var revision := int(_viewer_revisions.get(id, 0)) + 1
		_viewer_revisions[id] = revision
		if not bool(_terrain.call(
			"update_viewer", id, revision, _vector3(viewer.get("position", [])),
			int(viewer.get("radius_chunks", 0)), int(_profile.get("maximum_lod", 2))
		)):
			return {"status": "FAIL", "error": "native viewer update rejected"}
	for _frame in range(Harness.MAX_WAIT_FRAMES):
		if int((_terrain.call("get_runtime_metrics") as Dictionary).get("viewer_updates", 0)) \
				>= before + viewers.size():
			await get_tree().process_frame
			return await _harness.wait_for_settled()
		await get_tree().process_frame
	return {"status": "FAIL", "error": "native viewer update timed out"}


func _mode_result(settlement: Dictionary) -> Dictionary:
	var snapshot := get_validation_snapshot()
	var passed := str(settlement.get("status", "")) == "PASS" \
		and str(snapshot.get("status", "")) == "PASS"
	return {
		"status": "PASS" if passed else "FAIL",
		"settlement": settlement,
		"snapshot": snapshot,
	}


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
	return {"status": "PASS" if stopped else "FAIL"}


func _apply_preview_enabled() -> void:
	if editor_preview_enabled:
		await _start_preview()
	else:
		await _stop_preview()


func _apply_selected_mode() -> void:
	var modes := ["cave", "multi_viewer", "teleport"]
	await set_inspection_mode(modes[int(editor_inspection_mode)])


func _connect_interface() -> void:
	%CaveButton.pressed.connect(set_inspection_mode.bind("cave"))
	%MultiButton.pressed.connect(set_inspection_mode.bind("multi_viewer"))
	%TeleportButton.pressed.connect(set_inspection_mode.bind("teleport"))
	%RestartButton.pressed.connect(restart_and_wait)


func _refresh_status() -> void:
	if not is_instance_valid(status_label):
		return
	status_label.text = "WORKING" if _busy else ("PASS  PINNED STATE" if _ready_passed else "STARTING")
	if not _failure.is_empty():
		status_label.text = "FAIL  " + _failure
	mode_label.text = "MODE  " + _mode.to_upper()
	var state := Qualification._state_snapshot(_terrain) if is_instance_valid(_terrain) else {}
	var lods: Dictionary = state.get("lod_counts", {})
	residency_label.text = "Active %d   LOD0 %d   LOD1 %d   LOD2 %d" % [
		int(state.get("active_count", 0)), int(lods.get("0", 0)),
		int(lods.get("1", 0)), int(lods.get("2", 0)),
	]
	pipeline_label.text = "Render %d   collision %d\nQueued jobs %d   retirements %d" % [
		int(_metrics.get("render_resources", 0)), int(_metrics.get("collision_resources", 0)),
		int(_metrics.get("scheduler_queued_jobs", 0)), int(_metrics.get("pending_chunk_retirements", 0)),
	]


func _fail_preview(message: String) -> void:
	_failure = message
	_busy = false
	_ready_passed = false


static func _create_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = ReferenceShader
	return material


static func _is_settled(metrics: Dictionary) -> bool:
	return int(metrics.get("active_chunk_records", 0)) > 0 \
		and int(metrics.get("non_retiring_fully_ready_chunk_records", 0)) \
			== int(metrics.get("non_retiring_chunk_records", -1)) \
		and int(metrics.get("scheduler_queued_jobs", -1)) == 0 \
		and int(metrics.get("storage_queued_requests", -1)) == 0 \
		and int(metrics.get("queued_render", -1)) == 0 \
		and int(metrics.get("pending_chunk_retirements", -1)) == 0


static func _vector3(value: Variant) -> Vector3:
	var values: Array = value
	return Vector3(float(values[0]), float(values[1]), float(values[2])) \
		if values.size() == 3 else Vector3.ZERO
