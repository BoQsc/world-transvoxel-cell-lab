@tool
extends Node
class_name WtTerrainLabAdaptiveEditQualification

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
	"res://addons/world_transvoxel_terrain_lab/standards/adaptive_edit_standard.json"
)
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/adaptive_edit"
const CHUNK_CELLS := 16
const POSITION_SCALE := 1000000.0
const PLANE_EPSILON := 0.0001
const AREA_EPSILON_SQUARED := 0.0000000001

var _terrain: Node
var _stage := "startup"
var _maximum_settlement_frames := 2400
var _trace_limit := 8192
var _trace: Array[Dictionary] = []
var _frame_samples_usec: Array[float] = []
var _scenario_samples_usec: Array[float] = []
var _last_frame_usec := 0
var _audited_frame_count := 0
var _hole_frames := 0
var _render_overlap_frames := 0
var _collision_overlap_frames := 0
var _frame_failures := {}
var _maximums := {}
var _last_metrics := {}
var _scenario_filter := ""


func run() -> Dictionary:
	_reset()
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size() - 1):
		if arguments[index] == "--scenario":
			_scenario_filter = arguments[index + 1]
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var failures: Array[String] = []
	_validate_contract(standard, failures)
	if not failures.is_empty():
		return _report(standard, [], failures)
	var profile: Dictionary = standard.get("runtime_profile", {})
	var workload: Dictionary = standard.get("workload", {})
	var budgets: Dictionary = standard.get("budgets", {})
	_maximum_settlement_frames = int(budgets.get("maximum_settlement_frames", 2400))
	_trace_limit = int(budgets.get("maximum_trace_rows", 8192))
	Harness.remove_tree(RUNTIME_ROOT)
	var scenarios: Array[Dictionary] = []
	for scenario_value in workload.get("scenarios", []):
		var scenario: Dictionary = scenario_value
		if not _scenario_filter.is_empty() \
				and str(scenario.get("id", "")) != _scenario_filter:
			continue
		var started := Time.get_ticks_usec()
		var result := await _run_scenario(profile, scenario)
		var elapsed := float(Time.get_ticks_usec() - started)
		result["elapsed_usec"] = elapsed
		_scenario_samples_usec.append(elapsed)
		scenarios.append(result)
		if str(result.get("status", "")) != "PASS":
			failures.append("adaptive edit scenario failed: " + str(scenario.get("id", "")))
	if _scenario_filter.is_empty():
		_validate_results(standard, scenarios, failures)
	return _report(standard, scenarios, failures)


func _run_scenario(profile: Dictionary, scenario: Dictionary) -> Dictionary:
	var scenario_id := str(scenario.get("id", "unnamed"))
	_stage = scenario_id + ":startup"
	var local_failures: Array[String] = []
	var root := RUNTIME_ROOT.path_join(scenario_id)
	Harness.remove_tree(root)
	var harness := Harness.new()
	add_child(harness)
	if not harness.create_runtime(
		int(profile.get("worker_count", 2)),
		_configuration_overrides(profile)
	):
		local_failures.append("native runtime could not be created")
		return await _finish_scenario(harness, scenario, {}, local_failures)
	_terrain = harness.terrain
	if not await _start_world(harness, profile, root):
		local_failures.append("native procedural world did not start")
		return await _finish_scenario(harness, scenario, {}, local_failures)
	var viewer_position := _vector3(scenario.get("viewer_position", []))
	var viewer_revision := 1
	var initial_settlement := await _move_viewer_and_settle(
		profile, viewer_revision, viewer_position
	)
	if str(initial_settlement.get("status", "")) != "PASS":
		local_failures.append("initial viewer update was rejected")
		return await _finish_scenario(harness, scenario, {}, local_failures)
	_start_monitoring()
	_stage = scenario_id + ":baseline"
	var points := _scenario_points(scenario)
	var baseline_samples := await _sample_points(harness, points)
	var baseline_sample_signature := _sample_signature(baseline_samples)
	var baseline_geometry_signature := _geometry_signature()
	var center := _vector3i(scenario.get("center", []))
	var baseline_target_geometry_signature := _target_geometry_signature(center)
	var baseline_local_geometry_signature := _local_geometry_signature(center, 6.0)
	_expect(
		_all_samples_pass(baseline_samples),
		"baseline authoritative sample query failed",
		local_failures
	)
	var before_metrics := _terrain.call("get_runtime_metrics") as Dictionary
	var committed := await _commit_transactions(
		harness,
		scenario.get("transactions", []),
		370000 + int(abs(scenario_id.hash()) % 10000)
	)
	_expect(committed, "native edit transactions did not commit and settle", local_failures)
	var after_commit_metrics := _terrain.call("get_runtime_metrics") as Dictionary
	var actions: Array = scenario.get("actions", [])
	var unloaded_commit := "commit_while_unloaded" in actions
	if unloaded_commit:
		_expect(
			_delta(after_commit_metrics, before_metrics, "edit_replaced_chunks") == 0,
			"unloaded edit replaced an active chunk",
			local_failures
		)
		viewer_revision += 1
		var load_position := _vector3(scenario.get("load_position", []))
		_stage = scenario_id + ":load_later"
		var load_settlement := await _move_viewer_and_settle(
			profile, viewer_revision, load_position
		)
		_expect(
			str(load_settlement.get("status", "")) == "PASS",
			"edited unloaded region did not settle after loading",
			local_failures
		)
		viewer_position = load_position
	_stage = scenario_id + ":edited"
	var edited_samples := await _sample_points(harness, points)
	var after_sample_metrics := _terrain.call("get_runtime_metrics") as Dictionary
	var edited_sample_signature := _sample_signature(edited_samples)
	_validate_semantics(scenario, baseline_samples, edited_samples, local_failures)
	var topology := _geometry_audit(scenario.get("interface_planes", []))
	for topology_failure in topology.get("failures", []):
		local_failures.append(str(topology_failure))
	var edited_geometry_signature := _geometry_signature()
	var edited_target_geometry_signature := _target_geometry_signature(center)
	var edited_local_geometry_signature := _local_geometry_signature(center, 6.0)
	var action_results := {}
	if "origin_shift" in actions:
		var origin_result := await _origin_shift_identity(
			harness, points, edited_sample_signature, edited_geometry_signature
		)
		action_results["origin_shift"] = origin_result
		_append_action_failures("origin shift", origin_result, local_failures)
	if "unload_reload" in actions:
		viewer_revision += 1
		var reload_result := await _unload_reload_identity(
			harness,
			profile,
			viewer_revision,
			viewer_position,
			points,
			edited_sample_signature,
			edited_local_geometry_signature,
			center
		)
		viewer_revision += 1
		action_results["unload_reload"] = reload_result
		_append_action_failures("unload/reload", reload_result, local_failures)
	if "coarsen_and_refine" in actions:
		var refinement_result := await _coarsen_and_refine(
			harness,
			profile,
			viewer_revision,
			viewer_position,
			center,
			points,
			edited_sample_signature,
			edited_target_geometry_signature
		)
		viewer_revision = int(refinement_result.get("viewer_revision", viewer_revision))
		action_results["coarsen_and_refine"] = refinement_result
		_append_action_failures("coarsen/refine", refinement_result, local_failures)
	if "reconstructive_undo" in actions:
		var history_result := await _reconstructive_history(
			harness,
			profile,
			scenario,
			points,
			baseline_sample_signature,
			baseline_target_geometry_signature,
			edited_sample_signature,
			edited_target_geometry_signature
		)
		action_results["reconstructive_history"] = history_result
		_append_action_failures("reconstructive history", history_result, local_failures)
	elif "world_restart" in actions:
		var restart_result := await _world_restart_identity(
			harness,
			profile,
			root,
			viewer_position,
			points,
			edited_sample_signature,
			edited_target_geometry_signature,
			center
		)
		action_results["world_restart"] = restart_result
		_append_action_failures("world restart", restart_result, local_failures)
	var semantic_signature := _scenario_semantic_signature(
		scenario_id,
		edited_samples,
		topology,
		action_results
	)
	var details := {
		"baseline_sample_signature": baseline_sample_signature,
		"edited_sample_signature": edited_sample_signature,
		"baseline_geometry_signature": baseline_geometry_signature,
		"edited_geometry_signature": edited_geometry_signature,
		"baseline_target_geometry_signature": baseline_target_geometry_signature,
		"edited_target_geometry_signature": edited_target_geometry_signature,
		"baseline_local_geometry_signature": baseline_local_geometry_signature,
		"edited_local_geometry_signature": edited_local_geometry_signature,
		"semantic_signature": semantic_signature,
		"baseline_samples": baseline_samples,
		"edited_samples": edited_samples,
		"after_sample_metrics": after_sample_metrics,
		"topology": topology,
		"actions": action_results,
		"edit_replacements": _delta(
			after_commit_metrics, before_metrics, "edit_replaced_chunks"
		),
		"edit_empty_transactions": _delta(
			after_commit_metrics, before_metrics, "edit_empty_transactions"
		),
	}
	return await _finish_scenario(harness, scenario, details, local_failures)


