@tool
extends Node3D

const Harness := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_runtime_harness.gd"
)
const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const Qualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_adaptive_persistence_qualification.gd"
)
const ReferenceShader := preload(
	"res://labs/terrain_lab/shaders/adaptive_runtime_reference.gdshader"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/adaptive_persistence_standard.json"
)
const FIXTURE_ROOT := "res://labs/terrain_lab/fixtures/adaptive_persistence"
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/adaptive_persistence_observatory"

enum InspectionMode { EDITED, REPLAYED, DISTANT }

@export_group("Editor Preview")
@export var editor_preview_enabled := true:
	set(value):
		editor_preview_enabled = value
		if is_inside_tree():
			call_deferred("_apply_preview_enabled")
@export var editor_inspection_mode: InspectionMode = InspectionMode.EDITED:
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
@onready var revision_label: Label = %RevisionLabel
@onready var pipeline_label: Label = %PipelineLabel

var _standard := {}
var _fixture := {}
var _profile := {}
var _workload := {}
var _harness: Node
var _terrain: Node
var _session_root := ""
var _source_root := ""
var _compacted_root := ""
var _manifest_path := ""
var _viewer_revision := 0
var _metrics := {}
var _mode := "edited"
var _central_samples: Array[Dictionary] = []
var _distant_sample := {}
var _busy := false
var _ready_passed := false
var _failure := ""
var _focus_request: Variant = null


func _ready() -> void:
	_standard = JsonLoader.load_dictionary(STANDARD_PATH)
	_fixture = JsonLoader.load_dictionary(str(_standard.get("fixture_manifest", "")))
	_profile = _standard.get("runtime_profile", {})
	_workload = _standard.get("workload", {})
	_session_root = RUNTIME_ROOT + "/%s_%d" % [
		"editor" if Engine.is_editor_hint() else "runtime", OS.get_process_id()
	]
	_source_root = _session_root.path_join("source")
	_compacted_root = _session_root.path_join("compacted")
	_manifest_path = _source_root.path_join(str(_fixture.get("manifest", "world.wtworld")))
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
		"edited":
			if _mode != "edited":
				return await restart_and_wait()
		"replayed":
			return await replay_and_wait()
		"distant":
			return await show_distant_and_wait()
		_:
			return {"status": "FAIL", "error": "unknown inspection mode"}
	prepare_reference_capture(mode)
	return {"status": "PASS", "snapshot": get_validation_snapshot()}


func replay_and_wait() -> Dictionary:
	if _busy or not _ready_passed:
		return {"status": "FAIL", "error": "persistence observatory is not ready"}
	_busy = true
	if not await _release_runtime():
		return _fail_action("edited runtime did not stop")
	if not await _create_runtime_and_start():
		return _fail_action("fresh replay runtime did not start")
	var settled := await _update_viewer_and_wait(
		_vector3(_profile.get("viewer_position", [])),
		int(_profile.get("viewer_radius_chunks", 1))
	)
	if str(settled.get("status", "")) != "PASS" or int(_terrain.call("get_world_revision")) != 2:
		return _fail_action("journal replay did not restore revision 2")
	await _refresh_queries()
	_mode = "replayed"
	_busy = false
	prepare_reference_capture(_mode)
	return _mode_result(settled)


func show_distant_and_wait() -> Dictionary:
	if _busy or not _ready_passed:
		return {"status": "FAIL", "error": "persistence observatory is not ready"}
	_busy = true
	var compacted: Dictionary = await _harness.request_compaction(
		_compacted_root, int(_profile.get("compacted_source_revision", 941002))
	)
	if str(compacted.get("status", "")) != "PASS":
		return _fail_action("supported adaptive compaction failed")
	if not await _release_runtime():
		return _fail_action("journal runtime did not stop before compacted replay")
	if not await _create_runtime_and_start(
		str(compacted.get("manifest_path", "")), _compacted_root
	):
		return _fail_action("fresh compacted runtime did not start")
	var settled := await _update_viewer_and_wait(
		_vector3(_workload.get("distant_viewer_position", [])), 0
	)
	_distant_sample = await _harness.request_sample(
		_vector3i(_workload.get("distant_probe", [])), 1
	)
	_mode = "distant"
	_busy = false
	prepare_reference_capture(_mode)
	return _mode_result(settled)


func restart_and_wait() -> Dictionary:
	if _busy:
		return {"status": "FAIL", "error": "persistence observatory is busy"}
	await _stop_preview()
	await _start_preview()
	return await wait_until_ready()


func prepare_reference_capture(mode: String = "edited") -> void:
	cave_light.visible = false
	match mode:
		"distant":
			camera.position = Vector3(198.0, 74.0, 202.0)
			camera.look_at(Vector3(176.0, 58.0, 176.0), Vector3.UP)
		_:
			camera.position = Vector3(108.0, 76.0, 112.0)
			camera.look_at(Vector3(80.0, 57.0, 80.0), Vector3.UP)
	_focus_request = {
		"position": camera.position,
		"target": camera.position - camera.global_basis.z * 12.0,
	}


