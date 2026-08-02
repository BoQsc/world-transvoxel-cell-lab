@tool
extends RefCounted
class_name WtTerrainLabStreamingWindowQualification

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)

const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/streaming_window_standard.json"
)
const STANDARD_SCHEMA := "world_transvoxel.terrain_lab.streaming_window_standard.v1"


static func run() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var failures: Array[String] = []
	_validate_standard(standard, failures)
	var corpus := _run_fixture_corpus(standard, failures)
	var performance := _benchmark(standard, failures)
	return {
		"milestone": "TQP-19",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"qualification_status": "QUALIFIED_DETERMINISTIC_HORIZONTAL_STREAMING_WINDOW_REFERENCE_V1",
		"fixture_count": int(corpus.get("fixture_count", 0)),
		"fixture_corpus": corpus,
		"performance": performance,
		"memory": Statistics.memory_metrics(),
		"provenance": Statistics.provenance("tqp19_streaming_window_reference_v1"),
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


static func _validate_standard(standard: Dictionary, failures: Array[String]) -> void:
	_expect(str(standard.get("schema", "")) == STANDARD_SCHEMA, "streaming standard schema changed", failures)
	_expect(str(standard.get("milestone", "")) == "TQP-19", "streaming standard milestone changed", failures)
	var contract: Dictionary = standard.get("window_contract", {})
	_expect(str(contract.get("window_axes", "")) == "x_z_with_single_y_layer", "streaming axes changed", failures)
	var active_radius := int(contract.get("active_radius_chunks", -1))
	var prefetch_radius := int(contract.get("prefetch_radius_chunks", -1))
	_expect(active_radius == 3, "active radius changed", failures)
	_expect(prefetch_radius == 4, "prefetch radius changed", failures)
	_expect(prefetch_radius > active_radius, "prefetch radius must exceed active radius", failures)
	_expect(int(contract.get("active_chunk_budget", 0)) == 49, "active chunk budget changed", failures)
	_expect(int(contract.get("prefetch_chunk_budget", 0)) == 81, "prefetch chunk budget changed", failures)
	_expect(float(contract.get("center_hysteresis_m", 0.0)) > 0.0, "hysteresis must be positive", failures)


static func _run_fixture_corpus(standard: Dictionary, failures: Array[String]) -> Dictionary:
	var contract: Dictionary = standard.get("window_contract", {})
	var fixture: Dictionary = standard.get("fixture_contract", {})
	var fixture_count := 0
	var path_records: Array[Dictionary] = []

	var state := _new_state(Vector3(8.0, 0.0, 8.0), contract)
	var initial := _snapshot(state)
	_expect(int(initial.get("active_count", 0)) == int(contract.get("active_chunk_budget", 0)), "initial active window count changed", failures)
	_expect(int(initial.get("prefetch_count", 0)) == int(contract.get("prefetch_chunk_budget", 0)), "initial prefetch window count changed", failures)
	var lod_counts: Dictionary = initial.get("lod_counts", {})
	_expect(int(lod_counts.get(0, 0)) == 9, "LOD0 ring count changed", failures)
	_expect(int(lod_counts.get(1, 0)) == 16, "LOD1 ring count changed", failures)
	_expect(int(lod_counts.get(2, 0)) == 24, "LOD2 ring count changed", failures)
	_expect(int(lod_counts.get(3, 0)) == 32, "LOD3 prefetch ring count changed", failures)
	fixture_count += 6

	var jitter_path: Array[Vector3] = [
		Vector3(15.9, 0.0, 8.0),
		Vector3(16.1, 0.0, 8.0),
		Vector3(15.8, 0.0, 8.0),
		Vector3(16.2, 0.0, 8.0),
		Vector3(15.95, 0.0, 8.0),
	]
	var churn_before := int(state.get("center_changes", 0))
	for position in jitter_path:
		var record := _update(state, position, contract)
		_expect(record.get("center", Vector3i.ZERO) == Vector3i.ZERO, "boundary jitter moved the stream center", failures)
		fixture_count += 1
	var jitter_churn := int(state.get("center_changes", 0)) - churn_before
	_expect(jitter_churn <= int(fixture.get("boundary_jitter_churn_budget", -1)), "boundary jitter exceeded churn budget", failures)
	fixture_count += 1
	path_records.append({"id": "boundary_jitter", "updates": jitter_path.size(), "center_changes": jitter_churn})

	var crossed := _update(state, Vector3(18.1, 0.0, 8.0), contract)
	_expect(crossed.get("center", Vector3i.ZERO) == Vector3i(1, 0, 0), "forward hysteresis threshold did not advance", failures)
	_update(state, Vector3(14.1, 0.0, 8.0), contract)
	_expect(state.get("center", Vector3i.ZERO) == Vector3i(1, 0, 0), "reverse hysteresis released too early", failures)
	_update(state, Vector3(13.9, 0.0, 8.0), contract)
	_expect(state.get("center", Vector3i.ZERO) == Vector3i.ZERO, "reverse hysteresis threshold did not release", failures)
	fixture_count += 3

	var traversal_state := _new_state(Vector3(8.0, 0.0, 8.0), contract)
	var maximum_resident := 0
	var previous_center: Vector3i = traversal_state.get("center", Vector3i.ZERO)
	for index in range(64):
		var position := Vector3(8.0 + float(index) * 8.0, 0.0, 8.0 + sin(float(index) * 0.2) * 3.0)
		var record := _update(traversal_state, position, contract)
		var center: Vector3i = record.get("center", Vector3i.ZERO)
		_expect(absi(center.x - previous_center.x) <= 1, "steady traversal skipped a chunk center", failures)
		_expect(int(record.get("active_count", 0)) == 49, "steady traversal active count changed", failures)
		_expect(int(record.get("prefetch_count", 0)) == 81, "steady traversal prefetch count changed", failures)
		maximum_resident = maxi(maximum_resident, int(record.get("resident_count", 0)))
		previous_center = center
		fixture_count += 1
	_expect(maximum_resident <= int(contract.get("retained_chunk_budget", 0)), "steady traversal exceeded retained budget", failures)
	path_records.append({"id": "steady_traversal", "updates": 64, "maximum_resident": maximum_resident})
	fixture_count += 1

	var negative_state := _new_state(Vector3(-0.1, 0.0, -0.1), contract)
	_expect(negative_state.get("center", Vector3i.ZERO) == Vector3i(-1, 0, -1), "negative initial chunk addressing changed", failures)
	_update(negative_state, Vector3(-18.1, 0.0, -18.1), contract)
	_expect(negative_state.get("center", Vector3i.ZERO) == Vector3i(-2, 0, -2), "negative traversal hysteresis changed", failures)
	path_records.append({"id": "negative_traversal", "updates": 2, "final_center": negative_state.get("center", Vector3i.ZERO)})
	fixture_count += 2

	var eviction_state := _new_state(Vector3(8.0, 0.0, 8.0), contract)
	var old_edge_key := _chunk_key(Vector3i(-4, 0, 0))
	_update(eviction_state, Vector3(18.1, 0.0, 8.0), contract)
	for grace_update in range(int(contract.get("eviction_grace_updates", 0)) - 1):
		_update(eviction_state, Vector3(24.0, 0.0, 8.0), contract)
		_expect((eviction_state.get("residents", {}) as Dictionary).has(old_edge_key), "resident evicted before grace expired", failures)
		fixture_count += 1
	_expect((eviction_state.get("residents", {}) as Dictionary).has(old_edge_key), "resident grace did not cover declared updates", failures)
	_update(eviction_state, Vector3(24.0, 0.0, 8.0), contract)
	_expect(not (eviction_state.get("residents", {}) as Dictionary).has(old_edge_key), "resident survived beyond eviction grace", failures)
	fixture_count += 2

	var teleport_state := _new_state(Vector3(8.0, 0.0, 8.0), contract)
	var old_center_key := _chunk_key(Vector3i.ZERO)
	var teleport_position := Vector3(328.0, 0.0, -312.0)
	var teleport_record := _update(teleport_state, teleport_position, contract)
	_expect(bool(teleport_record.get("teleported", false)), "teleport was not detected", failures)
	_expect(int(teleport_record.get("resident_count", 0)) == 81, "teleport did not converge in one update", failures)
	_expect(not (teleport_state.get("residents", {}) as Dictionary).has(old_center_key), "teleport retained the abandoned center", failures)
	path_records.append({"id": "teleport", "updates": 1, "final_center": teleport_record.get("center", Vector3i.ZERO)})
	fixture_count += 3

	var edit_state := _new_state(Vector3(8.0, 0.0, 8.0), contract)
	var resident_coordinate := Vector3i.ZERO
	var resident_key := _chunk_key(resident_coordinate)
	var resident_edit := _apply_edit(edit_state, resident_coordinate)
	_expect(bool(resident_edit.get("requested", false)), "resident edit did not request regeneration", failures)
	_expect(bool(((edit_state.get("residents", {}) as Dictionary)[resident_key] as Dictionary).get("dirty", false)), "resident edit did not mark dirty", failures)
	var generation := int(resident_edit.get("generation", 0))
	_expect(_can_publish(edit_state, resident_coordinate, generation), "current edited generation was rejected", failures)
	_expect(not _can_publish(edit_state, resident_coordinate, generation - 1), "stale edited generation was accepted", failures)
	var resident_count_before := (edit_state.get("residents", {}) as Dictionary).size()
	var distant_coordinate := Vector3i(100, 0, -100)
	var distant_edit := _apply_edit(edit_state, distant_coordinate)
	_expect(not bool(distant_edit.get("requested", true)), "nonresident edit forced residency", failures)
	_expect((edit_state.get("residents", {}) as Dictionary).size() == resident_count_before, "nonresident edit changed residency", failures)
	_expect((edit_state.get("edit_journal", {}) as Dictionary).has(_chunk_key(distant_coordinate)), "nonresident edit was not retained", failures)
	fixture_count += 7

	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"fixture_count": fixture_count,
		"paths": path_records,
		"active_chunk_count": 49,
		"prefetch_chunk_count": 81,
		"maximum_retained_chunk_count": maximum_resident,
		"eviction_grace_updates": int(contract.get("eviction_grace_updates", 0)),
		"teleport_convergence_updates": int(fixture.get("teleport_convergence_updates", 0)),
	}


