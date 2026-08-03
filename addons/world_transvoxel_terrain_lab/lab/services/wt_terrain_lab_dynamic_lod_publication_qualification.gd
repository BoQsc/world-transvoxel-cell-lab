@tool
extends Node
class_name WtTerrainLabDynamicLodPublicationQualification

const Harness := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_runtime_harness.gd"
)
const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)

const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/dynamic_lod_publication_standard.json"
)
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/dynamic_lod_publication"
const CHUNK_CELLS := 16.0

var _terrain: Node
var _stage := "startup"
var _viewer_revision := 0
var _viewer_radius_chunks := 1
var _maximum_lod := 1
var _trace: Array[Dictionary] = []
var _frame_samples_usec: Array[float] = []
var _settlement_samples_usec: Array[float] = []
var _last_frame_usec := 0
var _audited_frame_count := 0
var _trace_limit := 4096
var _maximum_settlement_frames := 1800
var _frame_failures := {}
var _material_signatures := {}
var _material_mesh_instances := {}
var _previous_visible_keys := {}
var _split_observations := 0
var _merge_observations := 0
var _replacement_frames := 0
var _hole_frames := 0
var _render_overlap_frames := 0
var _collision_overlap_frames := 0
var _generation_incoherence_count := 0
var _material_mutation_count := 0
var _maximums := {}
var _last_publication_identity := ""
var _cached_render_overlap_count := 0
var _cached_collision_overlap_count := 0


func run() -> Dictionary:
	_reset()
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var failures: Array[String] = []
	_validate_contract(standard, failures)
	if not failures.is_empty():
		return _report(standard, [], failures, {}, {})
	var profile: Dictionary = standard.get("runtime_profile", {})
	var workload: Dictionary = standard.get("workload", {})
	_viewer_radius_chunks = int(profile.get("viewer_radius_chunks", 1))
	_maximum_lod = int(profile.get("maximum_lod", 1))
	_trace_limit = int((standard.get("budgets", {}) as Dictionary).get(
		"maximum_trace_rows", 4096
	))
	_maximum_settlement_frames = int((standard.get("budgets", {}) as Dictionary).get(
		"maximum_settlement_frames", 1800
	))
	Harness.remove_tree(RUNTIME_ROOT)
	var harness := Harness.new()
	add_child(harness)
	var overrides := {
		"active_chunk_capacity": int(profile.get("active_chunk_capacity", 512)),
		"demand_capacity_per_viewer": int(profile.get("demand_capacity_per_viewer", 1024)),
		"lod_refinement_radius_chunks": int(profile.get("lod_refinement_radius_chunks", 1)),
		"storage_request_capacity": 512,
		"storage_completion_capacity": 512,
		"encoded_page_entry_capacity": 512,
		"decoded_page_entry_capacity": 512,
		"mesh_entry_capacity": 512,
		"render_entry_capacity": 512,
		"collision_entry_capacity": 512,
		"render_transition_frames": int(profile.get("render_transition_frames", 0)),
		"shader_fade_parameter_enabled": bool(profile.get("shader_fade_parameter_enabled", false)),
		"global_coarse_lod_coverage": bool(profile.get("global_coarse_lod_coverage", false)),
	}
	if not harness.create_runtime(int(profile.get("worker_count", 2)), overrides):
		failures.append("native world-transvoxel runtime could not be created")
		return await _finish(harness, standard, [], failures, {}, {})
	_terrain = harness.terrain
	_expect(
		str(_terrain.call("get_backend_id")) == "transvoxel_mit_official"
			and str(_terrain.call("get_backend_license")) == "MIT",
		"native backend identity changed",
		failures
	)
	_start_monitoring()
	if not await _start_world(harness, profile):
		failures.append("native procedural publication world did not enter running")
		return await _finish(harness, standard, [], failures, {}, {})

	var checkpoints: Array[Dictionary] = []
	var action_status := {}
	var initial := _vector3(workload.get("initial_position", []))
	var split := _vector3(workload.get("split_position", []))
	var merge := _vector3(workload.get("merge_position", []))
	var teleport := _vector3(workload.get("teleport_position", []))
	var viewer_id := int(workload.get("viewer_id", 35))

	if not await _move_and_checkpoint(harness, viewer_id, initial, "initial_load", checkpoints):
		failures.append("initial dynamic LOD publication did not settle")
		return await _finish(harness, standard, checkpoints, failures, action_status, {})
	action_status["initial_load"] = "PASS"
	if not await _move_and_checkpoint(harness, viewer_id, split, "split_approach", checkpoints):
		failures.append("split-approach publication did not settle")
		return await _finish(harness, standard, checkpoints, failures, action_status, {})
	action_status["split_approach"] = "PASS"
	if not await _move_and_checkpoint(harness, viewer_id, merge, "merge_retreat", checkpoints):
		failures.append("merge-retreat publication did not settle")
		return await _finish(harness, standard, checkpoints, failures, action_status, {})
	action_status["merge_retreat"] = "PASS"

	_stage = "rapid_supersession"
	var rapid := await _rapid_supersession(
		harness,
		viewer_id,
		workload.get("supersession_positions", []),
		checkpoints
	)
	action_status["rapid_supersession"] = rapid.get("status", "FAIL")
	_expect(str(rapid.get("status", "")) == "PASS", "rapid supersession did not settle", failures)
	if not failures.is_empty():
		return await _finish(harness, standard, checkpoints, failures, action_status, rapid)

	_stage = "stale_revision_control"
	var stale_before := _metrics_value("rejected_events")
	var stale_submission := bool(_terrain.call(
		"update_viewer", viewer_id, maxi(0, _viewer_revision - 1), merge,
		_viewer_radius_chunks, _maximum_lod
	))
	var stale_rejected := await _wait_for_metric_increase("rejected_events", stale_before, 360)
	action_status["stale_revision_control"] = "PASS" if stale_rejected else "FAIL"
	_expect(stale_submission and stale_rejected, "stale viewer revision was not rejected asynchronously", failures)

	_stage = "presentation_origin_rebase"
	var before_rebase := _settled_snapshot("before_rebase")
	var rebase := _vector3(workload.get("presentation_rebase", []))
	_terrain.position = rebase
	for _frame in range(6):
		await get_tree().process_frame
	var after_rebase := _settled_snapshot("after_rebase")
	var rebase_stable: bool = (
		str(before_rebase.get("state_signature", ""))
			== str(after_rebase.get("state_signature", ""))
		and _terrain.position == rebase
	)
	_terrain.position = Vector3.ZERO
	action_status["presentation_origin_rebase"] = "PASS" if rebase_stable else "FAIL"
	_expect(rebase_stable, "presentation origin rebase changed native local publication state", failures)
	checkpoints.append(after_rebase)

	if not await _move_and_checkpoint(harness, viewer_id, teleport, "teleport", checkpoints):
		failures.append("teleport publication did not settle")
		return await _finish(harness, standard, checkpoints, failures, action_status, rapid)
	action_status["teleport"] = "PASS"

	_stage = "viewer_unload"
	_viewer_revision += 1
	var unload_accepted := bool(_terrain.call("remove_viewer", viewer_id, _viewer_revision))
	var unload_clean := unload_accepted and await _wait_for_empty()
	action_status["viewer_unload"] = "PASS" if unload_clean else "FAIL"
	_expect(unload_clean, "viewer unload did not drain all native resources", failures)
	checkpoints.append(_settled_snapshot("viewer_unload"))

	_stage = "world_reload"
	var stopped := await harness.stop_world()
	_expect(stopped, "dynamic publication world did not stop before reload", failures)
	_viewer_revision = 0
	var restarted := stopped and await _start_world(harness, profile)
	if restarted:
		restarted = await _move_and_checkpoint(
			harness, viewer_id, initial, "world_reload", checkpoints
		)
	action_status["world_reload"] = "PASS" if restarted else "FAIL"
	_expect(restarted, "deterministic dynamic publication world reload failed", failures)
	var initial_signature := str(checkpoints[0].get("state_signature", "")) if not checkpoints.is_empty() else ""
	var reload_signature := str(checkpoints[-1].get("state_signature", "")) if restarted else ""
	var reload_agreed := not initial_signature.is_empty() and initial_signature == reload_signature
	_expect(reload_agreed, "world reload changed the settled native mesh/material state", failures)
	return await _finish(
		harness,
		standard,
		checkpoints,
		failures,
		action_status,
		{
			"stale_submission_accepted_for_async_validation": stale_submission,
			"stale_viewer_revision_rejected": stale_rejected,
			"presentation_rebase_state_stable": rebase_stable,
			"unload_clean": unload_clean,
			"reload_signature_agreed": reload_agreed,
			"initial_state_signature": initial_signature,
			"reload_state_signature": reload_signature,
			"rapid": rapid,
		}
	)


