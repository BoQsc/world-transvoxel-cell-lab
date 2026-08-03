@tool
extends Node
class_name WtTerrainLabEditInvalidationQualification

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
	"res://addons/world_transvoxel_terrain_lab/standards/edit_invalidation_standard.json"
)
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/edit_invalidation"
const CHUNK_CELLS := 16

var _terrain: Node
var _stage := "startup"
var _trace: Array[Dictionary] = []
var _frame_samples_usec: Array[float] = []
var _settlement_samples_usec: Array[float] = []
var _oracle_samples_usec: Array[float] = []
var _last_frame_usec := 0
var _audited_frame_count := 0
var _maximum_settlement_frames := 2400
var _trace_limit := 4096
var _frame_failures := {}
var _baseline_failures := {}
var _hole_frames := 0
var _render_overlap_frames := 0
var _collision_overlap_frames := 0
var _maximums := {}


func run() -> Dictionary:
	_reset()
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var failures: Array[String] = []
	_validate_contract(standard, failures)
	if not failures.is_empty():
		return _report(standard, [], failures, {})
	var profile: Dictionary = standard.get("runtime_profile", {})
	var workload: Dictionary = standard.get("workload", {})
	var budgets: Dictionary = standard.get("budgets", {})
	_maximum_settlement_frames = int(budgets.get("maximum_settlement_frames", 2400))
	_trace_limit = int(budgets.get("maximum_trace_rows", 4096))
	Harness.remove_tree(RUNTIME_ROOT)
	var harness := Harness.new()
	add_child(harness)
	var capacity := int(profile.get("pipeline_capacity", 2048))
	var overrides := {
		"active_chunk_capacity": int(profile.get("active_chunk_capacity", 512)),
		"demand_capacity_per_viewer": capacity,
		"lod_refinement_radius_chunks": int(profile.get("lod_refinement_radius_chunks", 1)),
		"storage_request_capacity": capacity,
		"storage_completion_capacity": capacity,
		"encoded_page_entry_capacity": capacity,
		"decoded_page_entry_capacity": capacity,
		"mesh_entry_capacity": capacity,
		"render_entry_capacity": capacity,
		"collision_entry_capacity": capacity,
		"render_transition_frames": int(profile.get("render_transition_frames", 0)),
		"shader_fade_parameter_enabled": false,
		"global_coarse_lod_coverage": false,
	}
	if not harness.create_runtime(int(profile.get("worker_count", 2)), overrides):
		failures.append("native world-transvoxel runtime could not be created")
		return await _finish(harness, standard, [], failures, {})
	_terrain = harness.terrain
	_expect(
		str(_terrain.call("get_backend_id")) == "transvoxel_mit_official"
			and str(_terrain.call("get_backend_license")) == "MIT",
		"native backend identity changed",
		failures
	)
	if not await _start_world(harness, profile):
		failures.append("native edit-invalidation world did not enter running")
		return await _finish(harness, standard, [], failures, {})
	var viewer_position := _vector3(profile.get("viewer_position", []))
	if not bool(_terrain.call(
		"update_viewer",
		int(profile.get("viewer_id", 36)),
		1,
		viewer_position,
		int(profile.get("viewer_radius_chunks", 1)),
		int(profile.get("maximum_lod", 1))
	)):
		failures.append("authoritative edit viewer update was rejected")
		return await _finish(harness, standard, [], failures, {})
	var initial_settlement := await _wait_for_settled()
	if str(initial_settlement.get("status", "")) != "PASS":
		failures.append("initial native edit layout did not fully settle")
		return await _finish(harness, standard, [], failures, {})
	var initial_state := _active_state()
	_validate_initial_state(initial_state, failures)
	if not failures.is_empty():
		return await _finish(harness, standard, [], failures, {})
	_baseline_failures = _failure_metrics(_terrain.call("get_runtime_metrics"))
	_start_monitoring()

	var scenarios: Array[Dictionary] = []
	var controls := {
		"oracle_independent_of_native_spatial_query": true,
		"active_enumeration_includes_empty_payloads": (
			initial_state.size() > int(_terrain.call("get_rendered_chunk_count"))
		),
		"initial_lod_histogram": _lod_histogram(initial_state.keys()),
	}
	var benchmark := _benchmark_oracle(
		initial_state,
		(workload.get("scenarios", []) as Array)[3].get("commands", []),
		int(workload.get("oracle_benchmark_samples", 100))
	)
	controls["oracle_benchmark"] = benchmark
	_expect(
		int(benchmark.get("sample_count", 0)) >= 100,
		"independent oracle benchmark is incomplete",
		failures
	)
	var transaction_id := 360100
	for scenario_value in workload.get("scenarios", []):
		var scenario: Dictionary = scenario_value
		var result := await _run_scenario(scenario, transaction_id)
		transaction_id += 1
		scenarios.append(result)
		if str(result.get("status", "")) != "PASS":
			failures.append("edit invalidation scenario failed: " + str(scenario.get("id", "")))
	var rapid: Dictionary = workload.get("rapid_supersession", {})
	var rapid_result := await _run_rapid_supersession(rapid, transaction_id)
	scenarios.append(rapid_result)
	if str(rapid_result.get("status", "")) != "PASS":
		failures.append("edit invalidation scenario failed: rapid_supersession")
	controls["rapid_publication_held"] = rapid_result.get("publication_held", false)
	controls["rapid_stale_rejections"] = rapid_result.get("stale_rejections_delta", 0)
	controls["rapid_cancelled_generations"] = rapid_result.get(
		"cancelled_page_meshing_generations_delta", 0
	)
	return await _finish(harness, standard, scenarios, failures, controls)


