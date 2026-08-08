@tool
extends Node3D

const Harness := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_runtime_harness.gd"
)
const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const Qualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_fault_order_qualification.gd"
)
const ReferenceShader := preload(
	"res://labs/terrain_lab/shaders/adaptive_runtime_reference.gdshader"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/fault_order_determinism_standard.json"
)
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/fault_order_observatory"

@export_group("Editor Preview")
@export var editor_preview_enabled := true:
	set(value):
		editor_preview_enabled = value
		if is_inside_tree():
			call_deferred("_apply_preview_enabled")
@export var editor_run_storm_now := false:
	set(value):
		editor_run_storm_now = false
		if value and is_inside_tree():
			call_deferred("run_motion_storm_and_wait", 0)
@export var editor_reverse_replay_now := false:
	set(value):
		editor_reverse_replay_now = false
		if value and is_inside_tree():
			call_deferred("compare_reverse_and_wait")
@export_group("")

@onready var camera: Camera3D = %Camera3D
@onready var status_label: Label = %StatusLabel
@onready var trace_label: Label = %TraceLabel
@onready var events_label: Label = %EventsLabel
@onready var pipeline_label: Label = %PipelineLabel
@onready var identity_label: Label = %IdentityLabel

var _standard := {}
var _profile := {}
var _workload := {}
var _native := {}
var _harness: Node
var _terrain: Node
var _metrics := {}
var _session_root := ""
var _viewer_revision := 0
var _mode := "STARTING"
var _busy := false
var _ready_passed := false
var _failure := ""
var _last_snapshot := {}
var _comparison := {}
var _focus_request: Variant = null


func _ready() -> void:
	_standard = JsonLoader.load_dictionary(STANDARD_PATH)
	_profile = _standard.get("runtime_profile", {})
	_workload = _standard.get("workload", {})
	_native = JsonLoader.load_dictionary(str(_standard.get("native_benchmark_evidence", "")))
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


func run_motion_storm_and_wait(order_index: int = 0) -> Dictionary:
	if _busy or not is_instance_valid(_terrain):
		return _action_failure("runtime is not ready for a motion storm")
	var orders: Array = _workload.get("motion_orders", [])
	if order_index < 0 or order_index >= orders.size():
		return _action_failure("motion order is outside the retained corpus")
	_busy = true
	_mode = "MOTION STORM %d" % order_index
	var accepted := 0
	var order: Array = orders[order_index]
	var work_started := false
	for index in range(order.size()):
		var position_value: Variant = order[index]
		_viewer_revision += 1
		if bool(_terrain.call(
			"update_viewer", int(_profile.get("viewer_id", 431)), _viewer_revision,
			Qualification.vector3(position_value), int(_profile.get("viewer_radius_chunks", 1)),
			int(_profile.get("maximum_lod", 2))
		)):
			accepted += 1
		if index == 0:
			work_started = await _wait_for_work_started(360)
	_viewer_revision += 1
	var drain_submitted := bool(_terrain.call(
		"remove_viewer", int(_profile.get("viewer_id", 431)), _viewer_revision
	))
	var drain_completed := drain_submitted and await _wait_for_empty()
	_viewer_revision += 1
	var final_position := Qualification.vector3(_workload.get("final_position", []))
	if bool(_terrain.call(
		"update_viewer", int(_profile.get("viewer_id", 431)), _viewer_revision,
		final_position, int(_profile.get("viewer_radius_chunks", 1)),
		int(_profile.get("maximum_lod", 2))
	)):
		accepted += 1
	var settlement: Dictionary = await _harness.wait_for_settled(1)
	_metrics = _terrain.call("get_runtime_metrics")
	var stale_before := int(_metrics.get("rejected_events", 0))
	var stale_submitted := bool(_terrain.call(
		"update_viewer", int(_profile.get("viewer_id", 431)), _viewer_revision - 1,
		final_position, int(_profile.get("viewer_radius_chunks", 1)),
		int(_profile.get("maximum_lod", 2))
	))
	var stale_rejected := await _wait_for_metric_increase("rejected_events", stale_before, 360)
	_last_snapshot = Qualification.state_snapshot(_terrain, _harness)
	_metrics = _terrain.call("get_runtime_metrics")
	_busy = false
	var passed: bool = str(settlement.get("status", "")) == "PASS" \
		and work_started \
		and drain_completed \
		and accepted == (orders[order_index] as Array).size() + 1 \
		and stale_submitted and stale_rejected \
		and int(_last_snapshot.get("ready_mismatch_count", -1)) == 0
	if not passed:
		return _action_failure("motion storm did not converge or reject its stale control")
	_ready_passed = true
	_refresh_status()
	return {
		"status": "PASS",
		"order_index": order_index,
		"accepted_updates": accepted,
		"viewer_drain_submitted": drain_submitted,
		"viewer_drain_completed": drain_completed,
		"stale_revision_rejected": stale_rejected,
		"settlement_frames": settlement.get("frames", -1),
		"snapshot": get_validation_snapshot(),
	}


