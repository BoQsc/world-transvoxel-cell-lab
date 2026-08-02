@tool
extends RefCounted
class_name WtTerrainLabSystemQualification

const Observatory := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_observatory.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)
const TemporalWaveEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_temporal_wave_evidence.gd"
)

const CHUNK_WORLD_SIZE_M := 16.0
const STREAM_RADIUS_CHUNKS := 3

const LEGAL_TRANSITIONS := {
	"requested": ["generating", "cached", "failed"],
	"generating": ["ready", "stale", "failed"],
	"ready": ["visible", "collidable", "dirty", "cached", "evicted"],
	"visible": ["collidable", "dirty", "stale", "cached", "evicted"],
	"collidable": ["dirty", "stale", "cached", "evicted"],
	"dirty": ["requested", "generating", "failed"],
	"stale": ["requested", "evicted"],
	"cached": ["requested", "visible", "evicted"],
	"failed": ["requested", "evicted"],
	"evicted": ["requested"],
}


static func run() -> Dictionary:
	var milestones: Array[Dictionary] = [
		_qualify_chunk_lifecycle(),
		_qualify_scheduling(),
		_qualify_persistence(),
		_qualify_streaming(),
		_qualify_large_world(),
		_qualify_visibility_residency(),
		_qualify_collision_publication(),
		_qualify_observatory(),
		_qualify_reference_soak(),
	]
	var failures: Array[String] = []
	for milestone in milestones:
		for failure_value in milestone.get("failures", []):
			failures.append(
				"%s: %s" % [str(milestone.get("milestone", "UNKNOWN")), str(failure_value)]
			)
	return {
		"schema": "world_transvoxel.terrain_lab.system_qualification.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"scope_status": {
			"TQP-06": "qualified",
			"TQP-15": "qualified",
			"TQP-16": "qualified",
			"TQP-19": "implemented_pending_hysteresis_prefetch_eviction_and_edit_matrix",
			"TQP-20": "implemented_pending_long_traversal_save_and_gpu_equivalence",
			"TQP-22": "implemented_pending_culling_hlod_draw_and_buffer_evidence",
			"TQP-24": "implemented_pending_real_physics_query_and_navigation_publication",
			"TQP-26": "implemented_pending_complete_runtime_diagnostic_sources",
			"TQP-27": "implemented_pending_real_large_terrain_soak",
		},
		"qualified_scope": [
			"TQP-06 deterministic reference chunk lifecycle",
			"TQP-15 native Windows worker, versioning, and publication reference",
			"TQP-16 native Windows persistence, recovery, and migration reference",
		],
		"explicitly_unqualified_scope": [
			"production terrain mesh residency",
			"Godot physics and navigation integration",
			"snapshot atomicity on filesystems outside the Windows reference platform",
			"automatic abandoned snapshot staging cleanup",
			"production traversal and memory budgets",
			"complete TQP-19, TQP-20, TQP-22, TQP-24, TQP-26, and TQP-27 qualification",
		],
		"provenance": Statistics.provenance("terrain_system_reference_v1"),
		"milestones": milestones,
		"failures": failures,
	}


static func _qualify_chunk_lifecycle() -> Dictionary:
	var failures: Array[String] = []
	var transition_count := 0
	for from_state in LEGAL_TRANSITIONS:
		var targets: Array = LEGAL_TRANSITIONS[from_state]
		_expect(not targets.is_empty(), str(from_state) + " is a dead-end state", failures)
		for to_state in targets:
			transition_count += 1
			_expect(_can_transition(str(from_state), str(to_state)), "legal transition rejected", failures)
	for pair in [
		["requested", "visible"],
		["generating", "collidable"],
		["evicted", "visible"],
		["failed", "ready"],
		["ready", "generating"],
	]:
		_expect(not _can_transition(pair[0], pair[1]), "illegal transition accepted", failures)
	var result := _result("TQP-06", transition_count + 5, failures)
	result["states"] = LEGAL_TRANSITIONS.keys()
	result["legal_transition_count"] = transition_count
	return result


static func _qualify_scheduling() -> Dictionary:
	var failures: Array[String] = []
	var evidence := TemporalWaveEvidence.retained_milestone("TQP-15")
	if str(evidence.get("status", "")) != "PASS":
		for failure_value in evidence.get("failures", []):
			failures.append(str(failure_value))
		if failures.is_empty():
			failures.append("retained native scheduling evidence failed")
	var requested_generation := 7
	var dependency_signature := "field:11|journal:42|lod:2".sha256_text()
	var candidates := [
		{"generation": 6, "signature": dependency_signature, "expected": false},
		{"generation": 7, "signature": "wrong", "expected": false},
		{"generation": 8, "signature": dependency_signature, "expected": false},
		{"generation": 7, "signature": dependency_signature, "expected": true},
	]
	var accepted := 0
	for candidate in candidates:
		var should_publish := (
			int(candidate["generation"]) == requested_generation
			and str(candidate["signature"]) == dependency_signature
		)
		_expect(
			should_publish == bool(candidate["expected"]),
			"independent publication decision changed",
			failures
		)
		if should_publish:
			accepted += 1
	_expect(accepted == 1, "publication invariant accepted multiple results", failures)
	var priorities := [
		{"id": "far", "priority": 30},
		{"id": "collision", "priority": 5},
		{"id": "visible", "priority": 0},
	]
	priorities.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["priority"]) < int(b["priority"])
	)
	_expect(str(priorities[0]["id"]) == "visible", "priority invariant changed", failures)
	var result := _result("TQP-15", 20, failures)
	result["qualification_status"] = "QUALIFIED_NATIVE_WINDOWS_PUBLICATION_REFERENCE_V1"
	result["native_evidence"] = evidence
	result["independent_invariants"] = {
		"accepted_generation_count": accepted,
		"priority_order": [priorities[0]["id"], priorities[1]["id"], priorities[2]["id"]],
	}
	return result


