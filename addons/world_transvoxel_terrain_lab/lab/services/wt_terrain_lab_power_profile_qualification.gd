extends Node3D
class_name WtTerrainLabPowerProfileQualification

const Harness := preload("res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_runtime_harness.gd")
const JsonLoader := preload("res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd")
const Statistics := preload("res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd")
const STANDARD_PATH := "res://addons/world_transvoxel_terrain_lab/standards/low_power_qualification_standard.json"
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/tqp48_power_profile"

var _harness: Node
var _terrain: Node
var _camera: Camera3D
var _viewer_revision := 0
var _collision_revisions := {481: 0, 482: 0}
var _edit_id := 4800


func run(profile_id: String, warmup_seconds: int, measured_seconds: int) -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var profiles: Dictionary = standard.get("profiles", {})
	if not profiles.has(profile_id):
		return {"status": "FAIL", "failures": ["unknown power profile: " + profile_id]}
	var profile: Dictionary = profiles[profile_id]
	var world: Dictionary = standard.get("world", {})
	var failures: Array[String] = []
	Engine.max_fps = int(profile.get("target_fps", 60))
	_setup_render_scene(profile)
	Harness.remove_tree(RUNTIME_ROOT)
	_harness = Harness.new()
	add_child(_harness)
	if not _harness.create_runtime(int(world.get("worker_count", 2)), _overrides(profile)):
		return {"status": "FAIL", "failures": ["native runtime unavailable"]}
	_terrain = _harness.terrain
	var volume: Array = world.get("volume_chunks", [])
	if not await _harness.start_procedural_world_preset(
		RUNTIME_ROOT, int(world.get("source_revision", 948001)), int(world.get("seed", 480048)),
		str(world.get("preset", "rolling_hills_cave")), int(volume[0]), int(volume[1]),
		int(world.get("vertical_chunk_origin", -8)), int(volume[2])
	):
		return {"status": "FAIL", "failures": ["native world failed to start"]}
	_submit_demand(Vector3(1024.0, 44.0, 1024.0), profile)
	var initial: Dictionary = await _harness.wait_for_settled(1)
	if str(initial.get("status", "")) != "PASS":
		failures.append("initial power workload did not settle")
	var warmup := await _run_interval(warmup_seconds, profile, false)
	var measurement_started_unix := Time.get_unix_time_from_system()
	var measurement_contract: Dictionary = standard.get("measurement", {})
	var minimum_measured_frames := int(measurement_contract.get("minimum_frame_samples", 0)) \
		if measured_seconds >= int(measurement_contract.get("steady_state_seconds", 0)) else 0
	var measured := await _run_interval(
		measured_seconds, profile, true, minimum_measured_frames
	)
	var measurement_ended_unix := Time.get_unix_time_from_system()
	for failure_value in measured.get("failures", []):
		failures.append(str(failure_value))
	var final_metrics: Dictionary = _terrain.call("get_runtime_metrics")
	var stopped: bool = await _harness.stop_world()
	_harness.dispose()
	_harness.queue_free()
	await get_tree().process_frame
	Harness.remove_tree(RUNTIME_ROOT)
	if not stopped:
		failures.append("native runtime did not stop cleanly")
	Engine.max_fps = 0
	return {
		"schema": "world_transvoxel.terrain_lab.low_power_workload.v1",
		"profile_id": profile_id,
		"status": "PASS" if failures.is_empty() else "FAIL",
		"provenance": Statistics.provenance("tqp48_" + profile_id),
		"profile": profile,
		"warmup": warmup,
		"measurement": measured,
		"measurement_wall_clock": {
			"started_unix_seconds": measurement_started_unix,
			"ended_unix_seconds": measurement_ended_unix,
		},
		"memory": Statistics.memory_metrics(),
		"gpu_memory": {
			"video_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
			"texture_bytes": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
			"buffer_bytes": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),
		},
		"final_metrics": final_metrics,
		"shutdown": "PASS" if stopped else "FAIL",
		"failures": failures,
	}