static func _new_state(position: Vector3, contract: Dictionary) -> Dictionary:
	var center := _world_to_chunk(position, float(contract.get("chunk_world_size_m", 16.0)))
	var state := {
		"center": center,
		"residents": {},
		"generations": {},
		"edit_journal": {},
		"center_changes": 0,
		"updates": 0,
	}
	_update_residents(state, _window(center, contract), contract, false)
	return state


static func _update(state: Dictionary, position: Vector3, contract: Dictionary) -> Dictionary:
	var previous: Vector3i = state.get("center", Vector3i.ZERO)
	var raw := _world_to_chunk(position, float(contract.get("chunk_world_size_m", 16.0)))
	var teleport_distance := maxi(absi(raw.x - previous.x), absi(raw.z - previous.z))
	var teleported := teleport_distance > int(contract.get("teleport_threshold_chunks", 0))
	var center := raw if teleported else _hysteretic_center(previous, position, contract)
	if center != previous:
		state["center_changes"] = int(state.get("center_changes", 0)) + 1
	state["center"] = center
	state["updates"] = int(state.get("updates", 0)) + 1
	var desired := _window(center, contract)
	_update_residents(state, desired, contract, teleported)
	var result := _snapshot(state)
	result["teleported"] = teleported
	return result


static func _hysteretic_center(center: Vector3i, position: Vector3, contract: Dictionary) -> Vector3i:
	var size := float(contract.get("chunk_world_size_m", 16.0))
	var margin := float(contract.get("center_hysteresis_m", 0.0))
	return Vector3i(
		_hysteretic_axis(center.x, position.x, size, margin),
		floori(position.y / size),
		_hysteretic_axis(center.z, position.z, size, margin)
	)


