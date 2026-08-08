@tool
extends Node3D

const Harness := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_runtime_harness.gd"
)
const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const Qualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_sparse_hierarchy_qualification.gd"
)
const ReferenceShader := preload(
	"res://labs/terrain_lab/shaders/adaptive_runtime_reference.gdshader"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/sparse_hierarchy_storage_standard.json"
)
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/sparse_hierarchy_observatory"

@export_group("Editor Preview")
@export var editor_preview_enabled := true:
	set(value):
		editor_preview_enabled = value
		if is_inside_tree():
			call_deferred("_apply_preview_enabled")
@export var editor_apply_edit_now := false:
	set(value):
		editor_apply_edit_now = false
		if value and is_inside_tree():
			call_deferred("apply_localized_edit")
@export var editor_compact_now := false:
	set(value):
		editor_compact_now = false
		if value and is_inside_tree():
			call_deferred("compact_and_reopen")
@export_group("")

@onready var camera: Camera3D = %Camera3D
@onready var status_label: Label = %StatusLabel
@onready var pages_label: Label = %PagesLabel
@onready var memory_label: Label = %MemoryLabel
@onready var overlay_label: Label = %OverlayLabel
@onready var queries_label: Label = %QueriesLabel
@onready var pipeline_label: Label = %PipelineLabel

var _standard := {}
var _profile := {}
var _workload := {}
var _harness: Node
var _terrain: Node
var _session_root := ""
var _source_root := ""
var _snapshot_root := ""
var _reopen_journal_root := ""
var _metrics := {}
var _viewer_revision := 0
var _edit_revision := 0
var _overlay_pages := 0
var _mode := "SOURCE"
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
	_source_root = _session_root.path_join("source")
	_snapshot_root = _session_root.path_join("snapshot")
	_reopen_journal_root = _session_root.path_join("reopen_journal")
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


func apply_localized_edit() -> Dictionary:
	if _busy or not is_instance_valid(_terrain):
		return _action_failure("runtime is not ready for an edit")
	_busy = true
	_edit_revision += 1
	var committed := await _commit_operations(
		_workload.get("central_transaction", []), 4242, _edit_revision
	)
	var settled: Dictionary = await _harness.wait_for_settled(1) if committed else {}
	_busy = false
	if not committed or str(settled.get("status", "")) != "PASS":
		return _action_failure("localized construction failed")
	_mode = "EDIT JOURNAL"
	_refresh_status()
	return {"status": "PASS", "snapshot": get_validation_snapshot()}


func compact_and_reopen() -> Dictionary:
	if _busy or not is_instance_valid(_terrain):
		return _action_failure("runtime is not ready for compaction")
	_busy = true
	if _edit_revision == 0:
		_edit_revision = 1
		if not await _commit_operations(
			_workload.get("central_transaction", []), 4242, _edit_revision
		):
			_busy = false
			return _action_failure("localized construction failed before compaction")
		await _harness.wait_for_settled(1)
	var compacted: Dictionary = await _harness.request_compaction(
		_snapshot_root, int(_profile.get("compacted_source_revision", 0))
	)
	if str(compacted.get("status", "")) != "PASS":
		_busy = false
		return _action_failure("sparse compaction failed: " + str(compacted.get("error", "")))
	_overlay_pages = int(compacted.get("page_count", 0))
	if not await _harness.stop_world():
		_busy = false
		return _action_failure("source runtime did not stop")
	_release_runtime()
	if not _create_runtime() or not await _harness.start_procedural_snapshot(
		_snapshot_root, _reopen_journal_root
	):
		_busy = false
		return _action_failure("sparse snapshot did not reopen")
	_terrain = _harness.terrain
	_apply_material()
	var settled := await _update_viewer_and_wait()
	_busy = false
	if str(settled.get("status", "")) != "PASS":
		return _action_failure("reopened sparse snapshot did not settle")
	_mode = "SPARSE SNAPSHOT"
	_ready_passed = true
	_refresh_status()
	return {"status": "PASS", "snapshot": get_validation_snapshot()}


func restart_source() -> Dictionary:
	await _stop_preview()
	Harness.remove_tree(_session_root)
	await _start_preview()
	return await wait_until_ready()