func _configuration_overrides(profile: Dictionary) -> Dictionary:
	var capacity := int(profile.get("pipeline_capacity", 2048))
	return {
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
		"collision_activation_distance": float(
			profile.get("collision_activation_distance", 48.0)
		),
		"collision_deactivation_distance": float(
			profile.get("collision_deactivation_distance", 64.0)
		),
	}


func _start_world(harness: Node, profile: Dictionary, root: String) -> bool:
	var volume: Array = profile.get("volume_chunks", [])
	return await harness.start_procedural_world_preset(
		root,
		int(profile.get("source_revision", 937001)),
		int(profile.get("seed", 370037)),
		str(profile.get("preset", "rolling_hills_cave")),
		int(volume[0]),
		int(volume[1]),
		int(profile.get("vertical_chunk_origin", -2)),
		int(volume[2])
	)


func _update_viewer(profile: Dictionary, revision: int, position: Vector3) -> bool:
	return bool(_terrain.call(
		"update_viewer",
		int(profile.get("viewer_id", 37)),
		revision,
		position,
		int(profile.get("viewer_radius_chunks", 1)),
		int(profile.get("maximum_lod", 1))
	))


func _commit_transactions(harness: Node, transactions: Array, author_base: int) -> bool:
	var expected_revision := int(_terrain.call("get_world_revision"))
	for transaction_index in range(transactions.size()):
		var transaction: RefCounted = _terrain.call(
			"begin_edit_transaction", author_base + transaction_index
		)
		if transaction == null:
			return false
		for operation_value in transactions[transaction_index]:
			if not _append_operation(transaction, operation_value):
				return false
		if not bool(_terrain.call("commit_edit_transaction", transaction)):
			return false
		expected_revision += 1
		if not await harness.wait_for_commit(expected_revision):
			return false
		var settlement := await _wait_for_settled()
		if str(settlement.get("status", "")) != "PASS":
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
				method,
				center,
				radius,
				strength,
				float(operation.get("smooth_radius", 0.0))
			))
		"construct_material_sdf_sphere":
			return bool(transaction.call(
				method,
				center,
				radius,
				strength,
				int(operation.get("material", 0))
			))
		"construct_material_smooth_sdf_sphere":
			return bool(transaction.call(
				method,
				center,
				radius,
				strength,
				int(operation.get("material", 0)),
				float(operation.get("smooth_radius", 0.0))
			))
	return false


func _validate_semantics(
	scenario: Dictionary,
	baseline_samples: Array[Dictionary],
	edited_samples: Array[Dictionary],
	failures: Array[String]
) -> void:
	_expect(
		_all_samples_pass(edited_samples),
		"edited authoritative sample query failed",
		failures
	)
	if baseline_samples.size() < 2 or edited_samples.size() < 2:
		failures.append("semantic probe set is incomplete")
		return
	var baseline_center := baseline_samples[0]
	var edited_center := edited_samples[0]
	var delta := float(edited_center.get("density", 0.0)) \
		- float(baseline_center.get("density", 0.0))
	var relation := str(scenario.get("expected_center_relation", ""))
	_expect(
		(delta > 0.0001 if relation == "increase" else delta < -0.0001),
		"center density did not satisfy the declared edit relation",
		failures
	)
	var expected_material := int(scenario.get("expected_material", 0))
	if expected_material > 0:
		_expect(
			int(edited_center.get("material", 0)) == expected_material,
			"constructed center material changed",
			failures
		)
	var baseline_outside := baseline_samples[1]
	var edited_outside := edited_samples[1]
	_expect(
		is_equal_approx(
			float(baseline_outside.get("density", INF)),
			float(edited_outside.get("density", -INF))
		) and int(baseline_outside.get("material", -1)) \
			== int(edited_outside.get("material", -2)),
		"outside control probe changed",
		failures
	)