static func _hysteretic_axis(center: int, position: float, size: float, margin: float) -> int:
	var minimum := float(center) * size - margin
	var maximum := float(center + 1) * size + margin
	if position < minimum or position >= maximum:
		return floori(position / size)
	return center


static func _window(center: Vector3i, contract: Dictionary) -> Dictionary:
	var prefetch_radius := int(contract.get("prefetch_radius_chunks", 4))
	var active_radius := int(contract.get("active_radius_chunks", 3))
	var result := {}
	for x in range(center.x - prefetch_radius, center.x + prefetch_radius + 1):
		for z in range(center.z - prefetch_radius, center.z + prefetch_radius + 1):
			var coordinate := Vector3i(x, center.y, z)
			var distance := maxi(absi(x - center.x), absi(z - center.z))
			result[_chunk_key(coordinate)] = {
				"coordinate": coordinate,
				"lod": _lod_for_distance(distance),
				"active": distance <= active_radius,
			}
	return result


static func _update_residents(
	state: Dictionary,
	desired: Dictionary,
	contract: Dictionary,
	teleported: bool
) -> void:
	var residents: Dictionary = state.get("residents", {})
	if teleported:
		residents.clear()
	for key in residents.keys():
		if desired.has(key):
			continue
		var record: Dictionary = residents[key]
		record["outside_updates"] = int(record.get("outside_updates", 0)) + 1
		if int(record["outside_updates"]) > int(contract.get("eviction_grace_updates", 0)):
			residents.erase(key)
	for key in desired:
		var desired_record: Dictionary = desired[key]
		var generation := int((state.get("generations", {}) as Dictionary).get(key, 0))
		var resident: Dictionary = residents.get(key, {})
		resident["coordinate"] = desired_record["coordinate"]
		resident["lod"] = desired_record["lod"]
		resident["active"] = desired_record["active"]
		resident["outside_updates"] = 0
		resident["generation"] = generation
		if not resident.has("dirty"):
			resident["dirty"] = false
		residents[key] = resident
	state["residents"] = residents
	state["desired"] = desired


