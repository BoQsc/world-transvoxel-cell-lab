@tool
extends Node
class_name WtTerrainLabNativeRuntimeHarness

const MAX_WAIT_FRAMES := 1800

var terrain: Node
var sample_results := {}
var sample_failures := {}
var snapshot_results := {}
var snapshot_failures := {}
var committed_revisions: Array[int] = []
var edit_failures: Array[String] = []


func create_runtime(
	worker_count: int = 2,
	configuration_overrides: Dictionary = {}
) -> bool:
	if not ClassDB.class_exists("WorldTransvoxelConfig") \
			or not ClassDB.class_exists("WorldTransvoxelTerrain") \
			or not ClassDB.class_exists("WorldTransvoxelEditTransaction") \
			or not ClassDB.class_exists("WorldTransvoxelSample"):
		return false
	var config: Resource = ClassDB.instantiate("WorldTransvoxelConfig")
	var instance: Variant = ClassDB.instantiate("WorldTransvoxelTerrain")
	if config == null or not instance is Node:
		return false
	terrain = instance as Node
	var configuration_values := {
		"active_chunk_capacity": 128,
		"viewer_capacity": 4,
		"demand_capacity_per_viewer": 512,
		"lod_refinement_radius_chunks": 1,
		"procedural_generation_worker_count": worker_count,
		"storage_request_capacity": 128,
		"storage_completion_capacity": 128,
		"encoded_page_entry_capacity": 128,
		"decoded_page_entry_capacity": 128,
		"mesh_entry_capacity": 128,
		"render_entry_capacity": 128,
		"collision_entry_capacity": 128,
		"trace_event_capacity": 65536,
		"render_apply_budget": 2,
		"collision_apply_budget": 2,
		"collision_apply_deadline_us": 12000,
		"collision_activation_distance": 256.0,
		"collision_deactivation_distance": 320.0,
		"render_transition_frames": 0,
		"shader_fade_parameter_enabled": false,
		"global_coarse_lod_coverage": false,
	}
	for property_name in configuration_overrides:
		if not configuration_values.has(property_name):
			return false
		configuration_values[property_name] = configuration_overrides[property_name]
	for property_name in configuration_values:
		config.set(property_name, configuration_values[property_name])
	if not bool(config.call("is_valid")):
		return false
	add_child(terrain)
	terrain.set("configuration", config)
	terrain.connect("authoritative_sample_ready", _on_sample_ready)
	terrain.connect("authoritative_sample_failed", _on_sample_failed)
	terrain.connect("world_snapshot_ready", _on_snapshot_ready)
	terrain.connect("world_snapshot_failed", _on_snapshot_failed)
	terrain.connect("edit_committed", _on_edit_committed)
	terrain.connect("edit_failed", _on_edit_failed)
	return true


func start_flat_world(
	object_root: String,
	source_revision: int,
	chunk_count_x: int = 8,
	chunk_count_y: int = 4,
	chunk_origin_y: int = -2,
	chunk_count_z: int = 8
) -> bool:
	if terrain == null:
		return false
	ensure_directory(object_root)
	if not bool(terrain.call(
		"start_flat_world_with_vertical_origin",
		chunk_count_x,
		chunk_count_y,
		chunk_origin_y,
		chunk_count_z,
		source_revision,
		object_root
	)):
		return false
	return await wait_for_state("running")


func start_procedural_world_preset(
	object_root: String,
	source_revision: int,
	seed: int,
	preset_id: String,
	chunk_count_x: int,
	chunk_count_y: int,
	chunk_origin_y: int,
	chunk_count_z: int
) -> bool:
	if terrain == null:
		return false
	ensure_directory(object_root)
	if not bool(terrain.call(
		"start_procedural_world_preset_with_vertical_origin",
		chunk_count_x,
		chunk_count_y,
		chunk_origin_y,
		chunk_count_z,
		seed,
		source_revision,
		preset_id,
		object_root
	)):
		return false
	return await wait_for_state("running")


func start_manifest(manifest_path: String, object_root: String) -> bool:
	if terrain == null or not bool(terrain.call(
		"start_world",
		manifest_path,
		ProjectSettings.globalize_path(object_root)
	)):
		return false
	return await wait_for_state("running")


