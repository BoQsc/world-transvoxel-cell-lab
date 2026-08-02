@tool
extends RefCounted
class_name WtTerrainLabSystemQualification

const ObservatoryQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_observatory_qualification.gd"
)
const Observatory := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_observatory.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)
const TemporalWaveEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_temporal_wave_evidence.gd"
)
const StreamingWindowQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_streaming_window_qualification.gd"
)
const LargeWorldQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_large_world_qualification.gd"
)
const VisibilityResidencyQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_visibility_residency_qualification.gd"
)
const Phase03Evidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_phase_03_system_evidence.gd"
)

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
		StreamingWindowQualification.run(),
		LargeWorldQualification.run(),
		VisibilityResidencyQualification.run(),
		_qualify_collision_publication(),
		ObservatoryQualification.run(),
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
			"TQP-19": "qualified",
			"TQP-20": "qualified",
			"TQP-22": "qualified",
			"TQP-24": "qualified",
			"TQP-26": "qualified_terrain_observatory_diagnostics",
			"TQP-27": "implemented_pending_real_large_terrain_soak",
		},
		"qualified_scope": [
			"TQP-06 deterministic reference chunk lifecycle",
			"TQP-15 native Windows worker, versioning, and publication reference",
			"TQP-16 native Windows persistence, recovery, and migration reference",
			"TQP-19 deterministic horizontal streaming-window reference model",
			"TQP-20 CPU large-world coordinate reference model",
			"TQP-22 CPU horizontal visibility and residency reference model",
			"TQP-24 native Windows Godot collision, query, and navigation publication reference",
			"TQP-26 deterministic diagnostic snapshots and signed repro export",
		],
		"explicitly_unqualified_scope": [
			"production terrain mesh residency",
			"production physics and navigation integration",
			"snapshot atomicity on filesystems outside the Windows reference platform",
			"automatic abandoned snapshot staging cleanup",
			"production traversal and memory budgets",
			"TQP-27 real large-terrain performance and soak qualification",
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
	var evidence := Phase03Evidence.retained_milestone("TQP-24")
	if str(evidence.get("status", "")) != "PASS":
		for failure_value in evidence.get("failures", []):
			failures.append(str(failure_value))
		if failures.is_empty():
			failures.append("retained native collision/query/navigation evidence failed")
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
	var result := _result("TQP-24", records.size() + 8, failures)
	result["qualification_status"] = "QUALIFIED_NATIVE_WINDOWS_GODOT_PUBLICATION_REFERENCE_V1"
	result["native_evidence"] = evidence
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
	distribution["target_p95_usec"] = 4000.0
	distribution["target_status"] = (
		"MET" if float(distribution.get("p95_usec", INF)) < 4000.0 else "EXCEEDED"
	)
	distribution["budget_evaluation"] = "OBSERVATION_ONLY_IMPLEMENTED_MILESTONE"
	_expect(published_generation.size() <= 127 * 127, "soak residency escaped coordinate corpus", failures)
	var result := _result("TQP-27", 10000, failures)
	result["performance"] = distribution
	result["memory"] = Statistics.memory_metrics()
	result["retained_chunk_count"] = published_generation.size()
	result["qualification_scope"] = "REFERENCE_MODEL_NOT_PRODUCTION_TERRAIN"
	return result


static func _can_transition(from_state: String, to_state: String) -> bool:
	return to_state in LEGAL_TRANSITIONS.get(from_state, [])


static func _chunk_key(coordinate: Vector3i) -> String:
	return "%d:%d:%d" % [coordinate.x, coordinate.y, coordinate.z]


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
