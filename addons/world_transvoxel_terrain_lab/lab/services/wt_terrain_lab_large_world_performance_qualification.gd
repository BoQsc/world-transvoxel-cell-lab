@tool
extends Node3D
class_name WtTerrainLabLargeWorldPerformanceQualification

const Harness := preload("res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_runtime_harness.gd")
const JsonLoader := preload("res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd")
const Statistics := preload("res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd")
const STANDARD_PATH := "res://addons/world_transvoxel_terrain_lab/standards/large_world_performance_standard.json"
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/tqp47_large_world_performance"

var _harness: Node
var _terrain: Node
var _camera: Camera3D
var _viewer_revision := 0
var _collision_revision := 0
var _queue_peaks := {"scheduler": 0, "storage": 0, "render": 0, "collision": 0, "storage_age_ns": 0}


func run() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var profile: Dictionary = standard.get("runtime_profile", {})
	var failures: Array[String] = []
	_validate_native_authority(standard, failures)
	_setup_render_scene(profile)
	Harness.remove_tree(RUNTIME_ROOT)
	_harness = Harness.new()
	add_child(_harness)
	if not _harness.create_runtime(int(profile.get("worker_count", 2)), _overrides(profile)):
		failures.append("native runtime unavailable")
		return await _finish(standard, [], failures)
	_terrain = _harness.terrain
	var volume: Array = profile.get("volume_chunks", [])
	if volume.size() != 3 or not await _harness.start_procedural_world_preset(
		RUNTIME_ROOT, int(profile.get("source_revision", 947001)), int(profile.get("seed", 470047)),
		str(profile.get("preset", "rolling_hills_cave")), int(volume[0]), int(volume[1]),
		int(profile.get("vertical_chunk_origin", -8)), int(volume[2])
	):
		failures.append("native large world did not start")
		return await _finish(standard, [], failures)
	var scenarios: Array[Dictionary] = []
	for value in standard.get("scenarios", []):
		var scenario: Dictionary = value
		var result := await _run_scenario(scenario, profile)
		scenarios.append(result)
		_expect(str(result.get("status", "")) == "PASS", "scenario failed: " + str(scenario.get("id", "")), failures)
		print("TQP47 %s %s" % [str(scenario.get("id", "")), str(result.get("status", ""))])
	var aggregate := _aggregate(scenarios)
	_evaluate(standard, scenarios, aggregate, failures)
	return await _finish(standard, scenarios, failures, aggregate)


func _run_scenario(scenario: Dictionary, profile: Dictionary) -> Dictionary:
	var start := _vector3(scenario.get("start", []))
	var finish := _vector3(scenario.get("end", []))
	var kind := str(scenario.get("kind", ""))
	if kind == "teleport":
		await _publish_view(start, profile)
	var initial_settlement := await _publish_view(start if kind != "teleport" else finish, profile)
	var edit_result := {}
	if kind in ["dig", "construct"]:
		edit_result = await _commit_edit(scenario)
	var before: Dictionary = _terrain.call("get_runtime_metrics")
	var frame_values: Array[float] = []
	var process_values: Array[float] = []
	var physics_values: Array[float] = []
	var render_cpu_values: Array[float] = []
	var render_gpu_values: Array[float] = []
	var draw_values: Array[float] = []
	var primitive_values: Array[float] = []
	var frame_count := int(profile.get("frames_per_scenario", 120))
	var over_100ms := 0
	for frame in range(frame_count):
		var frame_started := Time.get_ticks_usec()
		var t := float(frame) / float(maxi(frame_count - 1, 1))
		var position := start.lerp(finish, t)
		if kind == "lod_churn":
			position = start.lerp(finish, 0.5 + 0.5 * sin(t * TAU * 4.0))
		if kind in ["motion", "lod_churn"] and frame % 12 == 0:
			_submit_view(position, profile)
		_camera.position = position + Vector3(0.0, 48.0, 72.0)
		_camera.look_at(position, Vector3.UP)
		await get_tree().process_frame
		var elapsed := float(Time.get_ticks_usec() - frame_started)
		frame_values.append(elapsed)
		over_100ms += 1 if elapsed > 100000.0 else 0
		process_values.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000000.0)
		physics_values.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000000.0)
		render_cpu_values.append(RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()) * 1000.0)
		render_gpu_values.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()) * 1000.0)
		draw_values.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitive_values.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		_observe_queues(_terrain.call("get_runtime_metrics"))
	var final_settlement: Dictionary = await _harness.wait_for_settled(1)
	var after: Dictionary = _terrain.call("get_runtime_metrics")
	var frame_distribution := Statistics.distribution(frame_values)
	var rendered := _maximum(draw_values) > 0.0 and _maximum(primitive_values) > 0.0
	var generation_agreement := _generation_agreement()
	return {
		"id": scenario.get("id", ""),
		"kind": kind,
		"status": "PASS" if str(initial_settlement.get("status", "")) == "PASS"
			and str(final_settlement.get("status", "")) == "PASS" and rendered
			and str(generation_agreement.get("status", "")) == "PASS"
			and (edit_result.is_empty() or str(edit_result.get("status", "")) == "PASS") else "FAIL",
		"frame": frame_distribution,
		"stutter_over_100ms_count": over_100ms,
		"stutter_fraction_over_100ms": float(over_100ms) / float(maxi(frame_count, 1)),
		"process": Statistics.distribution(process_values),
		"physics": Statistics.distribution(physics_values),
		"render_cpu": Statistics.distribution(render_cpu_values),
		"render_gpu": Statistics.distribution(render_gpu_values),
		"draw_calls": Statistics.distribution(draw_values),
		"primitives": Statistics.distribution(primitive_values),
		"worker_delta": {
			"sample_jobs": int(after.get("sample_jobs", 0)) - int(before.get("sample_jobs", 0)),
			"mesh_jobs": int(after.get("mesh_jobs", 0)) - int(before.get("mesh_jobs", 0)),
			"sample_time_ns": int(after.get("sample_job_time_ns_total", 0)) - int(before.get("sample_job_time_ns_total", 0)),
			"mesh_time_ns": int(after.get("mesh_job_time_ns_total", 0)) - int(before.get("mesh_job_time_ns_total", 0)),
		},
		"loading_state": _loading_state(after),
		"resources": _resource_metrics(after),
		"applied_generation_agreement": generation_agreement,
		"edit": edit_result,
	}


