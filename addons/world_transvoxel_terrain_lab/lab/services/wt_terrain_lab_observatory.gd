@tool
extends RefCounted
class_name WtTerrainLabObservatory

const MAX_RETAINED_EVENTS := 1024
const SNAPSHOT_SCHEMA := "world_transvoxel.terrain_lab.observatory_snapshot.v2"
const REPRO_SCHEMA := "world_transvoxel.terrain_lab.observatory_repro.v1"

var chunks := {}
var jobs := {}
var events: Array[Dictionary] = []
var _event_sequence := 0
var counters := {
	"published": 0,
	"rejections": 0,
	"stale_rejections": 0,
	"failed": 0,
	"evicted": 0,
	"rejection_reasons": {},
}


func reset() -> void:
	chunks.clear()
	jobs.clear()
	events.clear()
	_event_sequence = 0
	counters = {
		"published": 0,
		"rejections": 0,
		"stale_rejections": 0,
		"failed": 0,
		"evicted": 0,
		"rejection_reasons": {},
	}


func set_chunk_state(
	chunk_id: String,
	state: String,
	generation: int,
	lod: int,
	reason: String = "",
	diagnostics: Dictionary = {}
) -> void:
	var previous: Dictionary = chunks.get(chunk_id, {})
	var buffers: Dictionary = diagnostics.get("buffers", previous.get("buffers", {}))
	var edit_dependencies: Dictionary = diagnostics.get(
		"edit_dependencies",
		previous.get("edit_dependencies", {})
	)
	var memory_bytes := int(diagnostics.get("memory_bytes", _sum_dictionary_values(buffers)))
	chunks[chunk_id] = {
		"state": state,
		"generation": generation,
		"lod": lod,
		"reason": reason,
		"edit_dependencies": edit_dependencies.duplicate(true),
		"buffers": buffers.duplicate(true),
		"memory_bytes": memory_bytes,
		"timings_usec": (diagnostics.get(
			"timings_usec",
			previous.get("timings_usec", {})
		) as Dictionary).duplicate(true),
		"collision_state": str(diagnostics.get(
			"collision_state",
			previous.get("collision_state", "not_requested")
		)),
		"last_rejection_reason": str(previous.get("last_rejection_reason", "")),
	}
	_record("chunk_state", chunk_id, generation, state if reason.is_empty() else reason)
	if state == "failed" and str(previous.get("state", "")) != "failed":
		counters["failed"] = int(counters["failed"]) + 1
	elif state == "evicted" and str(previous.get("state", "")) != "evicted":
		counters["evicted"] = int(counters["evicted"]) + 1


func set_job(
	job_id: String,
	chunk_id: String,
	generation: int,
	state: String,
	priority: int,
	diagnostics: Dictionary = {}
) -> void:
	var previous: Dictionary = jobs.get(job_id, {})
	var edit_dependencies: Dictionary = diagnostics.get(
		"edit_dependencies",
		previous.get("edit_dependencies", {})
	)
	jobs[job_id] = {
		"chunk_id": chunk_id,
		"generation": generation,
		"state": state,
		"priority": priority,
		"edit_dependencies": edit_dependencies.duplicate(true),
		"timings_usec": (diagnostics.get(
			"timings_usec",
			previous.get("timings_usec", {})
		) as Dictionary).duplicate(true),
		"rejection_reason": str(diagnostics.get(
			"rejection_reason",
			previous.get("rejection_reason", "")
		)),
	}
	_record("job_state", job_id, generation, state)


func record_publication(chunk_id: String, generation: int) -> void:
	counters["published"] = int(counters["published"]) + 1
	_record("publication", chunk_id, generation, "")


func record_rejection(chunk_id: String, generation: int, reason: String) -> void:
	counters["rejections"] = int(counters["rejections"]) + 1
	if reason == "stale_generation":
		counters["stale_rejections"] = int(counters["stale_rejections"]) + 1
	var rejection_reasons: Dictionary = counters["rejection_reasons"]
	rejection_reasons[reason] = int(rejection_reasons.get(reason, 0)) + 1
	if chunks.has(chunk_id):
		var chunk: Dictionary = chunks[chunk_id]
		chunk["last_rejection_reason"] = reason
		chunks[chunk_id] = chunk
	_record("rejection", chunk_id, generation, reason)


func inspect_chunk(chunk_id: String) -> Dictionary:
	return (chunks.get(chunk_id, {}) as Dictionary).duplicate(true)


func inspect_job(job_id: String) -> Dictionary:
	return (jobs.get(job_id, {}) as Dictionary).duplicate(true)


