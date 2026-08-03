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
	"res://addons/world_transvoxel_terrain_lab/standards/edit_invalidation_standard.json"
)
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/edit_invalidation_observatory"

enum Action {
	COARSE_PARENT,
	FINE_CHILD,
	BOUNDARY_HALO,
	MIXED_LOD,
	DISJOINT_BATCH,
	UNLOADED_NOOP,
	RAPID_SUPERSESSION,
}

@export_group("Editor Preview")
@export var editor_preview_enabled := true:
	set(value):
		editor_preview_enabled = value
		if is_inside_tree():
			call_deferred("_apply_preview_enabled")
@export var editor_action: Action = Action.MIXED_LOD
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
@export_group("")

@onready var camera: Camera3D = %Camera3D
@onready var diagnostics: MeshInstance3D = %Diagnostics
@onready var status_label: Label = %StatusLabel
@onready var action_label: Label = %ActionLabel
@onready var affected_label: Label = %AffectedLabel
@onready var pipeline_label: Label = %PipelineLabel

var _standard := {}
var _profile := {}
var _workload := {}
var _scenario_by_id := {}
var _harness: Node
var _terrain: Node
var _material: ShaderMaterial
var _session_root := ""
var _viewer_revision := 0
var _transaction_id := 361000
var _busy := false
var _world_started := false
var _current_action := "starting"
var _last_result := {}
var _metrics := {}
var _focus_request: Variant = null


func _ready() -> void:
	_standard = JsonLoader.load_dictionary(STANDARD_PATH)
	_profile = _standard.get("runtime_profile", {})
	_workload = _standard.get("workload", {})
	for scenario_value in _workload.get("scenarios", []):
		var scenario: Dictionary = scenario_value
		_scenario_by_id[str(scenario.get("id", ""))] = scenario
	var rapid: Dictionary = _workload.get("rapid_supersession", {})
	_scenario_by_id[str(rapid.get("id", "rapid_supersession"))] = rapid
	_session_root = RUNTIME_ROOT + "/%s_%d" % [
		"editor" if Engine.is_editor_hint() else "runtime",
		OS.get_process_id(),
	]
	_material = ShaderMaterial.new()
	_material.shader = TerrainShader
	_connect_interface()
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
	if _busy or not _world_started:
		return {"status": "FAIL", "error": "native edit observatory is busy or unavailable"}
	if action_id == "rapid_supersession":
		return await _run_rapid(_scenario_by_id.get(action_id, {}))
	if not _scenario_by_id.has(action_id):
		return {"status": "FAIL", "error": "unknown edit action: " + action_id}
	return await _run_edit(_scenario_by_id[action_id])


func restart_and_wait() -> Dictionary:
	if _busy:
		return {"status": "FAIL", "error": "native edit observatory is busy"}
	await _stop_preview()
	await _start_preview()
	return await wait_until_ready()


func get_validation_snapshot() -> Dictionary:
	var overlap_count := _collision_overlap_count()
	return {
		"schema": "world_transvoxel.terrain_lab.edit_invalidation_observatory_snapshot.v1",
		"status": "PASS" if _world_started and overlap_count == 0
			and str(_last_result.get("status", "PASS")) == "PASS" else "FAIL",
		"action": _current_action,
		"backend_id": str(_terrain.call("get_backend_id")) if is_instance_valid(_terrain) else "",
		"backend_license": str(_terrain.call("get_backend_license")) if is_instance_valid(_terrain) else "",
		"collision_overlap_count": overlap_count,
		"result": _last_result.duplicate(true),
		"metrics": _metrics.duplicate(true),
	}


func prepare_reference_capture(action_id: String = "mixed_lod_transition_dependency") -> void:
	var targets := {
		"coarse_parent_interior": Vector3(80, 40, 40),
		"fine_child_interior": Vector3(120, 40, 40),
		"same_lod_boundary_halo": Vector3(128, 40, 40),
		"mixed_lod_transition_dependency": Vector3(96, 40, 40),
		"disjoint_batch_union": Vector3(128, 40, 64),
		"rapid_supersession": Vector3(96, 40, 40),
	}
	var target: Vector3 = targets.get(action_id, Vector3(112, 40, 56))
	camera.position = target + Vector3(72, 55, 96)
	camera.look_at(target, Vector3.UP)
	_focus_request = {"position": camera.position, "target": target}


