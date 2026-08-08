@tool
extends RefCounted
class_name WtTerrainLabComplexVisualEvidence

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/complex_visual_temporal_corpus_standard.json"
)


static func validate_retained() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var automation := JsonLoader.load_dictionary(str(standard.get("automation_evidence", "")))
	var review := JsonLoader.load_dictionary(str(standard.get("review_verdict", "")))
	return validate_reports(standard, automation, review)


static func validate_reports(
	standard: Dictionary,
	automation: Dictionary,
	review: Dictionary
) -> Dictionary:
	var failures: Array[String] = []
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.complex_visual_temporal_corpus_standard.v1",
		"TQP-44 standard schema changed", failures
	)
	_expect(
		str(automation.get("schema", ""))
			== "world_transvoxel.terrain_lab.complex_visual_temporal_corpus_automation.v1",
		"TQP-44 automation evidence is absent", failures
	)
	_expect(
		str(automation.get("status", "")) == "PASS_AUTOMATION_PENDING_HUMAN",
		"TQP-44 automation corpus failed", failures
	)
	_expect(
		not bool(automation.get("automation_accepts_milestone", true)),
		"TQP-44 automation attempted to accept human review", failures
	)
	var contract: Dictionary = standard.get("coverage_contract", {})
	var coverage: Dictionary = automation.get("coverage", {})
	_expect(
		int(coverage.get("still_count", 0)) >= int(contract.get("minimum_stills", 0)),
		"TQP-44 still coverage is incomplete", failures
	)
	_expect(
		int(coverage.get("motion_path_count", 0))
			>= int(contract.get("minimum_motion_paths", 0)),
		"TQP-44 motion coverage is incomplete", failures
	)
	_expect(
		int(coverage.get("distinct_live_scene_count", 0))
			>= int(contract.get("minimum_distinct_live_scenes", 0)),
		"TQP-44 live observatory coverage is incomplete", failures
	)
	_validate_assets(automation, failures)
	var review_status := str(review.get("status", "PENDING_HUMAN_REVIEW"))
	var review_failures: Array[String] = []
	if review_status == "PASS":
		_expect(
			str(review.get("corpus_signature", ""))
				== str(automation.get("corpus_signature", "")),
			"TQP-44 human review targets another corpus", review_failures
		)
		for category_value in contract.get("required_review_categories", []):
			var category := str(category_value)
			_expect(
				str((review.get("categories", {}) as Dictionary).get(category, "")) == "PASS",
				"TQP-44 human category is not accepted: " + category, review_failures
			)
		_expect(not str(review.get("reviewer", "")).is_empty(), "TQP-44 reviewer is absent", review_failures)
		_expect(not str(review.get("reviewed_at", "")).is_empty(), "TQP-44 review time is absent", review_failures)
		_expect(
			_sorted_field(review, "reviewed_still_ids")
				== _record_values(automation.get("stills", []), "id"),
			"TQP-44 human review did not traverse every still", review_failures
		)
		_expect(
			_sorted_field(review, "reviewed_motion_path_ids")
				== _record_values(automation.get("motion_paths", []), "id"),
			"TQP-44 human review did not traverse every motion path", review_failures
		)
		var required_scenes := _record_values(automation.get("stills", []), "scene")
		for scene in _record_values(automation.get("motion_paths", []), "scene"):
			if scene not in required_scenes:
				required_scenes.append(scene)
		required_scenes.sort()
		_expect(
			_sorted_field(review, "requested_live_scenes") == required_scenes,
			"TQP-44 human review did not request every live source", review_failures
		)
	elif review_status == "FAIL":
		review_failures.append("TQP-44 human review explicitly rejected the corpus")
	var human_pass := review_status == "PASS" and review_failures.is_empty()
	var status := "FAIL" if not failures.is_empty() or not review_failures.is_empty() else (
		"PASS" if human_pass else "PENDING_HUMAN_REVIEW"
	)
	return {
		"schema": "world_transvoxel.terrain_lab.complex_visual_temporal_corpus_evidence_validation.v1",
		"milestone": "TQP-44",
		"status": status,
		"automation_status": "PASS" if failures.is_empty() else "FAIL",
		"human_review_status": "PASS" if human_pass else review_status,
		"scope_status": {
			"TQP-44": "qualified_complex_visual_temporal_corpus_windows_v1" \
				if status == "PASS" else "implemented_pending_human_visual_review"
		},
		"corpus_signature": automation.get("corpus_signature", ""),
		"coverage": coverage,
		"review": review,
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures + review_failures,
	}


static func _validate_assets(automation: Dictionary, failures: Array[String]) -> void:
	for group in ["stills", "motion_paths"]:
		for record_value in automation.get(group, []):
			var record: Dictionary = record_value
			var path := str(record.get("path", ""))
			_expect(FileAccess.file_exists(path), "TQP-44 evidence missing: " + path, failures)
			if FileAccess.file_exists(path):
				_expect(
					FileAccess.get_sha256(path) == str(record.get("sha256", "")),
					"TQP-44 evidence changed: " + path, failures
				)


static func _sorted_field(value: Dictionary, key: String) -> Array[String]:
	var result: Array[String] = []
	for item in value.get(key, []):
		result.append(str(item))
	result.sort()
	return result


static func _record_values(records: Array, key: String) -> Array[String]:
	var result: Array[String] = []
	for record_value in records:
		var item := str((record_value as Dictionary).get(key, ""))
		if not item.is_empty() and item not in result:
			result.append(item)
	result.sort()
	return result


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