func _rapid_supersession(
	harness: Node,
	viewer_id: int,
	positions_value: Variant,
	checkpoints: Array[Dictionary]
) -> Dictionary:
	var positions: Array = positions_value if positions_value is Array else []
	if positions.size() < 3:
		return {"status": "FAIL", "error": "supersession path is incomplete"}
	var before := _terrain.call("get_runtime_metrics") as Dictionary
	_terrain.call("set_render_apply_budget", 0)
	_terrain.call("set_collision_apply_budget", 0)
	_viewer_revision += 1
	if not bool(_terrain.call(
		"update_viewer", viewer_id, _viewer_revision, _vector3(positions[0]),
		_viewer_radius_chunks, _maximum_lod
	)):
		return {"status": "FAIL", "error": "staging viewer update was rejected"}
	var publication_queued := false
	for frame in range(360):
		await get_tree().process_frame
		var metrics := _terrain.call("get_runtime_metrics") as Dictionary
		publication_queued = (
			int(metrics.get("queued_render", 0)) > 0
			or int(metrics.get("queued_collision", 0)) > 0
			or int(metrics.get("pending_chunk_replacements", 0)) > 0
			or int(metrics.get("scheduler_queued_jobs", 0)) > 0
		)
		if publication_queued:
			break
		if frame % 8 == 0:
			await get_tree().create_timer(0.001).timeout
	for index in range(1, positions.size()):
		_viewer_revision += 1
		if not bool(_terrain.call(
			"update_viewer", viewer_id, _viewer_revision, _vector3(positions[index]),
			_viewer_radius_chunks, _maximum_lod
		)):
			_terrain.call("set_render_apply_budget", 2)
			_terrain.call("set_collision_apply_budget", 2)
			return {"status": "FAIL", "error": "superseding viewer update was rejected"}
	_terrain.call("set_render_apply_budget", 2)
	_terrain.call("set_collision_apply_budget", 2)
	var settlement := await _wait_for_settled(
		harness,
		int(before.get("viewer_updates", 0)) + 1,
		int(before.get("planned_demands", 0)) + 1
	)
	if str(settlement.get("status", "")) == "PASS":
		checkpoints.append(_settled_snapshot("rapid_supersession"))
	var after := _terrain.call("get_runtime_metrics") as Dictionary
	var stale_before := int(before.get("application_stale_render", 0)) \
		+ int(before.get("application_stale_collision", 0)) \
		+ int(before.get("page_stale_storage_completions", 0))
	var stale_after := int(after.get("application_stale_render", 0)) \
		+ int(after.get("application_stale_collision", 0)) \
		+ int(after.get("page_stale_storage_completions", 0))
	return {
		"status": settlement.get("status", "FAIL"),
		"publication_queued_before_supersession": publication_queued,
		"coalesced_viewer_events_delta": int(after.get("coalesced_viewer_events", 0))
			- int(before.get("coalesced_viewer_events", 0)),
		"stale_application_rejections_delta": stale_after - stale_before,
		"settlement": settlement,
	}


