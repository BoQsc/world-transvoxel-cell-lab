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
	"res://addons/world_transvoxel_terrain_lab/standards/adaptive_edit_standard.json"
)
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/adaptive_edit_observatory"

enum Action {
	TRANSITION_CARVE,
	CORNER_CONSTRUCTION,
	REPEATED_TUNNEL,
	UNDER_RESOLVED_COARSE,
	UNDER_RESOLVED_REFINED,
	UNLOADED_EDIT,
	HISTORY_REPLAY,
}

@export_group("Editor Preview")
@export var editor_preview_enabled := true:
	set(value):
		editor_preview_enabled = value
		if is_inside_tree():
			call_deferred("_apply_preview_enabled")
@export var editor_action: Action = Action.TRANSITION_CARVE
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
var _scenario_by_id := {}
var _harness: Node
var _terrain: Node
var _material: ShaderMaterial
var _session_root := ""
var _viewer_revision := 0
var _transaction_id := 370000
var _busy := false
var _world_started := false
var _current_action := "starting"
var _current_scenario := {}
var _last_result := {}
var _metrics := {}
var _focus_request: Variant = null


func _ready() -> void:
	_standard = JsonLoader.load_dictionary(STANDARD_PATH)
	_profile = _standard.get("runtime_profile", {})
	for scenario_value in (_standard.get("workload", {}) as Dictionary).get("scenarios", []):
		var scenario: Dictionary = scenario_value
		_scenario_by_id[str(scenario.get("id", ""))] = scenario
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
		if _world_started and not _busy and _is_settled(_metrics):
			return {"status": "PASS", "frames": frame, "snapshot": get_validation_snapshot()}
		if status_label.text.begins_with("FAIL"):
			return {"status": "FAIL", "frames": frame, "snapshot": get_validation_snapshot()}
		await get_tree().process_frame
	return {"status": "FAIL", "frames": maximum_frames, "snapshot": get_validation_snapshot()}


func run_action_and_wait(action_id: String) -> Dictionary:
	if _busy:
		return {"status": "FAIL", "error": "adaptive edit observatory is busy"}
	var scenario_id := _scenario_for_action(action_id)
	if not _scenario_by_id.has(scenario_id):
		return {"status": "FAIL", "error": "unknown adaptive edit action: " + action_id}
	_busy = true
	_current_action = action_id
	var scenario: Dictionary = _scenario_by_id[scenario_id]
	var started := await _start_scenario(scenario, action_id)
	if not started:
		return _finish_failed_action("native scenario could not start")
	var before_metrics := _terrain.call("get_runtime_metrics") as Dictionary
	var committed := await _commit_transactions(scenario.get("transactions", []))
	if not committed:
		return _finish_failed_action("native edit transaction failed")
	if action_id in ["under_resolved_refined", "unloaded_edit_then_load"]:
		_viewer_revision += 1
		var settlement := await _move_viewer_and_settle(
			_vector3(scenario.get("center", []))
		)
		if not settlement:
			return _finish_failed_action("refined or loaded view did not settle")
	var center := Vector3(_vector3i(scenario.get("center", [])))
	var local_triangles := _triangle_near_count(center, 6.0)
	var after_metrics := _terrain.call("get_runtime_metrics") as Dictionary
	var expected_visible := action_id != "under_resolved_coarse"
	var visibility_ok := local_triangles > 0 if expected_visible else local_triangles == 0
	var active_records := int(after_metrics.get("active_chunk_records", 0))
	var collision_required := int(
		after_metrics.get("collision_required_chunk_records", 0)
	)
	var bounded_collision_profile := float(
		_profile.get("collision_activation_distance", 0.0)
	) > 0.0 and float(_profile.get("collision_deactivation_distance", 0.0)) \
		> float(_profile.get("collision_activation_distance", 0.0))
	_last_result = {
		"status": "PASS" if visibility_ok and bounded_collision_profile else "FAIL",
		"action": action_id,
		"scenario": scenario_id,
		"local_triangle_count": local_triangles,
		"classification": "under_resolved_authoritative_field"
			if action_id == "under_resolved_coarse" else "resolved_native_surface",
		"edit_commits_delta": int(after_metrics.get("edit_commits", 0))
			- int(before_metrics.get("edit_commits", 0)),
		"edit_replacements_delta": int(after_metrics.get("edit_replacements", 0))
			- int(before_metrics.get("edit_replacements", 0)),
		"edit_lod_retention_zones": int(
			after_metrics.get("edit_lod_retention_zones", 0)
		),
		"bounded_collision_profile": bounded_collision_profile,
		"collision_requirement_scope": "fixture_fully_inside_radius"
			if collision_required == active_records else "distance_targeted_subset",
	}
	_draw_diagnostics(scenario)
	prepare_reference_capture(action_id)
	_busy = false
	return _last_result.duplicate(true)


