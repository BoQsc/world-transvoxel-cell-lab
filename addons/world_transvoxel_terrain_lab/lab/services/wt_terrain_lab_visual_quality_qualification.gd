@tool
extends RefCounted
class_name WtTerrainLabVisualQualityQualification

const EditField := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_edit_field.gd"
)
const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/visual_quality_corpus_standard.json"
)


static func run() -> Dictionary:
	var failures: Array[String] = []
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	_validate_standard(standard, failures)
	var evidence := JsonLoader.load_dictionary(str(standard.get("automated_evidence", "")))
	_validate_evidence(standard, evidence, failures)
	var human_review := str(evidence.get("formal_human_review", "PENDING"))
	return {
		"milestone": "TQP-25",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"qualification_status": (
			"QUALIFIED_REFERENCE_VISUAL_QUALITY_CORPUS_V1"
			if human_review == "ACCEPTED"
			else "IMPLEMENTED_PENDING_HUMAN_VISUAL_ACCEPTANCE"
		),
		"fixture_count": (standard.get("fixtures", []) as Array).size(),
		"formal_human_review": human_review,
		"finding": evidence.get("finding", {}),
		"capture_contract": evidence.get("capture_contract", {}),
		"fixtures": _fixture_summaries(evidence),
		"implemented_scope": standard.get("implemented_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"provenance": Statistics.provenance("tqp25_visual_quality_corpus_v1"),
		"failures": failures,
	}


static func _validate_standard(standard: Dictionary, failures: Array[String]) -> void:
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.visual_quality_corpus_standard.v1",
		"visual quality standard schema changed",
		failures
	)
	_expect(str(standard.get("milestone", "")) == "TQP-25", "visual quality milestone changed", failures)
	_expect(bool(standard.get("native_dependency_only", false)), "visual corpus permits a non-native fallback", failures)
	_expect(bool(standard.get("formal_decision_required", false)), "visual corpus lacks a formal decision gate", failures)
	for path_key in ["review_scene", "automated_evidence"]:
		var path := str(standard.get(path_key, ""))
		_expect(not path.is_empty(), "visual corpus lacks " + path_key, failures)
	if not str(standard.get("review_scene", "")).is_empty():
		_expect(FileAccess.file_exists(str(standard["review_scene"])), "visual review scene is missing", failures)
	var contract: Dictionary = standard.get("capture_contract", {})
	for key in ["width", "height", "motion_frame_count", "motion_fps", "repeatability_passes"]:
		_expect(int(contract.get(key, 0)) > 0, "capture contract lacks " + key, failures)
	_expect(int(contract.get("repeatability_passes", 0)) >= 2, "visual capture lacks repeatability passes", failures)
	_expect(str(contract.get("video_codec", "")) == "h264", "visual video codec changed", failures)
	_expect(str(contract.get("video_pixel_format", "")) == "yuv420p", "visual video pixel format changed", failures)
	var criteria: Array = standard.get("criteria", [])
	_expect(criteria.size() >= 7, "visual review criteria are incomplete", failures)
	var criterion_ids := {}
	for criterion_value in criteria:
		var criterion: Dictionary = criterion_value
		var criterion_id := str(criterion.get("id", ""))
		_expect(not criterion_id.is_empty() and not criterion_ids.has(criterion_id), "visual criterion ID is empty or duplicated", failures)
		criterion_ids[criterion_id] = true
		_expect(not str(criterion.get("failure", "")).is_empty(), criterion_id + " lacks a rejection condition", failures)
	var fixture_ids: Array[String] = []
	for fixture_value in standard.get("fixtures", []):
		var fixture: Dictionary = fixture_value
		var fixture_id := str(fixture.get("id", ""))
		fixture_ids.append(fixture_id)
		_validate_fixture_standard(fixture_id, fixture, failures)
	_expect(fixture_ids == ["natural", "constructed", "destroyed", "adversarial"], "visual fixture set or order changed", failures)
	var finding: Dictionary = standard.get("finding_resolution", {})
	_expect(str(finding.get("finding", "")) == "TQP-F001", "visual corpus finding changed", failures)
	_expect(str(finding.get("required_fixture", "")) == "adversarial", "shadow finding fixture changed", failures)
	_expect(is_equal_approx(float(finding.get("required_sample_scale_m", 0.0)), 0.25), "shadow finding resolution changed", failures)
	_expect(bool(finding.get("requires_shadow_on_off_pair", false)), "shadow finding lacks a control pair", failures)
	_expect(bool(finding.get("requires_full_motion_video", false)), "shadow finding lacks motion evidence", failures)
	_expect(bool(finding.get("automated_result_cannot_close_finding", false)), "automation can incorrectly close TQP-F001", failures)
	var formal_review: Dictionary = standard.get("formal_review", {})
	_expect(str(formal_review.get("status", "")) == "ACCEPTED", "visual corpus formal review is not accepted", failures)
	_expect(str(formal_review.get("decision", "")).ends_with("TQP-D015.json"), "visual corpus acceptance decision is missing", failures)