func get_validation_snapshot() -> Dictionary:
	return {
		"schema": "world_transvoxel.terrain_lab.sparse_hierarchy_observatory_snapshot.v1",
		"status": "PASS" if _ready_passed and _failure.is_empty() else "FAIL",
		"mode": _mode,
		"authority": _standard.get("authority", ""),
		"declared_pages": int(_metrics.get("hierarchy_declared_pages", 0)),
		"explicit_index_entries": int(_metrics.get("hierarchy_explicit_index_entries", -1)),
		"hierarchy_index_bytes": int(_metrics.get("hierarchy_estimated_index_bytes", 0)),
		"overlay_pages": int(_metrics.get("hierarchy_sparse_overlay_entries", _overlay_pages)),
		"overlay_index_bytes": int(_metrics.get("hierarchy_sparse_overlay_index_bytes", 0)),
		"active_chunks": int(_metrics.get("active_chunk_records", 0)),
		"render_resources": int(_metrics.get("render_resources", 0)),
		"collision_resources": int(_metrics.get("collision_resources", 0)),
		"metrics": Qualification._selected_metrics(_metrics),
	}


func shutdown_for_validation() -> Dictionary:
	return await _stop_preview()


func _start_preview() -> void:
	if _busy or not editor_preview_enabled:
		return
	_busy = true
	_failure = ""
	_ready_passed = false
	Harness.remove_tree(_session_root)
	Harness.ensure_directory(_session_root)
	if not _create_runtime():
		_busy = false
		_action_failure("authoritative runtime could not be created")
		return
	var started: bool = await _harness.start_procedural_world_preset(
		_source_root,
		int(_profile.get("source_revision", 0)),
		int(_profile.get("seed", 0)),
		str(_profile.get("preset_id", "")),
		int(_profile.get("chunk_count_x", 0)),
		int(_profile.get("chunk_count_y", 0)),
		int(_profile.get("chunk_origin_y", 0)),
		int(_profile.get("chunk_count_z", 0))
	)
	if not started:
		_busy = false
		_action_failure("299,520-page procedural source did not start")
		return
	_apply_material()
	var settled := await _update_viewer_and_wait()
	_busy = false
	if str(settled.get("status", "")) != "PASS":
		_action_failure("initial sparse hierarchy demand did not settle")
		return
	_mode = "SOURCE"
	_ready_passed = true
	var target := _viewer_position()
	var position := target + Vector3(44.0, 34.0, 58.0)
	camera.global_position = position
	camera.look_at(target + Vector3(0.0, -8.0, 0.0), Vector3.UP)
	_focus_request = {"position": position, "target": target + Vector3(0.0, -8.0, 0.0)}
	_refresh_status()