func restart_and_wait() -> Dictionary:
	if _busy:
		return {"status": "FAIL", "error": "adaptive edit observatory is busy"}
	await _stop_preview()
	await _start_preview()
	return await wait_until_ready()


func get_validation_snapshot() -> Dictionary:
	var overlap_count := _collision_overlap_count()
	return {
		"schema": "world_transvoxel.terrain_lab.adaptive_edit_observatory_snapshot.v1",
		"status": "PASS" if _world_started and overlap_count == 0
			and str(_last_result.get("status", "PASS")) == "PASS"
			else "FAIL",
		"action": _current_action,
		"backend_id": str(_terrain.call("get_backend_id")) if is_instance_valid(_terrain) else "",
		"backend_license": str(_terrain.call("get_backend_license")) if is_instance_valid(_terrain) else "",
		"collision_overlap_count": overlap_count,
		"collision_profile": {
			"activation_distance": float(
				_profile.get("collision_activation_distance", 0.0)
			),
			"deactivation_distance": float(
				_profile.get("collision_deactivation_distance", 0.0)
			),
			"production_policy_qualification": "UNQUALIFIED_OWNED_BY_LATER_TQP",
		},
		"result": _last_result.duplicate(true),
		"metrics": _metrics.duplicate(true),
	}


func prepare_reference_capture(action_id: String = "transition_face_carve") -> void:
	var scenario_id := _scenario_for_action(action_id)
	var scenario: Dictionary = _scenario_by_id.get(scenario_id, _current_scenario)
	var target := Vector3(_vector3i(scenario.get("center", [96, 20, 48])))
	var offset := Vector3(58, 42, 74)
	if action_id == "chunk_edge_corner_construction":
		offset = Vector3(66, 52, 66)
	elif action_id.begins_with("under_resolved"):
		offset = Vector3(5.5, 3.5, 6.0)
	camera.position = target + offset
	camera.look_at(target, Vector3.UP)
	_focus_request = {"position": camera.position, "target": target}


func shutdown_for_validation() -> Dictionary:
	return await _stop_preview()


func _start_preview() -> void:
	if _busy or _world_started or not editor_preview_enabled:
		return
	_busy = true
	_current_action = "baseline"
	var scenario: Dictionary = _scenario_by_id.get("transition_face_carve", {})
	if not await _start_scenario(scenario, "baseline"):
		_finish_failed_action("native baseline could not start")
		return
	_last_result = {"status": "PASS", "action": "baseline", "local_triangle_count": 0}
	_draw_diagnostics(scenario)
	prepare_reference_capture()
	_busy = false


func _start_scenario(scenario: Dictionary, action_id: String) -> bool:
	await _release_runtime()
	var root := _session_root.path_join(action_id)
	Harness.remove_tree(root)
	_harness = Harness.new()
	_harness.name = "NativeTqp37Runtime"
	add_child(_harness)
	if not _harness.create_runtime(
		int(_profile.get("worker_count", 2)), _runtime_overrides()
	):
		return false
	_terrain = _harness.terrain
	_terrain.call("set_render_material_override", _material)
	var volume: Array = _profile.get("volume_chunks", [])
	var started: bool = volume.size() == 3 and await _harness.start_procedural_world_preset(
		root.path_join("source"),
		int(_profile.get("source_revision", 937001)),
		int(_profile.get("seed", 370037)),
		str(_profile.get("preset", "rolling_hills_cave")),
		int(volume[0]), int(volume[1]),
		int(_profile.get("vertical_chunk_origin", -2)), int(volume[2])
	)
	if not started:
		return false
	_current_scenario = scenario
	_world_started = true
	_viewer_revision = 1
	var before := _terrain.call("get_runtime_metrics") as Dictionary
	if not _update_viewer(_vector3(scenario.get("viewer_position", []))):
		return false
	return await _wait_for_settlement(
		int(before.get("viewer_updates", 0)) + 1,
		int(before.get("planned_demands", 0)) + 1
	)


func _stop_preview() -> Dictionary:
	_busy = true
	var stopped := await _release_runtime()
	_metrics = {}
	diagnostics.mesh = null
	Harness.remove_tree(_session_root)
	status_label.text = "STOPPED" if stopped else "FAIL: shutdown"
	_busy = false
	return {"status": "PASS" if stopped else "FAIL"}