func _publish_view(position: Vector3, profile: Dictionary) -> Dictionary:
	var before: Dictionary = _terrain.call("get_runtime_metrics")
	if not _submit_view(position, profile):
		return {"status": "FAIL", "error": "viewer submission rejected"}
	if not await _wait_for_demand_events(
		int(before.get("viewer_updates", 0)) + 1,
		int(before.get("collision_viewer_updates", 0)) + 1
	):
		return {"status": "FAIL", "error": "viewer demand was not consumed"}
	var settlement: Dictionary = await _harness.wait_for_settled(1)
	var agreement := _generation_agreement()
	if str(settlement.get("status", "")) != "PASS" \
			or str(agreement.get("status", "")) != "PASS":
		return {
			"status": "FAIL",
			"settlement": settlement,
			"applied_generation_agreement": agreement,
		}
	settlement["applied_generation_agreement"] = agreement
	return settlement


func _submit_view(position: Vector3, profile: Dictionary) -> bool:
	_viewer_revision += 1
	_collision_revision += 1
	return bool(_terrain.call(
		"update_viewer", 470, _viewer_revision, position,
		int(profile.get("viewer_radius_chunks", 2)), int(profile.get("maximum_lod", 2))
	)) and bool(_terrain.call(
		"update_collision_viewer", 471, _collision_revision, position,
		int(profile.get("collision_radius_chunks", 1))
	))


func _wait_for_demand_events(viewer_target: int, collision_target: int) -> bool:
	for _frame in range(Harness.MAX_WAIT_FRAMES):
		var metrics: Dictionary = _terrain.call("get_runtime_metrics")
		if int(metrics.get("viewer_updates", 0)) >= viewer_target \
				and int(metrics.get("collision_viewer_updates", 0)) >= collision_target:
			return true
		await get_tree().process_frame
	return false


func _commit_edit(scenario: Dictionary) -> Dictionary:
	var center := _vector3(scenario.get("edit_center", []))
	var revision := int(_terrain.call("get_world_revision")) + 1
	var transaction: RefCounted = _terrain.call("begin_edit_transaction", 4700 + revision)
	var started := Time.get_ticks_usec()
	var accepted := false
	if transaction != null:
		if str(scenario.get("kind", "")) == "dig":
			accepted = bool(transaction.call("carve_smooth_sdf_sphere", center, 5.0, 1.0, 1.0))
		else:
			accepted = bool(transaction.call("construct_material_smooth_sdf_sphere", center, 5.0, 1.0, int(scenario.get("material", 12)), 1.0))
		accepted = accepted and bool(_terrain.call("commit_edit_transaction", transaction))
	var committed: bool = await _harness.wait_for_commit(revision)
	var settled: Dictionary = await _harness.wait_for_settled(1)
	return {
		"status": "PASS" if accepted and committed and str(settled.get("status", "")) == "PASS"
			and str(_generation_agreement().get("status", "")) == "PASS" else "FAIL",
		"latency_usec": Time.get_ticks_usec() - started,
		"world_revision": int(_terrain.call("get_world_revision")),
	}


