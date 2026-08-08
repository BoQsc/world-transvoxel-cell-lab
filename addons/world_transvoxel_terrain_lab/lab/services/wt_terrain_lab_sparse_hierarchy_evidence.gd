@tool
extends RefCounted
class_name WtTerrainLabSparseHierarchyEvidence

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/sparse_hierarchy_storage_standard.json"
)


static func validate_retained() -> Dictionary:
	var failures: Array[String] = []
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var report := JsonLoader.load_dictionary(str(standard.get("evidence", "")))
	var native := JsonLoader.load_dictionary(
		str(standard.get("native_benchmark_evidence", ""))
	)
	var observatory := JsonLoader.load_dictionary(
		"res://labs/terrain_lab/results/sparse_hierarchy_observatory_validation_windows.json"
	)
	var expected: Dictionary = standard.get("stable_expected", {})
	var authority: Dictionary = native.get("authority", {})
	var counters: Dictionary = (
		(native.get("summary", {}) as Dictionary).get("fixed_counters", {})
	)
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.sparse_hierarchy_storage_standard.v1",
		"TQP-42 standard schema changed", failures
	)
	_expect(
		str(report.get("schema", ""))
			== "world_transvoxel.terrain_lab.sparse_hierarchy_qualification.v1",
		"TQP-42 report schema changed", failures
	)
	_expect(
		str(report.get("status", "")) == "PASS"
			and bool(report.get("retained_complete", false)),
		"TQP-42 retained report failed", failures
	)
	_expect(
		str(report.get("semantic_signature", ""))
			== str(expected.get("semantic_signature", "")),
		"TQP-42 semantic signature changed", failures
	)
	var actions: Dictionary = report.get("actions", {})
	for action in (standard.get("workload", {}) as Dictionary).get("required_actions", []):
		_expect(
			str(actions.get(str(action), "")) == "PASS",
			"TQP-42 action failed: " + str(action), failures
		)
	_expect(
		str(native.get("schema", ""))
			== "world_transvoxel.sparse_hierarchy_benchmark.v1"
			and str(native.get("status", "")) == "PASS",
		"TQP-42 native benchmark failed", failures
	)
	_expect(
		str(authority.get("git_commit", "")) == str(expected.get("upstream_commit", ""))
			and str(authority.get("executable_sha256", ""))
				== str(expected.get("executable_sha256", ""))
			and str(authority.get("native_contract_hash", ""))
				== str(expected.get("native_contract_hash", "")),
		"TQP-42 native authority changed", failures
	)
	_expect(
		int(counters.get("declared_pages", -1)) == int(expected.get("declared_pages", -2))
			and int(counters.get("hierarchy_index_bytes", -1))
				== int(expected.get("hierarchy_index_bytes", -2))
			and int(counters.get("overlay_pages", -1))
				== int(expected.get("native_overlay_pages", -2)),
		"TQP-42 native counters changed", failures
	)
	_expect(
		str(observatory.get("schema", ""))
			== "world_transvoxel.terrain_lab.sparse_hierarchy_observatory_validation.v1"
			and str(observatory.get("status", "")) == "PASS",
		"TQP-42 observatory evidence failed", failures
	)
	return {
		"schema": "world_transvoxel.terrain_lab.sparse_hierarchy_evidence_validation.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"scope_status": {
			"TQP-42": "qualified_implicit_procedural_hierarchy_sparse_overlay_v1"
				if failures.is_empty() else "failed_sparse_hierarchy"
		},
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
