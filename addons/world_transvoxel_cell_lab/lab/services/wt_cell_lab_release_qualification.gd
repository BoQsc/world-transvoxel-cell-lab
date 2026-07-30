@tool
extends RefCounted
class_name WtCellLabReleaseQualification

const Contracts := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_contracts.gd")
const IntegrationAdapter := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_integration_adapter.gd")
const Common := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_qualification_common.gd")

const INTEGRATION_FIXTURE_DIRECTORY := "res://addons/world_transvoxel_cell_lab/standards/integration_parity"
const PLATFORM_MATRIX_PATH := "res://addons/world_transvoxel_cell_lab/standards/platform_renderer_matrix.json"
const GOVERNANCE_PATH := "res://addons/world_transvoxel_cell_lab/standards/upstream_correction_registry.json"
const CI_WORKFLOW_PATH := "res://.github/workflows/cell-lab-validation.yml"
const RELEASE_EVIDENCE_PATHS := [
	"res://addons/world_transvoxel_cell_lab/standards/native_dependency_manifest.json",
	"res://addons/world_transvoxel_cell_lab/standards/reference_terrain_standard.json",
	"res://addons/world_transvoxel_cell_lab/standards/standard_cases.json",
	"res://addons/world_transvoxel_cell_lab/standards/performance_thresholds.json",
	"res://addons/world_transvoxel_cell_lab/standards/visual_manifest.json",
	PLATFORM_MATRIX_PATH,
	GOVERNANCE_PATH,
]


func validate(
	lab: Object,
	correctness: Dictionary,
	runtime: Dictionary
) -> Dictionary:
	var start_usec := Time.get_ticks_usec()
	var integration := _validate_integration_parity(lab)
	var platform := _validate_platform_renderer_matrix()
	var bundle := _build_release_bundle(correctness, runtime, integration, platform)
	var governance := _validate_upstream_governance(correctness, integration)
	var failures: Array[String] = []
	for entry in [
		["integration_parity", integration],
		["platform_renderer_matrix", platform],
		["release_bundle", bundle],
		["upstream_governance", governance],
	]:
		var section: Dictionary = entry[1]
		if str(section.get("status", "")) != "PASS":
			failures.append("%s=%s" % [str(entry[0]), str(section.get("status", "FAIL"))])
	return {
		"schema": Contracts.RELEASE_QUALIFICATION_SCHEMA,
		"status": "PASS" if failures.is_empty() else "FAIL",
		"integration_parity": integration,
		"platform_renderer_matrix": platform,
		"release_bundle": bundle,
		"upstream_governance": governance,
		"sample_failures": failures,
		"elapsed_ms": float(Time.get_ticks_usec() - start_usec) / 1000.0,
	}


func standard_signature(validation: Dictionary) -> Dictionary:
	var integration: Dictionary = validation.get("integration_parity", {})
	var platform: Dictionary = validation.get("platform_renderer_matrix", {})
	var bundle: Dictionary = validation.get("release_bundle", {})
	var governance: Dictionary = validation.get("upstream_governance", {})
	return {
		"schema": Contracts.RELEASE_QUALIFICATION_STANDARD_SCHEMA,
		"integration_fixture_count": int(integration.get("fixture_count", 0)),
		"integration_operation_count": int(integration.get("operation_count", 0)),
		"integration_classification_count": int(
			integration.get("classification_count", 0)
		),
		"required_platform_target_count": int(platform.get("required_target_count", 0)),
		"required_renderer_count": int(platform.get("required_renderer_count", 0)),
		"required_artifact_count": int(platform.get("required_artifact_count", 0)),
		"explicitly_unqualified_target_count": int(
			platform.get("explicitly_unqualified_target_count", 0)
		),
		"release_evidence_file_count": int(bundle.get("evidence_file_count", 0)),
		"release_visual_count": int(bundle.get("visual_standard_count", 0)),
		"release_bundle_hash": str(bundle.get("bundle_hash", "")),
		"governance_case_count": int(governance.get("case_count", 0)),
		"governance_required_evidence_count": int(
			governance.get("required_evidence_count", 0)
		),
		"confirmed_upstream_correction_count": int(
			governance.get("confirmed_upstream_correction_count", 0)
		),
		"status": str(validation.get("status", "FAIL")),
	}


