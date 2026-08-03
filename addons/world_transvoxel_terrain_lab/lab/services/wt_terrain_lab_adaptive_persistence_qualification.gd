@tool
extends Node
class_name WtTerrainLabAdaptivePersistenceQualification

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
	"res://addons/world_transvoxel_terrain_lab/standards/adaptive_persistence_standard.json"
)
const FIXTURE_ROOT := "res://labs/terrain_lab/fixtures/adaptive_persistence"
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/tqp41_adaptive_persistence"
const SOURCE_ROOT := RUNTIME_ROOT + "/source"
const CRASH_ROOT := RUNTIME_ROOT + "/crash_prefix"
const COMPACTED_ROOT := RUNTIME_ROOT + "/compacted"
const MIGRATED_ROOT := RUNTIME_ROOT + "/migrated"
const INTERRUPTED_ROOT := RUNTIME_ROOT + "/interrupted"


func run() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var profile: Dictionary = standard.get("runtime_profile", {})
	var workload: Dictionary = standard.get("workload", {})
	var failures: Array[String] = []
	var actions := {}
	var settlements: Array[Dictionary] = []
	var operation_times: Array[float] = []
	Harness.remove_tree(RUNTIME_ROOT)
	Harness.ensure_directory(RUNTIME_ROOT)
	var inherited_recovery := _inherited_tqp26_recovery(standard)
	var inherited_recovery_valid := str(inherited_recovery.get("status", "")) == "PASS"
	_expect(inherited_recovery_valid, "retained TQP-26 truncated-tail recovery is absent", failures)
	actions["inherited_truncated_journal_recovery"] = _status(inherited_recovery_valid)
	var fixture := JsonLoader.load_dictionary(str(standard.get("fixture_manifest", "")))
	var fixture_valid := _stage_fixture(fixture, SOURCE_ROOT, failures)
	_expect(fixture_valid, "native adaptive persistence fixture integrity failed", failures)
	actions["native_baked_fixture_integrity"] = _status(fixture_valid)
	var harness := Harness.new()
	add_child(harness)
	if not fixture_valid or not harness.create_runtime(
		int(profile.get("worker_count", 2)), _runtime_overrides(profile)
	):
		failures.append("native adaptive persistence runtime could not be created")
		return await _finish(harness, standard, fixture, {}, actions, settlements, operation_times, failures)
	var source_manifest := SOURCE_ROOT.path_join(str(fixture.get("manifest", "world.wtworld")))
	if not await harness.start_manifest(source_manifest, SOURCE_ROOT):
		failures.append("native baked adaptive fixture did not start")
		return await _finish(harness, standard, fixture, {}, actions, settlements, operation_times, failures)
	var terrain := harness.terrain
	var initial_settlement := await _update_viewer_and_settle(harness, terrain, profile, _vector3(profile.get("viewer_position", [])), 1, int(profile.get("viewer_radius_chunks", 1)))
	_record_settlement("initial", initial_settlement, settlements, operation_times)
	var initial_snapshot := _state_snapshot(terrain, harness)
	var initial_valid := str(initial_settlement.get("status", "")) == "PASS" \
		and _initial_residency_valid(initial_snapshot, standard)
	_expect(initial_valid, "initial adaptive baked residency changed", failures)
	actions["adaptive_residency_before_edit"] = _status(initial_valid)
	var central_points := _vector3i_array(workload.get("central_probes", []))
	var distant_point := _vector3i(workload.get("distant_probe", []))
	var baseline_central := await harness.request_samples(central_points)
	var baseline_distant := await harness.request_sample(distant_point, 1)

	var transaction_started := Time.get_ticks_usec()
	var central_committed := await _commit_operations(
		harness, terrain, workload.get("central_transaction", []), 4101, 1
	)
	operation_times.append(float(Time.get_ticks_usec() - transaction_started))
	var central_settlement := await harness.wait_for_settled(1)
	_record_settlement("central_edit", central_settlement, settlements, operation_times)
	var central_samples := await harness.request_samples(central_points)
	var distant_after_central := await harness.request_sample(distant_point, 1)
	var central_valid := central_committed \
		and str(central_settlement.get("status", "")) == "PASS" \
		and _central_edit_semantics(central_samples)
	_expect(central_valid, "central cave/construction transaction changed semantics", failures)

	transaction_started = Time.get_ticks_usec()
	var distant_committed := await _commit_operations(
		harness, terrain, workload.get("distant_transaction", []), 4102, 2
	)
	operation_times.append(float(Time.get_ticks_usec() - transaction_started))
	var distant_settlement := await harness.wait_for_settled()
	_record_settlement("distant_unloaded_edit", distant_settlement, settlements, operation_times)
	var distant_samples := await harness.request_sample(distant_point, 1)
	var final_central := await harness.request_samples(central_points)
	var distant_key := "5:1:5:1"
	var distant_unloaded := not (_key_set(terrain) as Dictionary).has(distant_key)
	var distant_valid := distant_committed \
		and str(distant_settlement.get("status", "")) == "PASS" \
		and distant_unloaded and _distant_edit_semantics(distant_samples)
	_expect(distant_valid, "distant unloaded construction was not durable and observable", failures)
	actions["complex_durable_edit_transactions"] = _status(central_valid and distant_valid)
	actions["distant_unloaded_edit"] = _status(distant_valid)
	var edited_snapshot := _state_snapshot(terrain, harness)
	var edited_geometry := str(edited_snapshot.get("geometry_signature", ""))
	var edited_sample_signature := _sample_bundle_signature(final_central, distant_samples)
	var journal_path := SOURCE_ROOT + "/world.wtedit"
	var journal_sha256 := FileAccess.get_sha256(journal_path) if FileAccess.file_exists(journal_path) else ""
	var journal_diagnostics := _journal_diagnostics(journal_path)
	_expect(not journal_sha256.is_empty(), "durable adaptive edit journal was not written", failures)

	_expect(await harness.stop_world(), "edited source did not stop before recovery", failures)
	await get_tree().process_frame
	var crash_fixture_ready := _copy_tree(SOURCE_ROOT, CRASH_ROOT) \
		and _retain_complete_prefix(CRASH_ROOT + "/world.wtedit")
	var truncated_journal_diagnostics := _journal_diagnostics(CRASH_ROOT + "/world.wtedit")
	harness = await _fresh_harness(harness, profile)
	terrain = harness.terrain if harness != null else null
	var crash_started := harness != null and crash_fixture_ready and await harness.start_manifest(
		CRASH_ROOT.path_join(str(fixture.get("manifest", "world.wtworld"))), CRASH_ROOT
	)
	var crash_central: Array[Dictionary] = []
	var crash_distant := {}
	if crash_started:
		crash_central = await harness.request_samples(central_points)
		crash_distant = await harness.request_sample(distant_point, 1)
	var crash_valid := crash_started \
		and int(terrain.call("get_world_revision")) == 1 \
		and _samples_semantically_equal(central_samples, crash_central) \
		and _sample_semantically_equal(distant_after_central, crash_distant)
	_expect(crash_valid, "adaptive complete journal prefix did not replay the first transaction", failures)
	actions["adaptive_complete_journal_prefix_replay"] = _status(crash_valid)
	if crash_started:
		_expect(await harness.stop_world(), "crash-prefix fixture did not stop", failures)

	harness = await _fresh_harness(harness, profile)
	terrain = harness.terrain if harness != null else null
	if harness != null:
		harness.clear_events()
	var replay_started := harness != null and await harness.start_manifest(source_manifest, SOURCE_ROOT)
	var replay_settlement := {}
	if replay_started:
		replay_settlement = await _update_viewer_and_settle(harness, terrain, profile, _vector3(profile.get("viewer_position", [])), 1, int(profile.get("viewer_radius_chunks", 1)))
	_record_settlement("journal_replay", replay_settlement, settlements, operation_times)
	var replay_central: Array[Dictionary] = []
	var replay_distant := {}
	var replay_snapshot := {}
	if replay_started:
		replay_central = await harness.request_samples(central_points)
		replay_distant = await harness.request_sample(distant_point, 1)
		replay_snapshot = _state_snapshot(terrain, harness)
	var replay_valid := replay_started \
		and str(replay_settlement.get("status", "")) == "PASS" \
		and int(terrain.call("get_world_revision")) == 2 \
		and _samples_equal(final_central, replay_central, false) \
		and _samples_equal([distant_samples], [replay_distant], false) \
		and str(replay_snapshot.get("geometry_signature", "")) == edited_geometry
	_expect(replay_valid, "journal replay changed queries, residency, or native geometry", failures)
	actions["journal_replay"] = _status(replay_valid)

	var compaction_started := Time.get_ticks_usec()
	var compacted := await harness.request_compaction(
		COMPACTED_ROOT, int(profile.get("compacted_source_revision", 941002))
	)
	operation_times.append(float(Time.get_ticks_usec() - compaction_started))
	var compaction_valid := str(compacted.get("status", "")) == "PASS" \
		and int(compacted.get("page_count", -1)) == int(fixture.get("page_count", -2)) \
		and int(compacted.get("world_revision", -1)) == 2 \
		and int(compacted.get("source_revision", -1)) == int(profile.get("compacted_source_revision", -2))
	_expect(compaction_valid, "supported 44-page adaptive snapshot compaction failed", failures)
	actions["supported_snapshot_compaction"] = _status(compaction_valid)
	_expect(await harness.stop_world(), "journal source did not stop after compaction", failures)

	harness = await _fresh_harness(harness, profile)
	terrain = harness.terrain if harness != null else null
	if harness != null:
		harness.clear_events()
	var compacted_manifest := str(compacted.get("manifest_path", ""))
	var compacted_started := harness != null and compaction_valid and await harness.start_manifest(compacted_manifest, COMPACTED_ROOT)
	var compacted_settlement := {}
	if compacted_started:
		compacted_settlement = await _update_viewer_and_settle(harness, terrain, profile, _vector3(profile.get("viewer_position", [])), 1, int(profile.get("viewer_radius_chunks", 1)))
	_record_settlement("compacted_restart", compacted_settlement, settlements, operation_times)
	var compacted_central: Array[Dictionary] = []
	var compacted_distant := {}
	var compacted_snapshot := {}
	if compacted_started:
		compacted_central = await harness.request_samples(central_points)
		compacted_distant = await harness.request_sample(distant_point, 1)
		compacted_snapshot = _state_snapshot(terrain, harness)
	var compacted_replay_valid := compacted_started \
		and str(compacted_settlement.get("status", "")) == "PASS" \
		and _samples_equal(final_central, compacted_central, true) \
		and _samples_equal([distant_samples], [compacted_distant], true) \
		and str(compacted_snapshot.get("state_signature", "")) == str(initial_snapshot.get("state_signature", "")) \
		and str(compacted_snapshot.get("geometry_signature", "")) == edited_geometry
	_expect(compacted_replay_valid, "compacted restart changed queries, adaptive residency, or geometry", failures)

	var distant_settle_after_restart := {}
	var distant_snapshot := {}
	if compacted_started:
		distant_settle_after_restart = await _update_viewer_and_settle(
			harness, terrain, profile, _vector3(workload.get("distant_viewer_position", [])), 2, 0
		)
		distant_snapshot = _state_snapshot(terrain, harness)
	_record_settlement("distant_post_restart", distant_settle_after_restart, settlements, operation_times)
	var post_restart_resource := str(distant_settle_after_restart.get("status", "")) == "PASS" \
		and int(distant_snapshot.get("active_count", 0)) == 1 \
		and int((distant_snapshot.get("metrics", {}) as Dictionary).get("render_resources", 0)) == 1 \
		and (_key_set(terrain) as Dictionary).has(distant_key)
	_expect(post_restart_resource, "distant edited resource did not regenerate after restart", failures)
	actions["post_restart_query_and_resource_regeneration"] = _status(compacted_replay_valid and post_restart_resource)

	Harness.ensure_directory(INTERRUPTED_ROOT + ".tmp")
	var marker_path := INTERRUPTED_ROOT + ".tmp/interrupted.marker"
	_store_bytes(marker_path, "incomplete".to_utf8_buffer())
	var interrupted := await harness.request_migration(INTERRUPTED_ROOT)
	var interrupted_valid := str(interrupted.get("status", "")) == "FAIL" \
		and str(interrupted.get("error", "")) == "world snapshot file writing failed" \
		and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(INTERRUPTED_ROOT)) \
		and FileAccess.file_exists(marker_path)
	_expect(interrupted_valid, "pre-existing interrupted staging state did not fail closed", failures)
	actions["atomic_staging_failure"] = _status(interrupted_valid)
	Harness.remove_tree(INTERRUPTED_ROOT + ".tmp")
	harness.snapshot_failures.clear()
	var migration_started := Time.get_ticks_usec()
	var migrated := await harness.request_migration(MIGRATED_ROOT)
	operation_times.append(float(Time.get_ticks_usec() - migration_started))
	var migration_valid := str(migrated.get("status", "")) == "PASS" \
		and int(migrated.get("page_count", -1)) == int(fixture.get("page_count", -2)) \
		and int(migrated.get("world_revision", -1)) == 2
	_expect(migration_valid, "adaptive snapshot migration failed", failures)
	if compacted_started:
		_expect(await harness.stop_world(), "compacted fixture did not stop", failures)
	harness = await _fresh_harness(harness, profile)
	terrain = harness.terrain if harness != null else null
	if harness != null:
		harness.clear_events()
	var migrated_started := harness != null and migration_valid and await harness.start_manifest(str(migrated.get("manifest_path", "")), MIGRATED_ROOT)
	var migrated_settlement := {}
	if migrated_started:
		migrated_settlement = await _update_viewer_and_settle(harness, terrain, profile, _vector3(profile.get("viewer_position", [])), 1, int(profile.get("viewer_radius_chunks", 1)))
	_record_settlement("migrated_restart", migrated_settlement, settlements, operation_times)
	var migrated_central: Array[Dictionary] = []
	var migrated_distant := {}
	var migrated_snapshot := {}
	if migrated_started:
		migrated_central = await harness.request_samples(central_points)
		migrated_distant = await harness.request_sample(distant_point, 1)
		migrated_snapshot = _state_snapshot(terrain, harness)
	var migrated_replay_valid := migrated_started \
		and str(migrated_settlement.get("status", "")) == "PASS" \
		and _samples_equal(compacted_central, migrated_central, false) \
		and _samples_equal([compacted_distant], [migrated_distant], false) \
		and str(migrated_snapshot.get("geometry_signature", "")) == edited_geometry
	_expect(migrated_replay_valid, "migrated restart changed queries or native geometry", failures)
	actions["snapshot_migration"] = _status(migration_valid and migrated_replay_valid)

	var data := {
		"initial_snapshot": initial_snapshot,
		"baseline_central": baseline_central,
		"baseline_distant": baseline_distant,
		"central_samples": final_central,
		"distant_samples": distant_samples,
		"edited_snapshot": edited_snapshot,
		"journal_sha256": journal_sha256,
		"journal_diagnostics": journal_diagnostics,
		"truncated_journal_diagnostics": truncated_journal_diagnostics,
		"crash_recovery": {"started": crash_started, "world_revision": 1 if crash_valid else -1, "central": crash_central, "distant": crash_distant},
		"inherited_recovery": inherited_recovery,
		"journal_replay_snapshot": replay_snapshot,
		"compaction": compacted,
		"compacted_snapshot": compacted_snapshot,
		"distant_post_restart_snapshot": distant_snapshot,
		"interrupted_staging": interrupted,
		"migration": migrated,
		"migrated_snapshot": migrated_snapshot,
		"edited_sample_signature": edited_sample_signature,
		"edited_geometry_signature": edited_geometry,
	}
	return await _finish(harness, standard, fixture, data, actions, settlements, operation_times, failures)