func stop_world() -> bool:
	if terrain == null:
		return false
	if str(terrain.call("get_world_state_name")) == "stopped":
		return true
	if not bool(terrain.call("stop_world")):
		return false
	return await wait_for_state("stopped")


func wait_for_state(expected: String, maximum_frames: int = MAX_WAIT_FRAMES) -> bool:
	for _frame in range(maximum_frames):
		if str(terrain.call("get_world_state_name")) == expected:
			await get_tree().process_frame
			return true
		await get_tree().process_frame
	return false


func wait_for_failure(maximum_frames: int = MAX_WAIT_FRAMES) -> bool:
	return await wait_for_state("failed", maximum_frames)


func wait_for_settled(minimum_active: int = 1) -> Dictionary:
	var started := Time.get_ticks_usec()
	for frame in range(MAX_WAIT_FRAMES):
		var metrics: Dictionary = terrain.call("get_runtime_metrics")
		var active := int(metrics.get("active_chunk_records", 0))
		var non_retiring := int(metrics.get("non_retiring_chunk_records", active))
		var ready := int(metrics.get("non_retiring_fully_ready_chunk_records", 0))
		if active >= minimum_active \
				and ready == non_retiring \
				and int(metrics.get("scheduler_queued_jobs", -1)) == 0 \
				and int(metrics.get("scheduler_queued_completions", -1)) == 0 \
				and int(metrics.get("storage_queued_requests", -1)) == 0 \
				and int(metrics.get("storage_queued_completions", -1)) == 0 \
				and int(metrics.get("queued_render", -1)) == 0 \
				and int(metrics.get("queued_collision", -1)) == 0 \
				and int(metrics.get("pending_chunk_retirements", -1)) == 0 \
				and int(metrics.get("blocked_pending_chunk_replacements", -1)) == 0:
			return {
				"status": "PASS",
				"frames": frame,
				"elapsed_usec": Time.get_ticks_usec() - started,
				"metrics": metrics,
			}
		await get_tree().process_frame
	return {
		"status": "FAIL",
		"frames": MAX_WAIT_FRAMES,
		"elapsed_usec": Time.get_ticks_usec() - started,
		"metrics": terrain.call("get_runtime_metrics"),
	}


func wait_for_chunk_ready(
	coordinate: Vector3i,
	lod: int,
	previous_generation: int = 0
) -> Dictionary:
	for frame in range(MAX_WAIT_FRAMES):
		var state: RefCounted = terrain.call("query_chunk_state", coordinate, lod)
		if state != null \
				and bool(state.call("is_present")) \
				and bool(state.call("is_fully_ready")) \
				and int(state.call("get_generation")) > previous_generation:
			return {"status": "PASS", "frames": frame, "state": chunk_state(state)}
		await get_tree().process_frame
	return {"status": "FAIL", "frames": MAX_WAIT_FRAMES, "state": {}}


func request_sample(point: Vector3i, lod: int = 0) -> Dictionary:
	var request_id := int(terrain.call("request_authoritative_sample", point, lod))
	if request_id <= 0:
		return {"status": "FAIL", "error": str(terrain.call("get_world_error"))}
	for _frame in range(MAX_WAIT_FRAMES):
		if sample_results.has(request_id):
			return sample_record(sample_results[request_id])
		if sample_failures.has(request_id):
			return {"status": "FAIL", "error": str(sample_failures[request_id])}
		await get_tree().process_frame
	return {"status": "FAIL", "error": "authoritative sample timed out"}


func request_compaction(output_root: String, source_revision: int) -> Dictionary:
	ensure_directory(output_root.get_base_dir())
	var request_id := int(terrain.call(
		"request_world_compaction",
		output_root,
		source_revision
	))
	return await _wait_for_snapshot(request_id)


func request_migration(output_root: String) -> Dictionary:
	ensure_directory(output_root.get_base_dir())
	var request_id := int(terrain.call("request_world_migration", output_root))
	return await _wait_for_snapshot(request_id)


func wait_for_commit(revision: int) -> bool:
	for _frame in range(MAX_WAIT_FRAMES):
		if revision in committed_revisions \
				and int(terrain.call("get_world_revision")) >= revision:
			return true
		await get_tree().process_frame
	return false


