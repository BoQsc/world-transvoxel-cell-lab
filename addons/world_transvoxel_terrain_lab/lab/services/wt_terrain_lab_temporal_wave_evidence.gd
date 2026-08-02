@tool
extends RefCounted
class_name WtTerrainLabTemporalWaveEvidence

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/temporal_wave_standard.json"
)


static func validate_retained() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var report := JsonLoader.load_dictionary(str(standard.get("evidence", "")))
	return validate_report(report, standard)


static func validate_report(
	report: Dictionary,
	standard: Dictionary = {}
) -> Dictionary:
	if standard.is_empty():
		standard = JsonLoader.load_dictionary(STANDARD_PATH)
	var failures: Array[String] = []
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.temporal_wave_standard.v1",
		"temporal wave standard schema mismatch",
		failures
	)
	_expect(
		str(report.get("schema", ""))
			== "world_transvoxel.terrain_lab.temporal_wave_qualification.v1",
		"temporal wave report schema mismatch",
		failures
	)
	_expect(str(report.get("status", "")) == "PASS", "temporal wave did not pass", failures)
	_expect(
		str(report.get("authority", "")) == str(standard.get("authority", "")),
		"temporal wave authority changed",
		failures
	)
	var provenance: Dictionary = report.get("provenance", {})
	for key in [
		"workload_signature",
		"build_type",
		"os",
		"architecture",
		"cpu",
		"driver",
		"godot_version",
		"backend_revision",
	]:
		_expect(
			not str(provenance.get(key, "")).is_empty(),
			"temporal wave provenance is missing " + key,
			failures
		)
	var memory: Dictionary = report.get("memory", {})
	_expect(
		int(memory.get("retained_bytes", 0)) > 0
			and int(memory.get("peak_bytes", 0)) >= int(memory.get("retained_bytes", 0)),
		"temporal wave memory metadata is invalid",
		failures
	)
	var milestones: Dictionary = report.get("milestones", {})
	for milestone_id in standard.get("qualified_milestones", []):
		var milestone: Dictionary = milestones.get(str(milestone_id), {})
		_expect(
			str(milestone.get("status", "")) == "PASS",
			str(milestone_id) + " native evidence did not pass",
			failures
		)
	_validate_tqp_21(milestones.get("TQP-15", {}), standard, failures)
	_validate_tqp_13(milestones.get("TQP-17", {}), standard, failures)
	_validate_tqp_25(milestones.get("TQP-16", {}), standard, failures)
	return {
		"schema": "world_transvoxel.terrain_lab.temporal_wave_evidence_validation.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"qualified_milestones": standard.get("qualified_milestones", []),
		"failures": failures,
	}


static func retained_milestone(milestone_id: String) -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var report := JsonLoader.load_dictionary(str(standard.get("evidence", "")))
	var validation := validate_report(report, standard)
	if str(validation.get("status", "")) != "PASS":
		return {
			"milestone": milestone_id,
			"status": "FAIL",
			"failures": validation.get("failures", []),
		}
	return (report.get("milestones", {}) as Dictionary).get(milestone_id, {})


