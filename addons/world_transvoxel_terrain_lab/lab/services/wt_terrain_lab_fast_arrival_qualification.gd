@tool
extends Node
class_name WtTerrainLabFastArrivalQualification

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
	"res://addons/world_transvoxel_terrain_lab/standards/fast_arrival_responsiveness_standard.json"
)
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/tqp45_fast_arrival"
const EMPTY_SIGNATURE := "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
const MAX_LATENCY_FRAMES := 720

var _harness: Node
var _terrain: Node
var _profile := {}
var _viewer_revision := 0
var _collision_revision := 0
var _queue_peaks := {
	"scheduler": 0,
	"render": 0,
	"collision": 0,
	"storage": 0,
}


func run() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var workload: Dictionary = standard.get("workload", {})
	var failures: Array[String] = []
	_profile = standard.get("runtime_profile", {})
	_validate_native_authority(standard, failures)
	Harness.remove_tree(RUNTIME_ROOT)
	_harness = Harness.new()
	add_child(_harness)
	if not _harness.create_runtime(
		int(_profile.get("worker_count", 2)), _runtime_overrides()
	):
		failures.append("native runtime unavailable")
		return await _finish(standard, [], {}, failures)
	_terrain = _harness.terrain
	if not await _start_world():
		failures.append("native procedural world did not start")
		return await _finish(standard, [], {}, failures)

	var cold: Array[Dictionary] = []
	for value in workload.get("cold_positions", []):
		var sample := await _measure_arrival("cold", _vector3(value))
		cold.append(sample)
		print("TQP45 cold " + str(sample.get("status", "")))
		if str(sample.get("status", "")) != "PASS":
			failures.append("cold arrival failed before corpus completion")
			return await _finish(standard, [cold], {
				"groups": {"cold": cold},
				"distributions": _distributions({"cold": cold}),
				"generation_agreement": _generation_agreement(),
			}, failures)
	var warm: Array[Dictionary] = []
	for value in workload.get("cold_positions", []):
		var sample := await _measure_arrival("warm", _vector3(value))
		warm.append(sample)
		print("TQP45 warm " + str(sample.get("status", "")))
	var edits: Array[Dictionary] = []
	for scenario_value in workload.get("edit_scenarios", []):
		var scenario: Dictionary = scenario_value
		var position := _vector3(scenario.get("viewer_position", []))
		var arrival := await _measure_arrival("edit_prefetch", position)
		if str(arrival.get("status", "")) != "PASS":
			failures.append("edit prefetch failed: " + str(scenario.get("id", "")))
			continue
		var sample := await _measure_edit(scenario)
		edits.append(sample)
		print("TQP45 edit %s %s" % [str(scenario.get("id", "")), str(sample.get("status", ""))])
	var evicted: Array[Dictionary] = []
	var eviction_moves: Array[Dictionary] = []
	for value in workload.get("cold_positions", []):
		var target := _vector3(value)
		var away := await _measure_arrival(
			"eviction_move", _vector3(workload.get("eviction_position", []))
		)
		eviction_moves.append(away)
		if str(away.get("status", "")) != "PASS":
			failures.append("eviction move did not settle")
			continue
		var sample := await _measure_arrival("previously_evicted", target)
		evicted.append(sample)
		print("TQP45 evicted " + str(sample.get("status", "")))
	var supersession := await _measure_supersession(workload)
	for group in [cold, warm, edits, evicted]:
		for sample in group:
			if str(sample.get("status", "")) != "PASS":
				failures.append("latency sample failed: " + str(sample.get("id", sample.get("class", ""))))
	_expect(str(supersession.get("status", "")) == "PASS", "distant-work supersession failed", failures)
	var groups := {
		"cold": cold,
		"warm": warm,
		"edited": edits,
		"previously_evicted": evicted,
	}
	var distributions := _distributions(groups)
	_evaluate(standard, groups, distributions, supersession, failures)
	return await _finish(standard, groups.values(), {
		"groups": groups,
		"distributions": distributions,
		"eviction_moves": eviction_moves,
		"supersession": supersession,
	}, failures)


func _start_world() -> bool:
	return await _harness.start_procedural_world_preset(
		RUNTIME_ROOT,
		int(_profile.get("source_revision", 945001)),
		int(_profile.get("seed", 450045)),
		str(_profile.get("preset", "rolling_hills_cave")),
		int((_profile.get("volume_chunks", []) as Array)[0]),
		int((_profile.get("volume_chunks", []) as Array)[1]),
		int(_profile.get("vertical_chunk_origin", -2)),
		int((_profile.get("volume_chunks", []) as Array)[2])
	)