func _origin_shift_identity(
	harness: Node,
	points: Array[Vector3i],
	expected_samples: String,
	expected_geometry: String
) -> Dictionary:
	_stage = "origin_shift"
	var local_failures: Array[String] = []
	var original_position: Vector3 = _terrain.position
	_terrain.position = Vector3(-4096.0, 2048.0, 4096.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var samples := await _sample_points(harness, points)
	_expect(_sample_signature(samples) == expected_samples, "sample identity changed", local_failures)
	_expect(_geometry_signature() == expected_geometry, "native local mesh changed", local_failures)
	_terrain.position = original_position
	await get_tree().process_frame
	return _action_result(local_failures, {
		"presentation_offset": Vector3(-4096.0, 2048.0, 4096.0),
	})


func _unload_reload_identity(
	harness: Node,
	profile: Dictionary,
	remove_revision: int,
	position: Vector3,
	points: Array[Vector3i],
	expected_samples: String,
	expected_geometry: String,
	center: Vector3i
) -> Dictionary:
	_stage = "unload_reload"
	var local_failures: Array[String] = []
	_expect(
		bool(_terrain.call(
			"remove_viewer", int(profile.get("viewer_id", 37)), remove_revision
		)),
		"viewer removal was rejected",
		local_failures
	)
	var empty := await _wait_for_empty()
	_expect(str(empty.get("status", "")) == "PASS", "unload did not drain", local_failures)
	var update_revision := remove_revision + 1
	var settlement := await _move_viewer_and_settle(
		profile, update_revision, position
	)
	_expect(str(settlement.get("status", "")) == "PASS", "reload did not settle", local_failures)
	var samples := await _sample_points(harness, points)
	_expect(_sample_signature(samples) == expected_samples, "sample identity changed", local_failures)
	var topology := _geometry_audit([])
	for failure in topology.get("failures", []):
		local_failures.append(str(failure))
	return _action_result(local_failures, {
		"viewer_revision": update_revision,
		"previous_target_geometry_signature": expected_geometry,
		"reloaded_target_geometry_signature": _target_geometry_signature(center),
		"topology": topology,
	})


func _world_restart_identity(
	harness: Node,
	profile: Dictionary,
	root: String,
	position: Vector3,
	points: Array[Vector3i],
	expected_samples: String,
	expected_geometry: String,
	center: Vector3i
) -> Dictionary:
	_stage = "world_restart"
	var local_failures: Array[String] = []
	_expect(await harness.stop_world(), "world stop failed", local_failures)
	harness.clear_events()
	_expect(await _start_world(harness, profile, root), "world restart failed", local_failures)
	var settlement := await _move_viewer_and_settle(profile, 1, position)
	_expect(str(settlement.get("status", "")) == "PASS", "restart did not settle", local_failures)
	var samples := await _sample_points(harness, points)
	_expect(_sample_signature(samples) == expected_samples, "restart sample changed", local_failures)
	var topology := _geometry_audit([])
	for failure in topology.get("failures", []):
		local_failures.append(str(failure))
	_expect(
		_triangle_near_count(Vector3(center), 6.0) > 0,
		"restart exposed no local edited surface",
		local_failures
	)
	return _action_result(local_failures, {
		"world_revision": int(_terrain.call("get_world_revision")),
		"previous_local_geometry_signature": expected_geometry,
		"restarted_local_geometry_signature": _local_geometry_signature(center, 6.0),
		"topology": topology,
	})


func _coarsen_and_refine(
	harness: Node,
	profile: Dictionary,
	viewer_revision: int,
	fine_position: Vector3,
	center: Vector3i,
	points: Array[Vector3i],
	expected_samples: String,
	_expected_geometry: String
) -> Dictionary:
	_stage = "coarsen_and_refine"
	var local_failures: Array[String] = []
	var child := Vector3i(
		floori(float(center.x) / 16.0),
		floori(float(center.y) / 16.0),
		floori(float(center.z) / 16.0)
	)
	var parent := Vector3i(
		floori(float(center.x) / 32.0),
		floori(float(center.y) / 32.0),
		floori(float(center.z) / 32.0)
	)
	var coarse_position := fine_position
	var coarse_found := _chunk_present(parent, 1) and not _chunk_present(child, 0)
	var coarse_triangle_count := _triangle_near_count(Vector3(center), 2.0)
	var coarse_samples := await _sample_points(harness, points)
	_expect(coarse_found, "feature did not begin in the retained coarse parent", local_failures)
	_expect(coarse_triangle_count == 0, "under-resolved feature did not disappear at coarse LOD", local_failures)
	_expect(_sample_signature(coarse_samples) == expected_samples, "coarse LOD changed field semantics", local_failures)
	var refinement_position := Vector3(center)
	viewer_revision += 1
	var refined_settlement := await _move_viewer_and_settle(
		profile, viewer_revision, refinement_position
	)
	_expect(str(refined_settlement.get("status", "")) == "PASS", "refinement did not settle", local_failures)
	var refined_samples := await _sample_points(harness, points)
	var fine_triangle_count := _triangle_near_count(Vector3(center), 2.0)
	var refined_geometry := _target_geometry_signature(center)
	_expect(_chunk_present(child, 0), "later refinement did not restore fine chunk", local_failures)
	_expect(fine_triangle_count > 0, "later refinement emitted no feature triangles", local_failures)
	_expect(_sample_signature(refined_samples) == expected_samples, "refinement changed field semantics", local_failures)
	viewer_revision += 1
	var coarse_return_settlement := await _move_viewer_and_settle(
		profile, viewer_revision, coarse_position
	)
	_expect(str(coarse_return_settlement.get("status", "")) == "PASS", "coarse return did not settle", local_failures)
	var retained_triangle_count := _triangle_near_count(Vector3(center), 2.0)
	var retained_metrics := _terrain.call("get_runtime_metrics") as Dictionary
	_expect(_chunk_present(child, 0), "edit retention released the refined child", local_failures)
	_expect(
		retained_triangle_count == fine_triangle_count,
		"edit retention changed the refined feature triangles",
		local_failures
	)
	_expect(
		_target_geometry_signature(center) == refined_geometry,
		"edit retention changed exact target fine geometry",
		local_failures
	)
	_expect(
		int(retained_metrics.get("edit_lod_retention_zones", 0)) > 0,
		"native edit LOD retention zone was not recorded",
		local_failures
	)
	viewer_revision += 1
	var second_refinement := await _move_viewer_and_settle(
		profile, viewer_revision, refinement_position
	)
	_expect(str(second_refinement.get("status", "")) == "PASS", "second refinement did not settle", local_failures)
	var refined_triangle_count := _triangle_near_count(Vector3(center), 2.0)
	_expect(refined_triangle_count == fine_triangle_count, "repeated refinement changed feature triangles", local_failures)
	_expect(
		_target_geometry_signature(center) == refined_geometry,
		"repeated refinement changed exact target fine geometry",
		local_failures
	)
	return _action_result(local_failures, {
		"viewer_revision": viewer_revision,
		"coarse_position": coarse_position,
		"refinement_position": refinement_position,
		"fine_triangle_count": fine_triangle_count,
		"coarse_triangle_count": coarse_triangle_count,
		"retained_triangle_count": retained_triangle_count,
		"refined_triangle_count": refined_triangle_count,
		"edit_lod_retention_zones": int(
			retained_metrics.get("edit_lod_retention_zones", 0)
		),
		"classification": "under_resolved_then_refined_and_retained",
	})


func _reconstructive_history(
	harness: Node,
	profile: Dictionary,
	scenario: Dictionary,
	points: Array[Vector3i],
	baseline_samples: String,
	baseline_geometry: String,
	edited_samples: String,
	edited_geometry: String
) -> Dictionary:
	_stage = "reconstructive_history"
	var local_failures: Array[String] = []
	var viewer_position := _vector3(scenario.get("viewer_position", []))
	_expect(await harness.stop_world(), "edited world stop failed", local_failures)
	var undo_root := RUNTIME_ROOT.path_join("history_undo")
	Harness.remove_tree(undo_root)
	harness.clear_events()
	_expect(await _start_world(harness, profile, undo_root), "undo reconstruction start failed", local_failures)
	var undo_settlement := await _move_viewer_and_settle(
		profile, 1, viewer_position
	)
	_expect(str(undo_settlement.get("status", "")) == "PASS", "undo reconstruction did not settle", local_failures)
	var undo_sample_records := await _sample_points(harness, points)
	var undo_sample_signature := _sample_signature(undo_sample_records)
	var center := _vector3i(scenario.get("center", []))
	var undo_geometry_signature := _target_geometry_signature(center)
	_expect(undo_sample_signature == baseline_samples, "undo did not restore baseline samples", local_failures)
	_expect(undo_geometry_signature == baseline_geometry, "undo did not restore baseline geometry", local_failures)
	_expect(await harness.stop_world(), "undo world stop failed", local_failures)
	var redo_root := RUNTIME_ROOT.path_join("history_redo")
	Harness.remove_tree(redo_root)
	harness.clear_events()
	_expect(await _start_world(harness, profile, redo_root), "redo reconstruction start failed", local_failures)
	var redo_initial := await _move_viewer_and_settle(
		profile, 1, viewer_position
	)
	_expect(str(redo_initial.get("status", "")) == "PASS", "redo baseline did not settle", local_failures)
	_expect(
		await _commit_transactions(harness, scenario.get("transactions", []), 379000),
		"redo command replay failed",
		local_failures
	)
	var redo_sample_records := await _sample_points(harness, points)
	var redo_sample_signature := _sample_signature(redo_sample_records)
	var redo_geometry_signature := _target_geometry_signature(center)
	_expect(redo_sample_signature == edited_samples, "redo did not restore edited samples", local_failures)
	_expect(redo_geometry_signature == edited_geometry, "redo did not restore edited geometry", local_failures)
	return _action_result(local_failures, {
		"method": "fresh_native_world_enabled_command_reconstruction",
		"undo_sample_signature": undo_sample_signature,
		"undo_geometry_signature": undo_geometry_signature,
		"redo_sample_signature": redo_sample_signature,
		"redo_geometry_signature": redo_geometry_signature,
		"in_place_generic_csg_undo": "UNQUALIFIED_NATIVE_API_ABSENT",
	})


func _geometry_audit(interface_planes: Array) -> Dictionary:
	var nodes := _render_nodes()
	var triangle_keys := {}
	var duplicate_count := 0
	var degenerate_count := 0
	var nonfinite_count := 0
	var triangle_count := 0
	for record in nodes:
		var instance := record.get("node") as MeshInstance3D
		for triangle in _node_triangles(instance):
			triangle_count += 1
			var a: Vector3 = triangle[0]
			var b: Vector3 = triangle[1]
			var c: Vector3 = triangle[2]
			if not a.is_finite() or not b.is_finite() or not c.is_finite():
				nonfinite_count += 1
				continue
			if (b - a).cross(c - a).length_squared() <= AREA_EPSILON_SQUARED:
				degenerate_count += 1
				continue
			var keys := [_point_key(a), _point_key(b), _point_key(c)]
			keys.sort()
			var key := "|".join(keys)
			if triangle_keys.has(key):
				duplicate_count += 1
			triangle_keys[key] = int(triangle_keys.get(key, 0)) + 1
	var interfaces: Array[Dictionary] = []
	var failures: Array[String] = []
	for plane_value in interface_planes:
		var plane: Dictionary = plane_value
		var audit := _interface_audit(
			nodes,
			int(plane.get("axis", -1)),
			float(plane.get("coordinate", INF))
		)
		interfaces.append(audit)
		if str(audit.get("status", "")) != "PASS":
			failures.append(
				"interface edge mismatch at axis %d coordinate %.3f" % [
					int(plane.get("axis", -1)),
					float(plane.get("coordinate", INF)),
				]
			)
	if duplicate_count != 0:
		failures.append("assembled visible terrain contains exact duplicate triangles")
	if degenerate_count != 0:
		failures.append("assembled visible terrain contains degenerate triangles")
	if nonfinite_count != 0:
		failures.append("assembled visible terrain contains nonfinite triangles")
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"visible_chunk_count": nodes.size(),
		"triangle_count": triangle_count,
		"exact_duplicate_triangle_count": duplicate_count,
		"degenerate_triangle_count": degenerate_count,
		"nonfinite_triangle_count": nonfinite_count,
		"interfaces": interfaces,
		"signature": _topology_signature(
			triangle_count, duplicate_count, degenerate_count, interfaces
		),
		"failures": failures,
	}