func _release_runtime() -> bool:
	var stopped := true
	if is_instance_valid(_harness) and is_instance_valid(_terrain):
		stopped = await _harness.stop_world()
		_harness.dispose()
		_harness.queue_free()
	_harness = null
	_terrain = null
	_world_started = false
	return stopped


func _runtime_overrides() -> Dictionary:
	var capacity := int(_profile.get("pipeline_capacity", 2048))
	return {
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
		"collision_activation_distance": float(
			_profile.get("collision_activation_distance", 48.0)
		),
		"collision_deactivation_distance": float(
			_profile.get("collision_deactivation_distance", 64.0)
		),
	}


func _commit_transactions(transactions: Array) -> bool:
	var expected_revision := int(_terrain.call("get_world_revision"))
	for transaction_value in transactions:
		_transaction_id += 1
		var transaction: RefCounted = _terrain.call(
			"begin_edit_transaction", _transaction_id
		)
		if transaction == null:
			return false
		for operation_value in transaction_value:
			if not _append_operation(transaction, operation_value):
				return false
		if not bool(_terrain.call("commit_edit_transaction", transaction)):
			return false
		expected_revision += 1
		if not await _harness.wait_for_commit(expected_revision):
			return false
		if not await _wait_for_settlement():
			return false
	return true


