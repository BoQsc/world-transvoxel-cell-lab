@tool
extends RefCounted
class_name WtTerrainLabObservatory

const MAX_RETAINED_EVENTS := 1024

var chunks := {}
var jobs := {}
var events: Array[Dictionary] = []
var _event_sequence := 0
var counters := {
	"published": 0,
	"stale_rejections": 0,
	"failed": 0,
	"evicted": 0,
}


func set_chunk_state(
	chunk_id: String,
	state: String,
	generation: int,
	lod: int,
	reason: String = ""
) -> void:
	chunks[chunk_id] = {
		"state": state,
		"generation": generation,
		"lod": lod,
		"reason": reason,
	}
	_record("chunk_state", chunk_id, generation, reason)
	if state == "failed":
		counters["failed"] = int(counters["failed"]) + 1
	elif state == "evicted":
		counters["evicted"] = int(counters["evicted"]) + 1


func set_job(
	job_id: String,
	chunk_id: String,
	generation: int,
	state: String,
	priority: int
) -> void:
	jobs[job_id] = {
		"chunk_id": chunk_id,
		"generation": generation,
		"state": state,
		"priority": priority,
	}
	_record("job_state", job_id, generation, state)


func record_publication(chunk_id: String, generation: int) -> void:
	counters["published"] = int(counters["published"]) + 1
	_record("publication", chunk_id, generation, "")


func record_rejection(chunk_id: String, generation: int, reason: String) -> void:
	counters["stale_rejections"] = int(counters["stale_rejections"]) + 1
	_record("rejection", chunk_id, generation, reason)


func snapshot() -> Dictionary:
	var ordered_events := _ordered_events()
	var document := {
		"schema": "world_transvoxel.terrain_lab.observatory_snapshot.v1",
		"chunks": chunks.duplicate(true),
		"jobs": jobs.duplicate(true),
		"counters": counters.duplicate(true),
		"events": ordered_events,
		"total_event_count": _event_sequence,
	}
	document["repro_signature"] = JSON.stringify(document).sha256_text()
	return document


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