static func _validate_fixture_standard(
	fixture_id: String,
	fixture: Dictionary,
	failures: Array[String]
) -> void:
	_expect(not fixture_id.is_empty(), "visual fixture ID is empty", failures)
	_expect(float(fixture.get("sample_scale_m", 0.0)) > 0.0, fixture_id + " sample scale is invalid", failures)
	_expect(int(fixture.get("chunk_range_xz", 0)) >= 1, fixture_id + " xz window is invalid", failures)
	_expect(int(fixture.get("chunk_y_max", 0)) >= 1, fixture_id + " y window is invalid", failures)
	var field := EditField.new()
	field.terrain_profile = str(fixture.get("terrain_profile", ""))
	field.sample_scale_m = float(fixture.get("sample_scale_m", 0.0))
	var operation_ids := {}
	for operation_value in fixture.get("operations", []):
		var operation: Dictionary = operation_value
		var operation_id := str(operation.get("id", ""))
		_expect(not operation_id.is_empty() and not operation_ids.has(operation_id), fixture_id + " operation ID is empty or duplicated", failures)
		operation_ids[operation_id] = true
		_expect(field.add_operation(operation), fixture_id + " operation was rejected: " + operation_id, failures)
	_expect(not field.operations.is_empty(), fixture_id + " has no authored operations", failures)
	var camera: Dictionary = fixture.get("camera", {})
	_expect(_valid_vector3_array(camera.get("still_position", [])), fixture_id + " still camera is invalid", failures)
	_expect(_valid_vector3_array(camera.get("target", [])), fixture_id + " camera target is invalid", failures)
	_expect(float(camera.get("motion_radius_m", 0.0)) > 0.0, fixture_id + " motion radius is invalid", failures)
	_expect(float(camera.get("motion_end_degrees", 0.0)) > float(camera.get("motion_start_degrees", 0.0)), fixture_id + " motion arc is invalid", failures)
	var target: Dictionary = fixture.get("art_direction_target", {})
	_expect(not str(target.get("intent", "")).is_empty(), fixture_id + " lacks an art-direction intent", failures)
	_expect(not (target.get("must_show", []) as Array).is_empty(), fixture_id + " lacks required observations", failures)
	_expect(not (target.get("reject_if", []) as Array).is_empty(), fixture_id + " lacks rejection conditions", failures)
	var expected: Dictionary = fixture.get("expected", {})
	for hash_key in ["still_sha256", "motion_sequence_sha256", "video_sha256", "geometry_signature"]:
		_expect(str(expected.get(hash_key, "")).length() == 64, fixture_id + " baseline lacks " + hash_key, failures)


