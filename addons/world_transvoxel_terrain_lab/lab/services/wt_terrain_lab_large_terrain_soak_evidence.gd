@tool
extends RefCounted
class_name WtTerrainLabLargeTerrainSoakEvidence

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)

const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/large_terrain_soak_standard.json"
)


static func validate_retained() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var report := JsonLoader.load_dictionary(str(standard.get("evidence", "")))
	return validate_report(report, standard)


static func validate_report(report: Dictionary, standard: Dictionary = {}) -> Dictionary:
	if standard.is_empty():
		standard = JsonLoader.load_dictionary(STANDARD_PATH)
	var failures: Array[String] = []
	_expect(str(standard.get("schema", "")) == "world_transvoxel.terrain_lab.large_terrain_soak_standard.v1", "TQP-27 standard schema changed", failures)
	_expect(str(report.get("schema", "")) == "world_transvoxel.terrain_lab.large_terrain_soak_qualification.v1", "TQP-27 report schema changed", failures)
	_expect(str(report.get("milestone", "")) == "TQP-27", "TQP-27 report milestone changed", failures)
	_expect(str(report.get("standard_id", "")) == str(standard.get("standard_id", "")), "TQP-27 report standard changed", failures)
	_expect(str(report.get("authority", "")) == str(standard.get("authority", "")), "TQP-27 report authority changed", failures)
	_expect(str(report.get("status", "")) == "PASS", "TQP-27 retained report failed", failures)
	var provenance: Dictionary = report.get("provenance", {})
	_expect(str(provenance.get("os", "")) == str((standard.get("runtime_profile", {}) as Dictionary).get("platform", "")), "TQP-27 platform changed", failures)
	for key in ["workload_signature", "build_type", "architecture", "cpu", "driver", "godot_version", "backend_revision"]:
		_expect(not str(provenance.get(key, "")).is_empty(), "TQP-27 provenance lacks " + key, failures)
	var workload: Dictionary = standard.get("workload", {})
	var budgets: Dictionary = standard.get("budgets", {})
	var coverage: Dictionary = report.get("coverage", {})
	_expect(int(coverage.get("actual_duration_ms", 0)) >= int(workload.get("minimum_duration_ms", 0)), "TQP-27 soak duration is incomplete", failures)
	_expect(int(coverage.get("movement_settlements", 0)) >= int(workload.get("continuous_traversal_steps", 0)) + int(workload.get("minimum_teleports", 0)), "TQP-27 traversal coverage is incomplete", failures)
	_expect(int(coverage.get("teleports", 0)) >= int(workload.get("minimum_teleports", 0)), "TQP-27 teleport coverage is incomplete", failures)
	_expect(int(coverage.get("committed_edits", 0)) >= int(workload.get("minimum_committed_edits", 0)), "TQP-27 edit coverage is incomplete", failures)
	_expect(float(coverage.get("virtual_span_m", 0.0)) >= float(workload.get("minimum_virtual_span_m", 0.0)), "TQP-27 terrain span is incomplete", failures)
	_expect(int(coverage.get("unique_render_chunks", 0)) >= int(workload.get("minimum_unique_render_chunks", 0)), "TQP-27 chunk coverage is incomplete", failures)
	_expect(bool(coverage.get("stale_viewer_revision_rejected", false)), "TQP-27 stale viewer control failed", failures)
	_expect(bool(coverage.get("stale_edit_transaction_rejected", false)), "TQP-27 stale edit control failed", failures)
	_expect(bool(coverage.get("shutdown_clean", false)), "TQP-27 shutdown is not clean", failures)
	_expect(int(coverage.get("post_restart_query_count", 0)) == int(coverage.get("committed_edits", -1)), "TQP-27 restart query coverage does not match committed edits", failures)
	var performance: Dictionary = report.get("performance", {})
	var frame: Dictionary = performance.get("frame", {})
	var update: Dictionary = performance.get("viewer_update", {})
	var settlement: Dictionary = performance.get("window_settlement", {})
	_expect(int(frame.get("sample_count", 0)) >= int(budgets.get("minimum_frame_samples", 0)), "TQP-27 frame sample count is incomplete", failures)
	_expect(float(frame.get("p99_usec", INF)) <= float(budgets.get("maximum_frame_p99_usec", 0.0)), "TQP-27 frame p99 exceeded", failures)
	_expect(float(frame.get("worst_usec", INF)) <= float(budgets.get("maximum_frame_usec", 0.0)), "TQP-27 maximum frame exceeded", failures)
	_expect(float(update.get("p95_usec", INF)) <= float(budgets.get("maximum_viewer_update_p95_usec", 0.0)), "TQP-27 viewer update p95 exceeded", failures)
	_expect(float(settlement.get("p95_usec", INF)) <= float(budgets.get("maximum_settlement_p95_usec", 0.0)), "TQP-27 settlement p95 exceeded", failures)
	_expect(float(performance.get("settled_windows_per_second", 0.0)) >= float(budgets.get("minimum_settled_windows_per_second", INF)), "TQP-27 throughput floor was not met", failures)
	_expect(float(performance.get("snapshot_capacity_control_usec", INF)) <= float(budgets.get("maximum_snapshot_capacity_control_usec", 0.0)), "TQP-27 snapshot capacity-control ceiling exceeded", failures)
	_expect(float(performance.get("restart_to_settlement_usec", INF)) <= float(budgets.get("maximum_restart_settlement_usec", 0.0)), "TQP-27 restart ceiling exceeded", failures)
	var resources: Dictionary = report.get("resources", {})
	for key in ["maximum_memory_bytes", "maximum_transient_chunk_records", "maximum_non_retiring_chunks", "maximum_render_resources", "maximum_collision_resources", "maximum_render_queue", "maximum_collision_queue"]:
		_expect(int(resources.get(key, 0)) <= int(budgets.get(key, -1)), "TQP-27 resource ceiling exceeded: " + key, failures)
	var persistence: Dictionary = report.get("persistence", {})
	_expect(int(persistence.get("catalog_page_count", 0)) >= int(workload.get("minimum_catalog_pages", 0)), "TQP-27 catalog coverage is incomplete", failures)
	_expect(int(persistence.get("post_restart_query_count", 0)) == int(coverage.get("committed_edits", -1)), "TQP-27 persistent query coverage does not match committed edits", failures)
	_expect(str(persistence.get("journal_restart_status", "")) == "PASS", "TQP-27 journal restart failed", failures)
	_expect(bool(persistence.get("post_restart_queries_agreed", false)), "TQP-27 restart queries diverged", failures)
	_expect(str(persistence.get("large_volume_compaction_status", "")) == "EXPECTED_CAPACITY_REJECTION", "TQP-27 compaction capacity control changed", failures)
	_expect(str(persistence.get("large_volume_compaction_error", "")) == str(workload.get("expected_compaction_error", "")), "TQP-27 compaction capacity error changed", failures)
	_expect(not bool(persistence.get("partial_compaction_output_exists", true)), "TQP-27 compaction published partial output", failures)
	return {
		"schema": "world_transvoxel.terrain_lab.large_terrain_soak_evidence_validation.v1",
		"milestone": "TQP-27",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"qualification_status": "QUALIFIED_NATIVE_WINDOWS_LARGE_TERRAIN_SOAK_V1" if failures.is_empty() else "FAILED",
		"coverage": coverage,
		"performance": performance,
		"resources": resources,
		"persistence": persistence,
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


static func retained_milestone() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var report := JsonLoader.load_dictionary(str(standard.get("evidence", "")))
	var validation := validate_report(report, standard)
	if str(validation.get("status", "")) != "PASS":
		return {
			"milestone": "TQP-27",
			"status": "FAIL",
			"failures": validation.get("failures", []),
		}
	return report


static func _expect(condition: bool, failure: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(failure)