func _measure_arrival(sample_class: String, position: Vector3) -> Dictionary:
	_viewer_revision += 1
	_collision_revision += 1
	var before_metrics: Dictionary = _terrain.call("get_runtime_metrics")
	var started := Time.get_ticks_usec()
	var accepted := bool(_terrain.call(
		"update_viewer", int(_profile.get("viewer_id", 450)), _viewer_revision,
		position, int(_profile.get("viewer_radius_chunks", 1)),
		int(_profile.get("maximum_lod", 1))
	)) and bool(_terrain.call(
		"update_collision_viewer", int(_profile.get("collision_viewer_id", 451)),
		_collision_revision, position, int(_profile.get("collision_radius_chunks", 1))
	))
	var acknowledged := Time.get_ticks_usec()
	var target := _chunk_at(position)
	var first_visual := -1
	var collision_ready := -1
	var settlement := -1
	var readiness := {"visual_leaf": {}, "collision_leaf": {}}
	var event_observed := false
	for frame in range(MAX_LATENCY_FRAMES):
		var now := Time.get_ticks_usec()
		var metrics: Dictionary = _terrain.call("get_runtime_metrics")
		_observe_queues(metrics)
		event_observed = (
			int(metrics.get("viewer_updates", 0)) > int(before_metrics.get("viewer_updates", 0))
			and int(metrics.get("collision_viewer_updates", 0))
				> int(before_metrics.get("collision_viewer_updates", 0))
		)
		if not event_observed:
			await get_tree().process_frame
			continue
		var visual_state: RefCounted = _find_covering_state(position, false)
		var collision_state: RefCounted = _find_covering_state(position, true)
		if visual_state != null:
			if first_visual < 0 and _has_current_visual(visual_state):
				first_visual = now - started
				readiness["visual_leaf"] = _readiness(visual_state)
		if collision_state != null:
			if collision_ready < 0 and _has_current_collision(collision_state):
				collision_ready = now - started
				readiness["collision_leaf"] = _readiness(collision_state)
		if event_observed and first_visual >= 0 and collision_ready >= 0 and _is_settled(metrics):
			settlement = now - started
			break
		await get_tree().process_frame
	return {
		"class": sample_class,
		"status": "PASS" if accepted and event_observed and first_visual >= 0 and collision_ready >= 0 and settlement >= 0 else "FAIL",
		"position": position,
		"target_chunk": target,
		"input_acknowledgement_usec": acknowledged - started,
		"first_correct_visual_usec": first_visual,
		"collision_coherence_usec": collision_ready,
		"local_settlement_usec": settlement,
		"event_observed": event_observed,
		"readiness": readiness,
		"generation_agreement": _generation_agreement(),
	}


func _measure_edit(scenario: Dictionary) -> Dictionary:
	var center := _vector3(scenario.get("center", []))
	var target := _chunk_at(center)
	var before_metrics: Dictionary = _terrain.call("get_runtime_metrics")
	var before_state: RefCounted = _find_covering_state(center, false)
	var previous_generation := int(before_state.call("get_generation")) \
		if before_state != null else 0
	var before_sample: Dictionary = await _harness.request_sample(Vector3i(center))
	var expected_revision := int(_terrain.call("get_world_revision")) + 1
	var transaction: RefCounted = _terrain.call("begin_edit_transaction", 4500 + expected_revision)
	var command_accepted := transaction != null and _append_edit(transaction, scenario)
	var started := Time.get_ticks_usec()
	var commit_accepted := command_accepted and bool(_terrain.call("commit_edit_transaction", transaction))
	var acknowledged := Time.get_ticks_usec()
	var first_visual := -1
	var collision_ready := -1
	var settlement := -1
	var readiness := {"visual_leaf": {}, "collision_leaf": {}}
	for _frame in range(MAX_LATENCY_FRAMES):
		var now := Time.get_ticks_usec()
		var metrics: Dictionary = _terrain.call("get_runtime_metrics")
		_observe_queues(metrics)
		var visual_state: RefCounted = _find_covering_state(center, false)
		if first_visual < 0 and visual_state != null \
				and int(visual_state.call("get_generation")) > previous_generation \
				and _has_current_visual(visual_state):
			first_visual = now - started
			readiness["visual_leaf"] = _readiness(visual_state)
		var collision_state: RefCounted = _find_covering_state(center, true)
		if collision_ready < 0 and collision_state != null \
				and int(collision_state.call("get_generation")) > previous_generation \
				and _has_current_collision(collision_state):
			collision_ready = now - started
			readiness["collision_leaf"] = _readiness(collision_state)
		if int(_terrain.call("get_world_revision")) >= expected_revision \
				and first_visual >= 0 and collision_ready >= 0 and _is_settled(metrics):
			settlement = now - started
			break
		await get_tree().process_frame
	var after_sample: Dictionary = await _harness.request_sample(Vector3i(center))
	var changed := str(after_sample.get("status", "")) == "PASS" \
		and float(after_sample.get("density", 0.0)) != float(before_sample.get("density", 0.0))
	if str(scenario.get("kind", "")) == "construct":
		changed = changed and int(after_sample.get("material", -1)) == int(scenario.get("material", -2))
	return {
		"id": scenario.get("id", ""),
		"class": "edited",
		"kind": scenario.get("kind", ""),
		"status": "PASS" if commit_accepted and changed and settlement >= 0 else "FAIL",
		"position": scenario.get("viewer_position", []),
		"target_chunk": target,
		"input_acknowledgement_usec": acknowledged - started,
		"first_correct_visual_usec": first_visual,
		"collision_coherence_usec": collision_ready,
		"local_settlement_usec": settlement,
		"world_revision": int(_terrain.call("get_world_revision")),
		"before_sample": before_sample,
		"after_sample": after_sample,
		"readiness": readiness,
		"generation_agreement": _generation_agreement(),
	}