func _finish(standard: Dictionary, scenarios: Array, failures: Array[String], aggregate: Dictionary = {}) -> Dictionary:
	var final_metrics := _terrain.call("get_runtime_metrics") as Dictionary if is_instance_valid(_terrain) else {}
	var stopped := true
	if is_instance_valid(_harness) and is_instance_valid(_terrain):
		stopped = await _harness.stop_world()
		_harness.dispose()
		_harness.queue_free()
		await get_tree().process_frame
	Harness.remove_tree(RUNTIME_ROOT)
	_expect(stopped, "native runtime did not stop cleanly", failures)
	return {
		"schema": "world_transvoxel.terrain_lab.large_world_performance_qualification.v1",
		"milestone": "TQP-47",
		"standard_id": standard.get("standard_id", ""),
		"authority": standard.get("authority", ""),
		"status": "PASS" if failures.is_empty() else "FAIL",
		"retained_complete": failures.is_empty(),
		"provenance": Statistics.provenance("tqp47_large_world_render_windows_v1"),
		"runtime_profile": standard.get("runtime_profile", {}),
		"scenarios": scenarios,
		"aggregate": aggregate,
		"queue_peaks": _queue_peaks,
		"memory": Statistics.memory_metrics(),
		"gpu_memory": {
			"video_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
			"texture_bytes": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
			"buffer_bytes": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),
		},
		"final_loading_state": _loading_state(final_metrics),
		"shutdown": "PASS" if stopped else "FAIL",
		"optimization_controls": {"authority_baseline_only": true, "unmeasured_optimizations_promoted": false},
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


func _setup_render_scene(profile: Dictionary) -> void:
	var size: Array = profile.get("resolution", [1280, 720])
	get_window().size = Vector2i(int(size[0]), int(size[1]))
	var environment := WorldEnvironment.new()
	var resource := Environment.new()
	resource.background_mode = Environment.BG_COLOR
	resource.background_color = Color(0.18, 0.22, 0.27)
	resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	resource.ambient_light_color = Color(0.65, 0.7, 0.75)
	resource.ambient_light_energy = 0.7
	environment.environment = resource
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58.0, -32.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.far = 4096.0
	add_child(_camera)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _observe_queues(metrics: Dictionary) -> void:
	_queue_peaks["scheduler"] = maxi(int(_queue_peaks["scheduler"]), int(metrics.get("scheduler_queued_jobs", 0)))
	_queue_peaks["storage"] = maxi(int(_queue_peaks["storage"]), int(metrics.get("storage_queued_requests", 0)))
	_queue_peaks["render"] = maxi(int(_queue_peaks["render"]), int(metrics.get("queued_render", 0)))
	_queue_peaks["collision"] = maxi(int(_queue_peaks["collision"]), int(metrics.get("total_collision_backlog", 0)))
	_queue_peaks["storage_age_ns"] = maxi(int(_queue_peaks["storage_age_ns"]), int(metrics.get("storage_in_flight_elapsed_ns", 0)))


static func _aggregate(scenarios: Array[Dictionary]) -> Dictionary:
	var frames: Array[float] = []
	var gpu: Array[float] = []
	var rendered := 0
	var over_100 := 0
	for scenario in scenarios:
		var frame: Dictionary = scenario.get("frame", {})
		frames.append(float(frame.get("p50_usec", 0.0)))
		frames.append(float(frame.get("p95_usec", 0.0)))
		frames.append(float(frame.get("p99_usec", 0.0)))
		frames.append(float(frame.get("worst_usec", 0.0)))
		gpu.append(float((scenario.get("render_gpu", {}) as Dictionary).get("p99_usec", 0.0)))
		rendered += 1 if float((scenario.get("primitives", {}) as Dictionary).get("worst_usec", 0.0)) > 0.0 else 0
		over_100 += int(scenario.get("stutter_over_100ms_count", 0))
	return {"frame_envelope": Statistics.distribution(frames), "gpu_p99_envelope": Statistics.distribution(gpu), "rendered_scenarios": rendered, "stutter_over_100ms_count": over_100}


static func _loading_state(metrics: Dictionary) -> Dictionary:
	return {
		"world_running": metrics.get("world_running", false),
		"scheduler_queued_jobs": metrics.get("scheduler_queued_jobs", -1),
		"storage_queued_requests": metrics.get("storage_queued_requests", -1),
		"queued_render": metrics.get("queued_render", -1),
		"collision_backlog": metrics.get("total_collision_backlog", -1),
		"pending_replacements": metrics.get("pending_chunk_replacements", -1),
		"pending_retirements": metrics.get("pending_chunk_retirements", -1),
	}