func _run_scenario(scenario: Dictionary, transaction_id: int) -> Dictionary:
	_stage = str(scenario.get("id", "unnamed"))
	var commands: Array = scenario.get("commands", [])
	var before_state := _active_state()
	var expected := _expected_ids(before_state, commands)
	var before_metrics := _terrain.call("get_runtime_metrics") as Dictionary
	var transaction: RefCounted = _terrain.call("begin_edit_transaction", transaction_id)
	var accepted := transaction != null and _append_commands(transaction, commands)
	if accepted:
		accepted = bool(_terrain.call("commit_edit_transaction", transaction))
	var settlement := {}
	if accepted:
		settlement = await _wait_for_edit(
			before_state,
			expected,
			int(before_metrics.get("edit_completed_transactions", 0)) + 1
		)
	var after_state := _active_state()
	var after_metrics := _terrain.call("get_runtime_metrics") as Dictionary
	var changed := _changed_ids(before_state, after_state)
	var exact := changed == expected
	var key_stable := _same_ids(before_state, after_state)
	var coherent := _final_resource_coherence(after_state)
	var queried_delta := _delta(after_metrics, before_metrics, "edit_queried_chunks")
	var replaced_delta := _delta(after_metrics, before_metrics, "edit_replaced_chunks")
	var empty_delta := _delta(after_metrics, before_metrics, "edit_empty_transactions")
	var completed_delta := _delta(after_metrics, before_metrics, "edit_completed_transactions")
	var cancelled_delta := _delta(
		after_metrics, before_metrics, "edit_cancelled_page_meshing_generations"
	)
	var local_failures: Array[String] = []
	_expect(accepted, "transaction was not accepted", local_failures)
	_expect(str(settlement.get("status", "")) == "PASS", "transaction did not settle", local_failures)
	_expect(key_stable, "active key ownership changed during a stationary edit", local_failures)
	_expect(exact, "observed generation changes differ from padded-footprint oracle", local_failures)
	_expect(coherent, "final native/resource generations are incoherent", local_failures)
	_expect(completed_delta == 1, "transaction completion count is not exact", local_failures)
	if expected.is_empty():
		_expect(queried_delta == 0 and replaced_delta == 0, "no-op rebuilt a loaded chunk", local_failures)
		_expect(empty_delta == 1, "empty loaded intersection was not recorded", local_failures)
	else:
		_expect(queried_delta == expected.size(), "queried chunk count differs from oracle", local_failures)
		_expect(replaced_delta == expected.size(), "replacement count differs from oracle", local_failures)
		_expect(empty_delta == 0, "non-empty edit was classified as empty", local_failures)
		_expect(cancelled_delta >= expected.size(), "page-meshing owners were not cancelled", local_failures)
	_validate_scenario_shape(_stage, expected, before_state, commands, local_failures)
	return {
		"id": _stage,
		"status": "PASS" if local_failures.is_empty() else "FAIL",
		"command_count": commands.size(),
		"command_bounds": _json_command_bounds(commands),
		"expected_ids": expected,
		"changed_ids": changed,
		"expected_signature": "\n".join(expected).sha256_text(),
		"changed_signature": "\n".join(changed).sha256_text(),
		"lod_histogram": _lod_histogram(expected),
		"unaffected_generation_count": before_state.size() - expected.size(),
		"queried_chunks_delta": queried_delta,
		"replaced_chunks_delta": replaced_delta,
		"empty_transactions_delta": empty_delta,
		"cancelled_page_meshing_generations_delta": cancelled_delta,
		"transition_mesh_completions_delta": _delta(
			after_metrics, before_metrics, "transition_mesh_completions"
		),
		"settlement": settlement,
		"failures": local_failures,
	}