func _interface_audit(nodes: Array[Dictionary], axis: int, coordinate: float) -> Dictionary:
	var negative := _plane_open_edges(nodes, axis, coordinate, -1)
	var positive := _plane_open_edges(nodes, axis, coordinate, 1)
	var negative_keys: Array = negative.keys()
	var positive_keys: Array = positive.keys()
	negative_keys.sort()
	positive_keys.sort()
	var negative_only: Array[String] = []
	var positive_only: Array[String] = []
	for key in negative_keys:
		if not positive.has(key):
			negative_only.append(str(key))
	for key in positive_keys:
		if not negative.has(key):
			positive_only.append(str(key))
	var passed := not negative_keys.is_empty() \
		and negative_only.is_empty() and positive_only.is_empty()
	return {
		"status": "PASS" if passed else "FAIL",
		"axis": axis,
		"coordinate": coordinate,
		"negative_edge_count": negative_keys.size(),
		"positive_edge_count": positive_keys.size(),
		"negative_only_count": negative_only.size(),
		"positive_only_count": positive_only.size(),
		"sample_negative_only": negative_only.slice(0, mini(8, negative_only.size())),
		"sample_positive_only": positive_only.slice(0, mini(8, positive_only.size())),
	}


func _plane_open_edges(
	nodes: Array[Dictionary], axis: int, coordinate: float, side: int
) -> Dictionary:
	var counts := {}
	for record in nodes:
		var bounds := _key_bounds(record)
		var face_coordinate := bounds.position[axis] if side > 0 else bounds.end[axis]
		if absf(face_coordinate - coordinate) > PLANE_EPSILON:
			continue
		var instance := record.get("node") as MeshInstance3D
		for triangle in _node_triangles(instance):
			for edge in [[0, 1], [1, 2], [2, 0]]:
				var a: Vector3 = triangle[edge[0]]
				var b: Vector3 = triangle[edge[1]]
				if absf(a[axis] - coordinate) > PLANE_EPSILON \
						or absf(b[axis] - coordinate) > PLANE_EPSILON:
					continue
				var key := _segment_key(a, b)
				counts[key] = int(counts.get(key, 0)) + 1
	var result := {}
	for key in counts:
		if int(counts[key]) == 1:
			result[key] = true
	return result