static func _qualify_streaming() -> Dictionary:
	var failures: Array[String] = []
	var path: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(15.9, 0.0, 0.0),
		Vector3(16.1, 0.0, 0.0),
		Vector3(47.9, 0.0, -16.1),
		Vector3(1024.0, 0.0, 1024.0),
	]
	var windows: Array[Dictionary] = []
	for point in path:
		var center := _world_to_chunk(point)
		var requested := _stream_window(center, STREAM_RADIUS_CHUNKS)
		_expect(
			requested.size() == int(pow(STREAM_RADIUS_CHUNKS * 2 + 1, 2)),
			"stream window cardinality changed",
			failures
		)
		_expect(requested.has(_chunk_key(center)), "stream center is not requested", failures)
		windows.append({"center": center, "requested_count": requested.size()})
	_expect(
		_world_to_chunk(path[0]) == _world_to_chunk(path[1]),
		"sub-chunk camera motion changed center",
		failures
	)
	_expect(
		_world_to_chunk(path[1]) != _world_to_chunk(path[2]),
		"chunk-boundary crossing was missed",
		failures
	)
	var result := _result("TQP-19", path.size() * 2 + 2, failures)
	result["windows"] = windows
	return result


static func _qualify_large_world() -> Dictionary:
	var failures: Array[String] = []
	var coordinates: Array[Vector3] = [
		Vector3(-32768.25, -2048.0, -32768.25),
		Vector3(-4097.0, 0.0, 4097.0),
		Vector3.ZERO,
		Vector3(4097.0, 8192.0, -4097.0),
		Vector3(32768.25, 8192.0, 32768.25),
	]
	for global_position in coordinates:
		var origin := _floating_origin(global_position, 4096.0, 1024.0)
		var local := global_position - origin
		_expect(local.length() <= 8870.0, "large-world local magnitude escaped reference bound", failures)
		_expect((origin + local).is_equal_approx(global_position), "large-world round trip changed", failures)
	var sample_fixtures: Array[int] = [-65, -33, -32, -31, -1, 0, 31, 32, 33, 65]
	for sample in sample_fixtures:
		var chunk := floori(float(sample) / 32.0)
		var local_sample: int = sample - chunk * 32
		_expect(local_sample >= 0 and local_sample < 32, "negative sample address escaped chunk", failures)
		_expect(chunk * 32 + local_sample == sample, "negative sample address did not round trip", failures)
	return _result("TQP-20", coordinates.size() * 2 + 20, failures)


static func _qualify_visibility_residency() -> Dictionary:
	var failures: Array[String] = []
	var candidates: Array[Dictionary] = []
	for x in range(-8, 9):
		for z in range(-8, 9):
			var distance_squared := x * x + z * z
			candidates.append({
				"id": "%d:%d" % [x, z],
				"distance_squared": distance_squared,
				"bytes": 4 * 1024 * 1024,
			})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["distance_squared"]) != int(b["distance_squared"]):
			return int(a["distance_squared"]) < int(b["distance_squared"])
		return str(a["id"]) < str(b["id"])
	)
	var budget := 256 * 1024 * 1024
	var retained := 0
	var resident: Array[String] = []
	for candidate in candidates:
		if retained + int(candidate["bytes"]) > budget:
			break
		retained += int(candidate["bytes"])
		resident.append(str(candidate["id"]))
	_expect(retained <= budget, "residency exceeded memory budget", failures)
	_expect(resident.size() == 64, "residency count changed", failures)
	_expect("0:0" in resident, "nearest chunk was not resident", failures)
	var result := _result("TQP-22", candidates.size() + 3, failures)
	result["resident_count"] = resident.size()
	result["retained_bytes"] = retained
	result["budget_bytes"] = budget
	return result


static func _qualify_persistence() -> Dictionary:
	var failures: Array[String] = []
	var evidence := TemporalWaveEvidence.retained_milestone("TQP-16")
	if str(evidence.get("status", "")) != "PASS":
		for failure_value in evidence.get("failures", []):
			failures.append(str(failure_value))
		if failures.is_empty():
			failures.append("retained native persistence evidence failed")
	var result := _result("TQP-16", 28, failures)
	result["qualification_status"] = "QUALIFIED_NATIVE_WINDOWS_PERSISTENCE_REFERENCE_V1"
	result["native_evidence"] = evidence
	return result