func _validate_integration_parity(lab: Object) -> Dictionary:
	var original := _capture_lab_state(lab)
	lab.set("auto_rebuild", false)
	var directory := DirAccess.open(INTEGRATION_FIXTURE_DIRECTORY)
	var paths: Array[String] = []
	if directory != null:
		directory.list_dir_begin()
		var file_name := directory.get_next()
		while not file_name.is_empty():
			if not directory.current_is_dir() and file_name.ends_with(".json"):
				paths.append("%s/%s" % [INTEGRATION_FIXTURE_DIRECTORY, file_name])
			file_name = directory.get_next()
		directory.list_dir_end()
	paths.sort()
	var fixtures: Array[Dictionary] = []
	var failures: Array = []
	var operation_count := 0
	var classifications := {}
	for path in paths:
		var source := _load_json(path)
		var expected: Dictionary = source.get("_expected", {})
		var imported := IntegrationAdapter.import_snapshot(source, lab, path)
		var comparison: Dictionary = imported.get("comparison", {})
		var modes: Array[String] = []
		for edit_value in lab.get("edits"):
			var edit: Dictionary = edit_value
			modes.append(str(edit.get("mode", "")))
		var adapter_kind := str(imported.get("adapter_kind", ""))
		var suspected_layer := str(comparison.get("suspected_fix_layer", ""))
		var fixture_ok := bool(imported.get("ok", false)) \
			and adapter_kind == str(expected.get("adapter_kind", "")) \
			and int(imported.get("operation_count", -1)) == int(
				expected.get("operation_count", -2)
			) \
			and suspected_layer == str(expected.get("suspected_fix_layer", "")) \
			and modes == _string_array(expected.get("edit_modes", [])) \
			and str((imported.get("report", {}) as Dictionary).get("status", "")) == "PASS"
		var entry := {
			"id": path.get_file().get_basename(),
			"status": "PASS" if fixture_ok else "FAIL",
			"adapter_kind": adapter_kind,
			"operation_count": int(imported.get("operation_count", 0)),
			"edit_modes": modes,
			"suspected_fix_layer": suspected_layer,
			"lab_status": str(
				(imported.get("report", {}) as Dictionary).get("status", "FAIL")
			),
		}
		fixtures.append(entry)
		operation_count += int(entry["operation_count"])
		classifications[suspected_layer] = true
		if not fixture_ok:
			failures.append(entry)
	_restore_lab_state(lab, original)
	return {
		"schema": Contracts.INTEGRATION_PARITY_SCHEMA,
		"status": "PASS" if failures.is_empty() and paths.size() == 3 else "FAIL",
		"fixture_count": paths.size(),
		"passing_fixtures": paths.size() - failures.size(),
		"failing_fixtures": failures.size(),
		"operation_count": operation_count,
		"classification_count": classifications.size(),
		"source_contracts": [
			"WtTerrainDebugSnapshot",
			"WtTerrainEditOperation bridge commands",
			"WtTerrainWatertightnessProbe",
		],
		"fixtures": fixtures,
		"sample_failures": failures,
	}


func _capture_lab_state(lab: Object) -> Dictionary:
	return {
		"auto_rebuild": bool(lab.get("auto_rebuild")),
		"cells_x": int(lab.get("cells_x")),
		"cells_y": int(lab.get("cells_y")),
		"cells_z": int(lab.get("cells_z")),
		"cell_size": float(lab.get("cell_size")),
		"field_mode": int(lab.get("field_mode")),
		"isovalue": float(lab.get("isovalue")),
		"surface_height": float(lab.get("surface_height")),
		"sphere_radius": float(lab.get("sphere_radius")),
		"edits": (lab.get("edits") as Array).duplicate(true),
	}