func _move_and_checkpoint(
	harness: Node,
	viewer_id: int,
	position: Vector3,
	action: String,
	checkpoints: Array[Dictionary]
) -> bool:
	_stage = action
	var before := _terrain.call("get_runtime_metrics") as Dictionary
	_viewer_revision += 1
	var accepted := bool(_terrain.call(
		"update_viewer", viewer_id, _viewer_revision, position,
		_viewer_radius_chunks, _maximum_lod
	))
	if not accepted:
		return false
	var settlement := await _wait_for_settled(
		harness,
		int(before.get("viewer_updates", 0)) + 1,
		int(before.get("planned_demands", 0)) + 1
	)
	if str(settlement.get("status", "")) != "PASS":
		return false
	checkpoints.append(_settled_snapshot(action))
	return true


func _wait_for_settled(
	harness: Node,
	minimum_viewer_updates: int = 0,
	minimum_planned_demands: int = 0
) -> Dictionary:
	var started := Time.get_ticks_usec()
	var result := {
		"status": "FAIL",
		"frames": _maximum_settlement_frames,
		"metrics": {},
	}
	for frame in range(_maximum_settlement_frames):
		var metrics := _terrain.call("get_runtime_metrics") as Dictionary
		var active := int(metrics.get("active_chunk_records", 0))
		var non_retiring := int(metrics.get("non_retiring_chunk_records", active))
		var ready := int(metrics.get("non_retiring_fully_ready_chunk_records", 0))
		if int(metrics.get("viewer_updates", 0)) >= minimum_viewer_updates \
				and int(metrics.get("planned_demands", 0)) >= minimum_planned_demands \
				and active >= 1 and ready == non_retiring \
				and int(metrics.get("scheduler_queued_jobs", -1)) == 0 \
				and int(metrics.get("scheduler_queued_completions", -1)) == 0 \
				and int(metrics.get("storage_queued_requests", -1)) == 0 \
				and int(metrics.get("storage_queued_completions", -1)) == 0 \
				and int(metrics.get("queued_render", -1)) == 0 \
				and int(metrics.get("queued_collision", -1)) == 0 \
				and int(metrics.get("pending_chunk_replacements", -1)) == 0 \
				and int(metrics.get("pending_chunk_retirements", -1)) == 0 \
				and int(metrics.get("blocked_pending_chunk_replacements", -1)) == 0 \
				and int(metrics.get("staged_render_resources", -1)) == 0 \
				and int(metrics.get("staged_collision_resources", -1)) == 0:
			result = {
				"status": "PASS",
				"frames": frame,
				"metrics": metrics,
			}
			break
		await get_tree().process_frame
		if frame % 8 == 0:
			await get_tree().create_timer(0.001).timeout
		if frame > 0 and frame % 300 == 0 \
				and "--trace-progress" in OS.get_cmdline_user_args():
			print("TQP35_PROGRESS %s frame=%d metrics=%s" % [
				_stage,
				frame,
				JSON.stringify(_metric_subset(metrics)),
			])
	if str(result.get("status", "")) != "PASS":
		result["metrics"] = _terrain.call("get_runtime_metrics")
	result["elapsed_usec"] = Time.get_ticks_usec() - started
	_settlement_samples_usec.append(float(Time.get_ticks_usec() - started))
	return result


func _wait_for_empty() -> bool:
	for frame in range(Harness.MAX_WAIT_FRAMES):
		var metrics := _terrain.call("get_runtime_metrics") as Dictionary
		if int(metrics.get("active_chunk_records", -1)) == 0 \
				and int(metrics.get("render_resources", -1)) == 0 \
				and int(metrics.get("collision_resources", -1)) == 0 \
				and int(metrics.get("queued_render", -1)) == 0 \
				and int(metrics.get("queued_collision", -1)) == 0 \
				and int(metrics.get("pending_chunk_retirements", -1)) == 0 \
				and int(metrics.get("pending_chunk_replacements", -1)) == 0:
			return true
		await get_tree().process_frame
		if frame % 8 == 0:
			await get_tree().create_timer(0.001).timeout
	return false