func _run_interval(
	seconds: int,
	profile: Dictionary,
	retain_samples: bool,
	minimum_frames: int = 0
) -> Dictionary:
	var frame_times: Array[float] = []
	var process_times: Array[float] = []
	var physics_times: Array[float] = []
	var render_cpu: Array[float] = []
	var render_gpu: Array[float] = []
	var queue_peaks := {"scheduler": 0, "storage": 0, "render": 0, "collision": 0}
	var window_queue_peaks := {"scheduler": 0, "storage": 0, "render": 0, "collision": 0}
	var workload_counts := {"idle": 0, "ground_traversal": 0, "high_speed_flight": 0, "vertical_cave": 0, "lod_churn": 0, "teleport": 0, "digging": 0, "construction": 0, "multiple_collision_invokers": 0, "resource_retirement": 0}
	var action_counts := {
		"demand_submissions": 0, "demand_rejections": 0,
		"secondary_invoker_updates": 0, "secondary_invoker_rejections": 0,
		"dig_commits": 0, "construction_commits": 0, "edit_rejections": 0,
		"secondary_invoker_retirements": 0, "retirement_rejections": 0,
	}
	var demand_acknowledgement: Array[float] = []
	var edit_acknowledgement: Array[float] = []
	var drift_windows: Array[Dictionary] = []
	var window_frames: Array[float] = []
	var over_33ms := 0
	var memory_start := OS.get_static_memory_usage()
	var metrics_start: Dictionary = _terrain.call("get_runtime_metrics")
	var started := Time.get_ticks_usec()
	var window_started := started
	var frame := 0
	while Time.get_ticks_usec() - started < seconds * 1000000 or frame < minimum_frames:
		var frame_started := Time.get_ticks_usec()
		var phase := (frame / 300) % 10
		var position := _workload_position(phase, frame)
		workload_counts[_workload_name(phase)] = int(workload_counts[_workload_name(phase)]) + 1
		if frame % 30 == 0:
			var demand := _submit_demand(position, profile, phase)
			action_counts["demand_submissions"] += 1
			demand_acknowledgement.append(float(demand.get("acknowledgement_usec", 0.0)))
			if not bool(demand.get("primary_accepted", false)):
				action_counts["demand_rejections"] += 1
			if bool(demand.get("secondary_attempted", false)):
				action_counts["secondary_invoker_updates"] += 1
				if not bool(demand.get("secondary_accepted", false)):
					action_counts["secondary_invoker_rejections"] += 1
		if frame % 300 == 0 and phase in [6, 7]:
			var edit := _commit_periodic_edit(position, phase == 7)
			edit_acknowledgement.append(float(edit.get("acknowledgement_usec", 0.0)))
			if bool(edit.get("accepted", false)):
				action_counts["construction_commits" if phase == 7 else "dig_commits"] += 1
			else:
				action_counts["edit_rejections"] += 1
		if frame % 300 == 0 and phase == 9:
			if _retire_secondary_collision_invoker():
				action_counts["secondary_invoker_retirements"] += 1
			else:
				action_counts["retirement_rejections"] += 1
		_camera.position = position + Vector3(0.0, 42.0, 64.0)
		_camera.look_at(position, Vector3.UP)
		await get_tree().process_frame
		var elapsed := float(Time.get_ticks_usec() - frame_started)
		if retain_samples:
			frame_times.append(elapsed)
			window_frames.append(elapsed)
			if elapsed > 33333.0:
				over_33ms += 1
			process_times.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000000.0)
			physics_times.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000000.0)
			render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()) * 1000.0)
			render_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()) * 1000.0)
		var metrics: Dictionary = _terrain.call("get_runtime_metrics")
		queue_peaks["scheduler"] = maxi(int(queue_peaks["scheduler"]), int(metrics.get("scheduler_queued_jobs", 0)))
		queue_peaks["storage"] = maxi(int(queue_peaks["storage"]), int(metrics.get("storage_queued_requests", 0)))
		queue_peaks["render"] = maxi(int(queue_peaks["render"]), int(metrics.get("queued_render", 0)))
		queue_peaks["collision"] = maxi(int(queue_peaks["collision"]), int(metrics.get("total_collision_backlog", 0)))
		window_queue_peaks["scheduler"] = maxi(int(window_queue_peaks["scheduler"]), int(metrics.get("scheduler_queued_jobs", 0)))
		window_queue_peaks["storage"] = maxi(int(window_queue_peaks["storage"]), int(metrics.get("storage_queued_requests", 0)))
		window_queue_peaks["render"] = maxi(int(window_queue_peaks["render"]), int(metrics.get("queued_render", 0)))
		window_queue_peaks["collision"] = maxi(int(window_queue_peaks["collision"]), int(metrics.get("total_collision_backlog", 0)))
		if retain_samples and Time.get_ticks_usec() - window_started >= 60000000:
			drift_windows.append(_drift_window(drift_windows.size(), window_started, window_frames, window_queue_peaks))
			window_frames.clear()
			window_queue_peaks = {"scheduler": 0, "storage": 0, "render": 0, "collision": 0}
			window_started = Time.get_ticks_usec()
		frame += 1
	if retain_samples and not window_frames.is_empty():
		drift_windows.append(_drift_window(drift_windows.size(), window_started, window_frames, window_queue_peaks))
	var interval_failures: Array[String] = []
	if int(action_counts.get("demand_rejections", 0)) > 0:
		interval_failures.append("power workload rejected primary demand")
	if int(action_counts.get("secondary_invoker_rejections", 0)) > 0:
		interval_failures.append("power workload rejected secondary collision demand")
	if int(action_counts.get("edit_rejections", 0)) > 0:
		interval_failures.append("power workload rejected an edit")
	if int(action_counts.get("retirement_rejections", 0)) > 0:
		interval_failures.append("power workload rejected collision retirement")
	var metrics_end: Dictionary = _terrain.call("get_runtime_metrics")
	return {
		"requested_seconds": seconds,
		"elapsed_seconds": float(Time.get_ticks_usec() - started) / 1000000.0,
		"frame_count": frame,
		"frame": Statistics.distribution(frame_times),
		"process": Statistics.distribution(process_times),
		"physics": Statistics.distribution(physics_times),
		"render_cpu": Statistics.distribution(render_cpu),
		"render_gpu": Statistics.distribution(render_gpu),
		"fraction_over_33_333ms": float(over_33ms) / float(frame_times.size()) if not frame_times.is_empty() else 0.0,
		"queue_peaks": queue_peaks,
		"workload_counts": workload_counts,
		"action_counts": action_counts,
		"demand_acknowledgement": Statistics.distribution(demand_acknowledgement),
		"edit_acknowledgement": Statistics.distribution(edit_acknowledgement),
		"memory": {
			"start_bytes": memory_start,
			"end_bytes": OS.get_static_memory_usage(),
			"peak_bytes": OS.get_static_memory_peak_usage(),
		},
		"drift_windows": drift_windows,
		"metric_deltas": {
			"application_applied_render": int(metrics_end.get("application_applied_render", 0)) - int(metrics_start.get("application_applied_render", 0)),
			"application_applied_collision": int(metrics_end.get("application_applied_collision", 0)) - int(metrics_start.get("application_applied_collision", 0)),
			"edit_commits": int(metrics_end.get("edit_commits", 0)) - int(metrics_start.get("edit_commits", 0)),
			"published_events": int(metrics_end.get("published_events", 0)) - int(metrics_start.get("published_events", 0)),
		},
		"failures": interval_failures,
	}