func _render_nodes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_instance_valid(_terrain):
		return result
	for child in _terrain.get_children():
		var name_text := str(child.name)
		if not name_text.begins_with("WT_Render_") or not child is MeshInstance3D:
			continue
		var key := _parse_key(name_text, "WT_Render_")
		if key.is_empty() or bool(key.get("retiring", false)) \
				or not (child as MeshInstance3D).visible:
			continue
		key["node"] = child
		result.append(key)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return result


func _node_triangles(instance: MeshInstance3D) -> Array:
	var result: Array = []
	if instance == null or instance.mesh == null:
		return result
	var origin := instance.position
	for surface in range(instance.mesh.get_surface_count()):
		var arrays := instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for offset in range(0, indices.size(), 3):
			if offset + 2 >= indices.size():
				break
			var ia := int(indices[offset])
			var ib := int(indices[offset + 1])
			var ic := int(indices[offset + 2])
			if ia < 0 or ib < 0 or ic < 0 \
					or ia >= vertices.size() or ib >= vertices.size() or ic >= vertices.size():
				continue
			result.append([origin + vertices[ia], origin + vertices[ib], origin + vertices[ic]])
	return result


func _geometry_signature() -> String:
	var lines: Array[String] = []
	for record in _render_nodes():
		var instance := record.get("node") as MeshInstance3D
		lines.append(str(record.get("id", "")) + ":" + _mesh_signature(instance))
	return "\n".join(lines).sha256_text()


func _target_geometry_signature(center: Vector3i) -> String:
	var coordinate := Vector3i(
		floori(float(center.x) / float(CHUNK_CELLS)),
		floori(float(center.y) / float(CHUNK_CELLS)),
		floori(float(center.z) / float(CHUNK_CELLS))
	)
	var target_id := "%d,%d,%d,L0" % [coordinate.x, coordinate.y, coordinate.z]
	for record in _render_nodes():
		if str(record.get("id", "")) == target_id:
			return _mesh_signature(record.get("node") as MeshInstance3D)
	return "EMPTY"


func _local_geometry_signature(center: Vector3i, radius: float) -> String:
	var lines: Array[String] = []
	var center_vector := Vector3(center)
	var radius_squared := radius * radius
	for record in _render_nodes():
		for triangle in _node_triangles(record.get("node") as MeshInstance3D):
			var centroid: Vector3 = (triangle[0] + triangle[1] + triangle[2]) / 3.0
			if centroid.distance_squared_to(center_vector) > radius_squared:
				continue
			var keys := [
				_point_key(triangle[0]),
				_point_key(triangle[1]),
				_point_key(triangle[2]),
			]
			keys.sort()
			lines.append("|".join(keys))
	lines.sort()
	return "\n".join(lines).sha256_text()


func _mesh_signature(instance: MeshInstance3D) -> String:
	if instance == null or instance.mesh == null:
		return "EMPTY"
	var lines: Array[String] = []
	for surface in range(instance.mesh.get_surface_count()):
		var arrays := instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		lines.append("s:%d:%d:%d" % [surface, vertices.size(), indices.size()])
		for vertex in vertices:
			lines.append("v:" + _point_key(vertex))
		for index_value in indices:
			lines.append("i:%d" % int(index_value))
	return "\n".join(lines).sha256_text()


func _triangle_near_count(center: Vector3, radius: float) -> int:
	var count := 0
	var radius_squared := radius * radius
	for record in _render_nodes():
		for triangle in _node_triangles(record.get("node") as MeshInstance3D):
			var centroid: Vector3 = (triangle[0] + triangle[1] + triangle[2]) / 3.0
			if centroid.distance_squared_to(center) <= radius_squared:
				count += 1
	return count


func _chunk_present(coordinate: Vector3i, lod: int) -> bool:
	var state: RefCounted = _terrain.call("query_chunk_state", coordinate, lod)
	return state != null and bool(state.call("is_present"))


func _sample_points(harness: Node, points: Array[Vector3i]) -> Array[Dictionary]:
	return await harness.request_samples(points, 0)


func _scenario_points(scenario: Dictionary) -> Array[Vector3i]:
	return [
		_vector3i(scenario.get("center", [])),
		_vector3i(scenario.get("outside_probe", [])),
	]


