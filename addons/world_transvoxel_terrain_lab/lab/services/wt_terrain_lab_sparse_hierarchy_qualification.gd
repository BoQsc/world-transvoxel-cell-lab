@tool
extends Node
class_name WtTerrainLabSparseHierarchyQualification

const Harness := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_runtime_harness.gd"
)
const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/sparse_hierarchy_storage_standard.json"
)
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/tqp42_sparse_hierarchy"
const SOURCE_ROOT := RUNTIME_ROOT + "/source"
const SNAPSHOT_ROOT := RUNTIME_ROOT + "/snapshot"
const REOPEN_JOURNAL_ROOT := RUNTIME_ROOT + "/reopen_journal"
const MIGRATED_ROOT := RUNTIME_ROOT + "/migrated"
const MIGRATED_JOURNAL_ROOT := RUNTIME_ROOT + "/migrated_journal"
const INTERRUPTED_ROOT := RUNTIME_ROOT + "/interrupted"
const CORRUPT_ROOT := RUNTIME_ROOT + "/corrupt"
const MISSING_ROOT := RUNTIME_ROOT + "/missing"


func run() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var profile: Dictionary = standard.get("runtime_profile", {})
	var workload: Dictionary = standard.get("workload", {})
	var budgets: Dictionary = standard.get("budgets", {})
	var failures: Array[String] = []
	var actions := {}
	var timings: Array[float] = []
	Harness.remove_tree(RUNTIME_ROOT)
	Harness.ensure_directory(RUNTIME_ROOT)
	var native_evidence := JsonLoader.load_dictionary(
		str(standard.get("native_benchmark_evidence", ""))
	)
	var native_valid := _native_evidence_valid(native_evidence, standard)
	_expect(native_valid, "upstream sparse hierarchy benchmark evidence is absent or invalid", failures)
	actions["native_exact_hierarchy_contract"] = _status(native_valid)
	actions["flat_catalog_comparison"] = _status(native_valid)

	var harness := Harness.new()
	add_child(harness)
	if not harness.create_runtime(int(profile.get("worker_count", 2)), _runtime_overrides(profile)):
		failures.append("native sparse hierarchy runtime could not be created")
		return await _finish(harness, standard, native_evidence, {}, actions, timings, failures)
	var started_usec := Time.get_ticks_usec()
	var started := await harness.start_procedural_world_preset(
		SOURCE_ROOT,
		int(profile.get("source_revision", 0)),
		int(profile.get("seed", 0)),
		str(profile.get("preset_id", "")),
		int(profile.get("chunk_count_x", 0)),
		int(profile.get("chunk_count_y", 0)),
		int(profile.get("chunk_origin_y", 0)),
		int(profile.get("chunk_count_z", 0))
	)
	var startup_usec := float(Time.get_ticks_usec() - started_usec)
	timings.append(startup_usec)
	if not started:
		failures.append("large implicit procedural world did not start")
		return await _finish(harness, standard, native_evidence, {}, actions, timings, failures)
	var terrain := harness.terrain
	var initial_metrics: Dictionary = terrain.call("get_runtime_metrics")
	var hierarchy_valid := _hierarchy_metrics_valid(initial_metrics, budgets, 0)
	_expect(hierarchy_valid, "runtime hierarchy materialized a catalog or changed accounting", failures)
	_expect(
		startup_usec <= float(budgets.get("maximum_startup_usec", 0.0)),
		"large implicit procedural startup exceeded the debug reference ceiling",
		failures
	)
	actions["implicit_runtime_startup"] = _status(started and hierarchy_valid)
	actions["declared_index_cache_resident_accounting"] = _status(hierarchy_valid)

	var central_point := _vector3i(workload.get("central_probe", []))
	var boundary_point := _vector3i(workload.get("boundary_probe", []))
	var baseline_central := await harness.request_sample(central_point)
	var baseline_boundary := await harness.request_sample(boundary_point)
	var settlement := await _update_viewer_and_settle(harness, terrain, profile, 1)
	var initial_state := _state_snapshot(terrain, harness)
	_expect(str(settlement.get("status", "")) == "PASS", "large hierarchy viewer did not settle", failures)

	var edit_started_usec := Time.get_ticks_usec()
	var central_committed := await _commit_operations(
		harness, terrain, workload.get("central_transaction", []), 4201, 1
	)
	var boundary_committed := await _commit_operations(
		harness, terrain, workload.get("boundary_transaction", []), 4202, 2
	)
	var edit_settlement := await harness.wait_for_settled(1)
	var edit_usec := float(Time.get_ticks_usec() - edit_started_usec)
	timings.append(edit_usec)
	var edited_central := await harness.request_sample(central_point)
	var edited_boundary := await harness.request_sample(boundary_point)
	var edited_state := _state_snapshot(terrain, harness)
	var edit_valid := central_committed and boundary_committed \
		and str(edit_settlement.get("status", "")) == "PASS" \
		and _sample_changed(baseline_central, edited_central) \
		and _sample_changed(baseline_boundary, edited_boundary) \
		and int(edited_central.get("world_revision", -1)) == 2 \
		and int(edited_boundary.get("world_revision", -1)) == 2
	_expect(edit_valid, "localized or finite-boundary edit invalidation failed", failures)
	actions["localized_and_boundary_edit_invalidation"] = _status(edit_valid)

	var compaction_started_usec := Time.get_ticks_usec()
	var compacted := await harness.request_compaction(
		SNAPSHOT_ROOT, int(profile.get("compacted_source_revision", 0))
	)
	var compaction_usec := float(Time.get_ticks_usec() - compaction_started_usec)
	timings.append(compaction_usec)
	var overlay_pages := int(compacted.get("page_count", -1))
	var compaction_valid := str(compacted.get("status", "")) == "PASS" \
		and overlay_pages > 0 \
		and overlay_pages < int(budgets.get("maximum_sparse_overlay_pages", 0)) \
		and compaction_usec <= float(budgets.get("maximum_compaction_usec", 0.0)) \
		and int(compacted.get("world_revision", -1)) == 2
	_expect(compaction_valid, "299,520-page sparse compaction failed", failures)
	actions["large_world_sparse_compaction"] = _status(compaction_valid)
	_expect(await harness.stop_world(), "large procedural source did not stop", failures)

	harness = await _fresh_harness(harness, profile)
	terrain = harness.terrain if harness != null else null
	var reopen_started_usec := Time.get_ticks_usec()
	var reopened := harness != null and compaction_valid and await harness.start_procedural_snapshot(
		SNAPSHOT_ROOT, REOPEN_JOURNAL_ROOT
	)
	var reopen_usec := float(Time.get_ticks_usec() - reopen_started_usec)
	timings.append(reopen_usec)
	var reopened_metrics := terrain.call("get_runtime_metrics") as Dictionary if reopened else {}
	var reopened_central := await harness.request_sample(central_point) if reopened else {}
	var reopened_boundary := await harness.request_sample(boundary_point) if reopened else {}
	var reopen_settlement := await _update_viewer_and_settle(harness, terrain, profile, 1) if reopened else {}
	var reopened_state := _state_snapshot(terrain, harness) if reopened else {}
	var reopen_valid := reopened \
		and _hierarchy_metrics_valid(reopened_metrics, budgets, overlay_pages) \
		and _samples_semantically_equal(edited_central, reopened_central) \
		and _samples_semantically_equal(edited_boundary, reopened_boundary) \
		and str(reopen_settlement.get("status", "")) == "PASS"
	_expect(reopen_valid, "sparse snapshot reopen or authoritative replay failed", failures)
	actions["sparse_snapshot_reopen_and_replay"] = _status(reopen_valid)
	var resources_valid := reopen_valid \
		and int(reopened_state.get("active_count", 0)) > 0 \
		and int((reopened_state.get("metrics", {}) as Dictionary).get("render_resources", 0)) > 0 \
		and str(reopened_state.get("geometry_signature", "")) == str(edited_state.get("geometry_signature", ""))
	_expect(resources_valid, "sparse snapshot did not regenerate identical adaptive resources", failures)
	actions["adaptive_resource_regeneration"] = _status(resources_valid)

	Harness.ensure_directory(INTERRUPTED_ROOT + ".tmp")
	var marker := INTERRUPTED_ROOT + ".tmp/interrupted.marker"
	_store_bytes(marker, "incomplete".to_utf8_buffer())
	var interrupted := await harness.request_migration(INTERRUPTED_ROOT)
	var interrupted_valid := str(interrupted.get("status", "")) == "FAIL" \
		and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(INTERRUPTED_ROOT)) \
		and FileAccess.file_exists(marker)
	_expect(interrupted_valid, "interrupted sparse publication did not fail closed", failures)
	actions["interrupted_publication_failure"] = _status(interrupted_valid)
	Harness.remove_tree(INTERRUPTED_ROOT + ".tmp")
	harness.snapshot_failures.clear()
	var migration_started_usec := Time.get_ticks_usec()
	var migrated := await harness.request_migration(MIGRATED_ROOT)
	var migration_usec := float(Time.get_ticks_usec() - migration_started_usec)
	timings.append(migration_usec)
	var migration_valid := str(migrated.get("status", "")) == "PASS" \
		and int(migrated.get("page_count", -1)) == overlay_pages \
		and migration_usec <= float(budgets.get("maximum_migration_usec", 0.0))
	_expect(migration_valid, "sparse snapshot migration failed", failures)
	if reopened:
		_expect(await harness.stop_world(), "reopened sparse snapshot did not stop", failures)
	harness = await _fresh_harness(harness, profile)
	terrain = harness.terrain if harness != null else null
	var migrated_started := harness != null and migration_valid and await harness.start_procedural_snapshot(
		MIGRATED_ROOT, MIGRATED_JOURNAL_ROOT
	)
	var migrated_central := await harness.request_sample(central_point) if migrated_started else {}
	var migrated_boundary := await harness.request_sample(boundary_point) if migrated_started else {}
	var migrated_valid := migrated_started \
		and _samples_semantically_equal(reopened_central, migrated_central) \
		and _samples_semantically_equal(reopened_boundary, migrated_boundary)
	_expect(migrated_valid, "migrated sparse snapshot changed authoritative samples", failures)
	actions["sparse_snapshot_migration"] = _status(migration_valid and migrated_valid)
	if migrated_started:
		_expect(await harness.stop_world(), "migrated sparse snapshot did not stop", failures)

	var corruption := await _corruption_contract(SNAPSHOT_ROOT)
	actions["corrupt_descriptor_failure"] = _status(bool(corruption.get("corrupt_descriptor", false)))
	actions["missing_manifest_failure"] = _status(bool(corruption.get("missing_manifest", false)))
	_expect(bool(corruption.get("corrupt_descriptor", false)), "corrupt descriptor was accepted", failures)
	_expect(bool(corruption.get("missing_manifest", false)), "missing sparse manifest was accepted", failures)

	var data := {
		"startup_usec": startup_usec,
		"edit_usec": edit_usec,
		"compaction_usec": compaction_usec,
		"reopen_usec": reopen_usec,
		"migration_usec": migration_usec,
		"initial_metrics": _selected_metrics(initial_metrics),
		"initial_state": initial_state,
		"baseline_central": baseline_central,
		"baseline_boundary": baseline_boundary,
		"edited_central": edited_central,
		"edited_boundary": edited_boundary,
		"edited_state": edited_state,
		"compaction": compacted,
		"reopened_metrics": _selected_metrics(reopened_metrics),
		"reopened_central": reopened_central,
		"reopened_boundary": reopened_boundary,
		"reopened_state": reopened_state,
		"interrupted": interrupted,
		"migration": migrated,
		"migrated_central": migrated_central,
		"migrated_boundary": migrated_boundary,
		"corruption": corruption,
	}
	return await _finish(harness, standard, native_evidence, data, actions, timings, failures)


