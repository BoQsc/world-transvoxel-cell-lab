extends SceneTree

const LabScript := preload(
	"res://addons/world_transvoxel_cell_lab/lab/wt_transvoxel_cell_lab.gd"
)
const ReproStore := preload(
	"res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_repro_store.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_cell_lab/standards/qualification_standard.json"
)
const BUNDLE_PATH := (
	"res://addons/world_transvoxel_cell_lab/standards/release_qualification_bundle.json"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if "--accept-upstream-baseline" not in OS.get_cmdline_user_args():
		_fail("explicit --accept-upstream-baseline flag is required")
		return
	if not ClassDB.class_exists("WorldTransvoxelCellProbe"):
		_fail("WorldTransvoxelCellProbe is required")
		return
	var lab := LabScript.new()
	root.add_child(lab)
	var evidence: Dictionary = lab.build_qualification_evidence()
	if str(evidence.get("status", "")) != "PASS":
		_fail("qualification evidence failed: " + str(evidence.get("sample_failures", [])))
		return
	var standard: Dictionary = evidence.get("standard_signature", {})
	if str(standard.get("status", "")) != "PASS" or not _write_json(
		STANDARD_PATH,
		ReproStore.to_json_safe(standard)
	):
		_fail("qualification standard could not be written")
		return
	var release: Dictionary = evidence.get("release", {})
	var source_bundle: Dictionary = release.get("release_bundle", {})
	if str(source_bundle.get("status", "")) != "PASS":
		_fail("release bundle evidence did not pass")
		return
	var evidence_files: Array[Dictionary] = []
	for entry_value in source_bundle.get("evidence_files", []):
		var entry: Dictionary = entry_value
		evidence_files.append({
			"path": str(entry.get("path", "")),
			"sha256": str(entry.get("sha256", "")),
			"bytes": int(entry.get("bytes", -1)),
		})
	evidence_files.append({
		"path": STANDARD_PATH,
		"sha256": FileAccess.get_sha256(STANDARD_PATH),
		"bytes": FileAccess.get_file_as_bytes(STANDARD_PATH).size(),
	})
	var bundle := {
		"schema": str(source_bundle.get("schema", "")),
		"status": "PASS",
		"authority": str(source_bundle.get("authority", "")),
		"qualification_standard_schema": str(standard.get("schema", "")),
		"bundle_hash": str(source_bundle.get("bundle_hash", "")),
		"core_evidence_file_count": int(source_bundle.get("evidence_file_count", 0)),
		"evidence_file_count": evidence_files.size(),
		"visual_standard_count": int(source_bundle.get("visual_standard_count", 0)),
		"visual_evidence_scope": str(source_bundle.get("visual_evidence_scope", "")),
		"visual_capture_contract": source_bundle.get("visual_capture_contract", {}),
		"visual_review_status": str(source_bundle.get("visual_review_status", "")),
		"milestone_range": [16, 29],
		"milestone_status": "PASS",
		"platform_scope": "Windows/x86_64 committed native artifacts",
		"renderer_scope": ["gl_compatibility", "mobile", "forward_plus"],
		"visual_diff_contract": "labs/cell_lab/tools/compare_visual_standards.py",
		"evidence_files": evidence_files,
	}
	if not _write_json(BUNDLE_PATH, bundle):
		_fail("release qualification bundle could not be written")
		return
	print(
		"WT_CELL_LAB_QUALIFICATION_STANDARDS_REFRESHED bundle_hash="
		+ str(bundle["bundle_hash"])
	)
	lab.free()
	quit(0)


func _write_json(path: String, value: Variant) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t", false) + "\n")
	file.close()
	return true


func _fail(message: String) -> void:
	push_error("WT_CELL_LAB_QUALIFICATION_REFRESH_FAIL: " + message)
	quit(1)