static func _validate_tqp_21(
	milestone: Dictionary,
	standard: Dictionary,
	failures: Array[String]
) -> void:
	var expected: Dictionary = (
		standard.get("stable_expected", {}) as Dictionary
	).get("TQP-15", {})
	var worker: Dictionary = milestone.get("worker_pipeline", {})
	var publication: Dictionary = milestone.get("publication", {})
	_expect(int(worker.get("worker_count", 0)) == int(expected.get("worker_count", -1)), "TQP-15 worker count changed", failures)
	_expect(int(worker.get("sample_jobs", 0)) >= int(expected.get("minimum_sample_jobs", 1)), "TQP-15 sampled no chunks", failures)
	_expect(int(worker.get("mesh_jobs", 0)) >= int(expected.get("minimum_mesh_jobs", 1)), "TQP-15 meshed no chunks", failures)
	_expect(int(worker.get("published_events", 0)) >= int(expected.get("minimum_published_events", 1)), "TQP-15 published no worker events", failures)
	_expect(int(worker.get("coalesced_viewer_events", 0)) >= int(expected.get("minimum_coalesced_viewer_events", 1)), "TQP-15 coalesced no superseded viewer work", failures)
	_expect(str(worker.get("target_mesh_signature", "")) == str(expected.get("target_mesh_signature", "")), "TQP-15 target mesh signature changed", failures)
	var chunk: Dictionary = worker.get("target_chunk", {})
	_expect(
		bool(chunk.get("fully_ready", false))
			and int(chunk.get("generation", -1)) == int(chunk.get("render_generation", -2))
			and int(chunk.get("generation", -1)) == int(chunk.get("collision_generation", -2)),
		"TQP-15 target generations are incoherent",
		failures
	)
	for key in [
		"published_generation",
		"stale_render_rejections",
		"stale_collision_rejections",
	]:
		_expect(int(publication.get(key, -1)) == int(expected.get(key, -2)), "TQP-15 " + key + " changed", failures)
	_expect(bool(publication.get("teardown_clean", false)), "TQP-15 teardown retained resources", failures)
	var performance: Dictionary = publication.get("performance", {})
	_expect(
		int(performance.get("sample_count", 0))
			== int(expected.get("performance_sample_count", -1))
			and float(performance.get("p50_usec", 0.0)) > 0.0
			and float(performance.get("p95_usec", 0.0)) > 0.0
			and float(performance.get("p99_usec", 0.0)) > 0.0
			and float(performance.get("worst_usec", 0.0)) > 0.0,
		"TQP-15 publication timing distribution is incomplete",
		failures
	)
	var minimum_latency := int(expected.get("minimum_application_latency_frames", 1))
	_expect(
		int(publication.get("render_latency_frames_maximum", 0)) >= minimum_latency
			and int(publication.get("collision_latency_frames_maximum", 0)) >= minimum_latency,
		"TQP-15 application latency telemetry is missing",
		failures
	)


static func _validate_tqp_13(
	milestone: Dictionary,
	standard: Dictionary,
	failures: Array[String]
) -> void:
	var expected: Dictionary = (
		standard.get("stable_expected", {}) as Dictionary
	).get("TQP-17", {})
	_expect(int(milestone.get("commits", 0)) == int(expected.get("commits", -1)), "TQP-17 commit count changed", failures)
	_expect(int(milestone.get("stale_rejections", 0)) == int(expected.get("stale_rejections", -1)), "TQP-17 stale rejection count changed", failures)
	_expect(int(milestone.get("chunk_replacements", 0)) >= int(expected.get("minimum_chunk_replacements", 1)), "TQP-17 observed no chunk replacement", failures)
	_expect(str(milestone.get("stale_error", "")) == str(expected.get("stale_error", "")), "TQP-17 stale rejection changed", failures)
	_expect(bool(milestone.get("streaming_and_lod_overlap", false)), "TQP-17 temporal overlap was not exercised", failures)
	_expect(
		int(milestone.get("edit_snapshot_ordering_world_revision", -1))
			== int(expected.get("edit_snapshot_ordering_world_revision", -2)),
		"TQP-17 edit/snapshot ordering changed",
		failures
	)
	_validate_samples(milestone, expected.get("samples", {}), "TQP-17", failures)
	_expect(
		str(milestone.get("journal_after_carve_sha256", ""))
			== str(milestone.get("journal_after_rejection_sha256", "")),
		"TQP-17 stale rejection mutated journal bytes",
		failures
	)
	for key in ["journal_after_carve_sha256", "journal_final_sha256"]:
		_expect(str(milestone.get(key, "")) == str(expected.get(key, "")), "TQP-17 " + key + " changed", failures)