func _finish(
	harness: Node,
	standard: Dictionary,
	native_evidence: Dictionary,
	data: Dictionary,
	actions: Dictionary,
	timings: Array[float],
	failures: Array[String]
) -> Dictionary:
	if harness != null and harness.terrain != null:
		if str(harness.terrain.call("get_world_state_name")) != "stopped" and not await harness.stop_world():
			failures.append("sparse hierarchy runtime did not stop cleanly")
		harness.dispose()
		harness.queue_free()
		await get_tree().process_frame
	Harness.remove_tree(RUNTIME_ROOT)
	var semantic_source := {
		"actions": actions,
		"native_hash": (native_evidence.get("authority", {}) as Dictionary).get("native_contract_hash", ""),
		"declared_pages": (data.get("initial_metrics", {}) as Dictionary).get("hierarchy_declared_pages", -1),
		"edited_central": _sample_semantic_record(data.get("edited_central", {})),
		"edited_boundary": _sample_semantic_record(data.get("edited_boundary", {})),
		"compacted_pages": (data.get("compaction", {}) as Dictionary).get("page_count", -1),
		"migrated_pages": (data.get("migration", {}) as Dictionary).get("page_count", -1),
		"geometry": (data.get("edited_state", {}) as Dictionary).get("geometry_signature", ""),
	}
	return {
		"schema": "world_transvoxel.terrain_lab.sparse_hierarchy_qualification.v1",
		"milestone": "TQP-42",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"retained_complete": true,
		"standard_id": standard.get("standard_id", ""),
		"authority": standard.get("authority", ""),
		"actions": actions,
		"native_benchmark": native_evidence,
		"runtime": data,
		"performance": {
			"scope": "WINDOWS_DEBUG_REFERENCE_NOT_PRODUCTION_FRAME_OR_SAVE_BUDGET",
			"operation_usec": Statistics.distribution(timings),
			"memory": Statistics.memory_metrics(),
		},
		"semantic_signature": JSON.stringify(semantic_source, "", true).sha256_text(),
		"provenance": Statistics.provenance("tqp42_sparse_hierarchy_windows_v1"),
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"finding_disposition": "TQP-F002_CLOSED_BY_TQP42_SPARSE_PROCEDURAL_SNAPSHOT",
		"failures": failures,
	}