func _run_rapid_supersession(scenario: Dictionary, transaction_id: int) -> Dictionary:
	_stage = str(scenario.get("id", "rapid_supersession"))
	var commands: Array = scenario.get("commands", [])
	var before_state := _active_state()
	var expected := _expected_ids(before_state, commands)
	var before_metrics := _terrain.call("get_runtime_metrics") as Dictionary
	var local_failures: Array[String] = []
	_terrain.call("set_render_apply_budget", 0)
	_terrain.call("set_collision_apply_budget", 0)
	var first := _submit_transaction(transaction_id, commands)
	var first_completed := first and await _wait_for_metric(
		"edit_completed_transactions",
		int(before_metrics.get("edit_completed_transactions", 0)) + 1,
		900
	)
	var publication_held := first_completed and await _wait_for_held_publication(
		before_metrics, before_state, expected, 1200
	)
	var second := false
	if first_completed:
		second = _submit_transaction(transaction_id + 1, commands)
	var second_completed := second and await _wait_for_metric(
		"edit_completed_transactions",
		int(before_metrics.get("edit_completed_transactions", 0)) + 2,
		900
	)
	_terrain.call("set_render_apply_budget", 2)
	_terrain.call("set_collision_apply_budget", 2)
	var settlement := {}
	if second_completed:
		settlement = await _wait_for_edit(
			before_state,
			expected,
			int(before_metrics.get("edit_completed_transactions", 0)) + 2
		)
	var after_state := _active_state()
	var after_metrics := _terrain.call("get_runtime_metrics") as Dictionary
	var changed := _changed_ids(before_state, after_state)
	var cancelled_delta := _delta(
		after_metrics, before_metrics, "edit_cancelled_page_meshing_generations"
	)
	var stale_delta := _stale_rejections(after_metrics) - _stale_rejections(before_metrics)
	_expect(first and first_completed, "first supersession edit did not complete", local_failures)
	_expect(publication_held, "first edit did not reach held completed publication", local_failures)
	_expect(second and second_completed, "second supersession edit did not complete", local_failures)
	_expect(str(settlement.get("status", "")) == "PASS", "supersession did not settle", local_failures)
	_expect(changed == expected, "supersession changed the wrong active generations", local_failures)
	_expect(_same_ids(before_state, after_state), "supersession changed active key ownership", local_failures)
	_expect(_final_resource_coherence(after_state), "supersession left stale or staged resources", local_failures)
	_expect(
		_delta(after_metrics, before_metrics, "edit_replaced_chunks") == expected.size() * 2,
		"supersession replacement count is not exact",
		local_failures
	)
	_expect(
		cancelled_delta >= expected.size() * 2,
		"supersession did not cancel both page-meshing generations",
		local_failures
	)
	_expect(stale_delta > 0, "held superseded publications were not rejected as stale", local_failures)
	return {
		"id": _stage,
		"status": "PASS" if local_failures.is_empty() else "FAIL",
		"command_count": commands.size() * 2,
		"command_bounds": _json_command_bounds(commands),
		"expected_ids": expected,
		"changed_ids": changed,
		"expected_signature": "\n".join(expected).sha256_text(),
		"changed_signature": "\n".join(changed).sha256_text(),
		"lod_histogram": _lod_histogram(expected),
		"publication_held": publication_held,
		"stale_rejections_delta": stale_delta,
		"cancelled_page_meshing_generations_delta": cancelled_delta,
		"replaced_chunks_delta": _delta(after_metrics, before_metrics, "edit_replaced_chunks"),
		"settlement": settlement,
		"failures": local_failures,
	}


func _submit_transaction(transaction_id: int, commands: Array) -> bool:
	var transaction: RefCounted = _terrain.call("begin_edit_transaction", transaction_id)
	return transaction != null and _append_commands(transaction, commands) \
		and bool(_terrain.call("commit_edit_transaction", transaction))


func _append_commands(transaction: RefCounted, commands: Array) -> bool:
	for command_value in commands:
		var command: Dictionary = command_value
		var shape := str(command.get("shape", ""))
		var accepted := false
		if shape == "sphere":
			accepted = bool(transaction.call(
				"add_density_sphere",
				_vector3(command.get("center", [])),
				float(command.get("radius", 0.0)),
				float(command.get("density_delta", 0.0))
			))
		elif shape == "box":
			accepted = bool(transaction.call(
				"add_density_box",
				_vector3(command.get("minimum", [])),
				_vector3(command.get("maximum", [])),
				float(command.get("density_delta", 0.0))
			))
		if not accepted:
			return false
	return not commands.is_empty()


func _wait_for_edit(
	before_state: Dictionary,
	expected: Array[String],
	minimum_completed_transactions: int
) -> Dictionary:
	var started := Time.get_ticks_usec()
	var result := {"status": "FAIL", "frames": _maximum_settlement_frames}
	for frame in range(_maximum_settlement_frames):
		var metrics := _terrain.call("get_runtime_metrics") as Dictionary
		var state := _active_state()
		var generations_ready := (
			_same_generations(before_state, state)
			if expected.is_empty() else _expected_advanced(before_state, state, expected)
		)
		if int(metrics.get("edit_completed_transactions", 0)) >= minimum_completed_transactions \
				and generations_ready and _is_settled(metrics) \
				and _final_resource_coherence(state):
			result = {"status": "PASS", "frames": frame, "metrics": _metric_subset(metrics)}
			break
		await get_tree().process_frame
		if frame % 8 == 0:
			await get_tree().create_timer(0.001).timeout
	var elapsed := Time.get_ticks_usec() - started
	_settlement_samples_usec.append(float(elapsed))
	result["elapsed_usec"] = elapsed
	if str(result.get("status", "")) != "PASS":
		result["metrics"] = _metric_subset(_terrain.call("get_runtime_metrics"))
	return result