static func _validate_evidence(
	standard: Dictionary,
	evidence: Dictionary,
	failures: Array[String]
) -> void:
	_expect(
		str(evidence.get("schema", ""))
			== "world_transvoxel.terrain_lab.visual_quality_corpus_evidence.v1",
		"visual quality evidence schema changed",
		failures
	)
	_expect(str(evidence.get("milestone", "")) == "TQP-25", "visual evidence milestone changed", failures)
	_expect(str(evidence.get("status", "")) == "PASS", "visual quality automation failed", failures)
	_expect(str(evidence.get("review_scene", "")) == str(standard.get("review_scene", "")), "visual evidence scene changed", failures)
	var contract: Dictionary = standard.get("capture_contract", {})
	var actual_contract: Dictionary = evidence.get("capture_contract", {})
	for key in ["width", "height", "motion_frame_count", "motion_fps", "repeatability_passes"]:
		_expect(int(actual_contract.get(key, -1)) == int(contract.get(key, -2)), "visual capture contract changed: " + key, failures)
	var records_by_id := {}
	for record_value in evidence.get("fixtures", []):
		var record: Dictionary = record_value
		records_by_id[str(record.get("id", ""))] = record
	_expect(records_by_id.size() == 4, "visual evidence fixture count changed", failures)
	for fixture_value in standard.get("fixtures", []):
		var fixture: Dictionary = fixture_value
		var fixture_id := str(fixture.get("id", ""))
		_validate_fixture_evidence(fixture_id, fixture, records_by_id.get(fixture_id, {}), contract, failures)
	var finding: Dictionary = evidence.get("finding", {})
	_expect(str(finding.get("id", "")) == "TQP-F001", "visual evidence finding changed", failures)
	_expect(bool(finding.get("automated_result_cannot_close_finding", false)), "visual evidence permits automated finding closure", failures)
	var human_review := str(evidence.get("formal_human_review", ""))
	_expect(human_review in ["PENDING", "ACCEPTED"], "visual human review state is invalid", failures)
	if human_review == "ACCEPTED":
		_expect(str(finding.get("status", "")) == "CLOSED_BOUNDED_TQP25_ACCEPTANCE", "accepted TQP-F001 finding is not closed for its bounded scope", failures)
		_expect(str(evidence.get("review_decision", "")).ends_with("TQP-D015.json"), "accepted visual evidence lacks TQP-D015", failures)
		_expect(str((evidence.get("human_review", {}) as Dictionary).get("status", "")) == "ACCEPTED", "visual human-review record is not accepted", failures)
	else:
		_expect(str(finding.get("status", "")) == "OPEN_PENDING_HUMAN_VISUAL_REVIEW", "TQP-F001 was closed without review", failures)


static func _validate_fixture_evidence(
	fixture_id: String,
	fixture: Dictionary,
	record: Dictionary,
	contract: Dictionary,
	failures: Array[String]
) -> void:
	_expect(not record.is_empty(), "visual evidence lacks " + fixture_id, failures)
	var expected: Dictionary = fixture.get("expected", {})
	var minimums: Dictionary = fixture.get("minimums", {})
	var still: Dictionary = record.get("still", {})
	var still_path := str(still.get("image", ""))
	var still_hash := str(expected.get("still_sha256", ""))
	_expect(FileAccess.file_exists(still_path), fixture_id + " still is missing", failures)
	if FileAccess.file_exists(still_path):
		_expect(FileAccess.get_sha256(still_path) == still_hash, fixture_id + " still file hash changed", failures)
	_expect(str(still.get("sha256", "")) == still_hash, fixture_id + " still evidence hash changed", failures)
	var still_passes: Array = still.get("pass_sha256", [])
	_expect(still_passes.size() == int(contract.get("repeatability_passes", 0)), fixture_id + " still pass count changed", failures)
	for pass_hash in still_passes:
		_expect(str(pass_hash) == still_hash, fixture_id + " still repeatability changed", failures)
	var image_metrics: Dictionary = still.get("metrics", {})
	_expect(int(image_metrics.get("surface_pixels", 0)) >= int(minimums.get("surface_pixels", 0)), fixture_id + " terrain coverage changed", failures)
	_expect(int(image_metrics.get("colorful_pixels", 0)) >= int(minimums.get("colorful_pixels", 0)), fixture_id + " color coverage changed", failures)
	var geometry: Dictionary = record.get("geometry", {})
	var metrics: Dictionary = geometry.get("metrics", {})
	_expect(str(metrics.get("geometry_signature", "")) == str(expected.get("geometry_signature", "")), fixture_id + " geometry signature changed", failures)
	_expect(int(metrics.get("triangle_count", 0)) >= int(minimums.get("triangle_count", 0)), fixture_id + " triangle coverage changed", failures)
	_expect(int(metrics.get("surface_seam_pair_count", 0)) >= int(minimums.get("surface_seam_pairs", 0)), fixture_id + " seam coverage changed", failures)
	_expect(int(metrics.get("seam_errors", -1)) == 0, fixture_id + " has seam failures", failures)
	_expect(int(metrics.get("interior_open_edges", -1)) == 0, fixture_id + " has interior openings", failures)
	_expect(int(metrics.get("nonmanifold_edges", -1)) == 0, fixture_id + " has non-manifold edges", failures)
	_expect(str((geometry.get("seams", {}) as Dictionary).get("status", "")) == "PASS", fixture_id + " seam report failed", failures)
	_expect(str((geometry.get("topology", {}) as Dictionary).get("status", "")) == "PASS", fixture_id + " topology report failed", failures)
	var motion: Dictionary = record.get("motion", {})
	_expect(int(motion.get("frame_count", 0)) == int(contract.get("motion_frame_count", 0)), fixture_id + " motion frame count changed", failures)
	_expect(int(motion.get("unique_frame_count", 0)) >= int(contract.get("minimum_unique_motion_frames", 0)), fixture_id + " motion viewpoints changed", failures)
	_expect(str(motion.get("sequence_sha256", "")) == str(expected.get("motion_sequence_sha256", "")), fixture_id + " motion sequence changed", failures)
	var repeatability_hashes: Array = motion.get("repeatability_pass_sha256", [])
	_expect(repeatability_hashes.size() == int(contract.get("repeatability_passes", 0)), fixture_id + " motion pass count changed", failures)
	for sequence_hash in repeatability_hashes:
		_expect(str(sequence_hash) == str(expected.get("motion_sequence_sha256", "")), fixture_id + " motion repeatability changed", failures)
	_expect(float(motion.get("adjacent_difference_min", 0.0)) > 0.001, fixture_id + " motion contains a static interval", failures)
	var video: Dictionary = record.get("video", {})
	var video_path := str(video.get("path", ""))
	var video_hash := str(expected.get("video_sha256", ""))
	_expect(str(video.get("status", "")) == "PASS", fixture_id + " video encoding failed", failures)
	_expect(FileAccess.file_exists(video_path), fixture_id + " video is missing", failures)
	if FileAccess.file_exists(video_path):
		_expect(FileAccess.get_sha256(video_path) == video_hash, fixture_id + " video file hash changed", failures)
	_expect(str(video.get("sha256", "")) == video_hash, fixture_id + " video evidence hash changed", failures)
	_expect(str(video.get("codec", "")) == str(contract.get("video_codec", "")), fixture_id + " video codec changed", failures)
	_expect(str(video.get("pixel_format", "")) == str(contract.get("video_pixel_format", "")), fixture_id + " video pixel format changed", failures)
	_expect(int(video.get("frame_count", 0)) == int(contract.get("motion_frame_count", 0)), fixture_id + " video frame count changed", failures)
	if fixture_id == "adversarial":
		_validate_shadow_pair(record.get("shadow_pair", {}), failures)