func get_validation_snapshot() -> Dictionary:
	var state := Qualification._state_snapshot(_terrain, _harness) \
		if is_instance_valid(_terrain) and is_instance_valid(_harness) else {}
	var expected: Dictionary = _standard.get("stable_expected", {})
	var common_valid := _ready_passed and is_instance_valid(_terrain) \
		and int(_terrain.call("get_world_revision")) == 2 \
		and int(state.get("ready_mismatch_count", -1)) == 0
	var cave_triangles := _triangle_near_count(Vector3(80.0, 42.0, 80.0), 8.0)
	var mode_valid := false
	if _mode == "distant":
		mode_valid = int(state.get("active_count", -1)) == 1 \
			and int((_metrics as Dictionary).get("render_resources", -1)) == 1 \
			and int(_distant_sample.get("material", -1)) == 7
	else:
		mode_valid = str(state.get("state_signature", "")) \
			== str(expected.get("initial_state_signature", "")) \
			and str(state.get("geometry_signature", "")) \
			== str(expected.get("edited_geometry_signature", "")) \
			and _central_queries_valid(_central_samples) \
			and cave_triangles > 0
	return {
		"schema": "world_transvoxel.terrain_lab.adaptive_persistence_observatory_snapshot.v1",
		"status": "PASS" if common_valid and mode_valid else "FAIL",
		"mode": _mode,
		"backend_id": str(_terrain.call("get_backend_id")) if is_instance_valid(_terrain) else "",
		"world_revision": int(_terrain.call("get_world_revision")) if is_instance_valid(_terrain) else -1,
		"central_queries": _central_samples.duplicate(true),
		"distant_query": _distant_sample.duplicate(true),
		"cave_triangle_count": cave_triangles,
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
	_mode = "edited"
	Harness.remove_tree(_session_root)
	var fixture_failures: Array[String] = []
	if not Qualification._stage_fixture(_fixture, _source_root, fixture_failures):
		_fail_preview("native-baked fixture integrity failed")
		return
	if not await _create_runtime_and_start():
		_fail_preview("native-baked fixture did not start")
		return
	var settled := await _update_viewer_and_wait(
		_vector3(_profile.get("viewer_position", [])),
		int(_profile.get("viewer_radius_chunks", 1))
	)
	if str(settled.get("status", "")) != "PASS":
		_fail_preview("initial adaptive residency did not settle")
		return
	if not await _commit_operations(_workload.get("central_transaction", []), 41101, 1):
		_fail_preview("central edit transaction failed")
		return
	if not await _commit_operations(_workload.get("distant_transaction", []), 41102, 2):
		_fail_preview("distant unloaded transaction failed")
		return
	if str((await _harness.wait_for_settled()).get("status", "")) != "PASS":
		_fail_preview("edited runtime did not settle")
		return
	await _refresh_queries()
	_ready_passed = true
	_busy = false
	prepare_reference_capture("edited")
	var validation := get_validation_snapshot()
	if str(validation.get("status", "")) != "PASS":
		var state: Dictionary = validation.get("state", {})
		_fail_preview(
			"edited state mismatch state=%s geometry=%s central=%s samples=%s" % [
				state.get("state_signature", ""),
				state.get("geometry_signature", ""),
				_central_queries_valid(_central_samples),
				_central_samples,
			]
		)


func _create_runtime_and_start(
	manifest_path: String = "", object_root: String = ""
) -> bool:
	_harness = Harness.new()
	_harness.name = "NativeTqp41Runtime"
	add_child(_harness)
	if not _harness.create_runtime(
		int(_profile.get("worker_count", 2)), Qualification._runtime_overrides(_profile)
	):
		return false
	_terrain = _harness.terrain
	_terrain.call("set_render_material_override", _create_material())
	_viewer_revision = 0
	return await _harness.start_manifest(
		_manifest_path if manifest_path.is_empty() else manifest_path,
		_source_root if object_root.is_empty() else object_root
	)


func _commit_operations(operations_value: Variant, author: int, expected_revision: int) -> bool:
	var transaction: RefCounted = _terrain.call("begin_edit_transaction", author)
	if transaction == null:
		return false
	for operation_value in operations_value:
		if not Qualification._append_operation(transaction, operation_value):
			return false
	return bool(_terrain.call("commit_edit_transaction", transaction)) \
		and await _harness.wait_for_commit(expected_revision)


func _update_viewer_and_wait(position: Vector3, radius: int) -> Dictionary:
	var before := int((_terrain.call("get_runtime_metrics") as Dictionary).get("viewer_updates", 0))
	_viewer_revision += 1
	if not bool(_terrain.call(
		"update_viewer", int(_profile.get("viewer_id", 411)), _viewer_revision,
		position, radius, int(_profile.get("maximum_lod", 1))
	)):
		return {"status": "FAIL", "error": "native viewer update rejected"}
	for _frame in range(Harness.MAX_WAIT_FRAMES):
		if int((_terrain.call("get_runtime_metrics") as Dictionary).get("viewer_updates", 0)) > before:
			await get_tree().process_frame
			return await _harness.wait_for_settled()
		await get_tree().process_frame
	return {"status": "FAIL", "error": "native viewer update timed out"}


func _refresh_queries() -> void:
	_central_samples = await _harness.request_samples(
		_vector3i_array(_workload.get("central_probes", []))
	)
	_distant_sample = await _harness.request_sample(
		_vector3i(_workload.get("distant_probe", [])), 1
	)


func _triangle_near_count(center: Vector3, radius: float) -> int:
	var count := 0
	var radius_squared := radius * radius
	if not is_instance_valid(_terrain):
		return count
	for child in _terrain.get_children():
		if not child is MeshInstance3D or not str(child.name).begins_with("WT_Render_"):
			continue
		var render := child as MeshInstance3D
		if render.mesh == null:
			continue
		for surface in range(render.mesh.get_surface_count()):
			var arrays := render.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for index in range(0, indices.size(), 3):
				var centroid := render.position + (
					vertices[indices[index]] + vertices[indices[index + 1]]
					+ vertices[indices[index + 2]]
				) / 3.0
				if centroid.distance_squared_to(center) <= radius_squared:
					count += 1
	return count


func _mode_result(settlement: Dictionary) -> Dictionary:
	var snapshot := get_validation_snapshot()
	var passed := str(settlement.get("status", "")) == "PASS" \
		and str(snapshot.get("status", "")) == "PASS"
	return {
		"status": "PASS" if passed else "FAIL",
		"settlement": settlement,
		"snapshot": snapshot,
	}


func _fail_action(message: String) -> Dictionary:
	_failure = message
	_busy = false
	_ready_passed = false
	return {"status": "FAIL", "error": message}


func _release_runtime() -> bool:
	var stopped := true
	if is_instance_valid(_harness) and is_instance_valid(_terrain):
		stopped = await _harness.stop_world()
		_harness.dispose()
		_harness.queue_free()
		await get_tree().process_frame
	_harness = null
	_terrain = null
	_metrics = {}
	return stopped


func _stop_preview() -> Dictionary:
	_busy = true
	var stopped := await _release_runtime()
	_ready_passed = false
	Harness.remove_tree(_session_root)
	_busy = false
	return {"status": "PASS" if stopped else "FAIL"}


func _apply_preview_enabled() -> void:
	if editor_preview_enabled:
		await _start_preview()
	else:
		await _stop_preview()


func _apply_selected_mode() -> void:
	var modes := ["edited", "replayed", "distant"]
	await set_inspection_mode(modes[int(editor_inspection_mode)])


func _connect_interface() -> void:
	%EditedButton.pressed.connect(set_inspection_mode.bind("edited"))
	%ReplayButton.pressed.connect(set_inspection_mode.bind("replayed"))
	%DistantButton.pressed.connect(set_inspection_mode.bind("distant"))
	%RestartButton.pressed.connect(restart_and_wait)


func _refresh_status() -> void:
	if not is_instance_valid(status_label):
		return
	status_label.text = "WORKING" if _busy else ("PASS  DURABLE STATE" if _ready_passed else "STARTING")
	if not _failure.is_empty():
		status_label.text = "FAIL  " + _failure
	mode_label.text = "MODE  " + _mode.to_upper()
	revision_label.text = "Source %d   world %d   pages %d" % [
		int(_terrain.call("get_world_source_revision")) if is_instance_valid(_terrain) else 0,
		int(_terrain.call("get_world_revision")) if is_instance_valid(_terrain) else 0,
		int(_terrain.call("get_world_page_count")) if is_instance_valid(_terrain) else 0,
	]
	pipeline_label.text = "Active %d   render %d\nQueued jobs %d   replacements %d" % [
		int(_metrics.get("active_chunk_records", 0)), int(_metrics.get("render_resources", 0)),
		int(_metrics.get("scheduler_queued_jobs", 0)), int(_metrics.get("pending_chunk_replacements", 0)),
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
		and int(metrics.get("pending_chunk_replacements", -1)) == 0 \
		and int(metrics.get("pending_chunk_retirements", -1)) == 0


static func _central_queries_valid(samples: Array[Dictionary]) -> bool:
	return samples.size() == 4 \
		and _sample_matches(samples[0], 5.0, 3, 2) \
		and _sample_matches(samples[1], -1.0, 3, 2) \
		and _sample_matches(samples[2], -4.0, 8, 2) \
		and _sample_matches(samples[3], 1.0, 6, 2)


static func _sample_matches(
	sample: Dictionary, density: float, material: int, revision: int
) -> bool:
	return str(sample.get("status", "")) == "PASS" \
		and is_equal_approx(float(sample.get("density", INF)), density) \
		and int(sample.get("material", -1)) == material \
		and int(sample.get("world_revision", -1)) == revision


static func _vector3(value: Variant) -> Vector3:
	var values: Array = value
	return Vector3(float(values[0]), float(values[1]), float(values[2])) \
		if values.size() == 3 else Vector3.ZERO


static func _vector3i(value: Variant) -> Vector3i:
	var values: Array = value
	return Vector3i(int(values[0]), int(values[1]), int(values[2])) \
		if values.size() == 3 else Vector3i.ZERO


static func _vector3i_array(value: Variant) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for point in value:
		result.append(_vector3i(point))
	return result
