@tool
extends RefCounted
class_name WtCellLabDependencyProvenance

const Contracts := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_contracts.gd")
const MANIFEST_PATH := "res://addons/world_transvoxel_cell_lab/standards/native_dependency_manifest.json"
const PLUGIN_PATH := "res://addons/world_transvoxel/plugin.cfg"
const EXPECTED_MANIFEST_SCHEMA := "world_transvoxel.cell_lab.native_dependency_manifest.v1"


func validate(probe: RefCounted) -> Dictionary:
	var manifest := _load_manifest()
	var failures: Array[String] = []
	if manifest.is_empty():
		failures.append("native dependency manifest could not be loaded")
	elif str(manifest.get("schema", "")) != EXPECTED_MANIFEST_SCHEMA:
		failures.append("native dependency manifest schema changed")
	var identity: Dictionary = probe.call("get_backend_identity") \
		if probe != null and probe.has_method("get_backend_identity") else {}
	if identity.is_empty():
		failures.append("native backend identity is unavailable")
	var expected_backend: Dictionary = manifest.get("backend", {})
	for comparison in [
		["backend_id", "id"],
		["backend_license", "license"],
		["backend_upstream_revision", "upstream_revision"],
		["regular_case_count", "regular_case_count"],
		["transition_case_count", "transition_case_count"],
	]:
		var actual_key := str(comparison[0])
		var expected_key := str(comparison[1])
		if identity.get(actual_key) != expected_backend.get(expected_key):
			failures.append(
				"native backend identity mismatch: %s" % actual_key
			)
	var config := ConfigFile.new()
	if config.load(PLUGIN_PATH) != OK:
		failures.append("vendored plugin configuration could not be loaded")
	var plugin_version := str(config.get_value("plugin", "version", ""))
	var plugin_name := str(config.get_value("plugin", "name", ""))
	if plugin_name != str(manifest.get("plugin", {}).get("name", "")):
		failures.append("vendored plugin name differs from manifest")
	if plugin_version != str(manifest.get("plugin", {}).get("version", "")):
		failures.append("vendored plugin version differs from manifest")
	var artifact_results: Array = []
	for artifact_value in manifest.get("artifacts", []):
		var artifact: Dictionary = artifact_value
		var relative_path := str(artifact.get("path", ""))
		var resource_path := "res://" + relative_path
		var actual_hash := FileAccess.get_sha256(resource_path)
		var file := FileAccess.open(resource_path, FileAccess.READ)
		var actual_bytes := file.get_length() if file != null else -1
		if file != null:
			file.close()
		var matches := actual_hash == str(artifact.get("sha256", "")) \
			and actual_bytes == int(artifact.get("bytes", -1))
		if not matches:
			failures.append("native artifact differs from manifest: %s" % relative_path)
		artifact_results.append({
			"path": relative_path,
			"configuration": artifact.get("configuration", ""),
			"bytes": actual_bytes,
			"sha256": actual_hash,
			"status": "PASS" if matches else "FAIL",
		})
	return {
		"schema": Contracts.NATIVE_DEPENDENCY_VALIDATION_SCHEMA,
		"status": "PASS" if failures.is_empty() else "FAIL",
		"authority": Contracts.NATIVE_AUTHORITY,
		"manifest_schema": manifest.get("schema", ""),
		"source": manifest.get("source", {}),
		"plugin": manifest.get("plugin", {}),
		"backend": expected_backend,
		"runtime_identity": identity,
		"artifact_count": artifact_results.size(),
		"artifacts": artifact_results,
		"sample_failures": failures,
	}


func standard_signature(probe: RefCounted) -> Dictionary:
	var result := validate(probe)
	return {
		"status": result.get("status", "FAIL"),
		"source_repository": result.get("source", {}).get("repository", ""),
		"source_commit": result.get("source", {}).get("commit", ""),
		"addon_source_tree": result.get("source", {}).get("addon_source_tree", ""),
		"addon_thirdparty_tree": result.get("source", {}).get(
			"addon_thirdparty_tree",
			""
		),
		"godot_cpp_revision": result.get("source", {}).get(
			"godot_cpp_revision",
			""
		),
		"plugin_name": result.get("plugin", {}).get("name", ""),
		"plugin_version": result.get("plugin", {}).get("version", ""),
		"backend_id": result.get("backend", {}).get("id", ""),
		"backend_license": result.get("backend", {}).get("license", ""),
		"backend_upstream_revision": result.get("backend", {}).get(
			"upstream_revision",
			""
		),
		"official_source_sha256": result.get("backend", {}).get(
			"official_source_sha256",
			""
		),
		"artifact_hashes": _artifact_hashes(result.get("artifacts", [])),
	}


func _load_manifest() -> Dictionary:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed := JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _artifact_hashes(artifacts: Array) -> Array[String]:
	var hashes: Array[String] = []
	for artifact_value in artifacts:
		var artifact: Dictionary = artifact_value
		hashes.append(str(artifact.get("sha256", "")))
	return hashes