func _measure_supersession(workload: Dictionary) -> Dictionary:
	var destination := _vector3(workload.get("supersession_destination", []))
	var baseline := await _measure_arrival("supersession_baseline_local", destination)
	var baseline_demand := _required_demand_signature()
	var before: Dictionary = _terrain.call("get_runtime_metrics")
	var accepted := 0
	for value in workload.get("supersession_positions", []):
		_viewer_revision += 1
		if bool(_terrain.call(
			"update_viewer", int(_profile.get("viewer_id", 450)), _viewer_revision,
			_vector3(value), int(_profile.get("viewer_radius_chunks", 1)),
			int(_profile.get("maximum_lod", 1))
		)):
			accepted += 1
	var result := await _measure_arrival("supersession_current_local", destination)
	var after: Dictionary = _terrain.call("get_runtime_metrics")
	var final_demand := _required_demand_signature()
	var demand_identity := baseline_demand == final_demand
	var coalesced_delta := int(after.get("coalesced_viewer_events", 0)) \
		- int(before.get("coalesced_viewer_events", 0))
	return {
		"status": "PASS" if str(baseline.get("status", "")) == "PASS" \
			and str(result.get("status", "")) == "PASS" \
			and accepted == (workload.get("supersession_positions", []) as Array).size() \
			and coalesced_delta > 0 and demand_identity else "FAIL",
		"submitted_obsolete_updates": (workload.get("supersession_positions", []) as Array).size(),
		"accepted_obsolete_updates": accepted,
		"coalesced_event_delta": coalesced_delta,
		"final_demand_matches_canonical_baseline": demand_identity,
		"baseline_demand": baseline_demand,
		"final_demand": final_demand,
		"baseline_local": baseline,
		"current_local": result,
		"before_metrics": _selected_metrics(before),
		"after_metrics": _selected_metrics(after),
	}


func _required_demand_signature() -> Dictionary:
	var visual: Array[String] = []
	var collision: Array[String] = []
	for state_value in _terrain.call("query_active_chunk_states"):
		var state: RefCounted = state_value
		if not bool(state.call("is_present")):
			continue
		var key := "%s@%d" % [str(state.call("get_chunk_coordinate")), int(state.call("get_lod"))]
		if bool(state.call("is_visual_required")):
			visual.append(key)
		if bool(state.call("is_collision_required")):
			collision.append(key)
	visual.sort()
	collision.sort()
	return {
		"visual_count": visual.size(),
		"collision_count": collision.size(),
		"visual_hash": "\n".join(visual).sha256_text(),
		"collision_hash": "\n".join(collision).sha256_text(),
	}


