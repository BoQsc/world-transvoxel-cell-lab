@tool
extends RefCounted
class_name WtTerrainLabAdaptiveLodQualification

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const Selector := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_adaptive_lod_selector.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)

const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/adaptive_lod_standard.json"
)


static func run(scenario_filter: String = "") -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var selector := Selector.new()
	var failures: Array[String] = []
	if not selector.configure(standard):
		failures.append("adaptive LOD selector rejected the standard")
	var contract := (
		_qualify_contract(selector, standard)
		if scenario_filter.is_empty()
		else {"status": "FOCUSED_REPRO", "checks": [], "failures": []}
	)
	if scenario_filter.is_empty() and str(contract.get("status", "")) != "PASS":
		failures.append_array(contract.get("failures", []))
	var scenario_results: Array[Dictionary] = []
	var signature_lines: Array[String] = []
	var timing_samples: Array[float] = []
	for scenario_value in standard.get("scenarios", []):
		if not scenario_value is Dictionary:
			failures.append("standard contains a non-dictionary scenario")
			continue
		var scenario: Dictionary = scenario_value
		var scenario_id := str(scenario.get("id", ""))
		if not scenario_filter.is_empty() and scenario_id != scenario_filter:
			continue
		var scenario_started := Time.get_ticks_usec()
		var root_origin := _vector3i(scenario.get("root_origin_chunk", []))
		var viewer := _vector3(scenario.get("viewer_local_m", []))
		var first := selector.select(root_origin, viewer)
		var second := selector.select(root_origin, viewer)
		var validation: Dictionary = first.get("validation", {})
		var scenario_failures: Array[String] = []
		if str(validation.get("status", "")) != "PASS":
			scenario_failures.append_array(validation.get("failures", []))
		if str(first.get("signature", "")) != str(second.get("signature", "")):
			scenario_failures.append("cold deterministic signatures differ")
		var histogram := _lod_histogram(first.get("leaves", []))
		var elapsed_usec := Time.get_ticks_usec() - scenario_started
		timing_samples.append(float(elapsed_usec))
		var result := {
			"scenario_id": scenario_id,
			"status": "PASS" if scenario_failures.is_empty() else "FAIL",
			"root_origin_chunk": root_origin,
			"viewer_local_m": viewer,
			"signature": first.get("signature", ""),
			"warm_signature": second.get("signature", ""),
			"leaf_count": (first.get("leaves", []) as Array).size(),
			"lod_histogram": histogram,
			"balance_split_count": first.get("balance_split_count", 0),
			"validation": validation,
			"elapsed_usec": elapsed_usec,
			"minimized_repro": {
				"runner": "res://labs/terrain_lab/tools/run_adaptive_lod_validation.gd",
				"arguments": ["--scenario", scenario_id],
				"scenario": scenario,
				"signature": first.get("signature", ""),
			},
			"failures": scenario_failures,
		}
		scenario_results.append(result)
		signature_lines.append(scenario_id + ":" + str(first.get("signature", "")))
		if not scenario_failures.is_empty():
			for failure in scenario_failures:
				failures.append(scenario_id + ": " + failure)
	if scenario_results.is_empty():
		failures.append("no adaptive LOD scenarios matched")
	var negative_controls := (
		_negative_controls(selector)
		if scenario_filter.is_empty()
		else {"status": "FOCUSED_REPRO", "control_count": 0, "controls": [], "failures": []}
	)
	if scenario_filter.is_empty() and str(negative_controls.get("status", "")) != "PASS":
		failures.append_array(negative_controls.get("failures", []))
	var budgets: Dictionary = standard.get("budgets", {})
	if scenario_filter.is_empty() and scenario_results.size() \
			< int(budgets.get("minimum_scenario_count", 0)):
		failures.append("adaptive LOD scenario coverage is incomplete")
	var distribution := Statistics.distribution(timing_samples)
	if scenario_filter.is_empty() and float(distribution.get("p95_usec", INF)) \
			> float(budgets.get("maximum_scenario_p95_usec", 0.0)):
		failures.append("adaptive LOD scenario p95 exceeded")
	var elapsed_usec := Time.get_ticks_usec() - started_usec
	if elapsed_usec > int(budgets.get("maximum_total_usec", 0)):
		failures.append("adaptive LOD qualification duration exceeded")
	signature_lines.sort()
	var corpus_signature := "\n".join(signature_lines).sha256_text()
	return {
		"schema": "world_transvoxel.terrain_lab.adaptive_lod_qualification.v1",
		"standard_id": standard.get("standard_id", ""),
		"authority": standard.get("authority", ""),
		"milestone": "TQP-30",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"retained_complete": scenario_filter.is_empty(),
		"scenario_filter": scenario_filter,
		"contract": contract,
		"scenario_corpus": {
			"scenario_count": scenario_results.size(),
			"signature": corpus_signature,
			"scenarios": scenario_results,
		},
		"negative_controls": negative_controls,
		"performance": {
			"profile": "debug_regression_reference_not_production_budget",
			"elapsed_usec": elapsed_usec,
			"scenario_distribution": distribution,
		},
		"provenance": Statistics.provenance(corpus_signature),
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


static func _qualify_contract(selector: RefCounted, standard: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	var checks: Array[Dictionary] = []
	var contract: Dictionary = standard.get("contract", {})
	_check(
		str(contract.get("hierarchy", ""))
			== "balanced_octree_over_finite_cubic_lod0_chunk_domain",
		"hierarchy_policy",
		"hierarchy policy changed",
		checks,
		failures
	)
	_check(
		selector.maximum_neighbor_delta == 1,
		"maximum_neighbor_delta",
		"maximum face-neighbor LOD delta changed",
		checks,
		failures
	)
	var root := Vector3i.ZERO
	_check(
		is_zero_approx(selector.distance_to_node_m(root, 4, root, Vector3(64.0, 64.0, 64.0)))
			and is_equal_approx(
				selector.distance_to_node_m(root, 4, root, Vector3(138.0, 64.0, 64.0)),
				10.0
			),
		"viewer_metric",
		"viewer-to-node AABB metric failed analytical cases",
		checks,
		failures
	)
	var near_viewer := Vector3(159.0, 64.0, 64.0)
	var middle_viewer := Vector3(168.0, 64.0, 64.0)
	var far_viewer := Vector3(177.0, 64.0, 64.0)
	var near: Dictionary = selector.call("select", root, near_viewer)
	var warm_middle: Dictionary = selector.call(
		"select",
		root,
		middle_viewer,
		near.get("leaves", []),
		near_viewer
	)
	var cold_middle: Dictionary = selector.call("select", root, middle_viewer)
	var warm_far: Dictionary = selector.call(
		"select",
		root,
		far_viewer,
		warm_middle.get("leaves", []),
		middle_viewer
	)
	_check(
		(near.get("leaves", []) as Array).size() > 1
			and (warm_middle.get("leaves", []) as Array).size() > 1
			and (cold_middle.get("leaves", []) as Array).size() == 1
			and (warm_far.get("leaves", []) as Array).size() == 1,
		"split_merge_hysteresis",
		"split/merge hysteresis did not retain and release the root deterministically",
		checks,
		failures
	)
	var local_viewer := Vector3(38.0, 57.0, 79.0)
	var local_selection: Dictionary = selector.call("select", Vector3i.ZERO, local_viewer)
	var shifted_selection: Dictionary = selector.call(
		"select",
		Vector3i(-1000000, 750000, 500000),
		local_viewer
	)
	_check(
		str(local_selection.get("signature", ""))
			== str(shifted_selection.get("signature", "")),
		"origin_shift_identity",
		"integer origin shift changed normalized selection",
		checks,
		failures
	)
	var center_viewer := Vector3(64.0, 64.0, 64.0)
	var center: Dictionary = selector.call("select", root, center_viewer)
	var teleported_viewer := Vector3(400.0, 64.0, 64.0)
	var teleported: Dictionary = selector.call(
		"select",
		root,
		teleported_viewer,
		center.get("leaves", []),
		center_viewer
	)
	var teleport_cold: Dictionary = selector.call("select", root, teleported_viewer)
	_check(
		bool(teleported.get("teleport_reset", false))
			and str(teleported.get("signature", ""))
				== str(teleport_cold.get("signature", "")),
		"teleport_convergence",
		"teleport did not clear hysteresis and converge in one selection",
		checks,
		failures
	)
	var threshold_ordered := true
	for lod in range(1, selector.max_lod + 1):
		threshold_ordered = threshold_ordered \
			and selector.merge_distances_m[lod] >= selector.split_distances_m[lod]
	_check(
		threshold_ordered,
		"threshold_order",
		"merge threshold precedes split threshold",
		checks,
		failures
	)
	return {
		"schema": "world_transvoxel.terrain_lab.adaptive_lod_contract_qualification.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"checks": checks,
		"failures": failures,
	}


static func _negative_controls(selector: RefCounted) -> Dictionary:
	var failures: Array[String] = []
	var controls: Array[Dictionary] = []
	var base: Dictionary = selector.select(Vector3i.ZERO, Vector3(4.0, 4.0, 4.0))
	var overlap := base.duplicate(true)
	(overlap["leaves"] as Array).append({"origin": Vector3i.ZERO, "lod": selector.max_lod})
	_record_negative(
		"parent_child_overlap",
		selector.validate_selection(overlap),
		"overlap_cells",
		controls,
		failures
	)
	var hole := base.duplicate(true)
	(hole["leaves"] as Array).remove_at(0)
	_record_negative(
		"coverage_hole",
		selector.validate_selection(hole),
		"missing_cells",
		controls,
		failures
	)
	var misaligned := base.duplicate(true)
	var misaligned_leaves: Array = misaligned.get("leaves", [])
	var misaligned_index := _first_lod_at_least(misaligned_leaves, 1)
	if misaligned_index >= 0:
		var shifted_leaf: Dictionary = misaligned_leaves[misaligned_index]
		shifted_leaf["origin"] = shifted_leaf.get("origin", Vector3i.ZERO) + Vector3i.RIGHT
		misaligned_leaves[misaligned_index] = shifted_leaf
	_record_negative(
		"misaligned_node",
		selector.validate_selection(misaligned),
		"misaligned_nodes",
		controls,
		failures
	)
	var invalid_lod := base.duplicate(true)
	(invalid_lod["leaves"] as Array).append({
		"origin": Vector3i.ZERO,
		"lod": selector.max_lod + 1,
	})
	_record_negative(
		"out_of_range_lod",
		selector.validate_selection(invalid_lod),
		"invalid_lod_nodes",
		controls,
		failures
	)
	var delta := base.duplicate(true)
	var delta_leaves: Array = delta.get("leaves", [])
	var coarse_index := _first_lod_at_least(delta_leaves, 2)
	if coarse_index >= 0:
		var coarse: Dictionary = delta_leaves[coarse_index]
		delta_leaves.remove_at(coarse_index)
		delta_leaves.append_array(_unit_descendants(coarse))
	_record_negative(
		"neighbor_delta_above_one",
		selector.validate_selection(delta),
		"neighbor_delta_violations",
		controls,
		failures
	)
	var split_record := base.duplicate(true)
	var records: Array = split_record.get("split_records", [])
	if not records.is_empty():
		var first_record: Dictionary = records[0]
		var children: Array = first_record.get("children", [])
		if not children.is_empty():
			children.remove_at(children.size() - 1)
		first_record["children"] = children
		records[0] = first_record
	_record_negative(
		"incomplete_split_record",
		selector.validate_selection(split_record),
		"invalid_split_records",
		controls,
		failures
	)
	return {
		"schema": "world_transvoxel.terrain_lab.adaptive_lod_negative_controls.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"control_count": controls.size(),
		"controls": controls,
		"failures": failures,
	}


static func _record_negative(
	control_id: String,
	validation: Dictionary,
	expected_metric: String,
	controls: Array[Dictionary],
	failures: Array[String]
) -> void:
	var detected := str(validation.get("status", "")) == "FAIL" \
		and int(validation.get(expected_metric, 0)) > 0
	controls.append({
		"id": control_id,
		"status": "PASS" if detected else "FAIL",
		"expected_metric": expected_metric,
		"observed_count": validation.get(expected_metric, 0),
	})
	if not detected:
		failures.append(control_id + " was not rejected by " + expected_metric)


static func _unit_descendants(node: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var origin: Vector3i = node.get("origin", Vector3i.ZERO)
	var span := 1 << int(node.get("lod", 0))
	for z in range(span):
		for y in range(span):
			for x in range(span):
				result.append({"origin": origin + Vector3i(x, y, z), "lod": 0})
	return result


static func _first_lod_at_least(leaves: Array, minimum_lod: int) -> int:
	for index in range(leaves.size()):
		if int((leaves[index] as Dictionary).get("lod", -1)) >= minimum_lod:
			return index
	return -1


static func _lod_histogram(leaves: Array) -> Dictionary:
	var result := {}
	for leaf_value in leaves:
		var lod := str(int((leaf_value as Dictionary).get("lod", -1)))
		result[lod] = int(result.get(lod, 0)) + 1
	return result


static func _check(
	condition: bool,
	check_id: String,
	failure: String,
	checks: Array[Dictionary],
	failures: Array[String]
) -> void:
	checks.append({"id": check_id, "status": "PASS" if condition else "FAIL"})
	if not condition:
		failures.append(failure)


static func _vector3i(value: Variant) -> Vector3i:
	if value is Array and value.size() == 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return value if value is Vector3i else Vector3i.ZERO


static func _vector3(value: Variant) -> Vector3:
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return value if value is Vector3 else Vector3.ZERO