func _restore_lab_state(lab: Object, state: Dictionary) -> void:
	lab.set("auto_rebuild", false)
	for key in [
		"cells_x",
		"cells_y",
		"cells_z",
		"cell_size",
		"field_mode",
		"isovalue",
		"surface_height",
		"sphere_radius",
	]:
		lab.set(key, state.get(key, lab.get(key)))
	lab.set("edits", (state.get("edits", []) as Array).duplicate(true))
	lab.call("rebuild")
	lab.set("auto_rebuild", bool(state.get("auto_rebuild", true)))


func _validate_platform_renderer_matrix() -> Dictionary:
	var matrix := _load_json(PLATFORM_MATRIX_PATH)
	var failures: Array = []
	var required_targets: Array = matrix.get("required_targets", [])
	var required_renderer_count := 0
	var required_artifact_count := 0
	var current_platform := OS.get_name()
	var current_architecture := Engine.get_architecture_name()
	var current_renderer := RenderingServer.get_current_rendering_method()
	var current_target_covered := false
	for target_value in required_targets:
		var target: Dictionary = target_value
		var renderers: Array = target.get("renderers", [])
		var artifacts: Array = target.get("artifacts", [])
		var lanes: Array = target.get("ci_lanes", [])
		required_renderer_count += renderers.size()
		required_artifact_count += artifacts.size()
		for artifact in artifacts:
			if not FileAccess.file_exists(str(artifact)):
				failures.append("missing native artifact: %s" % str(artifact))
		var workflow_text := _load_text(CI_WORKFLOW_PATH)
		for lane in lanes:
			if str(lane) not in workflow_text:
				failures.append("missing CI lane: %s" % str(lane))
		if str(target.get("platform", "")) == current_platform \
				and str(target.get("architecture", "")) == current_architecture:
			current_target_covered = true
			if current_renderer not in renderers:
				failures.append("current renderer is outside qualified matrix")
	if str(matrix.get("schema", "")) != Contracts.PLATFORM_RENDERER_MATRIX_SCHEMA:
		failures.append("unexpected platform matrix schema")
	if not current_target_covered:
		failures.append(
			"current target is not qualified: %s/%s" % [
				current_platform,
				current_architecture,
			]
		)
	return {
		"schema": Contracts.PLATFORM_RENDERER_MATRIX_SCHEMA,
		"status": "PASS" if failures.is_empty() else "FAIL",
		"qualification_scope": str(matrix.get("qualification_scope", "")),
		"required_target_count": required_targets.size(),
		"required_renderer_count": required_renderer_count,
		"required_artifact_count": required_artifact_count,
		"explicitly_unqualified_target_count": (
			matrix.get("declared_not_qualified", []) as Array
		).size(),
		"current_platform": current_platform,
		"current_architecture": current_architecture,
		"current_renderer": current_renderer,
		"current_target_covered": current_target_covered,
		"sample_failures": failures,
	}