func _finish(
	standard: Dictionary,
	_groups: Variant,
	payload: Dictionary,
	failures: Array[String]
) -> Dictionary:
	var final_metrics := _terrain.call("get_runtime_metrics") as Dictionary if is_instance_valid(_terrain) else {}
	var geometry_signature := _geometry_signature()
	var stopped := true
	if is_instance_valid(_harness) and is_instance_valid(_terrain):
		stopped = await _harness.stop_world()
		_harness.dispose()
		_harness.queue_free()
		await get_tree().process_frame
	Harness.remove_tree(RUNTIME_ROOT)
	_expect(stopped, "native runtime did not stop cleanly", failures)
	var report := {
		"schema": "world_transvoxel.terrain_lab.fast_arrival_responsiveness_qualification.v1",
		"milestone": "TQP-45",
		"standard_id": standard.get("standard_id", ""),
		"authority": standard.get("authority", ""),
		"status": "PASS" if failures.is_empty() else "FAIL",
		"retained_complete": failures.is_empty(),
		"provenance": Statistics.provenance("tqp45_native_fast_arrival_windows_v1"),
		"demand_classes": (standard.get("workload", {}) as Dictionary).get("required_demand_classes", []),
		"latency_stages": (standard.get("workload", {}) as Dictionary).get("required_latency_stages", []),
		"queue_peaks": _queue_peaks,
		"memory": Statistics.memory_metrics(),
		"geometry_signature_hash": geometry_signature,
		"final_metrics": _selected_metrics(final_metrics),
		"shutdown": "PASS" if stopped else "FAIL",
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}
	for key in payload:
		report[key] = payload[key]
	return report


static func _distributions(groups: Dictionary) -> Dictionary:
	var output := {}
	for group_name in groups:
		var samples: Array = groups[group_name]
		var stage_output := {}
		for stage in [
			"input_acknowledgement_usec", "first_correct_visual_usec",
			"collision_coherence_usec", "local_settlement_usec",
		]:
			var values: Array[float] = []
			for sample_value in samples:
				var sample: Dictionary = sample_value
				if float(sample.get(stage, -1.0)) >= 0.0:
					values.append(float(sample.get(stage, 0.0)))
			stage_output[stage.trim_suffix("_usec")] = Statistics.distribution(values)
		output[group_name] = stage_output
	return output


static func _evaluate(
	standard: Dictionary,
	groups: Dictionary,
	distributions: Dictionary,
	supersession: Dictionary,
	failures: Array[String]
) -> void:
	var budgets: Dictionary = standard.get("budgets", {})
	for group_name in ["cold", "warm", "previously_evicted"]:
		_expect(
			(groups.get(group_name, []) as Array).size()
				>= int(budgets.get("minimum_samples_per_arrival_class", 4)),
			"insufficient samples for " + group_name, failures
		)
	_expect(
		(groups.get("edited", []) as Array).size() >= int(budgets.get("minimum_edit_samples", 6)),
		"insufficient edited samples", failures
	)
	for group_name in distributions:
		var group: Dictionary = distributions[group_name]
		for pair in [
			["input_acknowledgement", "maximum_input_acknowledgement_p99_usec"],
			["first_correct_visual", "maximum_first_correct_visual_p99_usec"],
			["collision_coherence", "maximum_collision_coherence_p99_usec"],
			["local_settlement", "maximum_local_settlement_p99_usec"],
		]:
			_expect(
				float((group.get(pair[0], {}) as Dictionary).get("p99_usec", INF))
					<= float(budgets.get(pair[1], 0.0)),
				"%s %s p99 exceeded" % [group_name, pair[0]], failures
			)
	_expect(str(supersession.get("status", "")) == "PASS", "supersession contract failed", failures)


func _validate_native_authority(standard: Dictionary, failures: Array[String]) -> void:
	var native := JsonLoader.load_dictionary(str(standard.get("native_authority_evidence", "")))
	var expected: Dictionary = standard.get("stable_expected", {})
	var authority: Dictionary = native.get("authority", {})
	var hashes: Dictionary = native.get("expected_contract_hashes", {})
	var soak: Dictionary = native.get("native_soak", {})
	var soak_metrics: Dictionary = soak.get("metrics", {})
	_expect(str(native.get("status", "")) == "PASS", "native closure authority failed", failures)
	_expect(str(authority.get("git_commit", "")) == str(expected.get("upstream_commit", "")), "upstream commit changed", failures)
	_expect(str(hashes.get("workload_hash", "")) == str(expected.get("workload_hash", "")), "native priority workload hash changed", failures)
	_expect(str(hashes.get("lod_streaming_hash", "")) == str(expected.get("lod_streaming_hash", "")), "native LOD streaming hash changed", failures)
	_expect(int(soak_metrics.get("cancellations", 0)) >= int(expected.get("minimum_native_cancellations", 1)), "native cancellation proof absent", failures)
	for configuration in ["template_debug", "template_release"]:
		var build: Dictionary = (native.get("build_matrix", {}) as Dictionary).get(configuration, {})
		_expect(str(build.get("status", "")) == "PASS", "native build failed: " + configuration, failures)
		_expect(int((build.get("workload_metrics", {}) as Dictionary).get("readiness_max", 999)) <= int(expected.get("maximum_native_readiness_frames", 32)), "native readiness bound changed", failures)