func _wait_for_metric_increase(metric: String, before: int, maximum_frames: int) -> bool:
	for frame in range(maximum_frames):
		await get_tree().process_frame
		if _metrics_value(metric) > before:
			return true
		if frame % 8 == 0:
			await get_tree().create_timer(0.001).timeout
	return false


func _start_world(harness: Node, profile: Dictionary) -> bool:
	var volume: Array = profile.get("volume_chunks", [])
	if volume.size() != 3:
		return false
	return await harness.start_procedural_world_preset(
		RUNTIME_ROOT + "/source",
		int(profile.get("source_revision", 0)),
		int(profile.get("seed", 0)),
		str(profile.get("preset", "")),
		int(volume[0]),
		int(volume[1]),
		int(profile.get("vertical_chunk_origin", 0)),
		int(volume[2])
	)


func _settled_snapshot(action: String) -> Dictionary:
	var nodes := _publication_nodes(true)
	var metrics := _terrain.call("get_runtime_metrics") as Dictionary
	var rows: Array[String] = []
	var mesh_lines: Array[String] = []
	var material_lines: Array[String] = []
	var lod_histogram := {}
	for record_value in nodes.get("render", []):
		var record: Dictionary = record_value
		var key := str(record.get("id", ""))
		var mesh_signature := _mesh_signature(record.get("node"))
		var material_signature := _material_signature(record.get("node"))
		rows.append("%s:%s:%s" % [key, mesh_signature, material_signature])
		mesh_lines.append(key + ":" + mesh_signature)
		material_lines.append(key + ":" + material_signature)
		var lod := str(int(record.get("lod", 0)))
		lod_histogram[lod] = int(lod_histogram.get(lod, 0)) + 1
	rows.sort()
	mesh_lines.sort()
	material_lines.sort()
	return {
		"action": action,
		"state_signature": "\n".join(rows).sha256_text(),
		"mesh_signature": "\n".join(mesh_lines).sha256_text(),
		"material_signature": "\n".join(material_lines).sha256_text(),
		"render_key_signature": str(nodes.get("render_key_signature", "")),
		"collision_key_signature": str(nodes.get("collision_key_signature", "")),
		"render_keys": nodes.get("render_ids", []),
		"collision_keys": nodes.get("collision_ids", []),
		"lod_histogram": lod_histogram,
		"metrics": _metric_subset(metrics),
	}


func _start_monitoring() -> void:
	_last_frame_usec = Time.get_ticks_usec()
	var callback := Callable(self, "_record_frame")
	if not get_tree().process_frame.is_connected(callback):
		get_tree().process_frame.connect(callback)


func _stop_monitoring() -> void:
	var callback := Callable(self, "_record_frame")
	if get_tree() != null and get_tree().process_frame.is_connected(callback):
		get_tree().process_frame.disconnect(callback)


func _record_frame() -> void:
	var now := Time.get_ticks_usec()
	if _last_frame_usec > 0:
		_frame_samples_usec.append(float(now - _last_frame_usec))
	_last_frame_usec = now
	if not is_instance_valid(_terrain):
		return
	_audited_frame_count += 1
	var metrics := _terrain.call("get_runtime_metrics") as Dictionary
	var nodes := _publication_nodes(false)
	var active := int(metrics.get("active_chunk_records", 0))
	var visible := int(nodes.get("visible_render_count", 0))
	var readiness_identity := "%s:%d:%d:%d:%d:%d" % [
		str(nodes.get("publication_identity", "")),
		int(metrics.get("non_retiring_chunk_records", 0)),
		int(metrics.get("non_retiring_fully_ready_chunk_records", 0)),
		int(metrics.get("pending_chunk_replacements", 0)),
		int(metrics.get("pending_chunk_retirements", 0)),
		int(metrics.get("queued_render", 0)) + int(metrics.get("queued_collision", 0)),
	]
	if readiness_identity != _last_publication_identity:
		_last_publication_identity = readiness_identity
		var render_records: Array[Dictionary] = nodes.get("render_records", [])
		var collision_records: Array[Dictionary] = nodes.get("collision_records", [])
		var visible_render: Array[Dictionary] = []
		for record in render_records:
			_audit_generation_and_material(record, true)
			if bool(record.get("visible", false)):
				visible_render.append(record)
		for record in collision_records:
			_audit_generation_and_material(record, false)
		_cached_render_overlap_count = _overlap_count(visible_render)
		_cached_collision_overlap_count = _overlap_count(collision_records)
		_observe_lod_changes(nodes.get("visible_keys", {}))
	var render_overlaps := _cached_render_overlap_count
	var collision_overlaps := _cached_collision_overlap_count
	if _stage not in ["startup", "viewer_unload", "world_reload"] \
			and not _previous_visible_keys.is_empty() and active > 0 and visible == 0:
		_hole_frames += 1
		_frame_failure("visible terrain disappeared during " + _stage)
	if render_overlaps > 0:
		_render_overlap_frames += 1
		_frame_failure("overlapping visible LOD render ownership during " + _stage)
	if collision_overlaps > 0:
		_collision_overlap_frames += 1
		_frame_failure("overlapping collision ownership during " + _stage)
	var sink_failures := int(metrics.get("application_sink_failures", 0))
	var queue_rejections := int(metrics.get("application_queue_rejections", 0)) \
		+ int(metrics.get("scheduler_queue_rejections", 0)) \
		+ int(metrics.get("storage_request_queue_rejections", 0))
	var page_failures := int(metrics.get("page_sample_failures", 0)) \
		+ int(metrics.get("page_mesh_failures", 0)) \
		+ int(metrics.get("page_storage_failures", 0)) \
		+ int(metrics.get("page_cache_failures", 0))
	if sink_failures != 0 or queue_rejections != 0 or page_failures != 0:
		_frame_failure("native publication pipeline reported a failure or capacity rejection")
	if int(metrics.get("pending_retirement_records_missing", 0)) != 0:
		_frame_failure("pending retirement lost its native record")
	if int(nodes.get("render_count", -1)) != int(metrics.get("render_resources", -2)):
		_frame_failure("render resource metrics disagree with Godot ownership")
	if int(nodes.get("collision_count", -1)) != int(metrics.get("collision_resources", -2)):
		_frame_failure("collision resource metrics disagree with Godot ownership")
	if str(_terrain.call("get_world_state_name")) == "failed":
		_frame_failure("native world entered failed state")
	if int(metrics.get("pending_chunk_replacements", 0)) > 0 \
			or int(metrics.get("pending_chunk_retirements", 0)) > 0:
		_replacement_frames += 1
	_update_maximums(metrics)
	if _trace.size() < _trace_limit:
		var row := _metric_subset(metrics)
		row["frame"] = _audited_frame_count
		row["stage"] = _stage
		row["visible_render"] = visible
		row["render_overlap"] = render_overlaps
		row["collision_overlap"] = collision_overlaps
		row["render_key_signature"] = nodes.get("render_key_signature", "")
		row["collision_key_signature"] = nodes.get("collision_key_signature", "")
		_trace.append(row)