func _create_runtime() -> bool:
	_harness = Harness.new()
	add_child(_harness)
	if not _harness.create_runtime(
		int(_profile.get("worker_count", 2)),
		Qualification._runtime_overrides(_profile)
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


func _update_viewer_and_wait() -> Dictionary:
	_viewer_revision += 1
	if not bool(_terrain.call(
		"update_viewer",
		int(_profile.get("viewer_id", 421)),
		_viewer_revision,
		_viewer_position(),
		int(_profile.get("viewer_radius_chunks", 1)),
		int(_profile.get("maximum_lod", 3))
	)):
		return {"status": "FAIL", "error": "viewer update rejected"}
	return await _harness.wait_for_settled(1)


func _commit_operations(operations: Array, author: int, revision: int) -> bool:
	var transaction: RefCounted = _terrain.call("begin_edit_transaction", author)
	if transaction == null:
		return false
	for value in operations:
		var operation: Dictionary = value
		var method := str(operation.get("operation", ""))
		var accepted := false
		if method == "carve_smooth_sdf_sphere":
			accepted = bool(transaction.call(method, _vector3(operation.get("center", [])), float(operation.get("radius", 0.0)), float(operation.get("strength", 1.0)), float(operation.get("smooth_radius", 0.0))))
		elif method == "construct_material_smooth_sdf_sphere":
			accepted = bool(transaction.call(method, _vector3(operation.get("center", [])), float(operation.get("radius", 0.0)), float(operation.get("strength", 1.0)), int(operation.get("material", 0)), float(operation.get("smooth_radius", 0.0))))
		if not accepted:
			return false
	return bool(_terrain.call("commit_edit_transaction", transaction)) \
		and await _harness.wait_for_commit(revision)


func _stop_preview() -> Dictionary:
	_busy = true
	var stopped := true
	if is_instance_valid(_harness) and is_instance_valid(_terrain):
		stopped = await _harness.stop_world()
	_release_runtime()
	_busy = false
	_ready_passed = false
	_metrics = {}
	_refresh_status()
	return {"status": "PASS" if stopped else "FAIL"}


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
	%EditButton.pressed.connect(apply_localized_edit)
	%CompactButton.pressed.connect(compact_and_reopen)
	%RestartButton.pressed.connect(restart_source)


func _refresh_status() -> void:
	if not is_instance_valid(status_label):
		return
	var state := str(_terrain.call("get_world_state_name")) if is_instance_valid(_terrain) else "stopped"
	status_label.text = "%s  |  %s%s" % [
		_mode,
		state.to_upper(),
		"  |  " + _failure if not _failure.is_empty() else "",
	]
	pages_label.text = "Declared  %s    Active  %s" % [
		_grouped(int(_metrics.get("hierarchy_declared_pages", 0))),
		_grouped(int(_metrics.get("active_chunk_records", 0))),
	]
	memory_label.text = "Hierarchy index  %s B    Explicit keys  %s" % [
		_grouped(int(_metrics.get("hierarchy_estimated_index_bytes", 0))),
		_grouped(int(_metrics.get("hierarchy_explicit_index_entries", 0))),
	]
	overlay_label.text = "Overlay  %s pages / %s B    Cache  %s + %s" % [
		_grouped(int(_metrics.get("hierarchy_sparse_overlay_entries", _overlay_pages))),
		_grouped(int(_metrics.get("hierarchy_sparse_overlay_index_bytes", 0))),
		_grouped(int(_metrics.get("page_cache_encoded_entries", 0))),
		_grouped(int(_metrics.get("page_cache_decoded_entries", 0))),
	]
	queries_label.text = "Queries  member %s  child %s  range %s  roots %s" % [
		_grouped(int(_metrics.get("hierarchy_membership_queries", 0))),
		_grouped(int(_metrics.get("hierarchy_child_queries", 0))),
		_grouped(int(_metrics.get("hierarchy_range_queries", 0))),
		_grouped(int(_metrics.get("hierarchy_viewer_root_queries", 0))),
	]
	pipeline_label.text = "Resources  render %s  collision %s    Queue  %s / %s" % [
		_grouped(int(_metrics.get("render_resources", 0))),
		_grouped(int(_metrics.get("collision_resources", 0))),
		_grouped(int(_metrics.get("scheduler_queued_jobs", 0))),
		_grouped(int(_metrics.get("storage_queued_requests", 0))),
	]


func _action_failure(message: String) -> Dictionary:
	_failure = message
	_ready_passed = false
	_refresh_status()
	return {"status": "FAIL", "error": message}


func _viewer_position() -> Vector3:
	return _vector3(_profile.get("viewer_position", []))


static func _is_settled(metrics: Dictionary) -> bool:
	return int(metrics.get("active_chunk_records", 0)) > 0 \
		and int(metrics.get("non_retiring_fully_ready_chunk_records", 0)) \
			== int(metrics.get("non_retiring_chunk_records", -1)) \
		and int(metrics.get("scheduler_queued_jobs", -1)) == 0 \
		and int(metrics.get("storage_queued_requests", -1)) == 0 \
		and int(metrics.get("queued_render", -1)) == 0 \
		and int(metrics.get("pending_chunk_replacements", -1)) == 0 \
		and int(metrics.get("pending_chunk_retirements", -1)) == 0


static func _vector3(value: Variant) -> Vector3:
	var values: Array = value
	return Vector3(float(values[0]), float(values[1]), float(values[2])) if values.size() == 3 else Vector3.ZERO


static func _grouped(value: int) -> String:
	var digits := str(absi(value))
	var output := ""
	for index in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:
			output += ","
		output += digits[index]
	return "-" + output if value < 0 else output