func _wait_for_settled() -> Dictionary:
	var started := Time.get_ticks_usec()
	for frame in range(_maximum_settlement_frames):
		var metrics := _terrain.call("get_runtime_metrics") as Dictionary
		if _is_settled(metrics) and int(metrics.get("active_chunk_records", 0)) > 0:
			return {
				"status": "PASS",
				"frames": frame,
				"elapsed_usec": Time.get_ticks_usec() - started,
				"metrics": _metric_subset(metrics),
			}
		await get_tree().process_frame
		if frame % 8 == 0:
			await get_tree().create_timer(0.001).timeout
	return {
		"status": "FAIL",
		"frames": _maximum_settlement_frames,
		"elapsed_usec": Time.get_ticks_usec() - started,
		"metrics": _metric_subset(_terrain.call("get_runtime_metrics")),
	}


func _is_settled(metrics: Dictionary) -> bool:
	var active := int(metrics.get("active_chunk_records", 0))
	return int(metrics.get("non_retiring_fully_ready_chunk_records", -1)) \
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
		and int(metrics.get("blocked_pending_chunk_replacements", -1)) == 0 \
		and int(metrics.get("staged_render_resources", -1)) == 0 \
		and int(metrics.get("staged_collision_resources", -1)) == 0


func _wait_for_metric(metric: String, minimum: int, maximum_frames: int) -> bool:
	for frame in range(maximum_frames):
		if int((_terrain.call("get_runtime_metrics") as Dictionary).get(metric, 0)) >= minimum:
			return true
		await get_tree().process_frame
		if frame % 8 == 0:
			await get_tree().create_timer(0.001).timeout
	return false


func _wait_for_held_publication(
	before_metrics: Dictionary,
	before_state: Dictionary,
	expected: Array[String],
	maximum_frames: int
) -> bool:
	for frame in range(maximum_frames):
		var metrics := _terrain.call("get_runtime_metrics") as Dictionary
		var state := _active_state()
		if int(metrics.get("mesh_completions", 0)) \
				>= int(before_metrics.get("mesh_completions", 0)) + expected.size() \
				and _has_held_generation(before_state, state, expected) \
				and int(_terrain.call("get_render_apply_budget")) == 0 \
				and int(_terrain.call("get_collision_apply_budget")) == 0:
			return true
		await get_tree().process_frame
		if frame % 8 == 0:
			await get_tree().create_timer(0.001).timeout
	return false


func _has_held_generation(
	before: Dictionary,
	current: Dictionary,
	expected: Array[String]
) -> bool:
	for id in expected:
		if not before.has(id) or not current.has(id):
			return false
		var old: Dictionary = before[id]
		var row: Dictionary = current[id]
		var generation := int(row.get("generation", 0))
		if generation <= int(old.get("generation", 0)):
			return false
		if bool(row.get("fully_ready", false)) \
				and int(row.get("render_generation", 0)) in [0, generation] \
				and int(row.get("collision_generation", 0)) in [0, generation]:
			return false
	return true


func _active_state() -> Dictionary:
	var output := {}
	for state_value in _terrain.call("query_active_chunk_states"):
		var state := state_value as RefCounted
		if state == null or not bool(state.call("is_present")):
			continue
		var coordinate: Vector3i = state.call("get_chunk_coordinate")
		var lod := int(state.call("get_lod"))
		var id := _key_id(coordinate, lod)
		output[id] = {
			"coordinate": coordinate,
			"lod": lod,
			"generation": int(state.call("get_generation")),
			"render_generation": int(state.call("get_render_generation")),
			"staged_render_generation": int(state.call("get_staged_render_generation")),
			"collision_generation": int(state.call("get_collision_generation")),
			"staged_collision_generation": int(state.call("get_staged_collision_generation")),
			"fully_ready": bool(state.call("is_fully_ready")),
		}
	return output


func _expected_ids(state: Dictionary, commands: Array) -> Array[String]:
	var expected := {}
	for command_value in commands:
		var bounds := _command_bounds(command_value)
		for id in _expected_for_bounds(state, bounds[0], bounds[1]):
			expected[id] = true
	var output: Array[String] = []
	for id in expected:
		output.append(str(id))
	output.sort()
	return output