func _observe_queues(metrics: Dictionary) -> void:
	_queue_peaks["scheduler"] = maxi(int(_queue_peaks["scheduler"]), int(metrics.get("scheduler_queued_jobs", 0)))
	_queue_peaks["render"] = maxi(int(_queue_peaks["render"]), int(metrics.get("queued_render", 0)))
	_queue_peaks["collision"] = maxi(int(_queue_peaks["collision"]), int(metrics.get("total_collision_backlog", 0)))
	_queue_peaks["storage"] = maxi(int(_queue_peaks["storage"]), int(metrics.get("storage_queued_requests", 0)))


static func _readiness(state: RefCounted) -> Dictionary:
	return {
		"present": bool(state.call("is_present")),
		"coordinate": state.call("get_chunk_coordinate"),
		"lod": int(state.call("get_lod")),
		"generation": int(state.call("get_generation")),
		"visual_generation": int(state.call("get_render_generation")),
		"staged_visual_generation": int(state.call("get_staged_render_generation")),
		"collision_generation": int(state.call("get_collision_generation")),
		"staged_collision_generation": int(state.call("get_staged_collision_generation")),
		"visual_required": bool(state.call("is_visual_required")),
		"collision_required": bool(state.call("is_collision_required")),
		"visual_ready": bool(state.call("is_visual_ready")),
		"collision_ready": bool(state.call("is_collision_ready")),
		"fully_ready": bool(state.call("is_fully_ready")),
	}


func _find_covering_state(position: Vector3, require_collision: bool) -> RefCounted:
	var best: RefCounted = null
	var best_lod := 99
	for state_value in _terrain.call("query_active_chunk_states"):
		var state: RefCounted = state_value
		if not bool(state.call("is_present")):
			continue
		if require_collision and not bool(state.call("is_collision_required")):
			continue
		if not require_collision and not bool(state.call("is_visual_required")):
			continue
		var lod := int(state.call("get_lod"))
		var size := 16.0 * pow(2.0, lod)
		var coordinate: Vector3i = state.call("get_chunk_coordinate")
		var minimum := Vector3(coordinate) * size
		var maximum := minimum + Vector3.ONE * size
		if position.x < minimum.x or position.y < minimum.y or position.z < minimum.z \
				or position.x >= maximum.x or position.y >= maximum.y or position.z >= maximum.z:
			continue
		if lod < best_lod:
			best = state
			best_lod = lod
	return best


static func _selected_metrics(metrics: Dictionary) -> Dictionary:
	var output := {}
	for key in [
		"viewer_updates", "collision_viewer_updates", "coalesced_viewer_events",
		"planned_demands", "sample_jobs", "mesh_jobs", "edit_commits",
		"edit_replacements", "edit_cancelled_page_meshing_generations",
		"page_stale_storage_completions", "scheduler_queued_jobs",
		"storage_queued_requests", "queued_render", "total_collision_backlog",
		"active_chunk_records", "render_resources", "collision_resources",
		"application_applied_render", "application_applied_collision",
		"render_latency_frames_maximum", "collision_latency_frames_maximum",
		"pending_chunk_replacements", "pending_chunk_retirements",
	]:
		output[key] = metrics.get(key, -1)
	return output


func _runtime_overrides() -> Dictionary:
	var pipeline := int(_profile.get("pipeline_capacity", 2048))
	return {
		"active_chunk_capacity": int(_profile.get("active_chunk_capacity", 512)),
		"viewer_capacity": 8,
		"demand_capacity_per_viewer": pipeline,
		"lod_refinement_radius_chunks": int(_profile.get("lod_refinement_radius_chunks", 1)),
		"storage_request_capacity": pipeline,
		"storage_completion_capacity": pipeline,
		"encoded_page_entry_capacity": int(_profile.get("page_cache_capacity", 512)),
		"decoded_page_entry_capacity": int(_profile.get("page_cache_capacity", 512)),
		"mesh_entry_capacity": int(_profile.get("page_cache_capacity", 512)),
		"render_entry_capacity": int(_profile.get("page_cache_capacity", 512)),
		"collision_entry_capacity": int(_profile.get("collision_capacity", 128)),
		"trace_event_capacity": 65536,
		"render_apply_budget": 4,
		"collision_apply_budget": 2,
		"collision_apply_deadline_us": 12000,
		"render_transition_frames": 0,
	}