func _fresh_harness(previous: Node, profile: Dictionary) -> Node:
	if previous != null:
		previous.dispose()
		previous.queue_free()
		await get_tree().process_frame
	var replacement := Harness.new()
	add_child(replacement)
	if not replacement.create_runtime(int(profile.get("worker_count", 2)), _runtime_overrides(profile)):
		replacement.queue_free()
		await get_tree().process_frame
		return null
	return replacement


func _update_viewer_and_settle(harness: Node, terrain: Node, profile: Dictionary, revision: int) -> Dictionary:
	if terrain == null or not bool(terrain.call(
		"update_viewer",
		int(profile.get("viewer_id", 421)),
		revision,
		_vector3(profile.get("viewer_position", [])),
		int(profile.get("viewer_radius_chunks", 1)),
		int(profile.get("maximum_lod", 3))
	)):
		return {"status": "FAIL", "error": "viewer update rejected"}
	return await harness.wait_for_settled(1)


func _commit_operations(harness: Node, terrain: Node, operations: Array, author: int, revision: int) -> bool:
	var transaction: RefCounted = terrain.call("begin_edit_transaction", author)
	if transaction == null:
		return false
	for value in operations:
		var operation: Dictionary = value
		var method := str(operation.get("operation", ""))
		var accepted := false
		if method == "carve_smooth_sdf_sphere":
			accepted = bool(transaction.call(method, _vector3(operation.get("center", [])), float(operation.get("radius", 0.0)), float(operation.get("strength", 1.0)), float(operation.get("smooth_radius", 0.0))))
		elif method == "construct_material_smooth_sdf_sphere":
			accepted = bool(transaction.call(method, _vector3(operation.get("center", [])), float(operation.get("radius", 0.0)), float(operation.get("strength", 1.0)), int(operation.get("material", 0)), float(operation.get("smooth_radius", 0.0))))
		if not accepted:
			return false
	return bool(terrain.call("commit_edit_transaction", transaction)) \
		and await harness.wait_for_commit(revision)