func _build_release_bundle(
	correctness: Dictionary,
	runtime: Dictionary,
	integration: Dictionary,
	platform: Dictionary
) -> Dictionary:
	var evidence_files: Array[Dictionary] = []
	var failures: Array = []
	for path in RELEASE_EVIDENCE_PATHS:
		var absolute_path := ProjectSettings.globalize_path(path)
		if not FileAccess.file_exists(path):
			failures.append("missing evidence file: %s" % path)
			continue
		evidence_files.append({
			"path": path,
			"sha256": FileAccess.get_sha256(path),
			"bytes": FileAccess.get_file_as_bytes(path).size(),
			"absolute_path": absolute_path,
		})
	for fixture_path in _integration_fixture_paths():
		evidence_files.append({
			"path": fixture_path,
			"sha256": FileAccess.get_sha256(fixture_path),
			"bytes": FileAccess.get_file_as_bytes(fixture_path).size(),
		})
	var visual_manifest := _load_json(
		"res://addons/world_transvoxel_cell_lab/standards/visual_manifest.json"
	)
	var visual_count := (visual_manifest.get("visuals", []) as Array).size()
	var visual_evidence_scope := str(visual_manifest.get("evidence_scope", ""))
	var source_capture_contract: Dictionary = visual_manifest.get(
		"capture_contract",
		{}
	)
	var visual_capture_contract := {
		"platform": str(source_capture_contract.get("platform", "")),
		"renderer": str(source_capture_contract.get("renderer", "")),
		"rendering_driver": str(
			source_capture_contract.get("rendering_driver", "")
		),
		"width": int(source_capture_contract.get("width", 0)),
		"height": int(source_capture_contract.get("height", 0)),
	}
	var visual_review: Dictionary = visual_manifest.get("review", {})
	var visual_review_status := str(visual_review.get("status", ""))
	var stable_manifest: Array[String] = []
	for evidence in evidence_files:
		stable_manifest.append("%s:%s:%d" % [
			str(evidence.get("path", "")),
			str(evidence.get("sha256", "")),
			int(evidence.get("bytes", 0)),
		])
	stable_manifest.append(
		"correctness:" + Common.json_hash(_stable_status_summary(correctness))
	)
	stable_manifest.append("runtime:" + Common.json_hash(_stable_status_summary(runtime)))
	stable_manifest.append(
		"integration:" + Common.json_hash(_stable_status_summary(integration))
	)
	stable_manifest.append("platform:" + Common.json_hash(_stable_status_summary(platform)))
	var status_ok := failures.is_empty() \
		and str(correctness.get("status", "")) == "PASS" \
		and str(runtime.get("status", "")) == "PASS" \
		and str(integration.get("status", "")) == "PASS" \
		and str(platform.get("status", "")) == "PASS" \
		and visual_count == 14 \
		and visual_evidence_scope \
			== "visual_regression_not_standalone_correctness" \
		and str(visual_capture_contract.get("platform", "")) == "Windows" \
		and str(visual_capture_contract.get("renderer", "")) == "forward_plus" \
		and str(visual_capture_contract.get("rendering_driver", "")) == "d3d12" \
		and int(visual_capture_contract.get("width", 0)) == 1152 \
		and int(visual_capture_contract.get("height", 0)) == 648 \
		and visual_review_status == "HUMAN_REVIEWED"
	return {
		"schema": Contracts.RELEASE_BUNDLE_SCHEMA,
		"status": "PASS" if status_ok else "FAIL",
		"authority": Contracts.NATIVE_AUTHORITY,
		"correctness_status": str(correctness.get("status", "FAIL")),
		"runtime_status": str(runtime.get("status", "FAIL")),
		"integration_status": str(integration.get("status", "FAIL")),
		"platform_status": str(platform.get("status", "FAIL")),
		"evidence_file_count": evidence_files.size(),
		"visual_standard_count": visual_count,
		"visual_evidence_scope": visual_evidence_scope,
		"visual_capture_contract": visual_capture_contract,
		"visual_review_status": visual_review_status,
		"visual_diff_contract": (
			"candidate_images_compared_by_labs/cell_lab/tools/"
			+ "compare_visual_standards.py"
		),
		"bundle_hash": "\n".join(stable_manifest).sha256_text(),
		"evidence_files": evidence_files,
		"sample_failures": failures if not status_ok else [],
	}


func _stable_status_summary(value: Dictionary) -> Dictionary:
	var summary := {"status": str(value.get("status", "FAIL"))}
	for key in [
		"schema",
		"profile_count",
		"probe_count",
		"operation_count",
		"scenario_count",
		"fixture_count",
		"required_target_count",
	]:
		if value.has(key):
			summary[key] = value[key]
	return summary