func _publication_nodes(include_nodes: bool) -> Dictionary:
	var render: Array[Dictionary] = []
	var collision: Array[Dictionary] = []
	var render_ids: Array[String] = []
	var collision_ids: Array[String] = []
	var identity_lines: Array[String] = []
	var visible_keys := {}
	for child in _terrain.get_children():
		var name_text := str(child.name)
		if name_text.begins_with("WT_Render_") and child is MeshInstance3D:
			var key := _parse_key(name_text, "WT_Render_")
			if key.is_empty() or bool(key.get("retiring", false)):
				continue
			key["node"] = child
			key["visible"] = (child as MeshInstance3D).visible
			render.append(key)
			render_ids.append(str(key.get("id", "")))
			var mesh_id := (
				(child as MeshInstance3D).mesh.get_instance_id()
				if (child as MeshInstance3D).mesh != null else 0
			)
			identity_lines.append("r:%s:%d:%d" % [
				str(key.get("id", "")),
				1 if bool(key.get("visible", false)) else 0,
				mesh_id,
			])
			if bool(key.get("visible", false)):
				visible_keys[str(key.get("id", ""))] = key
		elif name_text.begins_with("WT_Collision_") and child is StaticBody3D:
			var key := _parse_key(name_text, "WT_Collision_")
			if key.is_empty():
				continue
			key["node"] = child
			collision.append(key)
			collision_ids.append(str(key.get("id", "")))
			var shape_node := child.get_node_or_null("Shape") as CollisionShape3D
			var shape_id := (
				shape_node.shape.get_instance_id()
				if shape_node != null and shape_node.shape != null else 0
			)
			identity_lines.append("c:%s:%d" % [str(key.get("id", "")), shape_id])
	render_ids.sort()
	collision_ids.sort()
	identity_lines.sort()
	var output := {
		"render_count": render.size(),
		"collision_count": collision.size(),
		"visible_render_count": visible_keys.size(),
		"render_ids": render_ids,
		"collision_ids": collision_ids,
		"visible_keys": visible_keys,
		"render_key_signature": "\n".join(render_ids).sha256_text(),
		"collision_key_signature": "\n".join(collision_ids).sha256_text(),
		"publication_identity": "\n".join(identity_lines).sha256_text(),
		"render_records": render,
		"collision_records": collision,
	}
	if include_nodes:
		output["render"] = render
		output["collision"] = collision
	return output


func _audit_generation_and_material(key: Dictionary, render_record: bool) -> void:
	var state: RefCounted = _terrain.call(
		"query_chunk_state",
		Vector3i(int(key.get("x", 0)), int(key.get("y", 0)), int(key.get("z", 0))),
		int(key.get("lod", 0))
	)
	if state == null or not bool(state.call("is_present")):
		_generation_incoherence_count += 1
		_frame_failure("Godot publication resource has no native chunk record")
		return
	if render_record:
		var visible := bool(key.get("visible", false))
		var generation := int(state.call("get_render_generation"))
		var staged_generation := int(state.call("get_staged_render_generation"))
		if (visible and generation <= 0) or (
				not visible and generation <= 0 and staged_generation <= 0
		):
			_generation_incoherence_count += 1
			_frame_failure("render resource generation is incoherent")
			return
		if visible:
			var identity := str(key.get("id", "")) + ":" + str(generation)
			var instance := key.get("node") as MeshInstance3D
			var mesh_instance_id := (
				instance.mesh.get_instance_id()
				if instance != null and instance.mesh != null else 0
			)
			if int(_material_mesh_instances.get(identity, -1)) != mesh_instance_id:
				var signature := _material_signature(instance)
				if _material_signatures.has(identity) \
						and str(_material_signatures[identity]) != signature:
					_material_mutation_count += 1
					_frame_failure("same-generation render material payload mutated")
				else:
					_material_signatures[identity] = signature
				_material_mesh_instances[identity] = mesh_instance_id
	else:
		if int(state.call("get_collision_generation")) <= 0:
			_generation_incoherence_count += 1
			_frame_failure("collision resource generation is incoherent")