static func _validate_tqp_25(
	milestone: Dictionary,
	standard: Dictionary,
	failures: Array[String]
) -> void:
	var expected: Dictionary = (
		standard.get("stable_expected", {}) as Dictionary
	).get("TQP-16", {})
	var fixture: Dictionary = milestone.get("fixture", {})
	var current: Dictionary = fixture.get("current_world", {})
	var legacy: Dictionary = fixture.get("legacy_world", {})
	_expect(str(fixture.get("upstream_revision", "")) == str(expected.get("fixture_upstream_revision", "")), "TQP-16 fixture revision changed", failures)
	_expect(str(current.get("manifest_sha256", "")) == str(expected.get("current_manifest_sha256", "")), "TQP-16 current fixture hash changed", failures)
	_expect(str(legacy.get("manifest_sha256", "")) == str(expected.get("legacy_manifest_sha256", "")), "TQP-16 legacy fixture hash changed", failures)
	var evidence: Dictionary = milestone.get("evidence", {})
	_validate_samples(evidence, expected.get("samples", {}), "TQP-16", failures)
	_expect(str(evidence.get("journal_before_rejection_sha256", "")) == str(expected.get("journal_sha256", "")), "TQP-16 journal signature changed", failures)
	_expect(str(evidence.get("journal_before_rejection_sha256", "")) == str(evidence.get("journal_after_rejection_sha256", "")), "TQP-16 stale rejection mutated journal", failures)
	_expect(str(evidence.get("compacted_manifest_sha256", "")) == str(expected.get("snapshot_manifest_sha256", "")), "TQP-16 compacted manifest changed", failures)
	_expect(str(evidence.get("migrated_manifest_sha256", "")) == str(expected.get("snapshot_manifest_sha256", "")), "TQP-16 migrated manifest changed", failures)
	var recovery: Dictionary = evidence.get("journal_truncated_tail_recovery", {})
	_expect(bool(recovery.get("recovered", false)) and int(recovery.get("world_revision", -1)) == 12 and int(recovery.get("committed_prefix_bytes", -1)) == 0, "TQP-16 truncated-tail recovery changed", failures)
	var journal_corruption: Dictionary = evidence.get("journal_corruption", {})
	_expect(bool(journal_corruption.get("rejected", false)) and str(journal_corruption.get("error", "")) == str(expected.get("journal_corruption_error", "")), "TQP-16 journal corruption handling changed", failures)
	var manifest_corruption: Dictionary = evidence.get("manifest_corruption", {})
	var records: Array = manifest_corruption.get("records", [])
	_expect(bool(manifest_corruption.get("rejected", false)) and records.size() == 2, "TQP-16 manifest corruption corpus changed", failures)
	for record_value in records:
		var record: Dictionary = record_value
		_expect(str(record.get("error", "")) == str(expected.get("manifest_corruption_error", "")), "TQP-16 manifest corruption error changed", failures)
	_expect(str((evidence.get("page_corruption", {}) as Dictionary).get("error", "")) == str(expected.get("page_corruption_error", "")), "TQP-16 page corruption error changed", failures)
	_expect(str((evidence.get("interrupted_staging", {}) as Dictionary).get("error", "")) == str(expected.get("interrupted_staging_error", "")), "TQP-16 interrupted staging behavior changed", failures)
	_expect(str((evidence.get("existing_output_rejection", {}) as Dictionary).get("error", "")) == str(expected.get("existing_output_error", "")), "TQP-16 existing output behavior changed", failures)
	for key in ["compacted_page_count", "migrated_page_count", "legacy_migrated_page_count"]:
		_expect(int(evidence.get(key, -1)) == int(expected.get("snapshot_page_count", -2)), "TQP-16 " + key + " changed", failures)


static func _validate_samples(
	observed: Dictionary,
	expected_samples: Dictionary,
	label: String,
	failures: Array[String]
) -> void:
	for sample_name in expected_samples:
		var actual: Dictionary = observed.get(sample_name, {})
		var expected: Dictionary = expected_samples[sample_name]
		_expect(str(actual.get("status", "")) == "PASS", label + " " + str(sample_name) + " failed", failures)
		_expect(is_equal_approx(float(actual.get("density", INF)), float(expected.get("density", -INF))), label + " " + str(sample_name) + " density changed", failures)
		for key in ["material", "source_revision", "world_revision"]:
			_expect(int(actual.get(key, -1)) == int(expected.get(key, -2)), label + " " + str(sample_name) + " " + key + " changed", failures)


static func _expect(condition: bool, failure: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(failure)