func _sample_signature(samples: Array[Dictionary]) -> String:
	var lines: Array[String] = []
	for sample in samples:
		lines.append("%s:%d:%d" % [
			str(sample.get("point", "")),
			roundi(float(sample.get("density", 0.0)) * POSITION_SCALE),
			int(sample.get("material", 0)),
		])
	return "\n".join(lines).sha256_text()


func _all_samples_pass(samples: Array[Dictionary]) -> bool:
	for sample in samples:
		if str(sample.get("status", "")) != "PASS":
			return false
	return not samples.is_empty()


func _scenario_semantic_signature(
	scenario_id: String,
	samples: Array[Dictionary],
	topology: Dictionary,
	actions: Dictionary
) -> String:
	var action_lines: Array[String] = []
	var action_keys: Array = actions.keys()
	action_keys.sort()
	for key in action_keys:
		action_lines.append("%s:%s" % [key, str((actions[key] as Dictionary).get("status", ""))])
	return "\n".join([
		scenario_id,
		_sample_signature(samples),
		str(topology.get("signature", "")),
		"|".join(action_lines),
	]).sha256_text()


func _topology_signature(
	triangle_count: int,
	duplicate_count: int,
	degenerate_count: int,
	interfaces: Array[Dictionary]
) -> String:
	var lines := ["%d:%d:%d" % [triangle_count, duplicate_count, degenerate_count]]
	for interface in interfaces:
		lines.append("%d:%.3f:%d:%d:%d:%d" % [
			int(interface.get("axis", -1)),
			float(interface.get("coordinate", 0.0)),
			int(interface.get("negative_edge_count", 0)),
			int(interface.get("positive_edge_count", 0)),
			int(interface.get("negative_only_count", 0)),
			int(interface.get("positive_only_count", 0)),
		])
	return "\n".join(lines).sha256_text()


func _move_viewer_and_settle(
	profile: Dictionary, revision: int, position: Vector3
) -> Dictionary:
	var before := _terrain.call("get_runtime_metrics") as Dictionary
	if not _update_viewer(profile, revision, position):
		return {"status": "FAIL", "reason": "viewer_update_rejected"}
	return await _wait_for_settled(
		int(before.get("viewer_updates", 0)) + 1,
		int(before.get("planned_demands", 0)) + 1
	)


func _wait_for_settled(
	minimum_viewer_updates: int = 0,
	minimum_planned_demands: int = 0
) -> Dictionary:
	var started := Time.get_ticks_usec()
	for frame in range(_maximum_settlement_frames):
		var metrics := _terrain.call("get_runtime_metrics") as Dictionary
		var active := int(metrics.get("active_chunk_records", 0))
		var non_retiring := int(metrics.get("non_retiring_chunk_records", active))
		var ready := int(metrics.get("non_retiring_fully_ready_chunk_records", 0))
		if int(metrics.get("viewer_updates", 0)) >= minimum_viewer_updates \
				and int(metrics.get("planned_demands", 0)) >= minimum_planned_demands \
				and active > 0 and ready == non_retiring \
				and int(metrics.get("scheduler_queued_jobs", -1)) == 0 \
				and int(metrics.get("scheduler_queued_completions", -1)) == 0 \
				and int(metrics.get("storage_queued_requests", -1)) == 0 \
				and int(metrics.get("storage_queued_completions", -1)) == 0 \
				and int(metrics.get("storage_active_requests", -1)) == 0 \
				and int(metrics.get("page_loading_records", -1)) == 0 \
				and int(metrics.get("queued_render", -1)) == 0 \
				and int(metrics.get("queued_collision", -1)) == 0 \
				and int(metrics.get("pending_chunk_retirements", -1)) == 0 \
				and int(metrics.get("blocked_pending_chunk_replacements", -1)) == 0 \
				and int(metrics.get("staged_render_resources", -1)) == 0 \
				and int(metrics.get("staged_collision_resources", -1)) == 0:
			return {
				"status": "PASS",
				"frames": frame,
				"elapsed_usec": Time.get_ticks_usec() - started,
			}
		await get_tree().process_frame
	return {
		"status": "FAIL",
		"frames": _maximum_settlement_frames,
		"elapsed_usec": Time.get_ticks_usec() - started,
	}


func _wait_for_empty() -> Dictionary:
	for frame in range(_maximum_settlement_frames):
		var metrics := _terrain.call("get_runtime_metrics") as Dictionary
		if int(metrics.get("active_chunk_records", -1)) == 0 \
				and int(metrics.get("render_resources", -1)) == 0 \
				and int(metrics.get("collision_resources", -1)) == 0 \
				and int(metrics.get("scheduler_queued_jobs", -1)) == 0 \
				and int(metrics.get("storage_active_requests", -1)) == 0 \
				and int(metrics.get("page_loading_records", -1)) == 0:
			return {"status": "PASS", "frames": frame}
		await get_tree().process_frame
	return {"status": "FAIL", "frames": _maximum_settlement_frames}


func _process(_delta_seconds: float) -> void:
	if not is_instance_valid(_terrain) or not _terrain.is_inside_tree():
		return
	var now := Time.get_ticks_usec()
	if _last_frame_usec > 0:
		_frame_samples_usec.append(float(now - _last_frame_usec))
	_last_frame_usec = now
	_audit_frame()