func compare_reverse_and_wait() -> Dictionary:
	var first_restart := await restart_and_wait()
	if str(first_restart.get("status", "")) != "PASS":
		return first_restart
	var forward := await run_motion_storm_and_wait(0)
	if str(forward.get("status", "")) != "PASS":
		return forward
	var forward_state: Dictionary = _last_snapshot.duplicate(true)
	var reverse_restart := await restart_and_wait()
	if str(reverse_restart.get("status", "")) != "PASS":
		return reverse_restart
	var reverse := await run_motion_storm_and_wait(1)
	if str(reverse.get("status", "")) != "PASS":
		return reverse
	var matched: bool = str(forward_state.get("state_signature", "")) \
			== str(_last_snapshot.get("state_signature", "")) \
		and str(forward_state.get("geometry_signature", "")) \
			== str(_last_snapshot.get("geometry_signature", ""))
	_comparison = {
		"status": "PASS" if matched else "FAIL",
		"forward_state_signature": forward_state.get("state_signature", ""),
		"reverse_state_signature": _last_snapshot.get("state_signature", ""),
		"forward_geometry_signature": forward_state.get("geometry_signature", ""),
		"reverse_geometry_signature": _last_snapshot.get("geometry_signature", ""),
	}
	_mode = "FORWARD = REVERSE" if matched else "DIVERGENCE DETECTED"
	if not matched:
		return _action_failure("forward and reverse motion histories diverged")
	_refresh_status()
	return {"status": "PASS", "comparison": _comparison, "snapshot": get_validation_snapshot()}


func restart_and_wait() -> Dictionary:
	await _stop_preview()
	Harness.remove_tree(_session_root)
	await _start_preview()
	return await wait_until_ready()


func get_validation_snapshot() -> Dictionary:
	var native_summary: Dictionary = _native.get("summary", {})
	var counters: Dictionary = native_summary.get("fixed_counters", {})
	return {
		"schema": "world_transvoxel.terrain_lab.fault_order_observatory_snapshot.v1",
		"status": "PASS" if _ready_passed and _failure.is_empty() else "FAIL",
		"mode": _mode,
		"authority": _standard.get("authority", ""),
		"backend_id": str(_terrain.call("get_backend_id")) if is_instance_valid(_terrain) else "",
		"native_runs": int((_native.get("method", {}) as Dictionary).get("measured_runs", 0)),
		"native_orders": int(counters.get("orders", 0)),
		"allocation_faults": int(counters.get("allocation_faults", 0)),
		"interruption_controls": int(counters.get("interruption", 0)),
		"malformed_controls": int(counters.get("malformed", 0)),
		"first_divergence_generation": int(counters.get("first_divergence_generation", -1)),
		"active_chunks": int(_metrics.get("active_chunk_records", 0)),
		"render_resources": int(_metrics.get("render_resources", 0)),
		"collision_resources": int(_metrics.get("collision_resources", 0)),
		"coalesced_viewer_events": int(_metrics.get("coalesced_viewer_events", 0)),
		"rejected_events": int(_metrics.get("rejected_events", 0)),
		"state_signature": _last_snapshot.get("state_signature", ""),
		"geometry_signature": _last_snapshot.get("geometry_signature", ""),
		"comparison": _comparison,
		"metrics": Qualification.selected_metrics(_metrics),
	}


func shutdown_for_validation() -> Dictionary:
	return await _stop_preview()