func _corruption_contract(snapshot_root: String) -> Dictionary:
	Harness.remove_tree(CORRUPT_ROOT)
	Harness.remove_tree(MISSING_ROOT)
	Harness.ensure_directory(CORRUPT_ROOT)
	Harness.ensure_directory(MISSING_ROOT)
	var descriptor := FileAccess.get_file_as_bytes(snapshot_root.path_join("world.wtproc"))
	if descriptor.is_empty():
		return {"corrupt_descriptor": false, "missing_manifest": false}
	descriptor[descriptor.size() - 1] = descriptor[descriptor.size() - 1] ^ 0x80
	_store_bytes(CORRUPT_ROOT.path_join("world.wtproc"), descriptor)
	var world := FileAccess.get_file_as_bytes(snapshot_root.path_join("world.wtworld"))
	_store_bytes(CORRUPT_ROOT.path_join("world.wtworld"), world)
	_store_bytes(MISSING_ROOT.path_join("world.wtproc"), FileAccess.get_file_as_bytes(snapshot_root.path_join("world.wtproc")))
	var corrupt_rejected := await _startup_rejected(CORRUPT_ROOT, CORRUPT_ROOT.path_join("journal"))
	var missing_rejected := await _startup_rejected(MISSING_ROOT, MISSING_ROOT.path_join("journal"))
	return {"corrupt_descriptor": corrupt_rejected, "missing_manifest": missing_rejected}