static func _validate_shadow_pair(pair: Dictionary, failures: Array[String]) -> void:
	var captures: Array = pair.get("captures", [])
	_expect(captures.size() == 2, "adversarial shadow pair is incomplete", failures)
	var hashes: Array[String] = []
	var states := {}
	for capture_value in captures:
		var capture: Dictionary = capture_value
		var path := str(capture.get("image", ""))
		var digest := str(capture.get("sha256", ""))
		states[bool(capture.get("sun_shadows", false))] = true
		hashes.append(digest)
		_expect(FileAccess.file_exists(path), "adversarial shadow control is missing", failures)
		if FileAccess.file_exists(path):
			_expect(FileAccess.get_sha256(path) == digest, "adversarial shadow control hash changed", failures)
	_expect(states.has(true) and states.has(false), "adversarial shadow states are incomplete", failures)
	_expect(hashes.size() == 2 and hashes[0] != hashes[1], "adversarial shadow controls are identical", failures)
	_expect(float(pair.get("mean_absolute_difference", 0.0)) >= 0.002, "adversarial shadow effect is absent", failures)


static func _fixture_summaries(evidence: Dictionary) -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	for record_value in evidence.get("fixtures", []):
		var record: Dictionary = record_value
		var geometry: Dictionary = record.get("geometry", {})
		var metrics: Dictionary = geometry.get("metrics", {})
		var still: Dictionary = record.get("still", {})
		var motion: Dictionary = record.get("motion", {})
		var video: Dictionary = record.get("video", {})
		summaries.append({
			"id": str(record.get("id", "")),
			"still_sha256": str(still.get("sha256", "")),
			"motion_sequence_sha256": str(motion.get("sequence_sha256", "")),
			"video_sha256": str(video.get("sha256", "")),
			"geometry_signature": str(metrics.get("geometry_signature", "")),
			"triangle_count": int(metrics.get("triangle_count", 0)),
			"surface_seam_pair_count": int(metrics.get("surface_seam_pair_count", 0)),
			"seam_errors": int(metrics.get("seam_errors", -1)),
			"interior_open_edges": int(metrics.get("interior_open_edges", -1)),
			"nonmanifold_edges": int(metrics.get("nonmanifold_edges", -1)),
			"unique_motion_frames": int(motion.get("unique_frame_count", 0)),
		})
	return summaries


static func _valid_vector3_array(value: Variant) -> bool:
	return value is Array and value.size() == 3


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
