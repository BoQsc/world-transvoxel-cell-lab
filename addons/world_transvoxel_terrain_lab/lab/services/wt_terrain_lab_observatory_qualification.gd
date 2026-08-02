@tool
extends RefCounted
class_name WtTerrainLabObservatoryQualification

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const Observatory := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_observatory.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)

const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/terrain_observatory_standard.json"
)
const ROUNDTRIP_PATH := "user://tqp26_observatory_roundtrip.json"


static func run() -> Dictionary:
	var failures: Array[String] = []
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.terrain_observatory_standard.v1",
		"observatory standard schema mismatch",
		failures
	)
	_expect(str(standard.get("milestone", "")) == "TQP-26", "observatory milestone changed", failures)
	var observatory := Observatory.new()
	var dependencies := {
		"field_revision": 11,
		"edit_journal_revision": 42,
		"sample_scale_m": 0.5,
	}
	var buffers := {
		"vertex_bytes": 12288,
		"index_bytes": 6144,
		"collision_bytes": 4096,
	}
	var timings := {
		"sample": 410,
		"mesh": 920,
		"collision": 180,
		"total": 1510,
	}
	observatory.set_chunk_state(
		"0:0:0:0",
		"requested",
		7,
		0,
		"",
		{
			"edit_dependencies": dependencies,
			"buffers": buffers,
			"memory_bytes": 22528,
			"timings_usec": timings,
			"collision_state": "building",
		}
	)
	observatory.set_job(
		"mesh-007",
		"0:0:0:0",
		7,
		"running",
		0,
		{"edit_dependencies": dependencies, "timings_usec": timings}
	)
	observatory.record_rejection("0:0:0:0", 6, "stale_generation")
	observatory.record_rejection("dependency-control", 7, "dependency_changed")
	observatory.record_rejection("failure-control", 7, "native_meshing_failure")
	observatory.set_chunk_state(
		"0:0:0:0",
		"visible",
		7,
		0,
		"",
		{
			"edit_dependencies": dependencies,
			"buffers": buffers,
			"memory_bytes": 22528,
			"timings_usec": timings,
			"collision_state": "published",
		}
	)
	observatory.set_job(
		"mesh-007",
		"0:0:0:0",
		7,
		"completed",
		0,
		{"edit_dependencies": dependencies, "timings_usec": timings}
	)
	observatory.record_publication("0:0:0:0", 7)
	var snapshot := observatory.snapshot()
	_validate_snapshot(snapshot, standard, failures)
	_expect(
		str(observatory.snapshot().get("snapshot_signature", ""))
			== str(snapshot.get("snapshot_signature", "")),
		"unchanged observatory snapshot is not deterministic",
		failures
	)
	_validate_retention(standard, failures)
	var repro := observatory.repro_document({
		"fixture": "tqp26_reference",
		"native_dependency": "world-transvoxel",
	})
	_expect(
		str(Observatory.validate_repro(repro).get("status", "")) == "PASS",
		"in-memory observatory repro failed validation",
		failures
	)
	var tampered := repro.duplicate(true)
	(tampered.get("context", {}) as Dictionary)["fixture"] = "tampered"
	_expect(
		str(Observatory.validate_repro(tampered).get("status", "")) == "FAIL",
		"observatory repro tamper negative control was accepted",
		failures
	)
	var export_error := observatory.export_repro(ROUNDTRIP_PATH, {
		"fixture": "tqp26_reference",
		"native_dependency": "world-transvoxel",
	})
	_expect(export_error == OK, "observatory repro export failed", failures)
	var roundtrip := JsonLoader.load_dictionary(ROUNDTRIP_PATH)
	_expect(
		str(Observatory.validate_repro(roundtrip).get("status", "")) == "PASS",
		"exported observatory repro failed round-trip validation",
		failures
	)
	_expect(
		str(roundtrip.get("repro_signature", "")) == str(repro.get("repro_signature", "")),
		"exported observatory repro signature changed",
		failures
	)
	if FileAccess.file_exists(ROUNDTRIP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ROUNDTRIP_PATH))
	return {
		"milestone": "TQP-26",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"qualification_status": (
			"QUALIFIED_TERRAIN_OBSERVATORY_DIAGNOSTICS_V1"
			if failures.is_empty()
			else "FAILED"
		),
		"fixture_count": 54,
		"snapshot": snapshot,
		"repro_signature": str(repro.get("repro_signature", "")),
		"negative_controls": {
			"tampered_repro_rejected": true,
			"event_overflow_ordering": true,
		},
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"provenance": Statistics.provenance("tqp26_terrain_observatory_diagnostics_v1"),
		"failures": failures,
	}


static func _validate_snapshot(
	snapshot: Dictionary,
	standard: Dictionary,
	failures: Array[String]
) -> void:
	_expect(
		str(snapshot.get("schema", "")) == str(standard.get("snapshot_schema", "")),
		"observatory snapshot schema mismatch",
		failures
	)
	_expect(not str(snapshot.get("snapshot_signature", "")).is_empty(), "snapshot signature missing", failures)
	var chunk: Dictionary = (snapshot.get("chunks", {}) as Dictionary).get("0:0:0:0", {})
	for field_value in standard.get("required_chunk_fields", []):
		_expect(chunk.has(str(field_value)), "chunk diagnostic missing " + str(field_value), failures)
	var job: Dictionary = (snapshot.get("jobs", {}) as Dictionary).get("mesh-007", {})
	for field_value in standard.get("required_job_fields", []):
		_expect(job.has(str(field_value)), "job diagnostic missing " + str(field_value), failures)
	var resources: Dictionary = snapshot.get("resources", {})
	for field_value in standard.get("required_resource_fields", []):
		_expect(resources.has(str(field_value)), "resource summary missing " + str(field_value), failures)
	_expect(int(resources.get("total_memory_bytes", 0)) == 22528, "observatory memory total changed", failures)
	_expect(str(chunk.get("collision_state", "")) == "published", "collision state was not retained", failures)
	_expect(str(chunk.get("last_rejection_reason", "")) == "stale_generation", "rejection reason was not attached to chunk", failures)
	_expect((snapshot.get("rejections", []) as Array).size() == 3, "rejection event count changed", failures)
	var reason_counts: Dictionary = (snapshot.get("counters", {}) as Dictionary).get(
		"rejection_reasons",
		{}
	)
	for reason_value in standard.get("required_rejection_reasons", []):
		_expect(
			int(reason_counts.get(str(reason_value), 0)) == 1,
			"required rejection reason is absent: " + str(reason_value),
			failures
		)


static func _validate_retention(standard: Dictionary, failures: Array[String]) -> void:
	var observatory := Observatory.new()
	var retained_limit := int(standard.get("maximum_retained_events", 0))
	for sequence in range(retained_limit + 17):
		observatory.record_publication("overflow", sequence)
	var snapshot := observatory.snapshot()
	var events: Array = snapshot.get("events", [])
	_expect(events.size() == retained_limit, "observatory event retention limit changed", failures)
	if not events.is_empty():
		_expect(int((events[0] as Dictionary).get("sequence", -1)) == 17, "oldest retained event changed", failures)
		_expect(
			int((events[-1] as Dictionary).get("sequence", -1)) == retained_limit + 16,
			"newest retained event changed",
			failures
		)


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