func _append_operation(transaction: RefCounted, value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var operation: Dictionary = value
	var method := str(operation.get("operation", ""))
	var center := _vector3(operation.get("center", []))
	var radius := float(operation.get("radius", 0.0))
	var strength := float(operation.get("strength", 0.0))
	match method:
		"carve_sdf_sphere", "construct_sdf_sphere":
			return bool(transaction.call(method, center, radius, strength))
		"carve_smooth_sdf_sphere", "construct_smooth_sdf_sphere":
			return bool(transaction.call(
				method, center, radius, strength,
				float(operation.get("smooth_radius", 0.0))
			))
		"construct_material_sdf_sphere":
			return bool(transaction.call(
				method, center, radius, strength,
				int(operation.get("material", 0))
			))
		"construct_material_smooth_sdf_sphere":
			return bool(transaction.call(
				method, center, radius, strength,
				int(operation.get("material", 0)),
				float(operation.get("smooth_radius", 0.0))
			))
	return false


func _move_viewer_and_settle(position: Vector3) -> bool:
	var before := _terrain.call("get_runtime_metrics") as Dictionary
	if not _update_viewer(position):
		return false
	return await _wait_for_settlement(
		int(before.get("viewer_updates", 0)) + 1,
		int(before.get("planned_demands", 0)) + 1
	)


func _update_viewer(position: Vector3) -> bool:
	return bool(_terrain.call(
		"update_viewer",
		int(_profile.get("viewer_id", 37)),
		_viewer_revision,
		position,
		int(_profile.get("viewer_radius_chunks", 1)),
		int(_profile.get("maximum_lod", 1))
	))


func _wait_for_settlement(
	minimum_viewer_updates: int = 0,
	minimum_planned_demands: int = 0
) -> bool:
	for frame in range(Harness.MAX_WAIT_FRAMES):
		_metrics = _terrain.call("get_runtime_metrics")
		if int(_metrics.get("viewer_updates", 0)) >= minimum_viewer_updates \
				and int(_metrics.get("planned_demands", 0)) >= minimum_planned_demands \
				and _is_settled(_metrics):
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


func _triangle_near_count(center: Vector3, radius: float) -> int:
	var count := 0
	if not is_instance_valid(_terrain):
		return count
	var radius_squared := radius * radius
	for child in _terrain.get_children():
		if not child is MeshInstance3D or not str(child.name).begins_with("WT_Render_"):
			continue
		var mesh := (child as MeshInstance3D).mesh as ArrayMesh
		if mesh == null:
			continue
		for surface in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for index in range(0, indices.size(), 3):
				var centroid: Vector3 = child.position + (
					vertices[indices[index]] + vertices[indices[index + 1]]
					+ vertices[indices[index + 2]]
				) / 3.0
				if centroid.distance_squared_to(center) <= radius_squared:
					count += 1
	return count


func _draw_diagnostics(scenario: Dictionary) -> void:
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	for transaction_value in scenario.get("transactions", []):
		for operation_value in transaction_value:
			var operation: Dictionary = operation_value
			var center := _vector3(operation.get("center", []))
			var radius := float(operation.get("radius", 0.0))
			immediate.surface_set_color(Color(1.0, 0.25, 0.16, 1.0))
			_add_box_lines(
				immediate, center - Vector3.ONE * radius,
				center + Vector3.ONE * radius
			)
	for interface_value in scenario.get("interface_planes", []):
		var interface: Dictionary = interface_value
		immediate.surface_set_color(Color(0.16, 0.9, 1.0, 1.0))
		_add_interface_lines(immediate, interface)
	immediate.surface_end()
	diagnostics.mesh = immediate


func _refresh_status() -> void:
	if not is_instance_valid(status_label):
		return
	status_label.text = "APPLYING" if _busy else ("SETTLED" if _world_started else "STOPPED")
	status_label.modulate = Color(0.96, 0.72, 0.24) if _busy else Color(0.35, 0.9, 0.65)
	action_label.text = _current_action
	var local_triangles := int(_last_result.get("local_triangle_count", 0))
	affected_label.text = "Field authoritative   local triangles %d\n%s" % [
		local_triangles,
		str(_last_result.get("classification", "native baseline")),
	]
	pipeline_label.text = "Active %d   render %d   collision %d\nCollision required %d   queued %d\nRetention zones %d" % [
		int(_metrics.get("active_chunk_records", 0)),
		int(_metrics.get("render_resources", 0)),
		int(_metrics.get("collision_resources", 0)),
		int(_metrics.get("collision_required_chunk_records", 0)),
		int(_metrics.get("queued_collision", 0)),
		int(_metrics.get("edit_lod_retention_zones", 0)),
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
		bounds.append(AABB(
			Vector3(float(parts[0]), float(parts[1]), float(parts[2])) * extent,
			Vector3.ONE * extent
		))
	var overlaps := 0
	for first in range(bounds.size()):
		for second in range(first + 1, bounds.size()):
			var overlap := bounds[first].intersection(bounds[second])
			if overlap.size.x > 0.0001 and overlap.size.y > 0.0001 \
					and overlap.size.z > 0.0001:
				overlaps += 1
	return overlaps


func _apply_selected_action() -> void:
	var ids := [
		"transition_face_carve", "chunk_edge_corner_construction",
		"repeated_transition_tunnel", "under_resolved_coarse",
		"under_resolved_refined", "unloaded_edit_then_load",
		"reconstructive_undo_redo",
	]
	await run_action_and_wait(ids[int(editor_action)])


func _connect_interface() -> void:
	%CoarseButton.pressed.connect(run_action_and_wait.bind("transition_face_carve"))
	%FineButton.pressed.connect(run_action_and_wait.bind("chunk_edge_corner_construction"))
	%BoundaryButton.pressed.connect(run_action_and_wait.bind("repeated_transition_tunnel"))
	%MixedButton.pressed.connect(run_action_and_wait.bind("under_resolved_coarse"))
	%BatchButton.pressed.connect(run_action_and_wait.bind("under_resolved_refined"))
	%NoopButton.pressed.connect(run_action_and_wait.bind("unloaded_edit_then_load"))
	%RapidButton.pressed.connect(run_action_and_wait.bind("reconstructive_undo_redo"))
	%RestartButton.pressed.connect(restart_and_wait)


func _apply_preview_enabled() -> void:
	if editor_preview_enabled:
		await _start_preview()
	else:
		await _stop_preview()


func _restart_preview() -> void:
	await restart_and_wait()


func _finish_failed_action(message: String) -> Dictionary:
	_busy = false
	_last_result = {"status": "FAIL", "error": message, "action": _current_action}
	status_label.text = "FAIL: " + message
	return _last_result.duplicate(true)


func _scenario_for_action(action_id: String) -> String:
	match action_id:
		"under_resolved_coarse", "under_resolved_refined":
			return "under_resolved_later_refinement"
	return action_id


static func _vector3(value: Variant) -> Vector3:
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


static func _vector3i(value: Variant) -> Vector3i:
	if value is Array and value.size() == 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i.ZERO


static func _add_box_lines(
	immediate: ImmediateMesh,
	minimum: Vector3,
	maximum: Vector3
) -> void:
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


static func _add_interface_lines(
	immediate: ImmediateMesh,
	interface: Dictionary
) -> void:
	var axis := int(interface.get("axis", 0))
	var coordinate := float(interface.get("coordinate", 0.0))
	var center := Vector3(96, 32, 64)
	center[axis] = coordinate
	var first_axis := (axis + 1) % 3
	var second_axis := (axis + 2) % 3
	var corners: Array[Vector3] = []
	for first in [-24.0, 24.0]:
		for second in [-24.0, 24.0]:
			var point := center
			point[first_axis] += first
			point[second_axis] += second
			corners.append(point)
	for edge in [[0, 1], [1, 3], [3, 2], [2, 0]]:
		immediate.surface_add_vertex(corners[edge[0]])
		immediate.surface_add_vertex(corners[edge[1]])