func _submit_demand(position: Vector3, profile: Dictionary, phase: int = -1) -> Dictionary:
	var started := Time.get_ticks_usec()
	_viewer_revision += 1
	_collision_revisions[481] = int(_collision_revisions[481]) + 1
	var visual_accepted := bool(_terrain.call("update_viewer", 480, _viewer_revision, position, int(profile.get("viewer_radius_chunks", 1)), int(profile.get("maximum_lod", 2))))
	var collision_accepted := bool(_terrain.call("update_collision_viewer", 481, int(_collision_revisions[481]), position, int(profile.get("collision_radius_chunks", 1))))
	var secondary_attempted := phase == 8
	var secondary_accepted := false
	if secondary_attempted:
		_collision_revisions[482] = int(_collision_revisions[482]) + 1
		secondary_accepted = bool(_terrain.call("update_collision_viewer", 482, int(_collision_revisions[482]), position + Vector3(32.0, 0.0, 0.0), 1))
	return {
		"primary_accepted": visual_accepted and collision_accepted,
		"secondary_attempted": secondary_attempted,
		"secondary_accepted": secondary_accepted,
		"acknowledgement_usec": Time.get_ticks_usec() - started,
	}


func _commit_periodic_edit(position: Vector3, construct: bool) -> Dictionary:
	var started := Time.get_ticks_usec()
	_edit_id += 1
	var transaction: RefCounted = _terrain.call("begin_edit_transaction", _edit_id)
	if transaction == null:
		return {"accepted": false, "acknowledgement_usec": Time.get_ticks_usec() - started}
	var center := Vector3(position.x, 28.0, position.z)
	var accepted := bool(transaction.call("construct_material_smooth_sdf_sphere", center, 3.0, 1.0, 13, 0.75)) if construct else bool(transaction.call("carve_smooth_sdf_sphere", center, 3.0, 1.0, 0.75))
	if accepted:
		accepted = bool(_terrain.call("commit_edit_transaction", transaction))
	return {"accepted": accepted, "acknowledgement_usec": Time.get_ticks_usec() - started}