func _start_preview() -> void:
	if _busy or not editor_preview_enabled:
		return
	_busy = true
	_failure = ""
	_ready_passed = false
	_viewer_revision = 0
	_last_snapshot = {}
	Harness.remove_tree(_session_root)
	if not _create_runtime():
		_busy = false
		_action_failure("authoritative runtime could not be created")
		return
	var started: bool = await _harness.start_procedural_world_preset(
		_session_root,
		int(_profile.get("source_revision", 943001)),
		int(_profile.get("seed", 43043)),
		str(_profile.get("preset_id", "rolling_hills_cave")),
		int(_profile.get("chunk_count_x", 16)),
		int(_profile.get("chunk_count_y", 4)),
		int(_profile.get("chunk_origin_y", -2)),
		int(_profile.get("chunk_count_z", 16))
	)
	if not started:
		_busy = false
		_action_failure("retained procedural world did not start")
		return
	_apply_material()
	_viewer_revision = 1
	var final_position := Qualification.vector3(_workload.get("final_position", []))
	if not bool(_terrain.call(
		"update_viewer", int(_profile.get("viewer_id", 431)), _viewer_revision,
		final_position, int(_profile.get("viewer_radius_chunks", 1)),
		int(_profile.get("maximum_lod", 2))
	)):
		_busy = false
		_action_failure("initial viewer demand was rejected")
		return
	var settlement: Dictionary = await _harness.wait_for_settled(1)
	_metrics = _terrain.call("get_runtime_metrics")
	_busy = false
	if str(settlement.get("status", "")) != "PASS":
		_action_failure("initial terrain demand did not settle")
		return
	_last_snapshot = Qualification.state_snapshot(_terrain, _harness)
	_mode = "SETTLED REFERENCE"
	_ready_passed = true
	var position := final_position + Vector3(54.0, 40.0, 68.0)
	camera.global_position = position
	camera.look_at(final_position + Vector3(0.0, -10.0, 0.0), Vector3.UP)
	_focus_request = {"position": position, "target": final_position + Vector3(0.0, -10.0, 0.0)}
	_refresh_status()


func _create_runtime() -> bool:
	_harness = Harness.new()
	add_child(_harness)
	if not _harness.create_runtime(
		int(_profile.get("worker_count", 2)), Qualification.runtime_overrides(_profile)
	):
		_harness.queue_free()
		_harness = null
		return false
	_terrain = _harness.terrain
	return true


func _apply_material() -> void:
	var material := ShaderMaterial.new()
	material.shader = ReferenceShader
	_terrain.call("set_render_material_override", material)


func _stop_preview() -> Dictionary:
	_busy = true
	var stopped := true
	var drained := true
	if is_instance_valid(_harness) and is_instance_valid(_terrain):
		stopped = await _harness.stop_world()
		drained = Qualification._queues_drained(_terrain.call("get_runtime_metrics"))
	_release_runtime()
	_busy = false
	_ready_passed = false
	_metrics = {}
	_refresh_status()
	return {"status": "PASS" if stopped and drained else "FAIL", "queues_drained": drained}


func _release_runtime() -> void:
	if is_instance_valid(_harness):
		_harness.dispose()
		_harness.queue_free()
	_harness = null
	_terrain = null


func _apply_preview_enabled() -> void:
	if editor_preview_enabled:
		await _start_preview()
	else:
		await _stop_preview()


func _connect_interface() -> void:
	%StormButton.pressed.connect(run_motion_storm_and_wait.bind(0))
	%CompareButton.pressed.connect(compare_reverse_and_wait)
	%RestartButton.pressed.connect(restart_and_wait)