func _validate_upstream_governance(
	correctness: Dictionary,
	integration: Dictionary
) -> Dictionary:
	var registry := _load_json(GOVERNANCE_PATH)
	var policy: Dictionary = registry.get("policy", {})
	var required: Array = policy.get("required_evidence", [])
	var cases: Array = registry.get("cases", [])
	var failures: Array = []
	var confirmed_upstream := 0
	for case_value in cases:
		var case: Dictionary = case_value
		for key in [
			"id",
			"status",
			"owning_layer",
			"classification",
			"minimized_native_repro",
			"stated_invariant",
			"deterministic_reproduction",
			"focused_automated_coverage",
			"visual_evidence_for_geometry",
			"retained_regression_standard",
			"downstream_parity_proof",
			"resolution",
		]:
			if not case.has(key) or (
				typeof(case[key]) == TYPE_STRING and str(case[key]).is_empty()
			):
				failures.append("%s missing %s" % [str(case.get("id", "case")), key])
		if str(case.get("owning_layer", "")) == "world_transvoxel" \
				and str(case.get("status", "")) == "resolved":
			confirmed_upstream += 1
			if str(case.get("upstream_fix_reference", "")).is_empty():
				failures.append("%s missing upstream fix reference" % str(case.get("id", "")))
	var synthetic_incomplete := {"id": "incomplete_gate_test"}
	var synthetic_rejected := _governance_missing_field_count(synthetic_incomplete) > 0
	var reduction: Dictionary = correctness.get("failure_reduction", {})
	var retained_case_matches := not cases.is_empty() \
		and str((cases[0] as Dictionary).get("id", "")) == str(
			reduction.get("fixture_id", "")
		)
	if not retained_case_matches:
		failures.append("retained negative fixture is not governed")
	if str(integration.get("status", "")) != "PASS":
		failures.append("downstream integration parity is not passing")
	if str(registry.get("schema", "")) != Contracts.UPSTREAM_GOVERNANCE_SCHEMA:
		failures.append("unexpected governance schema")
	if required.size() != 8:
		failures.append("governance evidence gate changed")
	if not synthetic_rejected:
		failures.append("incomplete governance entry was accepted")
	return {
		"schema": Contracts.UPSTREAM_GOVERNANCE_SCHEMA,
		"status": "PASS" if failures.is_empty() else "FAIL",
		"case_count": cases.size(),
		"required_evidence_count": required.size(),
		"confirmed_upstream_correction_count": confirmed_upstream,
		"retained_negative_count": _count_case_status(cases, "retained_negative"),
		"unresolved_upstream_candidate_count": _count_case_status(
			cases,
			"upstream_candidate"
		),
		"incomplete_entry_rejected": synthetic_rejected,
		"retained_fixture_matches_reduction": retained_case_matches,
		"downstream_parity_status": str(integration.get("status", "FAIL")),
		"sample_failures": failures,
	}


func _governance_missing_field_count(case: Dictionary) -> int:
	var missing := 0
	for key in [
		"id",
		"status",
		"owning_layer",
		"classification",
		"minimized_native_repro",
		"stated_invariant",
		"deterministic_reproduction",
		"focused_automated_coverage",
		"visual_evidence_for_geometry",
		"retained_regression_standard",
		"downstream_parity_proof",
		"resolution",
	]:
		if not case.has(key):
			missing += 1
	return missing


func _count_case_status(cases: Array, status_value: String) -> int:
	var count := 0
	for case_value in cases:
		if str((case_value as Dictionary).get("status", "")) == status_value:
			count += 1
	return count


func _integration_fixture_paths() -> Array[String]:
	var paths: Array[String] = []
	var directory := DirAccess.open(INTEGRATION_FIXTURE_DIRECTORY)
	if directory == null:
		return paths
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			paths.append("%s/%s" % [INTEGRATION_FIXTURE_DIRECTORY, file_name])
		file_name = directory.get_next()
	directory.list_dir_end()
	paths.sort()
	return paths


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item in value:
		result.append(str(item))
	return result


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed := JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _load_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text