func _startup_rejected(snapshot_root: String, journal_root: String) -> bool:
	var probe := Harness.new()
	add_child(probe)
	if not probe.create_runtime(1):
		probe.queue_free()
		return false
	var accepted := await probe.start_procedural_snapshot(snapshot_root, journal_root)
	var rejected := not accepted and str(probe.terrain.call("get_world_state_name")) != "running"
	probe.dispose()
	probe.queue_free()
	await get_tree().process_frame
	return rejected


static func _native_evidence_valid(evidence: Dictionary, standard: Dictionary) -> bool:
	var authority: Dictionary = evidence.get("authority", {})
	var summary: Dictionary = evidence.get("summary", {})
	var counters: Dictionary = summary.get("fixed_counters", {})
	var expected: Dictionary = standard.get("stable_expected", {})
	return str(evidence.get("status", "")) == "PASS" \
		and int((evidence.get("method", {}) as Dictionary).get("measured_runs", 0)) >= 7 \
		and str((evidence.get("method", {}) as Dictionary).get("memory_metric", "")) == str(expected.get("memory_metric", "")) \
		and str(authority.get("git_commit", "")) == str(expected.get("upstream_commit", "")) \
		and str(authority.get("executable_sha256", "")) == str(expected.get("executable_sha256", "")) \
		and str(authority.get("native_contract_hash", "")) == str(expected.get("native_contract_hash", "")) \
		and int(counters.get("declared_pages", -1)) == int(expected.get("declared_pages", -2)) \
		and int(counters.get("hierarchy_index_bytes", -1)) == int(expected.get("hierarchy_index_bytes", -2)) \
		and int(counters.get("overlay_pages", -1)) == int(expected.get("native_overlay_pages", -2)) \
		and int((summary.get("peak_working_set_bytes", {}) as Dictionary).get("worst", 0)) > 0


static func _hierarchy_metrics_valid(metrics: Dictionary, budgets: Dictionary, expected_overlay_pages: int) -> bool:
	return int(metrics.get("hierarchy_kind", -1)) == 2 \
		and int(metrics.get("hierarchy_declared_pages", -1)) == int(budgets.get("expected_declared_page_count", -2)) \
		and int(metrics.get("hierarchy_explicit_index_entries", -1)) <= int(budgets.get("maximum_explicit_index_entries", -2)) \
		and int(metrics.get("hierarchy_estimated_index_bytes", -1)) <= int(budgets.get("maximum_hierarchy_index_bytes", -2)) \
		and int(metrics.get("hierarchy_sparse_overlay_entries", -1)) == expected_overlay_pages \
		and int(metrics.get("hierarchy_sparse_overlay_index_bytes", -1)) <= int(budgets.get("maximum_sparse_overlay_index_bytes", -2))


static func _state_snapshot(terrain: Node, harness: Node) -> Dictionary:
	var lines: Array[String] = []
	var ready_mismatches := 0
	for value in terrain.call("query_active_chunk_states"):
		var state: RefCounted = value
		var coordinate: Vector3i = state.call("get_chunk_coordinate")
		lines.append("%d:%d:%d:%d" % [coordinate.x, coordinate.y, coordinate.z, int(state.call("get_lod"))])
		if not bool(state.call("is_fully_ready")):
			ready_mismatches += 1
	lines.sort()
	var mesh_lines: Array[String] = []
	for child in terrain.get_children():
		if child is MeshInstance3D and str(child.name).begins_with("WT_Render_"):
			mesh_lines.append(str(child.name) + ":" + harness.mesh_signature(str(child.name)))
	mesh_lines.sort()
	return {
		"active_count": lines.size(),
		"ready_mismatch_count": ready_mismatches,
		"state_signature": "\n".join(lines).sha256_text(),
		"geometry_signature": "\n".join(mesh_lines).sha256_text(),
		"metrics": _selected_metrics(terrain.call("get_runtime_metrics")),
	}