func shutdown_for_validation() -> Dictionary:
	return await _stop_preview()


func _start_preview() -> void:
	if _busy or _world_started or not editor_preview_enabled:
		return
	_busy = true
	_current_action = "starting"
	status_label.text = "STARTING"
	Harness.remove_tree(_session_root)
	_harness = Harness.new()
	_harness.name = "NativeTqp36Runtime"
	add_child(_harness)
	var capacity := int(_profile.get("pipeline_capacity", 2048))
	var overrides := {
		"active_chunk_capacity": int(_profile.get("active_chunk_capacity", 512)),
		"demand_capacity_per_viewer": capacity,
		"lod_refinement_radius_chunks": int(_profile.get("lod_refinement_radius_chunks", 1)),
		"storage_request_capacity": capacity,
		"storage_completion_capacity": capacity,
		"encoded_page_entry_capacity": capacity,
		"decoded_page_entry_capacity": capacity,
		"mesh_entry_capacity": capacity,
		"render_entry_capacity": capacity,
		"collision_entry_capacity": capacity,
		"render_transition_frames": int(_profile.get("render_transition_frames", 0)),
		"shader_fade_parameter_enabled": false,
		"global_coarse_lod_coverage": false,
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
	_viewer_revision = 1
	var accepted := bool(_terrain.call(
		"update_viewer",
		int(_profile.get("viewer_id", 36)),
		_viewer_revision,
		_vector3(_profile.get("viewer_position", [])),
		int(_profile.get("viewer_radius_chunks", 1)),
		int(_profile.get("maximum_lod", 1))
	))
	_busy = false
	if not accepted or not await _wait_for_settlement():
		_fail("initial native edit layout did not settle")
		return
	_current_action = "ready"
	_last_result = {"status": "PASS", "expected_ids": [], "changed_ids": []}
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
	diagnostics.mesh = null
	Harness.remove_tree(_session_root)
	status_label.text = "STOPPED" if stopped else "FAIL: shutdown"
	return {"status": "PASS" if stopped else "FAIL"}


func _run_edit(scenario: Dictionary) -> Dictionary:
	_busy = true
	_current_action = str(scenario.get("id", "unnamed"))
	var commands: Array = scenario.get("commands", [])
	var before := _active_state()
	var expected := _expected_ids(before, commands)
	var before_metrics := _terrain.call("get_runtime_metrics") as Dictionary
	var accepted := _submit_transaction(commands)
	var settled := accepted and await _wait_for_edit(
		before, expected, int(before_metrics.get("edit_completed_transactions", 0)) + 1
	)
	var after := _active_state()
	var changed := _changed_ids(before, after)
	var result := {
		"status": "PASS" if settled and changed == expected else "FAIL",
		"id": _current_action,
		"expected_ids": expected,
		"changed_ids": changed,
		"unaffected_count": before.size() - expected.size(),
		"empty_transaction": expected.is_empty(),
	}
	_last_result = result
	_draw_diagnostics(commands, before, expected, changed)
	_busy = false
	prepare_reference_capture(_current_action)
	return result


func _run_rapid(scenario: Dictionary) -> Dictionary:
	_busy = true
	_current_action = "rapid_supersession"
	var commands: Array = scenario.get("commands", [])
	var before := _active_state()
	var expected := _expected_ids(before, commands)
	var before_metrics := _terrain.call("get_runtime_metrics") as Dictionary
	_terrain.call("set_render_apply_budget", 0)
	_terrain.call("set_collision_apply_budget", 0)
	var first := _submit_transaction(commands)
	var first_complete := first and await _wait_for_metric(
		"edit_completed_transactions",
		int(before_metrics.get("edit_completed_transactions", 0)) + 1
	)
	for _frame in range(12):
		await get_tree().process_frame
	var second := first_complete and _submit_transaction(commands)
	var second_complete := second and await _wait_for_metric(
		"edit_completed_transactions",
		int(before_metrics.get("edit_completed_transactions", 0)) + 2
	)
	_terrain.call("set_render_apply_budget", 2)
	_terrain.call("set_collision_apply_budget", 2)
	var settled := second_complete and await _wait_for_edit(
		before, expected, int(before_metrics.get("edit_completed_transactions", 0)) + 2
	)
	var after := _active_state()
	var changed := _changed_ids(before, after)
	var after_metrics := _terrain.call("get_runtime_metrics") as Dictionary
	var stale := _stale_rejections(after_metrics) - _stale_rejections(before_metrics)
	var result := {
		"status": "PASS" if settled and changed == expected and stale > 0 else "FAIL",
		"id": _current_action,
		"expected_ids": expected,
		"changed_ids": changed,
		"unaffected_count": before.size() - expected.size(),
		"stale_rejections_delta": stale,
	}
	_last_result = result
	_draw_diagnostics(commands, before, expected, changed)
	_busy = false
	prepare_reference_capture(_current_action)
	return result


func _submit_transaction(commands: Array) -> bool:
	_transaction_id += 1
	var transaction: RefCounted = _terrain.call("begin_edit_transaction", _transaction_id)
	if transaction == null:
		return false
	for command_value in commands:
		var command: Dictionary = command_value
		var accepted := false
		if str(command.get("shape", "")) == "sphere":
			accepted = bool(transaction.call(
				"add_density_sphere", _vector3(command.get("center", [])),
				float(command.get("radius", 0.0)), float(command.get("density_delta", 0.0))
			))
		else:
			accepted = bool(transaction.call(
				"add_density_box", _vector3(command.get("minimum", [])),
				_vector3(command.get("maximum", [])), float(command.get("density_delta", 0.0))
			))
		if not accepted:
			return false
	return bool(_terrain.call("commit_edit_transaction", transaction))


func _wait_for_edit(before: Dictionary, expected: Array[String], minimum_completed: int) -> bool:
	for frame in range(Harness.MAX_WAIT_FRAMES):
		var state := _active_state()
		var metrics := _terrain.call("get_runtime_metrics") as Dictionary
		var advanced := _changed_ids(before, state) == expected
		if int(metrics.get("edit_completed_transactions", 0)) >= minimum_completed \
				and advanced and _is_settled(metrics):
			return true
		await get_tree().process_frame
		if frame % 8 == 0:
			await get_tree().create_timer(0.001).timeout
	return false


func _wait_for_settlement() -> bool:
	for frame in range(Harness.MAX_WAIT_FRAMES):
		_metrics = _terrain.call("get_runtime_metrics")
		if _is_settled(_metrics):
			return true
		await get_tree().process_frame
		if frame % 8 == 0:
			await get_tree().create_timer(0.001).timeout
	return false


func _wait_for_metric(metric: String, minimum: int) -> bool:
	for frame in range(900):
		if int((_terrain.call("get_runtime_metrics") as Dictionary).get(metric, 0)) >= minimum:
			return true
		await get_tree().process_frame
		if frame % 8 == 0:
			await get_tree().create_timer(0.001).timeout
	return false


func _is_settled(metrics: Dictionary) -> bool:
	var active := int(metrics.get("active_chunk_records", 0))
	return active > 0 \
		and int(metrics.get("non_retiring_fully_ready_chunk_records", -1)) \
			== int(metrics.get("non_retiring_chunk_records", active)) \
		and int(metrics.get("scheduler_queued_jobs", -1)) == 0 \
		and int(metrics.get("scheduler_queued_completions", -1)) == 0 \
		and int(metrics.get("storage_queued_requests", -1)) == 0 \
		and int(metrics.get("storage_queued_completions", -1)) == 0 \
		and int(metrics.get("storage_active_requests", -1)) == 0 \
		and int(metrics.get("page_loading_records", -1)) == 0 \
		and int(metrics.get("queued_render", -1)) == 0 \
		and int(metrics.get("queued_collision", -1)) == 0 \
		and int(metrics.get("pending_chunk_replacements", -1)) == 0 \
		and int(metrics.get("pending_chunk_retirements", -1)) == 0 \
		and int(metrics.get("staged_render_resources", -1)) == 0 \
		and int(metrics.get("staged_collision_resources", -1)) == 0


func _active_state() -> Dictionary:
	var output := {}
	for state_value in _terrain.call("query_active_chunk_states"):
		var state := state_value as RefCounted
		var coordinate: Vector3i = state.call("get_chunk_coordinate")
		var lod := int(state.call("get_lod"))
		var id := "%d,%d,%d,L%d" % [coordinate.x, coordinate.y, coordinate.z, lod]
		output[id] = {
			"coordinate": coordinate,
			"lod": lod,
			"generation": int(state.call("get_generation")),
		}
	return output


func _expected_ids(state: Dictionary, commands: Array) -> Array[String]:
	var expected := {}
	for command in commands:
		var bounds := _command_bounds(command)
		for id in state:
			var row: Dictionary = state[id]
			var lod := int(row.get("lod", 0))
			var spacing := 1 << lod
			var extent := 16 * spacing
			var coordinate: Vector3i = row.get("coordinate", Vector3i.ZERO)
			var minimum := coordinate * extent - Vector3i.ONE * spacing
			var maximum := coordinate * extent + Vector3i.ONE * (extent + spacing)
			if _intersects(bounds[0], bounds[1], minimum, maximum):
				expected[id] = true
	var output: Array[String] = []
	for id in expected:
		output.append(str(id))
	output.sort()
	return output


func _changed_ids(before: Dictionary, after: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for id in before:
		if after.has(id) and int((after[id] as Dictionary).get("generation", 0)) \
				!= int((before[id] as Dictionary).get("generation", 0)):
			output.append(str(id))
	output.sort()
	return output


func _draw_diagnostics(
	commands: Array,
	state: Dictionary,
	expected: Array[String],
	changed: Array[String]
) -> void:
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	for command in commands:
		var bounds := _command_bounds(command)
		immediate.surface_set_color(Color(1.0, 0.22, 0.13, 1.0))
		_add_box_lines(immediate, Vector3(bounds[0]), Vector3(bounds[1]))
	for id in expected:
		var row: Dictionary = state[id]
		var lod := int(row.get("lod", 0))
		var extent := 16.0 * float(1 << lod)
		var origin := Vector3(row.get("coordinate", Vector3i.ZERO)) * extent
		immediate.surface_set_color(
			Color(0.2, 1.0, 0.54, 1.0) if id in changed else Color(1.0, 0.82, 0.14, 1.0)
		)
		_add_box_lines(immediate, origin, origin + Vector3.ONE * extent)
	immediate.surface_end()
	diagnostics.mesh = immediate


func _refresh_status() -> void:
	status_label.text = "APPLYING" if _busy else "SETTLED"
	status_label.modulate = Color(0.96, 0.72, 0.24) if _busy else Color(0.35, 0.9, 0.65)
	action_label.text = _current_action
	var expected: Array = _last_result.get("expected_ids", [])
	var changed: Array = _last_result.get("changed_ids", [])
	affected_label.text = "Expected %d   changed %d   stable %d\n%s" % [
		expected.size(), changed.size(), int(_last_result.get("unaffected_count", 0)),
		"EXACT" if expected == changed else "MISMATCH",
	]
	pipeline_label.text = "Transactions %d   empty %d\nReplaced %d   cancelled %d\nStale resources %d" % [
		int(_metrics.get("edit_completed_transactions", 0)),
		int(_metrics.get("edit_empty_transactions", 0)),
		int(_metrics.get("edit_replaced_chunks", 0)),
		int(_metrics.get("edit_cancelled_page_meshing_generations", 0)),
		_stale_rejections(_metrics),
	]


func _collision_overlap_count() -> int:
	var bounds: Array[AABB] = []
	if not is_instance_valid(_terrain):
		return 0
	for child in _terrain.get_children():
		if not child is StaticBody3D or not str(child.name).begins_with("WT_Collision_"):
			continue
		var parts := str(child.name).trim_prefix("WT_Collision_").split("_")
		if parts.size() != 4:
			continue
		var lod := int(parts[3].trim_prefix("L"))
		var extent := 16.0 * float(1 << lod)
		bounds.append(AABB(Vector3(float(parts[0]), float(parts[1]), float(parts[2])) * extent, Vector3.ONE * extent))
	var overlaps := 0
	for first in range(bounds.size()):
		for second in range(first + 1, bounds.size()):
			var overlap := bounds[first].intersection(bounds[second])
			if overlap.size.x > 0.0001 and overlap.size.y > 0.0001 and overlap.size.z > 0.0001:
				overlaps += 1
	return overlaps


func _apply_selected_action() -> void:
	var ids := [
		"coarse_parent_interior", "fine_child_interior", "same_lod_boundary_halo",
		"mixed_lod_transition_dependency", "disjoint_batch_union", "unloaded_noop",
		"rapid_supersession",
	]
	await run_action_and_wait(ids[int(editor_action)])


func _connect_interface() -> void:
	%CoarseButton.pressed.connect(run_action_and_wait.bind("coarse_parent_interior"))
	%FineButton.pressed.connect(run_action_and_wait.bind("fine_child_interior"))
	%BoundaryButton.pressed.connect(run_action_and_wait.bind("same_lod_boundary_halo"))
	%MixedButton.pressed.connect(run_action_and_wait.bind("mixed_lod_transition_dependency"))
	%BatchButton.pressed.connect(run_action_and_wait.bind("disjoint_batch_union"))
	%NoopButton.pressed.connect(run_action_and_wait.bind("unloaded_noop"))
	%RapidButton.pressed.connect(run_action_and_wait.bind("rapid_supersession"))
	%RestartButton.pressed.connect(restart_and_wait)


func _apply_preview_enabled() -> void:
	if editor_preview_enabled:
		await _start_preview()
	else:
		await _stop_preview()


func _restart_preview() -> void:
	await restart_and_wait()


func _fail(message: String) -> void:
	_busy = false
	_world_started = false
	status_label.text = "FAIL: " + message


static func _command_bounds(command_value: Variant) -> Array[Vector3i]:
	var command: Dictionary = command_value
	if str(command.get("shape", "")) == "sphere":
		var center := _vector3(command.get("center", []))
		var radius := float(command.get("radius", 0.0))
		return [
			Vector3i(floori(center.x - radius), floori(center.y - radius), floori(center.z - radius)),
			Vector3i(ceili(center.x + radius), ceili(center.y + radius), ceili(center.z + radius)),
		]
	var minimum := _vector3(command.get("minimum", []))
	var maximum := _vector3(command.get("maximum", []))
	return [
		Vector3i(floori(minimum.x), floori(minimum.y), floori(minimum.z)),
		Vector3i(ceili(maximum.x), ceili(maximum.y), ceili(maximum.z)),
	]


static func _intersects(
	left_minimum: Vector3i,
	left_maximum: Vector3i,
	right_minimum: Vector3i,
	right_maximum: Vector3i
) -> bool:
	return left_maximum.x >= right_minimum.x and left_minimum.x <= right_maximum.x \
		and left_maximum.y >= right_minimum.y and left_minimum.y <= right_maximum.y \
		and left_maximum.z >= right_minimum.z and left_minimum.z <= right_maximum.z


static func _vector3(value: Variant) -> Vector3:
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


static func _stale_rejections(metrics: Dictionary) -> int:
	return int(metrics.get("application_stale_render", 0)) \
		+ int(metrics.get("application_stale_collision", 0)) \
		+ int(metrics.get("page_stale_storage_completions", 0))


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