func snapshot() -> Dictionary:
	var ordered_events := _ordered_events()
	var document := {
		"schema": SNAPSHOT_SCHEMA,
		"chunks": _canonicalize(chunks),
		"jobs": _canonicalize(jobs),
		"counters": _canonicalize(counters),
		"resources": _resource_summary(),
		"rejections": ordered_events.filter(
			func(event: Dictionary) -> bool: return str(event.get("kind", "")) == "rejection"
		),
		"events": ordered_events,
		"retained_event_count": ordered_events.size(),
		"total_event_count": _event_sequence,
	}
	document["snapshot_signature"] = _signature_for(document)
	return document


func repro_document(context: Dictionary = {}) -> Dictionary:
	var document := {
		"schema": REPRO_SCHEMA,
		"context": _canonicalize(context),
		"snapshot": snapshot(),
	}
	document["repro_signature"] = _signature_for(document)
	return document


func export_repro(path: String, context: Dictionary = {}) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(repro_document(context), "\t", false) + "\n")
	return OK


static func validate_repro(document: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	if str(document.get("schema", "")) != REPRO_SCHEMA:
		failures.append("repro schema mismatch")
	var expected_repro_signature := str(document.get("repro_signature", ""))
	var unsigned_repro := document.duplicate(true)
	unsigned_repro.erase("repro_signature")
	if expected_repro_signature != _signature_for(unsigned_repro):
		failures.append("repro signature mismatch")
	var snapshot_value: Variant = document.get("snapshot", null)
	if not snapshot_value is Dictionary:
		failures.append("snapshot is not an object")
	else:
		for failure_value in validate_snapshot(snapshot_value).get("failures", []):
			failures.append(str(failure_value))
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"failures": failures,
	}


static func validate_snapshot(document: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	if str(document.get("schema", "")) != SNAPSHOT_SCHEMA:
		failures.append("snapshot schema mismatch")
	var expected_signature := str(document.get("snapshot_signature", ""))
	var unsigned_snapshot := document.duplicate(true)
	unsigned_snapshot.erase("snapshot_signature")
	if expected_signature != _signature_for(unsigned_snapshot):
		failures.append("snapshot signature mismatch")
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"failures": failures,
	}


func _resource_summary() -> Dictionary:
	var buffer_bytes := {}
	var total_memory_bytes := 0
	var collision_states := {}
	var timing_max_usec := {}
	for chunk_value in chunks.values():
		var chunk: Dictionary = chunk_value
		total_memory_bytes += int(chunk.get("memory_bytes", 0))
		for buffer_name in (chunk.get("buffers", {}) as Dictionary):
			buffer_bytes[buffer_name] = int(buffer_bytes.get(buffer_name, 0)) + int(
				(chunk.get("buffers", {}) as Dictionary)[buffer_name]
			)
		var collision_state := str(chunk.get("collision_state", "unknown"))
		collision_states[collision_state] = int(collision_states.get(collision_state, 0)) + 1
		for timing_name in (chunk.get("timings_usec", {}) as Dictionary):
			timing_max_usec[timing_name] = maxi(
				int(timing_max_usec.get(timing_name, 0)),
				int((chunk.get("timings_usec", {}) as Dictionary)[timing_name])
			)
	return {
		"chunk_count": chunks.size(),
		"job_count": jobs.size(),
		"total_memory_bytes": total_memory_bytes,
		"buffer_bytes": _canonicalize(buffer_bytes),
		"collision_states": _canonicalize(collision_states),
		"timing_max_usec": _canonicalize(timing_max_usec),
	}


func _record(kind: String, subject: String, generation: int, detail: String) -> void:
	var event := {
		"sequence": _event_sequence,
		"kind": kind,
		"subject": subject,
		"generation": generation,
		"detail": detail,
	}
	if events.size() < MAX_RETAINED_EVENTS:
		events.append(event)
	else:
		events[_event_sequence % MAX_RETAINED_EVENTS] = event
	_event_sequence += 1


func _ordered_events() -> Array[Dictionary]:
	if _event_sequence <= MAX_RETAINED_EVENTS:
		return events.duplicate(true)
	var result: Array[Dictionary] = []
	var oldest_index := _event_sequence % MAX_RETAINED_EVENTS
	for offset in range(events.size()):
		result.append(events[(oldest_index + offset) % events.size()].duplicate(true))
	return result


static func _sum_dictionary_values(values: Dictionary) -> int:
	var total := 0
	for value in values.values():
		total += int(value)
	return total


static func _signature_for(document: Dictionary) -> String:
	return JSON.stringify(_canonicalize(document)).sha256_text()


static func _canonicalize(value: Variant) -> Variant:
	if value is int:
		return float(value)
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		var result := {}
		for key in keys:
			result[str(key)] = _canonicalize(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_canonicalize(item))
		return result
	return value
