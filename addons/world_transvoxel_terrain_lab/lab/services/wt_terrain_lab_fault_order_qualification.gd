@tool
extends Node
class_name WtTerrainLabFaultOrderQualification

const Harness := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_runtime_harness.gd"
)
const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/fault_order_determinism_standard.json"
)
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/tqp43_fault_order"


func run() -> Dictionary:
	var failures: Array[String] = []
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var profile: Dictionary = standard.get("runtime_profile", {})
	var workload: Dictionary = standard.get("workload", {})
	var budgets: Dictionary = standard.get("budgets", {})
	var native := JsonLoader.load_dictionary(str(standard.get("native_benchmark_evidence", "")))
	_expect(_native_evidence_valid(native, standard), "pinned native fault-order authority changed", failures)
	var actions := _native_actions(native, standard)
	var replays: Array[Dictionary] = []
	var orders: Array = workload.get("motion_orders", [])
	for order_index in range(orders.size()):
		var replay: Dictionary = await _run_motion_order(order_index, orders[order_index], profile, workload)
		replays.append(replay)
		_expect(str(replay.get("status", "")) == "PASS", "motion order %d failed" % order_index, failures)
		_expect(
			int(replay.get("settlement_frames", Harness.MAX_WAIT_FRAMES + 1))
				<= int(budgets.get("maximum_settlement_frames", Harness.MAX_WAIT_FRAMES)),
			"motion order %d exceeded the settlement-frame ceiling" % order_index,
			failures
		)
		_expect(
			int(replay.get("total_elapsed_usec", 0))
				<= int(budgets.get("maximum_replay_elapsed_usec", 8000000)),
			"motion order %d exceeded the replay-time ceiling" % order_index,
			failures
		)
	var converged := _replays_converged(replays)
	_expect(converged, "rapid viewer histories did not converge to identical state and geometry", failures)
	actions["rapid_viewer_cross_order_convergence"] = _status(converged)
	var stale_pass := not replays.is_empty()
	var shutdown_pass := not replays.is_empty()
	for replay in replays:
		stale_pass = stale_pass and bool(replay.get("stale_revision_rejected", false))
		shutdown_pass = shutdown_pass and str((replay.get("shutdown", {}) as Dictionary).get("status", "")) == "PASS"
	actions["stale_viewer_revision_rejection"] = _status(stale_pass)
	actions["clean_runtime_shutdown"] = _status(shutdown_pass)
	_expect(stale_pass, "one or more stale viewer revisions were not rejected", failures)
	_expect(shutdown_pass, "one or more runtime queues did not shut down cleanly", failures)
	for required in workload.get("required_actions", []):
		_expect(str(actions.get(str(required), "")) == "PASS", "required action failed: " + str(required), failures)
	var semantic_signature := _semantic_signature(native, replays)
	return {
		"schema": "world_transvoxel.terrain_lab.fault_order_qualification.v1",
		"milestone": "TQP-43",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"retained_complete": failures.is_empty(),
		"authority": standard.get("authority", ""),
		"native_evidence": native,
		"actions": actions,
		"replays": replays,
		"cross_order_converged": converged,
		"semantic_signature": semantic_signature,
		"performance_claim": "REFERENCE_ONLY_NOT_A_PRODUCTION_PERFORMANCE_GATE",
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


func _run_motion_order(
	order_index: int,
	order_value: Variant,
	profile: Dictionary,
	workload: Dictionary
) -> Dictionary:
	var replay_started := Time.get_ticks_usec()
	var root := RUNTIME_ROOT + "/order_%d" % order_index
	Harness.remove_tree(root)
	var harness := Harness.new()
	add_child(harness)
	if not harness.create_runtime(int(profile.get("worker_count", 2)), runtime_overrides(profile)):
		harness.queue_free()
		return {"status": "FAIL", "failure": "native runtime unavailable"}
	if not await harness.start_procedural_world_preset(
		root,
		int(profile.get("source_revision", 943001)),
		int(profile.get("seed", 43043)),
		str(profile.get("preset_id", "rolling_hills_cave")),
		int(profile.get("chunk_count_x", 16)),
		int(profile.get("chunk_count_y", 4)),
		int(profile.get("chunk_origin_y", -2)),
		int(profile.get("chunk_count_z", 16))
	):
		harness.dispose()
		harness.queue_free()
		return {"status": "FAIL", "failure": "procedural world startup failed"}
	var terrain := harness.terrain
	var viewer_id := int(profile.get("viewer_id", 431))
	var radius := int(profile.get("viewer_radius_chunks", 1))
	var maximum_lod := int(profile.get("maximum_lod", 2))
	var revision := 0
	var accepted := 0
	var work_started := false
	var order: Array = order_value
	for index in range(order.size()):
		var position_value: Variant = order[index]
		revision += 1
		if bool(terrain.call("update_viewer", viewer_id, revision, vector3(position_value), radius, maximum_lod)):
			accepted += 1
		if index == 0:
			work_started = await _wait_for_work_started(terrain, 360)
	revision += 1
	var drain_submitted := bool(terrain.call("remove_viewer", viewer_id, revision))
	var drain_completed := drain_submitted and await _wait_for_empty(terrain)
	revision += 1
	var final_position := vector3(workload.get("final_position", []))
	if bool(terrain.call("update_viewer", viewer_id, revision, final_position, radius, maximum_lod)):
		accepted += 1
	var settlement: Dictionary = await harness.wait_for_settled(1)
	var metrics: Dictionary = terrain.call("get_runtime_metrics")
	var stale_before := int(metrics.get("rejected_events", 0))
	var stale_submitted := bool(terrain.call(
		"update_viewer", viewer_id, revision - 1, final_position, radius, maximum_lod
	))
	var stale_rejected := await _wait_for_metric_increase(terrain, "rejected_events", stale_before, 360)
	var snapshot := state_snapshot(terrain, harness)
	var stopped := await harness.stop_world()
	var shutdown_metrics: Dictionary = terrain.call("get_runtime_metrics")
	var shutdown := {
		"status": _status(stopped and _queues_drained(shutdown_metrics)),
		"world_state": str(terrain.call("get_world_state_name")),
		"metrics": selected_metrics(shutdown_metrics),
	}
	var result := {
		"order_index": order_index,
		"status": _status(
			str(settlement.get("status", "")) == "PASS"
			and work_started
			and drain_completed
			and accepted == (order_value as Array).size() + 1
			and stale_submitted and stale_rejected
			and str(shutdown.get("status", "")) == "PASS"
			and int(snapshot.get("active_count", 0)) > 0
			and int(snapshot.get("ready_mismatch_count", -1)) == 0
			and int((snapshot.get("metrics", {}) as Dictionary).get("render_resources", 0)) > 0
			and int(metrics.get("coalesced_viewer_events", 0)) > 0
			and str(snapshot.get("geometry_signature", ""))
				!= "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
		),
		"submitted_updates": (order_value as Array).size() + 1,
		"accepted_updates": accepted,
		"viewer_drain_submitted": drain_submitted,
		"viewer_drain_completed": drain_completed,
		"settlement_frames": int(settlement.get("frames", -1)),
		"elapsed_usec": int(settlement.get("elapsed_usec", -1)),
		"total_elapsed_usec": Time.get_ticks_usec() - replay_started,
		"coalesced_viewer_events": int(metrics.get("coalesced_viewer_events", 0)),
		"stale_revision_submitted": stale_submitted,
		"stale_revision_rejected": stale_rejected,
		"snapshot": snapshot,
		"shutdown": shutdown,
	}
	harness.dispose()
	harness.queue_free()
	await get_tree().process_frame
	Harness.remove_tree(root)
	return result


static func _native_actions(native: Dictionary, standard: Dictionary) -> Dictionary:
	var valid := _native_evidence_valid(native, standard)
	return {
		"native_randomized_completion_orders": _status(valid),
		"native_cancellation_and_replacement": _status(valid),
		"native_duplicate_and_stale_completion": _status(valid),
		"native_allocation_failure_controls": _status(valid),
		"native_interrupted_publication_control": _status(valid),
		"native_malformed_input_controls": _status(valid),
		"native_first_divergent_generation_trace": _status(valid),
	}


static func _native_evidence_valid(native: Dictionary, standard: Dictionary) -> bool:
	var expected: Dictionary = standard.get("stable_expected", {})
	var authority: Dictionary = native.get("authority", {})
	var method: Dictionary = native.get("method", {})
	var build_matrix: Dictionary = native.get("build_matrix", {})
	var debug_build: Dictionary = build_matrix.get("template_debug", {})
	var release_build: Dictionary = build_matrix.get("template_release", {})
	var counters: Dictionary = (native.get("summary", {}) as Dictionary).get("fixed_counters", {})
	return str(native.get("schema", "")) == "world_transvoxel.terrain_lab.fault_order_native_benchmark.v1" \
		and str(native.get("status", "")) == "PASS" \
		and int(method.get("measured_runs", 0)) >= int((standard.get("budgets", {}) as Dictionary).get("minimum_native_measured_runs", 15)) \
		and str(method.get("memory_metric", "")) == str(expected.get("memory_metric", "")) \
		and str(authority.get("git_commit", "")) == str(expected.get("upstream_commit", "")) \
		and str(authority.get("executable_sha256", "")) == str(expected.get("executable_sha256", "")) \
		and str(authority.get("release_executable_sha256", "")) == str(expected.get("release_executable_sha256", "")) \
		and str(authority.get("native_contract_hash", "")) == str(expected.get("native_contract_hash", "")) \
		and str(debug_build.get("status", "")) == "PASS" \
		and str(release_build.get("status", "")) == "PASS" \
		and str(debug_build.get("native_hash", "")) == str(expected.get("native_contract_hash", "")) \
		and str(release_build.get("native_hash", "")) == str(expected.get("native_contract_hash", "")) \
		and _fixed_counters_match(counters, expected) \
		and int(((native.get("summary", {}) as Dictionary).get("peak_working_set_bytes", {}) as Dictionary).get("worst", 0)) > 0


static func _fixed_counters_match(counters: Dictionary, expected: Dictionary) -> bool:
	for key in ["orders", "records", "stale", "cancellations", "allocation_faults", "interruption", "malformed", "first_divergence_generation"]:
		if int(counters.get(key, -1)) != int(expected.get(key, -2)):
			return false
	return str(counters.get("shutdown", "")) == str(expected.get("shutdown", ""))


static func _replays_converged(replays: Array[Dictionary]) -> bool:
	if replays.size() < 2:
		return false
	var reference: Dictionary = replays[0].get("snapshot", {})
	for index in range(1, replays.size()):
		var candidate: Dictionary = replays[index].get("snapshot", {})
		if str(candidate.get("state_signature", "")) != str(reference.get("state_signature", "")) \
				or str(candidate.get("geometry_signature", "")) != str(reference.get("geometry_signature", "")) \
				or int(candidate.get("active_count", -1)) != int(reference.get("active_count", -2)):
			return false
	return true


static func state_snapshot(terrain: Node, harness: Node) -> Dictionary:
	var state_lines: Array[String] = []
	var ready_mismatches := 0
	for value in terrain.call("query_active_chunk_states"):
		var state: RefCounted = value
		var coordinate: Vector3i = state.call("get_chunk_coordinate")
		state_lines.append("%d:%d:%d:%d" % [coordinate.x, coordinate.y, coordinate.z, int(state.call("get_lod"))])
		if not bool(state.call("is_fully_ready")):
			ready_mismatches += 1
	state_lines.sort()
	var mesh_lines: Array[String] = []
	for child in terrain.get_children():
		if child is MeshInstance3D and str(child.name).begins_with("WT_Render_"):
			mesh_lines.append(str(child.name) + ":" + harness.mesh_signature(str(child.name)))
	mesh_lines.sort()
	return {
		"active_count": state_lines.size(),
		"ready_mismatch_count": ready_mismatches,
		"state_signature": "\n".join(state_lines).sha256_text(),
		"geometry_signature": "\n".join(mesh_lines).sha256_text(),
		"metrics": selected_metrics(terrain.call("get_runtime_metrics")),
	}


static func selected_metrics(metrics: Dictionary) -> Dictionary:
	var selected := {}
	for key in [
		"active_chunk_records", "non_retiring_chunk_records", "render_resources",
		"collision_resources", "sample_jobs", "mesh_jobs", "published_events",
		"coalesced_viewer_events", "rejected_events", "stale_render_events",
		"stale_collision_events", "scheduler_queued_jobs", "scheduler_queued_completions",
		"storage_queued_requests", "storage_queued_completions", "queued_render",
		"queued_collision", "pending_chunk_replacements", "pending_chunk_retirements",
		"scheduler_failed_records", "scheduler_queue_rejections", "page_mesh_failures",
		"page_storage_failures", "world_revision",
	]:
		selected[key] = metrics.get(key, -1)
	return selected


static func runtime_overrides(profile: Dictionary) -> Dictionary:
	return {
		"active_chunk_capacity": int(profile.get("active_chunk_capacity", 256)),
		"demand_capacity_per_viewer": int(profile.get("active_chunk_capacity", 256)),
		"lod_refinement_radius_chunks": int(profile.get("lod_refinement_radius_chunks", 1)),
		"storage_request_capacity": int(profile.get("pipeline_capacity", 1024)),
		"storage_completion_capacity": int(profile.get("pipeline_capacity", 1024)),
		"encoded_page_entry_capacity": int(profile.get("page_cache_capacity", 256)),
		"decoded_page_entry_capacity": int(profile.get("page_cache_capacity", 256)),
		"mesh_entry_capacity": int(profile.get("page_cache_capacity", 256)),
		"render_entry_capacity": int(profile.get("page_cache_capacity", 256)),
		"collision_entry_capacity": int(profile.get("collision_capacity", 64)),
		"global_coarse_lod_coverage": false,
	}


static func _queues_drained(metrics: Dictionary) -> bool:
	for key in [
		"scheduler_queued_jobs", "scheduler_queued_completions", "storage_queued_requests",
		"storage_queued_completions", "queued_render", "queued_collision",
		"pending_chunk_replacements", "pending_chunk_retirements",
	]:
		if int(metrics.get(key, -1)) != 0:
			return false
	return true


func _wait_for_metric_increase(terrain: Node, key: String, previous: int, maximum_frames: int) -> bool:
	for _frame in range(maximum_frames):
		if int((terrain.call("get_runtime_metrics") as Dictionary).get(key, 0)) > previous:
			return true
		await get_tree().process_frame
	return false


func _wait_for_work_started(terrain: Node, maximum_frames: int) -> bool:
	for frame in range(maximum_frames):
		var metrics: Dictionary = terrain.call("get_runtime_metrics")
		if int(metrics.get("active_chunk_records", 0)) > 0 \
				or int(metrics.get("scheduler_queued_jobs", 0)) > 0 \
				or int(metrics.get("storage_queued_requests", 0)) > 0:
			return true
		await get_tree().process_frame
		if frame % 8 == 0:
			await get_tree().create_timer(0.001).timeout
	return false


func _wait_for_empty(terrain: Node) -> bool:
	for _frame in range(Harness.MAX_WAIT_FRAMES):
		var metrics: Dictionary = terrain.call("get_runtime_metrics")
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


static func _semantic_signature(native: Dictionary, replays: Array[Dictionary]) -> String:
	var lines: Array[String] = [
		str((native.get("authority", {}) as Dictionary).get("native_contract_hash", "")),
		str(((native.get("summary", {}) as Dictionary).get("fixed_counters", {}) as Dictionary).get("first_divergence_generation", -1)),
	]
	for replay in replays:
		var snapshot: Dictionary = replay.get("snapshot", {})
		lines.append("%s:%s" % [snapshot.get("state_signature", ""), snapshot.get("geometry_signature", "")])
	return "\n".join(lines).sha256_text()


static func vector3(value: Variant) -> Vector3:
	var values: Array = value
	return Vector3(float(values[0]), float(values[1]), float(values[2])) if values.size() == 3 else Vector3.ZERO


static func _status(value: bool) -> String:
	return "PASS" if value else "FAIL"


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