static func _selected_metrics(metrics: Dictionary) -> Dictionary:
	var selected := {}
	for key in [
		"hierarchy_kind", "hierarchy_declared_pages", "hierarchy_explicit_index_entries",
		"hierarchy_estimated_index_bytes", "hierarchy_sparse_overlay_entries",
		"hierarchy_sparse_overlay_index_bytes", "hierarchy_membership_queries",
		"hierarchy_child_queries", "hierarchy_ancestor_queries", "hierarchy_neighbor_queries",
		"hierarchy_range_queries", "hierarchy_viewer_root_queries", "hierarchy_lod_enumerations",
		"page_cache_encoded_entries", "page_cache_decoded_entries", "active_chunk_records",
		"render_resources", "collision_resources", "scheduler_queued_jobs",
		"scheduler_queued_completions", "storage_queued_requests", "queued_render",
		"pending_chunk_replacements", "pending_chunk_retirements", "page_mesh_failures",
		"page_storage_failures", "world_snapshots", "world_snapshot_rejections",
	]:
		selected[key] = metrics.get(key, -1)
	return selected


static func _sample_changed(before: Dictionary, after: Dictionary) -> bool:
	return str(before.get("status", "")) == "PASS" \
		and str(after.get("status", "")) == "PASS" \
		and (float(before.get("density", 0.0)) != float(after.get("density", 0.0)) \
			or int(before.get("material", 0)) != int(after.get("material", 0)))


static func _samples_semantically_equal(left: Dictionary, right: Dictionary) -> bool:
	return str(left.get("status", "")) == "PASS" \
		and str(right.get("status", "")) == "PASS" \
		and str(left.get("point", "")) == str(right.get("point", "")) \
		and int(left.get("lod", -1)) == int(right.get("lod", -2)) \
		and float(left.get("density", 0.0)) == float(right.get("density", 1.0)) \
		and int(left.get("material", -1)) == int(right.get("material", -2)) \
		and int(left.get("world_revision", -1)) == int(right.get("world_revision", -2))


static func _sample_semantic_record(value: Variant) -> Dictionary:
	var sample: Dictionary = value
	return {
		"status": sample.get("status", ""),
		"point": sample.get("point", ""),
		"lod": sample.get("lod", -1),
		"density": sample.get("density", 0.0),
		"material": sample.get("material", -1),
		"world_revision": sample.get("world_revision", -1),
	}


static func _runtime_overrides(profile: Dictionary) -> Dictionary:
	return {
		"active_chunk_capacity": int(profile.get("active_chunk_capacity", 512)),
		"demand_capacity_per_viewer": int(profile.get("active_chunk_capacity", 512)),
		"lod_refinement_radius_chunks": int(profile.get("lod_refinement_radius_chunks", 1)),
		"storage_request_capacity": int(profile.get("pipeline_capacity", 2048)),
		"storage_completion_capacity": int(profile.get("pipeline_capacity", 2048)),
		"encoded_page_entry_capacity": int(profile.get("page_cache_capacity", 512)),
		"decoded_page_entry_capacity": int(profile.get("page_cache_capacity", 512)),
		"mesh_entry_capacity": int(profile.get("page_cache_capacity", 512)),
		"render_entry_capacity": int(profile.get("page_cache_capacity", 512)),
		"collision_entry_capacity": int(profile.get("collision_capacity", 128)),
		"global_coarse_lod_coverage": false,
	}


static func _store_bytes(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	return true


static func _vector3(value: Variant) -> Vector3:
	var values: Array = value
	return Vector3(float(values[0]), float(values[1]), float(values[2])) if values.size() == 3 else Vector3.ZERO


static func _vector3i(value: Variant) -> Vector3i:
	var values: Array = value
	return Vector3i(int(values[0]), int(values[1]), int(values[2])) if values.size() == 3 else Vector3i.ZERO


static func _status(value: bool) -> String:
	return "PASS" if value else "FAIL"


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