func _audit_frame() -> void:
	if str(_terrain.call("get_world_state_name")) != "running":
		return
	_audited_frame_count += 1
	var metrics := _terrain.call("get_runtime_metrics") as Dictionary
	_last_metrics = metrics
	var render_records := _render_nodes()
	var collision_records := _collision_nodes()
	var render_overlaps := _overlap_count(render_records)
	var collision_overlaps := _overlap_count(collision_records)
	var intentional_empty_stage := _stage in [
		"unload_reload", "world_restart", "reconstructive_history"
	]
	if int(metrics.get("active_chunk_records", 0)) > 0 \
			and render_records.is_empty() and not _stage.ends_with(":startup") \
			and not intentional_empty_stage:
		_hole_frames += 1
		_frame_failure("visible terrain disappeared during " + _stage)
	if render_overlaps > 0:
		_render_overlap_frames += 1
		_frame_failure("visible render ownership overlaps during " + _stage)
	if collision_overlaps > 0:
		_collision_overlap_frames += 1
		_frame_failure("collision ownership overlaps during " + _stage)
	var pipeline_failures := int(metrics.get("application_sink_failures", 0)) \
		+ int(metrics.get("scheduler_queue_rejections", 0)) \
		+ int(metrics.get("storage_request_queue_rejections", 0)) \
		+ int(metrics.get("page_sample_failures", 0)) \
		+ int(metrics.get("page_mesh_failures", 0))
	if pipeline_failures != 0:
		_frame_failure("native pipeline reported a failure during " + _stage)
	_update_maximums(metrics)
	var trace_frame := _audited_frame_count <= 64 \
		or (_audited_frame_count % 10) == 0 \
		or int(metrics.get("pending_chunk_replacements", 0)) > 0 \
		or int(metrics.get("pending_chunk_retirements", 0)) > 0
	if trace_frame and _trace.size() < _trace_limit:
		_trace.append({
			"frame": _audited_frame_count,
			"stage": _stage,
			"world_revision": int(metrics.get("world_revision", 0)),
			"active": int(metrics.get("active_chunk_records", 0)),
			"render_resources": int(metrics.get("render_resources", 0)),
			"collision_resources": int(metrics.get("collision_resources", 0)),
			"pending_replacements": int(metrics.get("pending_chunk_replacements", 0)),
			"pending_retirements": int(metrics.get("pending_chunk_retirements", 0)),
			"queued_jobs": int(metrics.get("scheduler_queued_jobs", 0)),
			"render_overlap": render_overlaps,
			"collision_overlap": collision_overlaps,
		})


func _collision_nodes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_instance_valid(_terrain):
		return result
	for child in _terrain.get_children():
		var name_text := str(child.name)
		if not name_text.begins_with("WT_Collision_") or not child is StaticBody3D:
			continue
		var key := _parse_key(name_text, "WT_Collision_")
		if not key.is_empty():
			result.append(key)
	return result


func _overlap_count(records: Array[Dictionary]) -> int:
	var count := 0
	for left_index in range(records.size()):
		var left := _key_bounds(records[left_index])
		for right_index in range(left_index + 1, records.size()):
			var intersection := left.intersection(_key_bounds(records[right_index]))
			if intersection.size.x > PLANE_EPSILON \
					and intersection.size.y > PLANE_EPSILON \
					and intersection.size.z > PLANE_EPSILON:
				count += 1
	return count


func _update_maximums(metrics: Dictionary) -> void:
	for pair in [
		["maximum_active_chunk_records", "active_chunk_records"],
		["maximum_render_resources", "render_resources"],
		["maximum_collision_resources", "collision_resources"],
		["maximum_render_queue", "queued_render"],
		["maximum_collision_queue", "queued_collision"],
		["maximum_pending_replacements", "pending_chunk_replacements"],
		["maximum_pending_retirements", "pending_chunk_retirements"],
	]:
		_maximums[pair[0]] = maxi(
			int(_maximums.get(pair[0], 0)), int(metrics.get(pair[1], 0))
		)


func _finish_scenario(
	harness: Node,
	scenario: Dictionary,
	details: Dictionary,
	failures: Array[String]
) -> Dictionary:
	var stopped := false
	if is_instance_valid(harness):
		stopped = await harness.stop_world()
	if not stopped:
		failures.append("native world did not stop cleanly")
	if is_instance_valid(harness):
		harness.dispose()
		harness.queue_free()
		await get_tree().process_frame
	_terrain = null
	var output := details.duplicate(true)
	output["id"] = scenario.get("id", "")
	output["operation_kind"] = scenario.get("operation_kind", "")
	output["status"] = "PASS" if failures.is_empty() else "FAIL"
	output["failures"] = failures
	return output


func _report(
	standard: Dictionary,
	scenarios: Array[Dictionary],
	failures: Array[String]
) -> Dictionary:
	for frame_failure in _frame_failures.keys():
		failures.append(str(frame_failure))
	var scenario_lines: Array[String] = []
	var semantic_lines: Array[String] = []
	for scenario in scenarios:
		scenario_lines.append("%s:%s:%s" % [
			str(scenario.get("id", "")),
			str(scenario.get("status", "")),
			str(scenario.get("semantic_signature", "")),
		])
		semantic_lines.append(str(scenario.get("semantic_signature", "")))
	var matrix_signature := "\n".join(scenario_lines).sha256_text()
	var final_semantic_signature := "\n".join(semantic_lines).sha256_text()
	var stable: Dictionary = standard.get("stable_expected", {})
	var expected_matrix := str(stable.get("scenario_matrix_signature", ""))
	var expected_semantic := str(stable.get("final_semantic_signature", ""))
	if _scenario_filter.is_empty() and not expected_matrix.is_empty() \
			and matrix_signature != expected_matrix:
		failures.append("scenario matrix signature changed")
	if _scenario_filter.is_empty() and not expected_semantic.is_empty() \
			and final_semantic_signature != expected_semantic:
		failures.append("final semantic signature changed")
	var budgets: Dictionary = standard.get("budgets", {})
	var frame_distribution := Statistics.distribution(_frame_samples_usec)
	var scenario_distribution := Statistics.distribution(_scenario_samples_usec)
	_expect(
		float(frame_distribution.get("p99_usec", INF))
			<= float(budgets.get("maximum_frame_p99_usec", 0.0)),
		"frame p99 diagnostic ceiling exceeded",
		failures
	)
	_expect(
		float(frame_distribution.get("worst_usec", INF))
			<= float(budgets.get("maximum_frame_usec", 0.0)),
		"frame worst diagnostic ceiling exceeded",
		failures
	)
	_expect(
		float(scenario_distribution.get("p95_usec", INF))
			<= float(budgets.get("maximum_scenario_p95_usec", 0.0)),
		"scenario p95 diagnostic ceiling exceeded",
		failures
	)
	for pair in [
		["maximum_active_chunk_records", "maximum_active_chunk_records"],
		["maximum_render_resources", "maximum_render_resources"],
		["maximum_collision_resources", "maximum_collision_resources"],
	]:
		_expect(
			int(_maximums.get(pair[0], 0)) <= int(budgets.get(pair[1], 0)),
			str(pair[0]) + " ceiling exceeded",
			failures
		)
	var status := "PASS" if failures.is_empty() else "FAIL"
	return {
		"schema": "world_transvoxel.terrain_lab.adaptive_edit_qualification.v1",
		"milestone": "TQP-37",
		"standard_id": standard.get("standard_id", ""),
		"authority": standard.get("authority", ""),
		"status": status,
		"retained_complete": status == "PASS",
		"provenance": Statistics.provenance(matrix_signature),
		"coverage": {
			"scenario_count": scenarios.size(),
			"passed_scenario_count": scenarios.filter(
				func(value: Dictionary) -> bool: return str(value.get("status", "")) == "PASS"
			).size(),
			"audited_frame_count": _audited_frame_count,
			"dig_scenario_count": scenarios.filter(
				func(value: Dictionary) -> bool: return str(value.get("operation_kind", "")) == "dig"
			).size(),
			"construction_scenario_count": scenarios.filter(
				func(value: Dictionary) -> bool: return str(value.get("operation_kind", "")) == "construct"
			).size(),
		},
		"temporal_invariants": {
			"visible_hole_frames": _hole_frames,
			"render_overlap_frames": _render_overlap_frames,
			"double_collision_frames": _collision_overlap_frames,
			"frame_failure_count": _frame_failures.size(),
		},
		"scenarios": scenarios,
		"scenario_matrix_signature": matrix_signature,
		"final_semantic_signature": final_semantic_signature,
		"frame_trace": _trace,
		"performance": {
			"frame": frame_distribution,
			"scenario": scenario_distribution,
			"memory": Statistics.memory_metrics(),
			"scope": "WINDOWS_DEBUG_DIAGNOSTIC_ADAPTIVE_EDIT_NOT_PRODUCTION_FRAME_BUDGET",
		},
		"resources": _maximums,
		"history_policy": standard.get("history_policy", {}),
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
		"runtime_metrics": _last_metrics,
		"standard_validation": "PASS" if status == "PASS" else "FAIL",
	}