static func _resource_metrics(metrics: Dictionary) -> Dictionary:
	return {"active_chunks": metrics.get("active_chunk_records", -1), "render_resources": metrics.get("render_resources", -1), "collision_resources": metrics.get("collision_resources", -1)}


func _generation_agreement() -> Dictionary:
	var visual_mismatches: Array[String] = []
	var collision_mismatches: Array[String] = []
	for state_value in _terrain.call("query_active_chunk_states"):
		var state: RefCounted = state_value
		if not bool(state.call("is_present")):
			continue
		var generation := int(state.call("get_generation"))
		var key := "%s@%d" % [str(state.call("get_chunk_coordinate")), int(state.call("get_lod"))]
		var render_generation := int(state.call("get_render_generation"))
		var collision_generation := int(state.call("get_collision_generation"))
		if bool(state.call("is_visual_required")) and (
			not bool(state.call("is_visual_ready"))
			or render_generation not in [0, generation]
			or int(state.call("get_staged_render_generation")) != 0
		):
			visual_mismatches.append(key)
		if bool(state.call("is_collision_required")) and (
			not bool(state.call("is_collision_ready"))
			or collision_generation not in [0, generation]
			or int(state.call("get_staged_collision_generation")) != 0
		):
			collision_mismatches.append(key)
	return {
		"status": "PASS" if visual_mismatches.is_empty() and collision_mismatches.is_empty() else "FAIL",
		"visual_mismatches": visual_mismatches,
		"collision_mismatches": collision_mismatches,
	}


static func _evaluate(standard: Dictionary, scenarios: Array[Dictionary], aggregate: Dictionary, failures: Array[String]) -> void:
	var budgets: Dictionary = standard.get("budgets", {})
	_expect(scenarios.size() >= int(budgets.get("minimum_rendered_scenarios", 8)), "scenario coverage incomplete", failures)
	for scenario in scenarios:
		var frame: Dictionary = scenario.get("frame", {})
		_expect(int(frame.get("sample_count", 0)) >= int(budgets.get("minimum_frame_samples_per_scenario", 120)), "frame sample count incomplete", failures)
		_expect(float(frame.get("p99_usec", INF)) <= float(budgets.get("maximum_frame_p99_usec", 0.0)), "frame p99 exceeded: " + str(scenario.get("id", "")), failures)
		_expect(float(frame.get("worst_usec", INF)) <= float(budgets.get("maximum_frame_worst_usec", 0.0)), "worst frame exceeded: " + str(scenario.get("id", "")), failures)
		_expect(float(scenario.get("stutter_fraction_over_100ms", INF)) <= float(budgets.get("maximum_stutter_fraction_over_100ms", 0.0)), "stutter fraction exceeded: " + str(scenario.get("id", "")), failures)
	_expect(int(aggregate.get("rendered_scenarios", 0)) >= int(budgets.get("minimum_rendered_scenarios", 8)), "render instrumentation was blank", failures)


func _validate_native_authority(standard: Dictionary, failures: Array[String]) -> void:
	var native := JsonLoader.load_dictionary(str(standard.get("native_authority_evidence", "")))
	_expect(str(native.get("status", "")) == "PASS", "native closure authority failed", failures)
	_expect((native.get("proof_map", {}) as Dictionary).has("TQP-47"), "native TQP-47 proof map absent", failures)


static func _overrides(profile: Dictionary) -> Dictionary:
	var pipeline := int(profile.get("pipeline_capacity", 8192))
	var cache := int(profile.get("cache_capacity", 2048))
	return {
		"active_chunk_capacity": int(profile.get("active_chunk_capacity", 2048)), "viewer_capacity": 8,
		"demand_capacity_per_viewer": pipeline, "lod_refinement_radius_chunks": 1,
		"storage_request_capacity": pipeline, "storage_completion_capacity": pipeline,
		"encoded_page_entry_capacity": cache, "decoded_page_entry_capacity": cache,
		"mesh_entry_capacity": cache, "render_entry_capacity": cache,
		"collision_entry_capacity": int(profile.get("collision_capacity", 256)),
		"trace_event_capacity": 65536, "render_apply_budget": 8, "collision_apply_budget": 3,
		"collision_apply_deadline_us": 12000, "collision_activation_distance": 64.0,
		"collision_deactivation_distance": 96.0, "render_transition_frames": 0,
	}


static func _maximum(values: Array[float]) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, value)
	return result


static func _vector3(value: Variant) -> Vector3:
	var array: Array = value
	return Vector3(float(array[0]), float(array[1]), float(array[2])) if array.size() == 3 else Vector3.ZERO


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