func _retire_secondary_collision_invoker() -> bool:
	_collision_revisions[482] = int(_collision_revisions[482]) + 1
	return bool(_terrain.call("remove_collision_viewer", 482, int(_collision_revisions[482])))


static func _drift_window(
	index: int,
	started_usec: int,
	frames: Array[float],
	queue_peaks: Dictionary
) -> Dictionary:
	return {
		"index": index,
		"elapsed_seconds": float(Time.get_ticks_usec() - started_usec) / 1000000.0,
		"frame": Statistics.distribution(frames),
		"queue_peaks": queue_peaks.duplicate(true),
		"memory_bytes": OS.get_static_memory_usage(),
	}


static func _workload_position(phase: int, frame: int) -> Vector3:
	var t := float(frame % 300) / 299.0
	match phase:
		0: return Vector3(1024.0, 44.0, 1024.0)
		1: return Vector3(256.0, 38.0, 256.0).lerp(Vector3(512.0, 42.0, 448.0), t)
		2: return Vector3(512.0, 120.0, 512.0).lerp(Vector3(1152.0, 120.0, 896.0), t)
		3: return Vector3(1024.0, 72.0, 1024.0).lerp(Vector3(1024.0, -24.0, 1024.0), t)
		4: return Vector3(768.0, 44.0, 768.0).lerp(Vector3(960.0, 44.0, 960.0), 0.5 + 0.5 * sin(t * TAU * 4.0))
		5: return Vector3(192.0, 42.0, 1792.0) if t < 0.5 else Vector3(1792.0, 42.0, 1792.0)
		6: return Vector3(1792.0, 42.0, 1792.0)
		7: return Vector3(1800.0, 42.0, 1792.0)
		8: return Vector3(1024.0, 42.0, 1024.0)
		_: return Vector3(1280.0, 42.0, 1280.0)


static func _workload_name(phase: int) -> String:
	return ["idle", "ground_traversal", "high_speed_flight", "vertical_cave", "lod_churn", "teleport", "digging", "construction", "multiple_collision_invokers", "resource_retirement"][phase]


func _setup_render_scene(profile: Dictionary) -> void:
	var resolution: Array = profile.get("resolution", [960, 540])
	get_window().size = Vector2i(int(resolution[0]), int(resolution[1]))
	var environment := WorldEnvironment.new()
	var resource := Environment.new()
	resource.background_mode = Environment.BG_COLOR
	resource.background_color = Color(0.16, 0.2, 0.24)
	resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	resource.ambient_light_energy = 0.65
	environment.environment = resource
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58.0, -32.0, 0.0)
	sun.shadow_enabled = bool(profile.get("shadows", false))
	add_child(sun)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.far = 4096.0
	add_child(_camera)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


static func _overrides(profile: Dictionary) -> Dictionary:
	var pipeline := int(profile.get("pipeline_capacity", 4096))
	var cache := int(profile.get("cache_capacity", 1024))
	return {
		"active_chunk_capacity": int(profile.get("active_chunk_capacity", 1024)), "viewer_capacity": 8,
		"demand_capacity_per_viewer": pipeline, "lod_refinement_radius_chunks": 1,
		"storage_request_capacity": pipeline, "storage_completion_capacity": pipeline,
		"encoded_page_entry_capacity": cache, "decoded_page_entry_capacity": cache,
		"mesh_entry_capacity": cache, "render_entry_capacity": cache,
		"collision_entry_capacity": 256, "trace_event_capacity": 65536,
		"render_apply_budget": int(profile.get("render_apply_budget", 4)),
		"collision_apply_budget": int(profile.get("collision_apply_budget", 2)),
		"collision_apply_deadline_us": 12000, "collision_activation_distance": 64.0,
		"collision_deactivation_distance": 96.0, "render_transition_frames": 0,
	}