func _validate_contract(standard: Dictionary, failures: Array[String]) -> void:
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.adaptive_edit_standard.v1",
		"adaptive edit standard schema mismatch",
		failures
	)
	_expect(str(standard.get("milestone", "")) == "TQP-37", "milestone changed", failures)
	_expect(
		str(standard.get("authority", "")) == "world_transvoxel_native_runtime",
		"native authority changed",
		failures
	)
	var scenarios: Array = (standard.get("workload", {}) as Dictionary).get("scenarios", [])
	_expect(scenarios.size() == 6, "adaptive edit scenario count changed", failures)
	var ids := {}
	for scenario_value in scenarios:
		var scenario: Dictionary = scenario_value
		ids[str(scenario.get("id", ""))] = true
		_expect(not (scenario.get("transactions", []) as Array).is_empty(), "scenario lacks edits", failures)
	for required in (standard.get("workload", {}) as Dictionary).get("required_actions", []):
		_expect(ids.has(str(required)), "missing adaptive edit scenario: " + str(required), failures)
	var history: Dictionary = standard.get("history_policy", {})
	_expect(
		str(history.get("in_place_generic_csg_undo", ""))
			== "UNQUALIFIED_NATIVE_API_ABSENT",
		"generic native CSG undo boundary changed",
		failures
	)


func _validate_results(
	standard: Dictionary,
	scenarios: Array[Dictionary],
	failures: Array[String]
) -> void:
	var ids := {}
	for scenario in scenarios:
		ids[str(scenario.get("id", ""))] = scenario
	for required in (standard.get("workload", {}) as Dictionary).get("required_actions", []):
		_expect(
			ids.has(str(required)) and str((ids[str(required)] as Dictionary).get("status", "")) == "PASS",
			"required scenario did not pass: " + str(required),
			failures
		)


func _reset() -> void:
	_terrain = null
	_stage = "startup"
	_trace.clear()
	_frame_samples_usec.clear()
	_scenario_samples_usec.clear()
	_last_frame_usec = 0
	_audited_frame_count = 0
	_hole_frames = 0
	_render_overlap_frames = 0
	_collision_overlap_frames = 0
	_frame_failures.clear()
	_maximums = {
		"maximum_active_chunk_records": 0,
		"maximum_render_resources": 0,
		"maximum_collision_resources": 0,
		"maximum_render_queue": 0,
		"maximum_collision_queue": 0,
		"maximum_pending_replacements": 0,
		"maximum_pending_retirements": 0,
	}
	_last_metrics.clear()
	_scenario_filter = ""
	set_process(false)


func _start_monitoring() -> void:
	_last_frame_usec = Time.get_ticks_usec()
	set_process(true)


func _frame_failure(message: String) -> void:
	_frame_failures[message] = true


func _append_action_failures(
	label: String, result: Dictionary, failures: Array[String]
) -> void:
	for value in result.get("failures", []):
		failures.append(label + ": " + str(value))


static func _action_result(failures: Array[String], details: Dictionary = {}) -> Dictionary:
	var result := details.duplicate(true)
	result["status"] = "PASS" if failures.is_empty() else "FAIL"
	result["failures"] = failures
	return result


static func _delta(after: Dictionary, before: Dictionary, key: String) -> int:
	return int(after.get(key, 0)) - int(before.get(key, 0))


static func _parse_key(node_name: String, prefix: String) -> Dictionary:
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


static func _key_bounds(key: Dictionary) -> AABB:
	var extent := float(CHUNK_CELLS * (1 << int(key.get("lod", 0))))
	return AABB(
		Vector3(
			float(key.get("x", 0)) * extent,
			float(key.get("y", 0)) * extent,
			float(key.get("z", 0)) * extent
		),
		Vector3.ONE * extent
	)


static func _point_key(point: Vector3) -> String:
	return "%d,%d,%d" % [
		roundi(point.x * POSITION_SCALE),
		roundi(point.y * POSITION_SCALE),
		roundi(point.z * POSITION_SCALE),
	]


static func _segment_key(a: Vector3, b: Vector3) -> String:
	var first := _point_key(a)
	var second := _point_key(b)
	return first + "|" + second if first < second else second + "|" + first


static func _vector3(value: Variant) -> Vector3:
	var values: Array = value if value is Array else []
	return Vector3(
		float(values[0]) if values.size() > 0 else 0.0,
		float(values[1]) if values.size() > 1 else 0.0,
		float(values[2]) if values.size() > 2 else 0.0
	)


static func _vector3i(value: Variant) -> Vector3i:
	var vector := _vector3(value)
	return Vector3i(roundi(vector.x), roundi(vector.y), roundi(vector.z))


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