func _refresh_status() -> void:
	if not is_instance_valid(status_label):
		return
	var state := str(_terrain.call("get_world_state_name")) if is_instance_valid(_terrain) else "stopped"
	status_label.text = "%s  |  %s%s" % [
		_mode, state.to_upper(), "  |  " + _failure if not _failure.is_empty() else ""
	]
	var counters: Dictionary = (_native.get("summary", {}) as Dictionary).get("fixed_counters", {})
	trace_label.text = "Native  %s runs x %s orders    First divergence  generation %s" % [
		_grouped(int((_native.get("method", {}) as Dictionary).get("measured_runs", 0))),
		_grouped(int(counters.get("orders", 0))),
		_grouped(int(counters.get("first_divergence_generation", -1))),
	]
	events_label.text = "Events  coalesced %s  rejected %s    Faults  alloc %s / interrupt %s / malformed %s" % [
		_grouped(int(_metrics.get("coalesced_viewer_events", 0))),
		_grouped(int(_metrics.get("rejected_events", 0))),
		_grouped(int(counters.get("allocation_faults", 0))),
		_grouped(int(counters.get("interruption", 0))),
		_grouped(int(counters.get("malformed", 0))),
	]
	pipeline_label.text = "Active %s    Render %s    Collision %s    Queue %s / %s" % [
		_grouped(int(_metrics.get("active_chunk_records", 0))),
		_grouped(int(_metrics.get("render_resources", 0))),
		_grouped(int(_metrics.get("collision_resources", 0))),
		_grouped(int(_metrics.get("scheduler_queued_jobs", 0))),
		_grouped(int(_metrics.get("storage_queued_requests", 0))),
	]
	identity_label.text = "State %s    Geometry %s" % [
		_short_hash(str(_last_snapshot.get("state_signature", ""))),
		_short_hash(str(_last_snapshot.get("geometry_signature", ""))),
	]


func _action_failure(message: String) -> Dictionary:
	_failure = message
	_ready_passed = false
	_busy = false
	_refresh_status()
	return {"status": "FAIL", "error": message}


func _wait_for_metric_increase(key: String, previous: int, maximum_frames: int) -> bool:
	for _frame in range(maximum_frames):
		if int((_terrain.call("get_runtime_metrics") as Dictionary).get(key, 0)) > previous:
			return true
		await get_tree().process_frame
	return false


func _wait_for_work_started(maximum_frames: int) -> bool:
	for frame in range(maximum_frames):
		var metrics: Dictionary = _terrain.call("get_runtime_metrics")
		if int(metrics.get("active_chunk_records", 0)) > 0 \
				or int(metrics.get("scheduler_queued_jobs", 0)) > 0 \
				or int(metrics.get("storage_queued_requests", 0)) > 0:
			return true
		await get_tree().process_frame
		if frame % 8 == 0:
			await get_tree().create_timer(0.001).timeout
	return false


func _wait_for_empty() -> bool:
	for _frame in range(Harness.MAX_WAIT_FRAMES):
		var metrics: Dictionary = _terrain.call("get_runtime_metrics")
		if int(metrics.get("active_chunk_records", -1)) == 0 \
				and int(metrics.get("render_resources", -1)) == 0 \
				and int(metrics.get("collision_resources", -1)) == 0 \
				and int(metrics.get("scheduler_queued_jobs", -1)) == 0 \
				and int(metrics.get("storage_queued_requests", -1)) == 0 \
				and int(metrics.get("queued_render", -1)) == 0 \
				and int(metrics.get("queued_collision", -1)) == 0 \
				and int(metrics.get("pending_chunk_retirements", -1)) == 0:
			return true
		await get_tree().process_frame
	return false


static func _is_settled(metrics: Dictionary) -> bool:
	return int(metrics.get("active_chunk_records", 0)) > 0 \
		and int(metrics.get("non_retiring_fully_ready_chunk_records", 0)) \
			== int(metrics.get("non_retiring_chunk_records", -1)) \
		and int(metrics.get("scheduler_queued_jobs", -1)) == 0 \
		and int(metrics.get("scheduler_queued_completions", -1)) == 0 \
		and int(metrics.get("storage_queued_requests", -1)) == 0 \
		and int(metrics.get("storage_queued_completions", -1)) == 0 \
		and int(metrics.get("queued_render", -1)) == 0 \
		and int(metrics.get("queued_collision", -1)) == 0 \
		and int(metrics.get("pending_chunk_replacements", -1)) == 0 \
		and int(metrics.get("pending_chunk_retirements", -1)) == 0


static func _short_hash(value: String) -> String:
	return value.left(12) if not value.is_empty() else "pending"


static func _grouped(value: int) -> String:
	var digits := str(absi(value))
	var output := ""
	for index in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:
			output += ","
		output += digits[index]
	return "-" + output if value < 0 else output