static func _apply_edit(state: Dictionary, coordinate: Vector3i) -> Dictionary:
	var key := _chunk_key(coordinate)
	var generations: Dictionary = state.get("generations", {})
	var generation := int(generations.get(key, 0)) + 1
	generations[key] = generation
	state["generations"] = generations
	var journal: Dictionary = state.get("edit_journal", {})
	journal[key] = int(journal.get(key, 0)) + 1
	state["edit_journal"] = journal
	var residents: Dictionary = state.get("residents", {})
	if residents.has(key):
		var record: Dictionary = residents[key]
		record["generation"] = generation
		record["dirty"] = true
		residents[key] = record
		return {"generation": generation, "requested": true}
	return {"generation": generation, "requested": false}


static func _can_publish(state: Dictionary, coordinate: Vector3i, generation: int) -> bool:
	var key := _chunk_key(coordinate)
	return (
		(state.get("residents", {}) as Dictionary).has(key)
		and int((state.get("generations", {}) as Dictionary).get(key, 0)) == generation
	)


static func _snapshot(state: Dictionary) -> Dictionary:
	var desired: Dictionary = state.get("desired", {})
	var active_count := 0
	var lod_counts := {}
	for record_value in desired.values():
		var record: Dictionary = record_value
		if bool(record.get("active", false)):
			active_count += 1
		var lod := int(record.get("lod", -1))
		lod_counts[lod] = int(lod_counts.get(lod, 0)) + 1
	return {
		"center": state.get("center", Vector3i.ZERO),
		"active_count": active_count,
		"prefetch_count": desired.size(),
		"resident_count": (state.get("residents", {}) as Dictionary).size(),
		"lod_counts": lod_counts,
		"center_changes": int(state.get("center_changes", 0)),
	}


static func _benchmark(standard: Dictionary, failures: Array[String]) -> Dictionary:
	var contract: Dictionary = standard.get("window_contract", {})
	var budget: Dictionary = standard.get("performance_budget", {})
	var warmup := int(budget.get("warmup_iterations", 10))
	var sample_count := int(budget.get("sample_count", 100))
	var updates := int(budget.get("path_updates_per_sample", 64))
	for warmup_index in range(warmup):
		_run_path_batch(contract, updates, warmup_index)
	var timings: Array[float] = []
	for sample in range(sample_count):
		var started := Time.get_ticks_usec()
		_run_path_batch(contract, updates, sample)
		timings.append(float(Time.get_ticks_usec() - started))
	var distribution := Statistics.distribution(timings)
	distribution["warmup_iterations"] = warmup
	distribution["path_updates_per_sample"] = updates
	distribution["budget_p95_usec"] = float(budget.get("p95_usec", 0.0))
	_expect(int(distribution.get("sample_count", 0)) == sample_count, "streaming benchmark sample count changed", failures)
	_expect(float(distribution.get("p95_usec", INF)) <= float(budget.get("p95_usec", 0.0)), "streaming benchmark p95 exceeded budget", failures)
	return distribution


static func _run_path_batch(contract: Dictionary, updates: int, seed: int) -> void:
	var state := _new_state(Vector3(8.0, 0.0, 8.0), contract)
	for index in range(updates):
		var x := 8.0 + float(index) * 4.25 + float(seed % 7) * 0.1
		var z := 8.0 + sin(float(index + seed) * 0.13) * 24.0
		_update(state, Vector3(x, 0.0, z), contract)


static func _world_to_chunk(point: Vector3, chunk_world_size_m: float) -> Vector3i:
	return Vector3i(
		floori(point.x / chunk_world_size_m),
		floori(point.y / chunk_world_size_m),
		floori(point.z / chunk_world_size_m)
	)


static func _lod_for_distance(distance: int) -> int:
	if distance <= 1:
		return 0
	if distance <= 2:
		return 1
	if distance <= 3:
		return 2
	return 3


static func _chunk_key(coordinate: Vector3i) -> String:
	return "%d:%d:%d" % [coordinate.x, coordinate.y, coordinate.z]


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