func _fresh_harness(previous: Node, profile: Dictionary) -> Node:
	if previous != null:
		previous.dispose()
		previous.queue_free()
		await get_tree().process_frame
	var replacement := Harness.new()
	add_child(replacement)
	if not replacement.create_runtime(
		int(profile.get("worker_count", 2)), _runtime_overrides(profile)
	):
		replacement.queue_free()
		await get_tree().process_frame
		return null
	return replacement


func _finish(
	harness: Node,
	standard: Dictionary,
	fixture: Dictionary,
	data: Dictionary,
	actions: Dictionary,
	settlements: Array[Dictionary],
	operation_times: Array[float],
	failures: Array[String]
) -> Dictionary:
	if harness != null and harness.terrain != null:
		if str(harness.terrain.call("get_world_state_name")) != "stopped" and not await harness.stop_world():
			failures.append("native adaptive persistence fixture did not stop cleanly")
		harness.dispose()
		harness.queue_free()
		await get_tree().process_frame
	Harness.remove_tree(RUNTIME_ROOT)
	var semantic_source := {
		"actions": actions,
		"fixture": fixture.get("manifest_sha256", ""),
		"initial": (data.get("initial_snapshot", {}) as Dictionary).get("state_signature", ""),
		"samples": data.get("edited_sample_signature", ""),
		"geometry": data.get("edited_geometry_signature", ""),
		"journal": data.get("journal_sha256", ""),
		"compacted_pages": (data.get("compaction", {}) as Dictionary).get("page_count", -1),
		"migrated_pages": (data.get("migration", {}) as Dictionary).get("page_count", -1),
		"large_volume_limit": "TQP-F002_REMAINS_EXPLICIT_CAPACITY_LIMIT",
	}
	return {
		"schema": "world_transvoxel.terrain_lab.adaptive_persistence_qualification.v1",
		"milestone": "TQP-41",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"retained_complete": true,
		"standard_id": standard.get("standard_id", ""),
		"authority": standard.get("authority", ""),
		"actions": actions,
		"fixture": fixture,
		"initial_residency": data.get("initial_snapshot", {}),
		"baseline_queries": {"central": data.get("baseline_central", []), "distant": data.get("baseline_distant", {})},
		"edited_queries": {"central": data.get("central_samples", []), "distant": data.get("distant_samples", {})},
		"edited_residency": data.get("edited_snapshot", {}),
		"journal_sha256": data.get("journal_sha256", ""),
		"journal_diagnostics": data.get("journal_diagnostics", {}),
		"truncated_journal_diagnostics": data.get("truncated_journal_diagnostics", {}),
		"crash_recovery": data.get("crash_recovery", {}),
		"inherited_truncated_tail_recovery": data.get("inherited_recovery", {}),
		"journal_replay_residency": data.get("journal_replay_snapshot", {}),
		"compaction": data.get("compaction", {}),
		"compacted_residency": data.get("compacted_snapshot", {}),
		"distant_post_restart_residency": data.get("distant_post_restart_snapshot", {}),
		"interrupted_staging": data.get("interrupted_staging", {}),
		"migration": data.get("migration", {}),
		"migrated_residency": data.get("migrated_snapshot", {}),
		"edited_sample_signature": data.get("edited_sample_signature", ""),
		"edited_geometry_signature": data.get("edited_geometry_signature", ""),
		"large_volume_snapshot_disposition": "TQP-F002_REMAINS_EXPLICIT_CAPACITY_LIMIT",
		"settlements": settlements,
		"performance": {
			"scope": "WINDOWS_DEBUG_DIAGNOSTIC_NOT_PRODUCTION_SAVE_OR_FRAME_BUDGET",
			"operation_usec": Statistics.distribution(operation_times),
			"memory": Statistics.memory_metrics(),
		},
		"semantic_signature": JSON.stringify(semantic_source, "", true).sha256_text(),
		"provenance": Statistics.provenance("tqp41_native_adaptive_persistence_windows_v1"),
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


func _update_viewer_and_settle(harness: Node, terrain: Node, profile: Dictionary, position: Vector3, revision: int, radius: int) -> Dictionary:
	var before := int((terrain.call("get_runtime_metrics") as Dictionary).get("viewer_updates", 0))
	if not bool(terrain.call("update_viewer", int(profile.get("viewer_id", 411)), revision, position, radius, int(profile.get("maximum_lod", 1)))):
		return {"status": "FAIL", "error": "adaptive persistence viewer update rejected"}
	for _frame in range(Harness.MAX_WAIT_FRAMES):
		if int((terrain.call("get_runtime_metrics") as Dictionary).get("viewer_updates", 0)) > before:
			await get_tree().process_frame
			return await harness.wait_for_settled()
		await get_tree().process_frame
	return {"status": "FAIL", "error": "adaptive persistence viewer update timed out"}


func _commit_operations(harness: Node, terrain: Node, operations: Array, author: int, expected_revision: int) -> bool:
	var transaction: RefCounted = terrain.call("begin_edit_transaction", author)
	if transaction == null:
		return false
	for operation_value in operations:
		if not _append_operation(transaction, operation_value):
			return false
	return bool(terrain.call("commit_edit_transaction", transaction)) \
		and await harness.wait_for_commit(expected_revision)


static func _append_operation(transaction: RefCounted, value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var operation: Dictionary = value
	var method := str(operation.get("operation", ""))
	match method:
		"carve_smooth_sdf_sphere":
			return bool(transaction.call(method, _vector3(operation.get("center", [])), float(operation.get("radius", 0.0)), float(operation.get("strength", 1.0)), float(operation.get("smooth_radius", 0.0))))
		"construct_material_smooth_sdf_sphere":
			return bool(transaction.call(method, _vector3(operation.get("center", [])), float(operation.get("radius", 0.0)), float(operation.get("strength", 1.0)), int(operation.get("material", 0)), float(operation.get("smooth_radius", 0.0))))
	return false


static func _state_snapshot(terrain: Node, harness: Node) -> Dictionary:
	var lines: Array[String] = []
	var lod_counts := {}
	var ready_mismatches := 0
	for value in terrain.call("query_active_chunk_states"):
		var state: RefCounted = value
		var coordinate: Vector3i = state.call("get_chunk_coordinate")
		var lod := int(state.call("get_lod"))
		lines.append("%d:%d:%d:%d" % [coordinate.x, coordinate.y, coordinate.z, lod])
		lod_counts[str(lod)] = int(lod_counts.get(str(lod), 0)) + 1
		if not bool(state.call("is_fully_ready")):
			ready_mismatches += 1
	lines.sort()
	return {
		"active_count": lines.size(),
		"lod_counts": lod_counts,
		"ready_mismatch_count": ready_mismatches,
		"state_signature": "\n".join(lines).sha256_text(),
		"geometry_signature": _geometry_signature(terrain, harness),
		"metrics": _selected_metrics(terrain.call("get_runtime_metrics")),
	}


static func _geometry_signature(terrain: Node, harness: Node) -> String:
	var lines: Array[String] = []
	for child in terrain.get_children():
		if child is MeshInstance3D and str(child.name).begins_with("WT_Render_"):
			lines.append(str(child.name) + ":" + harness.mesh_signature(str(child.name)))
	lines.sort()
	return "\n".join(lines).sha256_text()


static func _key_set(terrain: Node) -> Dictionary:
	var result := {}
	for value in terrain.call("query_active_chunk_states"):
		var state: RefCounted = value
		var c: Vector3i = state.call("get_chunk_coordinate")
		result["%d:%d:%d:%d" % [c.x, c.y, c.z, int(state.call("get_lod"))]] = true
	return result


static func _initial_residency_valid(snapshot: Dictionary, standard: Dictionary) -> bool:
	var budgets: Dictionary = standard.get("budgets", {})
	var expected: Dictionary = standard.get("stable_expected", {})
	return int(snapshot.get("active_count", -1)) == int(budgets.get("expected_initial_active_chunks", -2)) \
		and int((snapshot.get("lod_counts", {}) as Dictionary).get("0", -1)) == int(budgets.get("expected_initial_lod0_chunks", -2)) \
		and int((snapshot.get("lod_counts", {}) as Dictionary).get("1", -1)) == int(budgets.get("expected_initial_lod1_chunks", -2)) \
		and int(snapshot.get("ready_mismatch_count", -1)) == 0 \
		and str(snapshot.get("state_signature", "")) == str(expected.get("initial_state_signature", ""))


static func _central_edit_semantics(samples: Array[Dictionary]) -> bool:
	return samples.size() == 4 \
		and _sample_matches(samples[0], 5.0, 3, 1) \
		and _sample_matches(samples[1], -1.0, 3, 1) \
		and _sample_matches(samples[2], -4.0, 8, 1) \
		and _sample_matches(samples[3], 1.0, 6, 1)


static func _distant_edit_semantics(sample: Dictionary) -> bool:
	return _sample_matches(sample, -5.0, 7, 2)


static func _sample_matches(sample: Dictionary, density: float, material: int, revision: int) -> bool:
	return str(sample.get("status", "")) == "PASS" \
		and is_equal_approx(float(sample.get("density", INF)), density) \
		and int(sample.get("material", -1)) == material \
		and int(sample.get("world_revision", -1)) == revision


static func _sample_semantically_equal(left: Dictionary, right: Dictionary) -> bool:
	return str(left.get("status", "")) == "PASS" and str(right.get("status", "")) == "PASS" \
		and str(left.get("point", "")) == str(right.get("point", "")) \
		and is_equal_approx(float(left.get("density", INF)), float(right.get("density", -INF))) \
		and int(left.get("material", -1)) == int(right.get("material", -2))


static func _samples_semantically_equal(left: Array[Dictionary], right: Array[Dictionary]) -> bool:
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		if not _sample_semantically_equal(left[index], right[index]):
			return false
	return true


static func _samples_equal(left: Array[Dictionary], right: Array[Dictionary], allow_source_revision_change: bool) -> bool:
	if not _samples_semantically_equal(left, right):
		return false
	for index in range(left.size()):
		if int(left[index].get("world_revision", -1)) != int(right[index].get("world_revision", -2)):
			return false
		if not allow_source_revision_change and int(left[index].get("source_revision", -1)) != int(right[index].get("source_revision", -2)):
			return false
	return true


static func _sample_bundle_signature(central: Array[Dictionary], distant: Dictionary) -> String:
	var lines: Array[String] = []
	for sample in central + [distant]:
		lines.append("%s:%d:%d:%d" % [sample.get("point", ""), roundi(float(sample.get("density", 0.0)) * 1000000.0), int(sample.get("material", 0)), int(sample.get("world_revision", -1))])
	return "\n".join(lines).sha256_text()


static func _stage_fixture(fixture: Dictionary, destination: String, failures: Array[String]) -> bool:
	if str(fixture.get("schema", "")) != "world_transvoxel.terrain_lab.adaptive_persistence_fixture.v1":
		return false
	if int(fixture.get("page_count", -1)) != 44:
		return false
	Harness.ensure_directory(destination)
	var manifest_name := str(fixture.get("manifest", ""))
	var source_manifest := FIXTURE_ROOT.path_join(manifest_name)
	if FileAccess.get_sha256(source_manifest) != str(fixture.get("manifest_sha256", "")):
		failures.append("adaptive fixture manifest hash changed")
		return false
	if not _copy_file(source_manifest, destination.path_join(manifest_name)):
		return false
	for page_value in fixture.get("pages", []):
		var page: Dictionary = page_value
		var name := str(page.get("file", ""))
		var source := FIXTURE_ROOT.path_join(name)
		if FileAccess.get_sha256(source) != str(page.get("sha256", "")):
			failures.append("adaptive fixture page hash changed: " + name)
			return false
		if not _copy_file(source, destination.path_join(name)):
			return false
	return true


static func _copy_tree(source: String, destination: String) -> bool:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(source)):
		return false
	Harness.remove_tree(destination)
	Harness.ensure_directory(destination)
	var directory := DirAccess.open(source)
	if directory == null:
		return false
	for name in directory.get_files():
		if not _copy_file(source.path_join(name), destination.path_join(name)):
			return false
	for name in directory.get_directories():
		if not _copy_tree(source.path_join(name), destination.path_join(name)):
			return false
	return true


static func _copy_file(source: String, destination: String) -> bool:
	var bytes := FileAccess.get_file_as_bytes(source)
	if bytes.is_empty() and FileAccess.get_open_error() != OK:
		return false
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.close()
	return true


static func _retain_complete_prefix(path: String) -> bool:
	var bytes := FileAccess.get_file_as_bytes(path)
	var diagnostics := _journal_diagnostics(path)
	var offsets: Array = diagnostics.get("segment_magic_offsets", [])
	if offsets.size() < 2:
		return false
	var prefix_size := int(offsets[1])
	if prefix_size <= 0 or prefix_size >= bytes.size():
		return false
	return _store_bytes(path, bytes.slice(0, prefix_size))


static func _inherited_tqp26_recovery(standard: Dictionary) -> Dictionary:
	var report := JsonLoader.load_dictionary(str(standard.get("temporal_wave_evidence", "")))
	var milestone: Dictionary = (report.get("milestones", {}) as Dictionary).get("TQP-16", {})
	var evidence: Dictionary = milestone.get("evidence", {})
	var recovery: Dictionary = evidence.get("journal_truncated_tail_recovery", {})
	var passed := str(report.get("status", "")) == "PASS" \
		and str(milestone.get("status", "")) == "PASS" \
		and bool(recovery.get("recovered", false))
	return {
		"status": _status(passed),
		"authority": "TQP-26 native persistence retained evidence",
		"recovered": recovery.get("recovered", false),
		"world_revision": recovery.get("world_revision", -1),
		"committed_prefix_bytes": recovery.get("committed_prefix_bytes", -1),
	}


static func _journal_diagnostics(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	var magic := PackedByteArray([87, 84, 69, 68, 73, 84, 0, 0])
	var offsets: Array[int] = []
	for index in range(maxi(0, bytes.size() - magic.size() + 1)):
		var matches := true
		for byte_index in range(magic.size()):
			if bytes[index + byte_index] != magic[byte_index]:
				matches = false
				break
		if matches:
			offsets.append(index)
	return {"bytes": bytes.size(), "segment_magic_offsets": offsets}


static func _store_bytes(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.close()
	return true


static func _runtime_overrides(profile: Dictionary) -> Dictionary:
	var pipeline := int(profile.get("pipeline_capacity", 2048))
	var pages := int(profile.get("page_cache_capacity", 512))
	return {
		"active_chunk_capacity": int(profile.get("active_chunk_capacity", 512)),
		"viewer_capacity": 4,
		"demand_capacity_per_viewer": pipeline,
		"lod_refinement_radius_chunks": int(profile.get("lod_refinement_radius_chunks", 1)),
		"storage_request_capacity": pages,
		"storage_completion_capacity": pages,
		"encoded_page_entry_capacity": pages,
		"decoded_page_entry_capacity": pages,
		"mesh_entry_capacity": pages,
		"render_entry_capacity": pages,
		"collision_entry_capacity": int(profile.get("collision_capacity", 128)),
		"render_apply_budget": 16,
		"collision_apply_budget": 4,
		"collision_activation_distance": 0.0,
		"collision_deactivation_distance": 0.0,
		"global_coarse_lod_coverage": false,
	}


static func _selected_metrics(metrics: Dictionary) -> Dictionary:
	var selected := {}
	for key in [
		"viewer_updates", "planned_demands", "edit_commits", "edit_replacements",
		"edit_lod_retention_zones", "sample_queries", "sample_query_rejections",
		"world_snapshots", "world_snapshot_rejections", "page_mesh_failures",
		"active_chunk_records", "visual_ready_chunk_records", "render_resources",
		"collision_resources", "pending_chunk_retirements", "pending_chunk_replacements",
		"scheduler_queued_jobs", "scheduler_queued_completions",
	]:
		selected[key] = metrics.get(key, -1)
	return selected


static func _record_settlement(id: String, settlement: Dictionary, records: Array[Dictionary], times: Array[float]) -> void:
	records.append({"id": id, "status": settlement.get("status", ""), "frames": settlement.get("frames", -1), "elapsed_usec": settlement.get("elapsed_usec", -1)})
	if settlement.has("elapsed_usec"):
		times.append(float(settlement.get("elapsed_usec", 0.0)))


static func _vector3(value: Variant) -> Vector3:
	var values: Array = value
	return Vector3(float(values[0]), float(values[1]), float(values[2])) if values.size() == 3 else Vector3.ZERO


static func _vector3i(value: Variant) -> Vector3i:
	var values: Array = value
	return Vector3i(int(values[0]), int(values[1]), int(values[2])) if values.size() == 3 else Vector3i.ZERO


static func _vector3i_array(value: Variant) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for point in value:
		result.append(_vector3i(point))
	return result


static func _status(value: bool) -> String:
	return "PASS" if value else "FAIL"


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
