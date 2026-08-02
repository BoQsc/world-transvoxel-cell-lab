@tool
extends Node
class_name WtTerrainLabTemporalWaveQualification

const PublicationQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_publication_qualification.gd"
)
const TemporalEditQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_temporal_edit_qualification.gd"
)
const PersistenceQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_persistence_qualification.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)


func run() -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var publication := PublicationQualification.new()
	var temporal := TemporalEditQualification.new()
	var persistence := PersistenceQualification.new()
	add_child(publication)
	add_child(temporal)
	add_child(persistence)
	var publication_result: Dictionary = await publication.run()
	var temporal_result: Dictionary = await temporal.run()
	var persistence_result: Dictionary = await persistence.run()
	var failures: Array[String] = []
	_append_failures("TQP-21 publication", publication_result, failures)
	_append_failures("temporal runtime", temporal_result, failures)
	_append_failures("TQP-25 persistence", persistence_result, failures)
	var scheduling: Dictionary = temporal_result.get("scheduling", {})
	var temporal_edits: Dictionary = temporal_result.get("temporal_edits", {})
	var persistence_evidence: Dictionary = persistence_result.get("evidence", {})
	temporal_edits["edit_snapshot_ordering_world_revision"] = int(
		persistence_evidence.get("edit_snapshot_ordering_world_revision", -1)
	)
	var tqp_21_status := (
		"PASS" if str(publication_result.get("status", "")) == "PASS"
			and str(scheduling.get("status", "")) == "PASS" else "FAIL"
	)
	return {
		"schema": "world_transvoxel.terrain_lab.temporal_wave_qualification.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"authority": "world-transvoxel native GDExtension; no fallback path",
		"platform_scope": "Godot 4.7.1 Windows x86_64 reference run",
		"provenance": Statistics.provenance("native_temporal_integrity_windows_v1"),
		"memory": Statistics.memory_metrics(),
		"milestones": {
			"TQP-21": {
				"milestone": "TQP-21",
				"status": tqp_21_status,
				"worker_pipeline": scheduling,
				"publication": publication_result,
			},
			"TQP-25": persistence_result,
			"TQP-13": temporal_edits,
		},
		"elapsed_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
		"failures": failures,
	}


static func _append_failures(
	label: String,
	result: Dictionary,
	failures: Array[String]
) -> void:
	if str(result.get("status", "")) == "PASS":
		return
	var nested: Array = result.get("failures", [])
	if nested.is_empty():
		failures.append(label + " failed without a diagnostic")
		return
	for failure in nested:
		failures.append(label + ": " + str(failure))