func _geometry_signature() -> String:
	if not is_instance_valid(_harness) or not is_instance_valid(_terrain):
		return EMPTY_SIGNATURE
	var lines: Array[String] = []
	for child in _terrain.get_children():
		if child is MeshInstance3D and str(child.name).begins_with("WT_Render_"):
			lines.append(str(child.name) + ":" + _harness.mesh_signature(str(child.name)))
	lines.sort()
	return "\n".join(lines).sha256_text()


static func _append_edit(transaction: RefCounted, scenario: Dictionary) -> bool:
	if str(scenario.get("kind", "")) == "dig":
		return bool(transaction.call(
			"carve_smooth_sdf_sphere", _vector3(scenario.get("center", [])),
			float(scenario.get("radius", 1.0)), 1.0,
			float(scenario.get("smooth_radius", 0.0))
		))
	return bool(transaction.call(
		"construct_material_smooth_sdf_sphere", _vector3(scenario.get("center", [])),
		float(scenario.get("radius", 1.0)), 1.0, int(scenario.get("material", 1)),
		float(scenario.get("smooth_radius", 0.0))
	))


static func _chunk_at(position: Vector3) -> Vector3i:
	return Vector3i(floori(position.x / 16.0), floori(position.y / 16.0), floori(position.z / 16.0))


func _is_settled(metrics: Dictionary) -> bool:
	return int(metrics.get("active_chunk_records", 0)) > 0 \
		and int(metrics.get("non_retiring_visual_ready_chunk_records", -1)) \
			== int(metrics.get("non_retiring_chunk_records", -2)) \
		and int(metrics.get("queued_render", -1)) == 0 \
		and int(metrics.get("total_collision_backlog", -1)) == 0 \
		and int(metrics.get("scheduler_queued_jobs", -1)) == 0 \
		and int(metrics.get("scheduler_queued_completions", -1)) == 0 \
		and int(metrics.get("storage_queued_requests", -1)) == 0 \
		and int(metrics.get("storage_queued_completions", -1)) == 0 \
		and int(metrics.get("pending_chunk_replacements", -1)) == 0 \
		and int(metrics.get("pending_chunk_retirements", -1)) == 0 \
		and _all_required_generations_match()


func _all_required_generations_match() -> bool:
	return str(_generation_agreement().get("status", "")) == "PASS"


func _generation_agreement() -> Dictionary:
	var mismatches: Array[Dictionary] = []
	for state_value in _terrain.call("query_active_chunk_states"):
		var state: RefCounted = state_value
		if not bool(state.call("is_present")):
			continue
		var visual_mismatch := bool(state.call("is_visual_required")) \
			and not _has_current_visual(state)
		var collision_mismatch := bool(state.call("is_collision_required")) \
			and not _has_current_collision(state)
		if visual_mismatch or collision_mismatch:
			var record := _readiness(state)
			record["visual_mismatch"] = visual_mismatch
			record["collision_mismatch"] = collision_mismatch
			mismatches.append(record)
	return {
		"status": "PASS" if mismatches.is_empty() else "FAIL",
		"mismatch_count": mismatches.size(),
		"mismatches": mismatches,
	}


static func _has_current_visual(state: RefCounted) -> bool:
	var applied := int(state.call("get_render_generation"))
	var current := int(state.call("get_generation"))
	return bool(state.call("is_visual_ready")) \
		and applied in [0, current] \
		and int(state.call("get_staged_render_generation")) == 0


static func _has_current_collision(state: RefCounted) -> bool:
	var applied := int(state.call("get_collision_generation"))
	var current := int(state.call("get_generation"))
	return bool(state.call("is_collision_ready")) \
		and applied in [0, current] \
		and int(state.call("get_staged_collision_generation")) == 0


static func _vector3(value: Variant) -> Vector3:
	var array: Array = value
	return Vector3(float(array[0]), float(array[1]), float(array[2])) if array.size() == 3 else Vector3.ZERO


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