func wait_for_edit_failure(previous_count: int) -> String:
	for _frame in range(MAX_WAIT_FRAMES):
		if edit_failures.size() > previous_count:
			return edit_failures.back()
		await get_tree().process_frame
	return ""


func mesh_signature(chunk_name: String) -> String:
	var mesh_instance := terrain.get_node_or_null(chunk_name) as MeshInstance3D
	if mesh_instance == null or mesh_instance.mesh == null:
		return "EMPTY"
	var lines: Array[String] = []
	for surface in range(mesh_instance.mesh.get_surface_count()):
		var arrays := mesh_instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		lines.append("surface:%d:%d:%d" % [surface, vertices.size(), indices.size()])
		for vertex in vertices:
			lines.append("v:%d,%d,%d" % [
				roundi(vertex.x * 1000000.0),
				roundi(vertex.y * 1000000.0),
				roundi(vertex.z * 1000000.0),
			])
		for index_value in indices:
			lines.append("i:%d" % int(index_value))
	return "\n".join(lines).sha256_text()


func runtime_metrics() -> Dictionary:
	return terrain.call("get_runtime_metrics") if terrain != null else {}


func clear_events() -> void:
	sample_results.clear()
	sample_failures.clear()
	snapshot_results.clear()
	snapshot_failures.clear()
	committed_revisions.clear()
	edit_failures.clear()


func dispose() -> void:
	if terrain != null:
		if str(terrain.call("get_world_state_name")) != "stopped":
			terrain.call("stop_world")
		terrain.queue_free()
		terrain = null


static func chunk_state(state: RefCounted) -> Dictionary:
	return {
		"coordinate": str(state.call("get_chunk_coordinate")),
		"lod": int(state.call("get_lod")),
		"generation": int(state.call("get_generation")),
		"render_generation": int(state.call("get_render_generation")),
		"staged_render_generation": int(state.call("get_staged_render_generation")),
		"collision_generation": int(state.call("get_collision_generation")),
		"visual_ready": bool(state.call("is_visual_ready")),
		"collision_ready": bool(state.call("is_collision_ready")),
		"fully_ready": bool(state.call("is_fully_ready")),
	}


static func sample_record(sample: RefCounted) -> Dictionary:
	return {
		"status": "PASS",
		"point": str(sample.call("get_grid_point")),
		"lod": int(sample.call("get_lod")),
		"density": float(sample.call("get_density")),
		"material": int(sample.call("get_material")),
		"source_revision": int(sample.call("get_source_revision")),
		"world_revision": int(sample.call("get_world_revision")),
		"agreeing_page_count": int(sample.call("get_agreeing_page_count")),
	}


static func ensure_directory(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


static func remove_tree(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	_remove_tree_absolute(absolute)


static func _remove_tree_absolute(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		var child := path.path_join(name)
		if directory.current_is_dir():
			_remove_tree_absolute(child)
		else:
			DirAccess.remove_absolute(child)
		name = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _wait_for_snapshot(request_id: int) -> Dictionary:
	if request_id <= 0:
		return {"status": "FAIL", "error": str(terrain.call("get_world_error"))}
	for _frame in range(MAX_WAIT_FRAMES):
		if snapshot_results.has(request_id):
			var result: Dictionary = snapshot_results[request_id]
			result["status"] = "PASS"
			return result
		if snapshot_failures.has(request_id):
			return {"status": "FAIL", "error": str(snapshot_failures[request_id])}
		await get_tree().process_frame
	return {"status": "FAIL", "error": "world snapshot timed out"}


func _on_sample_ready(request_id: int, sample: RefCounted) -> void:
	sample_results[request_id] = sample


func _on_sample_failed(request_id: int, error: String) -> void:
	sample_failures[request_id] = error


func _on_snapshot_ready(
	request_id: int,
	manifest_path: String,
	source_revision: int,
	world_revision: int,
	page_count: int
) -> void:
	snapshot_results[request_id] = {
		"manifest_path": manifest_path,
		"source_revision": source_revision,
		"world_revision": world_revision,
		"page_count": page_count,
	}


func _on_snapshot_failed(request_id: int, error: String) -> void:
	snapshot_failures[request_id] = error


func _on_edit_committed(world_revision: int) -> void:
	committed_revisions.append(world_revision)


func _on_edit_failed(error: String) -> void:
	edit_failures.append(error)