static func _qualify_collision_publication() -> Dictionary:
	var failures: Array[String] = []
	var records := [
		{"render": 4, "collision": 4, "query": 4, "nav": 4, "expected": true},
		{"render": 5, "collision": 4, "query": 5, "nav": 5, "expected": false},
		{"render": 6, "collision": 6, "query": 5, "nav": 6, "expected": false},
		{"render": 7, "collision": 7, "query": 7, "nav": 6, "expected": false},
	]
	for record in records:
		var coherent := (
			int(record["render"]) == int(record["collision"])
			and int(record["render"]) == int(record["query"])
			and int(record["render"]) == int(record["nav"])
		)
		_expect(coherent == bool(record["expected"]), "publication coherence decision changed", failures)
	return _result("TQP-24", records.size(), failures)


static func _qualify_observatory() -> Dictionary:
	var failures: Array[String] = []
	var observatory := Observatory.new()
	observatory.set_chunk_state("0:0:0:0", "requested", 1, 0)
	observatory.set_job("job-001", "0:0:0:0", 1, "running", 0)
	observatory.record_rejection("0:0:0:0", 0, "stale_generation")
	observatory.set_chunk_state("0:0:0:0", "visible", 1, 0)
	observatory.record_publication("0:0:0:0", 1)
	var snapshot := observatory.snapshot()
	_expect(str(snapshot.get("schema", "")).ends_with(".v1"), "observatory schema changed", failures)
	_expect(not str(snapshot.get("repro_signature", "")).is_empty(), "repro signature missing", failures)
	var counters: Dictionary = snapshot.get("counters", {})
	_expect(int(counters.get("published", 0)) == 1, "publication counter changed", failures)
	_expect(int(counters.get("stale_rejections", 0)) == 1, "rejection counter changed", failures)
	_expect((snapshot.get("events", []) as Array).size() == 5, "event retention changed", failures)
	var result := _result("TQP-26", 5, failures)
	result["snapshot"] = snapshot
	return result


static func _qualify_reference_soak() -> Dictionary:
	var failures: Array[String] = []
	var observatory := Observatory.new()
	var timings: Array[float] = []
	var published_generation := {}
	for batch in range(100):
		var started := Time.get_ticks_usec()
		for index in range(100):
			var sequence := batch * 100 + index
			var coordinate := Vector3i((sequence * 17) % 127 - 63, 0, (sequence * 29) % 127 - 63)
			var chunk_id := _chunk_key(coordinate)
			var generation := int(published_generation.get(chunk_id, 0)) + 1
			observatory.set_chunk_state(chunk_id, "requested", generation, sequence % 5)
			if sequence % 19 == 0:
				observatory.record_rejection(chunk_id, generation - 1, "stale_generation")
			observatory.record_publication(chunk_id, generation)
			published_generation[chunk_id] = generation
		timings.append(float(Time.get_ticks_usec() - started))
	var distribution := Statistics.distribution(timings)
	_expect(int(distribution.get("sample_count", 0)) == 100, "soak sample count changed", failures)
	_expect(float(distribution.get("p95_usec", INF)) < 4000.0, "reference model p95 exceeded 4 ms", failures)
	_expect(published_generation.size() <= 127 * 127, "soak residency escaped coordinate corpus", failures)
	var result := _result("TQP-27", 10000, failures)
	result["performance"] = distribution
	result["memory"] = Statistics.memory_metrics()
	result["retained_chunk_count"] = published_generation.size()
	result["qualification_scope"] = "REFERENCE_MODEL_NOT_PRODUCTION_TERRAIN"
	return result


static func _can_transition(from_state: String, to_state: String) -> bool:
	return to_state in LEGAL_TRANSITIONS.get(from_state, [])


static func _world_to_chunk(point: Vector3) -> Vector3i:
	return Vector3i(
		floori(point.x / CHUNK_WORLD_SIZE_M),
		floori(point.y / CHUNK_WORLD_SIZE_M),
		floori(point.z / CHUNK_WORLD_SIZE_M)
	)


static func _stream_window(center: Vector3i, radius: int) -> Dictionary:
	var result := {}
	for x in range(center.x - radius, center.x + radius + 1):
		for z in range(center.z - radius, center.z + radius + 1):
			result[_chunk_key(Vector3i(x, center.y, z))] = true
	return result


static func _chunk_key(coordinate: Vector3i) -> String:
	return "%d:%d:%d" % [coordinate.x, coordinate.y, coordinate.z]


static func _floating_origin(
	position: Vector3,
	threshold: float,
	quantum: float
) -> Vector3:
	var result := Vector3.ZERO
	for axis in range(3):
		if absf(position[axis]) > threshold:
			result[axis] = floorf(position[axis] / quantum) * quantum
	return result


static func _result(
	milestone: String,
	fixture_count: int,
	failures: Array[String]
) -> Dictionary:
	return {
		"milestone": milestone,
		"status": "PASS" if failures.is_empty() else "FAIL",
		"fixture_count": fixture_count,
		"failures": failures,
	}


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