func _expected_for_bounds(
	state: Dictionary,
	edit_minimum: Vector3i,
	edit_maximum: Vector3i
) -> Array[String]:
	var output: Array[String] = []
	for id in state:
		var row: Dictionary = state[id]
		var coordinate: Vector3i = row.get("coordinate", Vector3i.ZERO)
		var lod := int(row.get("lod", 0))
		var spacing := 1 << lod
		var extent := CHUNK_CELLS * spacing
		var footprint_minimum := coordinate * extent - Vector3i.ONE * spacing
		var footprint_maximum := coordinate * extent + Vector3i.ONE * (extent + spacing)
		if edit_maximum.x >= footprint_minimum.x \
				and edit_minimum.x <= footprint_maximum.x \
				and edit_maximum.y >= footprint_minimum.y \
				and edit_minimum.y <= footprint_maximum.y \
				and edit_maximum.z >= footprint_minimum.z \
				and edit_minimum.z <= footprint_maximum.z:
			output.append(str(id))
	output.sort()
	return output


func _command_bounds(command_value: Variant) -> Array[Vector3i]:
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


func _json_command_bounds(commands: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for command in commands:
		var bounds := _command_bounds(command)
		output.append({
			"minimum": _vector3i_array(bounds[0]),
			"maximum": _vector3i_array(bounds[1]),
		})
	return output


func _changed_ids(before: Dictionary, after: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for id in before:
		if after.has(id) and int((after[id] as Dictionary).get("generation", 0)) \
				!= int((before[id] as Dictionary).get("generation", 0)):
			output.append(str(id))
	output.sort()
	return output


func _same_ids(before: Dictionary, after: Dictionary) -> bool:
	var before_ids := before.keys()
	var after_ids := after.keys()
	before_ids.sort()
	after_ids.sort()
	return before_ids == after_ids


func _same_generations(before: Dictionary, after: Dictionary) -> bool:
	return _same_ids(before, after) and _changed_ids(before, after).is_empty()


func _expected_advanced(
	before: Dictionary,
	after: Dictionary,
	expected: Array[String]
) -> bool:
	if not _same_ids(before, after):
		return false
	for id in expected:
		if not after.has(id) or int((after[id] as Dictionary).get("generation", 0)) \
				<= int((before[id] as Dictionary).get("generation", 0)):
			return false
	return true


func _final_resource_coherence(state: Dictionary) -> bool:
	for row_value in state.values():
		var row: Dictionary = row_value
		var generation := int(row.get("generation", 0))
		var render_generation := int(row.get("render_generation", 0))
		var collision_generation := int(row.get("collision_generation", 0))
		if generation <= 0 or not bool(row.get("fully_ready", false)) \
				or int(row.get("staged_render_generation", 0)) != 0 \
				or int(row.get("staged_collision_generation", 0)) != 0 \
				or (render_generation != 0 and render_generation != generation) \
				or (collision_generation != 0 and collision_generation != generation):
			return false
	return true


func _validate_initial_state(state: Dictionary, failures: Array[String]) -> void:
	var metrics := _terrain.call("get_runtime_metrics") as Dictionary
	_expect(
		state.size() == int(metrics.get("active_chunk_records", -1)),
		"active native enumeration is incomplete",
		failures
	)
	var histogram := _lod_histogram(state.keys())
	_expect(
		int(histogram.get("0", 0)) > 0 and int(histogram.get("1", 0)) > 0,
		"edit fixture does not contain both fine and coarse records",
		failures
	)
	_expect(_final_resource_coherence(state), "initial native resources are incoherent", failures)


func _validate_scenario_shape(
	id: String,
	expected: Array[String],
	state: Dictionary,
	commands: Array,
	failures: Array[String]
) -> void:
	var histogram := _lod_histogram(expected)
	if id == "coarse_parent_interior":
		_expect(int(histogram.get("1", 0)) > 0 and int(histogram.get("0", 0)) == 0, "coarse-parent fixture is not coarse-only", failures)
	elif id == "fine_child_interior":
		_expect(int(histogram.get("0", 0)) > 0 and int(histogram.get("1", 0)) == 0, "fine-child fixture is not fine-only", failures)
	elif id == "same_lod_boundary_halo":
		_expect(expected.size() >= 2 and int(histogram.get("0", 0)) == expected.size(), "same-LOD halo did not reach neighboring fine chunks", failures)
	elif id == "mixed_lod_transition_dependency":
		_expect(int(histogram.get("0", 0)) > 0 and int(histogram.get("1", 0)) > 0, "mixed-LOD edit lacks regular or transition dependent", failures)
	elif id == "disjoint_batch_union":
		var envelope := _command_bounds(commands[0])
		for command_index in range(1, commands.size()):
			var bounds := _command_bounds(commands[command_index])
			envelope[0] = Vector3i(
				mini(envelope[0].x, bounds[0].x),
				mini(envelope[0].y, bounds[0].y),
				mini(envelope[0].z, bounds[0].z)
			)
			envelope[1] = Vector3i(
				maxi(envelope[1].x, bounds[1].x),
				maxi(envelope[1].y, bounds[1].y),
				maxi(envelope[1].z, bounds[1].z)
			)
		var bridge := _expected_for_bounds(state, envelope[0], envelope[1])
		_expect(commands.size() == 2 and bridge.size() > expected.size(), "disjoint batch fixture does not prove bridge exclusion", failures)
	elif id == "unloaded_noop":
		_expect(expected.is_empty(), "no-op edit intersects a loaded sample footprint", failures)


func _benchmark_oracle(state: Dictionary, commands: Array, sample_count: int) -> Dictionary:
	var signature := ""
	for _sample in range(sample_count):
		var started := Time.get_ticks_usec()
		var expected := _expected_ids(state, commands)
		_oracle_samples_usec.append(float(Time.get_ticks_usec() - started))
		signature = "\n".join(expected).sha256_text()
	return {
		"sample_count": sample_count,
		"affected_signature": signature,
		"distribution": Statistics.distribution(_oracle_samples_usec),
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
	var render_records := _publication_records("WT_Render_", true)
	var collision_records := _publication_records("WT_Collision_", false)
	var visible_render := render_records.size()
	var render_overlaps := _overlap_count(render_records)
	var collision_overlaps := _overlap_count(collision_records)
	if _stage != "startup" and int(metrics.get("active_chunk_records", 0)) > 0 \
			and visible_render == 0:
		_hole_frames += 1
		_frame_failure("visible terrain disappeared during " + _stage)
	if render_overlaps > 0:
		_render_overlap_frames += 1
		_frame_failure("overlapping visible render ownership during " + _stage)
	if collision_overlaps > 0:
		_collision_overlap_frames += 1
		_frame_failure("overlapping collision ownership during " + _stage)
	var current_failures := _failure_metrics(metrics)
	for key in current_failures:
		if int(current_failures[key]) > int(_baseline_failures.get(key, 0)):
			_frame_failure("native pipeline failure increased: " + str(key))
	_update_maximums(metrics)
	if _trace.size() < _trace_limit:
		var row := _metric_subset(metrics)
		row["frame"] = _audited_frame_count
		row["stage"] = _stage
		row["visible_render"] = visible_render
		row["render_overlap"] = render_overlaps
		row["collision_overlap"] = collision_overlaps
		_trace.append(row)


func _publication_records(prefix: String, render: bool) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for child in _terrain.get_children():
		var name_text := str(child.name)
		if not name_text.begins_with(prefix) or name_text.contains("_retiring_"):
			continue
		if render and (not child is MeshInstance3D or not (child as MeshInstance3D).visible):
			continue
		if not render and not child is StaticBody3D:
			continue
		var parts := name_text.trim_prefix(prefix).split("_")
		if parts.size() != 4 or not parts[3].begins_with("L"):
			continue
		output.append({
			"x": int(parts[0]),
			"y": int(parts[1]),
			"z": int(parts[2]),
			"lod": int(parts[3].trim_prefix("L")),
		})
	return output


func _overlap_count(records: Array[Dictionary]) -> int:
	var count := 0
	for first_index in range(records.size()):
		var first := _key_bounds(records[first_index])
		for second_index in range(first_index + 1, records.size()):
			var intersection := first.intersection(_key_bounds(records[second_index]))
			if intersection.size.x > 0.0001 and intersection.size.y > 0.0001 \
					and intersection.size.z > 0.0001:
				count += 1
	return count


func _key_bounds(key: Dictionary) -> AABB:
	var extent := float(CHUNK_CELLS * (1 << int(key.get("lod", 0))))
	return AABB(
		Vector3(float(key.get("x", 0)), float(key.get("y", 0)), float(key.get("z", 0))) * extent,
		Vector3.ONE * extent
	)


func _finish(
	harness: Node,
	standard: Dictionary,
	scenarios: Array[Dictionary],
	failures: Array[String],
	controls: Dictionary
) -> Dictionary:
	_stop_monitoring()
	for failure in _frame_failures:
		failures.append(str(failure))
	var final_metrics := {}
	if is_instance_valid(_terrain):
		final_metrics = _terrain.call("get_runtime_metrics")
	var report := _report(standard, scenarios, failures, controls)
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
	scenarios: Array[Dictionary],
	failures: Array[String],
	controls: Dictionary
) -> Dictionary:
	var lines: Array[String] = []
	var actions := {}
	for scenario in scenarios:
		var id := str(scenario.get("id", ""))
		actions[id] = scenario.get("status", "FAIL")
		lines.append("%s:%s:%s" % [
			id,
			str(scenario.get("expected_signature", "")),
			str(scenario.get("changed_signature", "")),
		])
	var final_state := _active_state() if is_instance_valid(_terrain) else {}
	return {
		"schema": "world_transvoxel.terrain_lab.edit_invalidation_qualification.v1",
		"milestone": "TQP-36",
		"standard_id": standard.get("standard_id", ""),
		"authority": standard.get("authority", ""),
		"status": "FAIL" if not failures.is_empty() else "PENDING_BUDGET_EVALUATION",
		"retained_complete": true,
		"provenance": Statistics.provenance("tqp36_edit_invalidation_windows_v1"),
		"coverage": {
			"actions": actions,
			"scenario_count": scenarios.size(),
			"audited_frame_count": _audited_frame_count,
			"retained_trace_rows": _trace.size(),
			"exact_affected_set_scenarios": _count_exact_scenarios(scenarios),
			"oracle_benchmark_samples": _oracle_samples_usec.size(),
		},
		"temporal_invariants": {
			"visible_hole_frames": _hole_frames,
			"render_overlap_frames": _render_overlap_frames,
			"double_collision_frames": _collision_overlap_frames,
			"frame_failure_count": _frame_failures.size(),
		},
		"scenarios": scenarios,
		"scenario_matrix_signature": "\n".join(lines).sha256_text(),
		"final_active_key_signature": _state_key_signature(final_state),
		"frame_trace": _trace,
		"performance": {
			"frame": Statistics.distribution(_frame_samples_usec),
			"edit_settlement": Statistics.distribution(_settlement_samples_usec),
			"oracle": Statistics.distribution(_oracle_samples_usec),
			"memory": Statistics.memory_metrics(),
			"scope": "WINDOWS_DEBUG_DIAGNOSTIC_EDIT_INVALIDATION_NOT_PRODUCTION_FRAME_BUDGET",
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
	var actions: Dictionary = coverage.get("actions", {})
	var invariants: Dictionary = report.get("temporal_invariants", {})
	var budgets: Dictionary = standard.get("budgets", {})
	for action_value in workload.get("required_actions", []):
		var action := str(action_value)
		_expect(str(actions.get(action, "")) == "PASS", "required action failed: " + action, failures)
	_expect(int(coverage.get("scenario_count", 0)) == 7, "scenario matrix is incomplete", failures)
	_expect(int(coverage.get("exact_affected_set_scenarios", 0)) == 7, "affected-set equality is incomplete", failures)
	_expect(int(coverage.get("oracle_benchmark_samples", 0)) >= 100, "oracle sample floor was not met", failures)
	for key in ["visible_hole_frames", "render_overlap_frames", "double_collision_frames", "frame_failure_count"]:
		_expect(int(invariants.get(key, -1)) == 0, "temporal invariant failed: " + key, failures)
	var performance: Dictionary = report.get("performance", {})
	var frame: Dictionary = performance.get("frame", {})
	var settlement: Dictionary = performance.get("edit_settlement", {})
	var oracle: Dictionary = performance.get("oracle", {})
	_expect(float(frame.get("p99_usec", INF)) <= float(budgets.get("maximum_frame_p99_usec", 0.0)), "frame p99 ceiling exceeded", failures)
	_expect(float(frame.get("worst_usec", INF)) <= float(budgets.get("maximum_frame_usec", 0.0)), "maximum frame ceiling exceeded", failures)
	_expect(float(settlement.get("p95_usec", INF)) <= float(budgets.get("maximum_edit_settlement_p95_usec", 0.0)), "edit settlement p95 ceiling exceeded", failures)
	_expect(float(oracle.get("p99_usec", INF)) <= float(budgets.get("maximum_oracle_p99_usec", 0.0)), "oracle p99 ceiling exceeded", failures)
	for pair in [
		["maximum_active_chunk_records", "maximum_active_chunk_records"],
		["maximum_render_resources", "maximum_render_resources"],
		["maximum_collision_resources", "maximum_collision_resources"],
	]:
		_expect(int(_maximums.get(pair[0], 0)) <= int(budgets.get(pair[1], -1)), str(pair[0]) + " ceiling exceeded", failures)
	var stable: Dictionary = standard.get("stable_expected", {})
	for signature in ["scenario_matrix_signature", "final_active_key_signature"]:
		var expected := str(stable.get(signature, ""))
		if not expected.is_empty():
			_expect(str(report.get(signature, "")) == expected, "stable signature changed: " + signature, failures)


func _start_world(harness: Node, profile: Dictionary) -> bool:
	var volume: Array = profile.get("volume_chunks", [])
	return volume.size() == 3 and await harness.start_procedural_world_preset(
		RUNTIME_ROOT + "/source",
		int(profile.get("source_revision", 0)),
		int(profile.get("seed", 0)),
		str(profile.get("preset", "")),
		int(volume[0]),
		int(volume[1]),
		int(profile.get("vertical_chunk_origin", 0)),
		int(volume[2])
	)


func _failure_metrics(metrics: Dictionary) -> Dictionary:
	var output := {}
	for key in [
		"application_sink_failures",
		"application_queue_rejections",
		"scheduler_queue_rejections",
		"storage_request_queue_rejections",
		"page_sample_failures",
		"page_mesh_failures",
		"page_storage_failures",
		"page_cache_failures",
		"edit_spatial_rejections",
		"edit_capacity_rejections",
		"edit_state_rejections",
		"edit_scheduler_failures",
		"edit_application_failures",
		"edit_page_meshing_runtime_failures",
	]:
		output[key] = int(metrics.get(key, 0))
	return output


func _stale_rejections(metrics: Dictionary) -> int:
	return int(metrics.get("application_stale_render", 0)) \
		+ int(metrics.get("application_stale_collision", 0)) \
		+ int(metrics.get("page_stale_storage_completions", 0))


func _update_maximums(metrics: Dictionary) -> void:
	for pair in [
		["maximum_active_chunk_records", "active_chunk_records"],
		["maximum_render_resources", "render_resources"],
		["maximum_collision_resources", "collision_resources"],
		["maximum_render_queue", "queued_render"],
		["maximum_collision_queue", "queued_collision"],
	]:
		_maximums[pair[0]] = maxi(int(_maximums.get(pair[0], 0)), int(metrics.get(pair[1], 0)))


func _metric_subset(metrics: Dictionary) -> Dictionary:
	var output := {}
	for key in [
		"active_chunk_records",
		"non_retiring_chunk_records",
		"non_retiring_fully_ready_chunk_records",
		"render_resources",
		"collision_resources",
		"staged_render_resources",
		"staged_collision_resources",
		"scheduler_queued_jobs",
		"scheduler_queued_completions",
		"storage_queued_requests",
		"storage_queued_completions",
		"storage_active_requests",
		"page_loading_records",
		"queued_render",
		"queued_collision",
		"pending_chunk_replacements",
		"pending_chunk_retirements",
		"edit_completed_transactions",
		"edit_empty_transactions",
		"edit_queried_chunks",
		"edit_replaced_chunks",
		"edit_cancelled_page_meshing_generations",
		"application_stale_render",
		"application_stale_collision",
		"page_stale_storage_completions",
		"transition_mesh_completions",
	]:
		output[key] = int(metrics.get(key, 0))
	return output


func _lod_histogram(ids: Array) -> Dictionary:
	var output := {}
	for id_value in ids:
		var id := str(id_value)
		var marker := id.rfind("L")
		var lod := id.substr(marker + 1) if marker >= 0 else "?"
		output[lod] = int(output.get(lod, 0)) + 1
	return output


func _state_key_signature(state: Dictionary) -> String:
	var ids: Array[String] = []
	for id in state:
		ids.append(str(id))
	ids.sort()
	return "\n".join(ids).sha256_text()


func _count_exact_scenarios(scenarios: Array[Dictionary]) -> int:
	var count := 0
	for scenario in scenarios:
		if str(scenario.get("expected_signature", "")) == str(scenario.get("changed_signature", "")):
			count += 1
	return count


func _delta(after: Dictionary, before: Dictionary, key: String) -> int:
	return int(after.get(key, 0)) - int(before.get(key, 0))


func _frame_failure(message: String) -> void:
	_frame_failures[message] = true


func _reset() -> void:
	_terrain = null
	_stage = "startup"
	_trace.clear()
	_frame_samples_usec.clear()
	_settlement_samples_usec.clear()
	_oracle_samples_usec.clear()
	_last_frame_usec = 0
	_audited_frame_count = 0
	_frame_failures.clear()
	_baseline_failures.clear()
	_hole_frames = 0
	_render_overlap_frames = 0
	_collision_overlap_frames = 0
	_maximums = {
		"maximum_active_chunk_records": 0,
		"maximum_render_resources": 0,
		"maximum_collision_resources": 0,
		"maximum_render_queue": 0,
		"maximum_collision_queue": 0,
	}


static func _key_id(coordinate: Vector3i, lod: int) -> String:
	return "%d,%d,%d,L%d" % [coordinate.x, coordinate.y, coordinate.z, lod]


static func _vector3(value: Variant) -> Vector3:
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


static func _vector3i_array(value: Vector3i) -> Array[int]:
	return [value.x, value.y, value.z]


static func _validate_contract(standard: Dictionary, failures: Array[String]) -> void:
	_expect(str(standard.get("schema", "")) == "world_transvoxel.terrain_lab.edit_invalidation_standard.v1", "edit invalidation standard is missing", failures)
	_expect(str(standard.get("milestone", "")) == "TQP-36", "edit invalidation milestone changed", failures)
	_expect(str(standard.get("authority", "")) == "world_transvoxel_native_runtime", "edit invalidation authority changed", failures)
	var profile: Dictionary = standard.get("runtime_profile", {})
	_expect(int(profile.get("worker_count", 0)) >= 2, "edit invalidation requires concurrent native workers", failures)
	_expect(int(profile.get("maximum_lod", 0)) >= 1, "edit invalidation requires mixed LOD", failures)
	_expect(int(profile.get("render_transition_frames", -1)) == 0, "edit invalidation requires atomic publication", failures)
	var workload: Dictionary = standard.get("workload", {})
	_expect((workload.get("scenarios", []) as Array).size() == 6, "edit invalidation scenario contract is incomplete", failures)


static func _expect(condition: bool, failure: String, failures: Array[String]) -> void:
	if not condition and failure not in failures:
		failures.append(failure)