func _observe_lod_changes(current: Dictionary) -> void:
	if _previous_visible_keys.is_empty():
		_previous_visible_keys = current.duplicate(true)
		return
	for old_id in _previous_visible_keys:
		if current.has(old_id):
			continue
		var old_key: Dictionary = _previous_visible_keys[old_id]
		for new_id in current:
			if _previous_visible_keys.has(new_id):
				continue
			var new_key: Dictionary = current[new_id]
			if int(old_key.get("lod", 0)) > int(new_key.get("lod", 0)) \
					and _contains_key(old_key, new_key):
				_split_observations += 1
			elif int(new_key.get("lod", 0)) > int(old_key.get("lod", 0)) \
					and _contains_key(new_key, old_key):
				_merge_observations += 1
	_previous_visible_keys = current.duplicate(true)


func _contains_key(coarse: Dictionary, fine: Dictionary) -> bool:
	var coarse_bounds := _key_bounds(coarse)
	var fine_bounds := _key_bounds(fine)
	return coarse_bounds.encloses(fine_bounds)


func _overlap_count(records: Array[Dictionary]) -> int:
	var count := 0
	for first_index in range(records.size()):
		var first := _key_bounds(records[first_index])
		for second_index in range(first_index + 1, records.size()):
			var second := _key_bounds(records[second_index])
			var intersection := first.intersection(second)
			if intersection.size.x > 0.0001 \
					and intersection.size.y > 0.0001 \
					and intersection.size.z > 0.0001:
				count += 1
	return count


func _key_bounds(key: Dictionary) -> AABB:
	var extent := CHUNK_CELLS * float(1 << int(key.get("lod", 0)))
	return AABB(
		Vector3(
			float(key.get("x", 0)) * extent,
			float(key.get("y", 0)) * extent,
			float(key.get("z", 0)) * extent
		),
		Vector3.ONE * extent
	)


func _parse_key(node_name: String, prefix: String) -> Dictionary:
	var body := node_name.trim_prefix(prefix)
	var retiring := body.contains("_retiring_")
	if retiring:
		body = body.get_slice("_retiring_", 0)
	var parts := body.split("_")
	if parts.size() != 4 or not parts[3].begins_with("L"):
		return {}
	var x := int(parts[0])
	var y := int(parts[1])
	var z := int(parts[2])
	var lod := int(parts[3].trim_prefix("L"))
	return {
		"id": "%d,%d,%d,L%d" % [x, y, z, lod],
		"x": x,
		"y": y,
		"z": z,
		"lod": lod,
		"retiring": retiring,
	}


func _mesh_signature(node_value: Variant) -> String:
	if not node_value is MeshInstance3D:
		return "EMPTY"
	var instance := node_value as MeshInstance3D
	if instance.mesh == null:
		return "EMPTY"
	var lines: Array[String] = []
	for surface in range(instance.mesh.get_surface_count()):
		var arrays := instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		lines.append("s:%d:%d:%d" % [surface, vertices.size(), indices.size()])
		for vertex in vertices:
			lines.append("v:%d,%d,%d" % [
				roundi(vertex.x * 1000000.0),
				roundi(vertex.y * 1000000.0),
				roundi(vertex.z * 1000000.0),
			])
		for index_value in indices:
			lines.append("i:%d" % int(index_value))
	return "\n".join(lines).sha256_text()


func _material_signature(node_value: Variant) -> String:
	if not node_value is MeshInstance3D:
		return "EMPTY"
	var instance := node_value as MeshInstance3D
	if instance.mesh == null:
		return "EMPTY"
	var lines: Array[String] = []
	for surface in range(instance.mesh.get_surface_count()):
		var arrays := instance.mesh.surface_get_arrays(surface)
		var material_data: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		lines.append("s:%d:%d" % [surface, material_data.size()])
		for material in material_data:
			lines.append("m:%d,%d" % [roundi(material.x), roundi(material.y)])
	return "\n".join(lines).sha256_text()


func _finish(
	harness: Node,
	standard: Dictionary,
	checkpoints: Array[Dictionary],
	failures: Array[String],
	action_status: Dictionary,
	controls: Dictionary
) -> Dictionary:
	_stop_monitoring()
	for failure in _frame_failures:
		failures.append(str(failure))
	var final_metrics := {}
	if is_instance_valid(_terrain):
		final_metrics = _terrain.call("get_runtime_metrics")
	var report := _report(standard, checkpoints, failures, action_status, controls)
	report["runtime_metrics"] = final_metrics
	_validate_result(report, standard, failures)
	report["status"] = "PASS" if failures.is_empty() else "FAIL"
	report["failures"] = failures
	if harness != null and harness.terrain != null:
		if str(harness.terrain.call("get_world_state_name")) != "stopped":
			await harness.stop_world()
		harness.dispose()
		harness.queue_free()
		await get_tree().process_frame
	Harness.remove_tree(RUNTIME_ROOT)
	_terrain = null
	return report


func _report(
	standard: Dictionary,
	checkpoints: Array[Dictionary],
	failures: Array[String],
	action_status: Dictionary,
	controls: Dictionary
) -> Dictionary:
	var checkpoint_lines: Array[String] = []
	for checkpoint_value in checkpoints:
		var checkpoint: Dictionary = checkpoint_value
		checkpoint_lines.append("%s:%s" % [
			str(checkpoint.get("action", "")),
			str(checkpoint.get("state_signature", "")),
		])
	var rapid: Dictionary = controls.get("rapid", {})
	return {
		"schema": "world_transvoxel.terrain_lab.dynamic_lod_publication_qualification.v1",
		"milestone": "TQP-35",
		"standard_id": standard.get("standard_id", ""),
		"authority": standard.get("authority", ""),
		"status": "FAIL" if not failures.is_empty() else "PENDING_BUDGET_EVALUATION",
		"retained_complete": true,
		"provenance": Statistics.provenance("tqp35_dynamic_lod_publication_windows_v1"),
		"coverage": {
			"actions": action_status,
			"audited_frame_count": _audited_frame_count,
			"retained_trace_rows": _trace.size(),
			"split_observations": _split_observations,
			"merge_observations": _merge_observations,
			"replacement_frames": _replacement_frames,
			"transition_mesh_completions": int(_maximums.get("maximum_transition_mesh_completions", 0)),
			"coalesced_viewer_events": int(rapid.get("coalesced_viewer_events_delta", 0)),
			"stale_application_rejections": int(rapid.get("stale_application_rejections_delta", 0)),
			"stale_viewer_revision_rejected": controls.get("stale_viewer_revision_rejected", false),
			"presentation_rebase_state_stable": controls.get("presentation_rebase_state_stable", false),
			"unload_clean": controls.get("unload_clean", false),
			"reload_signature_agreed": controls.get("reload_signature_agreed", false),
		},
		"temporal_invariants": {
			"visible_hole_frames": _hole_frames,
			"render_overlap_frames": _render_overlap_frames,
			"double_collision_frames": _collision_overlap_frames,
			"generation_incoherence_count": _generation_incoherence_count,
			"same_generation_material_mutation_count": _material_mutation_count,
			"frame_failure_count": _frame_failures.size(),
		},
		"checkpoints": checkpoints,
		"checkpoint_matrix_signature": "\n".join(checkpoint_lines).sha256_text(),
		"reload_state_signature": controls.get("reload_state_signature", ""),
		"frame_trace": _trace,
		"performance": {
			"frame": Statistics.distribution(_frame_samples_usec),
			"action_settlement": Statistics.distribution(_settlement_samples_usec),
			"memory": Statistics.memory_metrics(),
			"scope": "WINDOWS_DEBUG_DIAGNOSTIC_PUBLICATION_OBSERVATION_NOT_PRODUCTION_FRAME_BUDGET",
		},
		"resources": _maximums,
		"controls": controls,
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


func _validate_result(report: Dictionary, standard: Dictionary, failures: Array[String]) -> void:
	var workload: Dictionary = standard.get("workload", {})
	var coverage: Dictionary = report.get("coverage", {})
	var invariants: Dictionary = report.get("temporal_invariants", {})
	var budgets: Dictionary = standard.get("budgets", {})
	var actions: Dictionary = coverage.get("actions", {})
	for action_value in workload.get("required_actions", []):
		var action := str(action_value)
		_expect(str(actions.get(action, "")) == "PASS", "required action failed: " + action, failures)
	_expect(int(coverage.get("split_observations", 0)) > 0, "no parent-to-child split publication was observed", failures)
	_expect(int(coverage.get("merge_observations", 0)) > 0, "no child-to-parent merge publication was observed", failures)
	_expect(int(coverage.get("replacement_frames", 0)) > 0, "no staged replacement frame was observed", failures)
	_expect(int(coverage.get("transition_mesh_completions", 0)) > 0, "no native transition mesh completion was observed", failures)
	_expect(int(coverage.get("coalesced_viewer_events", 0)) > 0, "rapid viewer events were not coalesced", failures)
	_expect(int(coverage.get("stale_application_rejections", 0)) > 0, "no stale dynamic publication result was rejected", failures)
	_expect(bool(coverage.get("stale_viewer_revision_rejected", false)), "stale viewer revision control failed", failures)
	_expect(bool(coverage.get("presentation_rebase_state_stable", false)), "presentation rebase control failed", failures)
	_expect(bool(coverage.get("unload_clean", false)), "viewer unload control failed", failures)
	_expect(bool(coverage.get("reload_signature_agreed", false)), "world reload state differs", failures)
	for key in [
		"visible_hole_frames",
		"render_overlap_frames",
		"double_collision_frames",
		"generation_incoherence_count",
		"same_generation_material_mutation_count",
		"frame_failure_count",
	]:
		_expect(int(invariants.get(key, -1)) == 0, "temporal invariant failed: " + key, failures)
	var performance: Dictionary = report.get("performance", {})
	var frame: Dictionary = performance.get("frame", {})
	var settlement: Dictionary = performance.get("action_settlement", {})
	_expect(float(frame.get("p99_usec", INF)) <= float(budgets.get("maximum_frame_p99_usec", 0.0)), "frame p99 ceiling exceeded", failures)
	_expect(float(frame.get("worst_usec", INF)) <= float(budgets.get("maximum_frame_usec", 0.0)), "maximum frame ceiling exceeded", failures)
	_expect(float(settlement.get("p95_usec", INF)) <= float(budgets.get("maximum_action_settlement_p95_usec", 0.0)), "action settlement p95 ceiling exceeded", failures)
	var metrics: Dictionary = report.get("runtime_metrics", {})
	_expect(int(metrics.get("render_latency_frames_maximum", 0)) <= int(budgets.get("maximum_render_latency_frames", 0)), "render latency frame ceiling exceeded", failures)
	_expect(int(metrics.get("collision_latency_frames_maximum", 0)) <= int(budgets.get("maximum_collision_latency_frames", 0)), "collision latency frame ceiling exceeded", failures)
	for pair in [
		["maximum_active_chunk_records", "maximum_active_chunk_records"],
		["maximum_render_resources", "maximum_render_resources"],
		["maximum_collision_resources", "maximum_collision_resources"],
		["maximum_render_queue", "maximum_render_queue"],
		["maximum_collision_queue", "maximum_collision_queue"],
	]:
		_expect(int(_maximums.get(pair[0], 0)) <= int(budgets.get(pair[1], -1)), str(pair[0]) + " ceiling exceeded", failures)


func _update_maximums(metrics: Dictionary) -> void:
	for pair in [
		["maximum_active_chunk_records", "active_chunk_records"],
		["maximum_render_resources", "render_resources"],
		["maximum_collision_resources", "collision_resources"],
		["maximum_render_queue", "queued_render"],
		["maximum_collision_queue", "queued_collision"],
		["maximum_transition_mesh_completions", "transition_mesh_completions"],
	]:
		_maximums[pair[0]] = maxi(
			int(_maximums.get(pair[0], 0)), int(metrics.get(pair[1], 0))
		)


func _metric_subset(metrics: Dictionary) -> Dictionary:
	var output := {}
	for key in [
		"active_chunk_records",
		"non_retiring_chunk_records",
		"non_retiring_fully_ready_chunk_records",
		"render_resources",
		"staged_render_resources",
		"staged_collision_resources",
		"collision_resources",
		"scheduler_queued_jobs",
		"scheduler_queued_completions",
		"storage_queued_requests",
		"storage_queued_completions",
		"queued_render",
		"queued_collision",
		"pending_chunk_replacements",
		"pending_chunk_retirements",
		"blocked_pending_chunk_replacements",
		"transition_mesh_completions",
		"coalesced_viewer_events",
		"rejected_events",
		"application_stale_render",
		"application_stale_collision",
		"page_stale_storage_completions",
	]:
		output[key] = int(metrics.get(key, 0))
	return output


func _metrics_value(key: String) -> int:
	if not is_instance_valid(_terrain):
		return 0
	return int((_terrain.call("get_runtime_metrics") as Dictionary).get(key, 0))


func _frame_failure(message: String) -> void:
	_frame_failures[message] = true


func _reset() -> void:
	_terrain = null
	_stage = "startup"
	_viewer_revision = 0
	_viewer_radius_chunks = 1
	_maximum_lod = 1
	_trace.clear()
	_frame_samples_usec.clear()
	_settlement_samples_usec.clear()
	_last_frame_usec = 0
	_audited_frame_count = 0
	_frame_failures.clear()
	_material_signatures.clear()
	_material_mesh_instances.clear()
	_previous_visible_keys.clear()
	_split_observations = 0
	_merge_observations = 0
	_replacement_frames = 0
	_hole_frames = 0
	_render_overlap_frames = 0
	_collision_overlap_frames = 0
	_generation_incoherence_count = 0
	_material_mutation_count = 0
	_maximums = {
		"maximum_active_chunk_records": 0,
		"maximum_render_resources": 0,
		"maximum_collision_resources": 0,
		"maximum_render_queue": 0,
		"maximum_collision_queue": 0,
		"maximum_transition_mesh_completions": 0,
	}
	_last_publication_identity = ""
	_cached_render_overlap_count = 0
	_cached_collision_overlap_count = 0


static func _vector3(value: Variant) -> Vector3:
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


static func _validate_contract(standard: Dictionary, failures: Array[String]) -> void:
	_expect(str(standard.get("schema", "")) == "world_transvoxel.terrain_lab.dynamic_lod_publication_standard.v1", "dynamic publication standard is missing", failures)
	_expect(str(standard.get("milestone", "")) == "TQP-35", "dynamic publication milestone changed", failures)
	_expect(str(standard.get("authority", "")) == "world_transvoxel_native_runtime", "dynamic publication authority changed", failures)
	var profile: Dictionary = standard.get("runtime_profile", {})
	_expect(int(profile.get("worker_count", 0)) >= 2, "dynamic publication requires concurrent native workers", failures)
	_expect(int(profile.get("maximum_lod", 0)) >= 1, "dynamic publication requires at least two LOD levels", failures)
	_expect(int(profile.get("render_transition_frames", -1)) == 0, "atomic publication profile must disable crossfade overlap", failures)


static func _expect(condition: bool, failure: String, failures: Array[String]) -> void:
	if not condition and failure not in failures:
		failures.append(failure)
