@tool
extends Node
class_name WtTerrainLabNativePersistenceQualification

const Harness := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_runtime_harness.gd"
)

const FIXTURE_ROOT := "res://labs/terrain_lab/fixtures/native_persistence"
const FIXTURE_MANIFEST := FIXTURE_ROOT + "/fixture_manifest.json"
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/native_persistence"
const SOURCE_ROOT := RUNTIME_ROOT + "/source"
const COMPACTED_ROOT := RUNTIME_ROOT + "/compacted"
const MIGRATED_ROOT := RUNTIME_ROOT + "/migrated"
const INTERRUPTED_ROOT := RUNTIME_ROOT + "/interrupted"
const JOURNAL_TRUNCATED_ROOT := RUNTIME_ROOT + "/journal_truncated"
const JOURNAL_CORRUPT_ROOT := RUNTIME_ROOT + "/journal_corrupt"
const PAGE_CORRUPT_ROOT := RUNTIME_ROOT + "/page_corrupt"
const LEGACY_ROOT := RUNTIME_ROOT + "/legacy"
const LEGACY_MIGRATED_ROOT := RUNTIME_ROOT + "/legacy_migrated"
const SAMPLE_POINT := Vector3i(8, 8, 8)
const COMPACTED_SOURCE_REVISION := 7002


func run() -> Dictionary:
	var failures: Array[String] = []
	Harness.remove_tree(RUNTIME_ROOT)
	Harness.ensure_directory(RUNTIME_ROOT)
	var fixture := _load_json(FIXTURE_MANIFEST)
	_expect(
		str(fixture.get("schema", ""))
			== "world_transvoxel.terrain_lab.native_persistence_fixture.v1",
		"retained fixture manifest is invalid",
		failures
	)
	var current_fixture: Dictionary = fixture.get("current_world", {})
	var legacy_fixture: Dictionary = fixture.get("legacy_world", {})
	_expect(
		_copy_fixture_variant(current_fixture, SOURCE_ROOT, failures),
		"current baked fixture could not be staged",
		failures
	)
	_expect(
		_copy_fixture_variant(legacy_fixture, LEGACY_ROOT, failures),
		"legacy baked fixture could not be staged",
		failures
	)
	var harness := Harness.new()
	add_child(harness)
	if not harness.create_runtime(2):
		failures.append("native runtime harness could not be created")
		await _dispose_harness(harness)
		return _result({}, fixture, failures)
	var source_manifest := SOURCE_ROOT.path_join(
		str(current_fixture.get("manifest", ""))
	)
	if not await harness.start_manifest(source_manifest, SOURCE_ROOT):
		failures.append("current baked fixture did not reach running")
		await _dispose_harness(harness)
		return _result({}, fixture, failures)
	var terrain := harness.terrain
	var initial_sample: Dictionary = await harness.request_sample(SAMPLE_POINT)
	_expect(
		_sample_matches(initial_sample, -0.25, 7, 7001, 12),
		"initial baked authoritative sample changed",
		failures
	)
	var valid: RefCounted = terrain.call("begin_edit_transaction", 2501)
	var stale: RefCounted = terrain.call("begin_edit_transaction", 2502)
	_expect(valid != null and stale != null, "persistence transactions were not created", failures)
	if valid == null or stale == null:
		await _dispose_harness(harness)
		return _result({}, fixture, failures)
	_expect(
		bool(valid.call(
			"set_density_box", Vector3(-2, -2, -2), Vector3(18, 18, 18), 10.0
		)) and bool(stale.call(
			"add_density_sphere", Vector3(SAMPLE_POINT), 2.0, -1.0
		)),
		"persistence edit commands were rejected",
		failures
	)
	_expect(
		bool(terrain.call("commit_edit_transaction", valid)),
		"durable edit submission failed",
		failures
	)
	var compacted: Dictionary = await harness.request_compaction(
		COMPACTED_ROOT, COMPACTED_SOURCE_REVISION
	)
	_expect(
		await harness.wait_for_commit(13)
			and str(compacted.get("status", "")) == "PASS"
			and int(compacted.get("source_revision", -1)) == COMPACTED_SOURCE_REVISION
			and int(compacted.get("world_revision", -1)) == 13
			and int(compacted.get("page_count", -1)) == 4,
		"edit/snapshot ordering did not publish committed revision 13",
		failures
	)
	var edited_sample: Dictionary = await harness.request_sample(SAMPLE_POINT)
	_expect(
		_sample_matches(edited_sample, 10.0, 7, 7001, 13),
		"committed baked authoritative sample changed",
		failures
	)
	var journal_path := SOURCE_ROOT + "/world.wtedit"
	var journal_before_rejection := _file_signature(journal_path)
	_expect(
		not journal_before_rejection.is_empty(),
		"durable journal was not created",
		failures
	)
	var failure_count := harness.edit_failures.size()
	_expect(
		bool(terrain.call("commit_edit_transaction", stale)),
		"stale persistence transaction was not queued for validation",
		failures
	)
	var stale_error: String = await harness.wait_for_edit_failure(failure_count)
	var journal_after_rejection := _file_signature(journal_path)
	_expect(
		stale_error == "edit transaction world revision is stale"
			and journal_after_rejection == journal_before_rejection,
		"stale rejection changed revision or journal bytes",
		failures
	)
	_expect(await harness.stop_world(), "edited source did not stop cleanly", failures)
	_expect(
		_copy_tree(SOURCE_ROOT, JOURNAL_TRUNCATED_ROOT)
			and _copy_tree(SOURCE_ROOT, JOURNAL_CORRUPT_ROOT),
		"journal recovery fixtures could not be copied",
		failures
	)
	var truncated_journal_path := JOURNAL_TRUNCATED_ROOT + "/world.wtedit"
	_expect(
		_truncate_file(truncated_journal_path),
		"journal recovery fixture could not be truncated",
		failures
	)
	var journal_recovery: Dictionary = await _qualify_truncated_journal_recovery(
		harness,
		JOURNAL_TRUNCATED_ROOT.path_join(str(current_fixture.get("manifest", ""))),
		JOURNAL_TRUNCATED_ROOT,
		initial_sample
	)
	_expect(
		bool(journal_recovery.get("recovered", false)),
		"truncated journal did not recover its complete transaction prefix",
		failures
	)
	var corrupt_journal_path := JOURNAL_CORRUPT_ROOT + "/world.wtedit"
	_expect(
		_corrupt_file_byte(corrupt_journal_path),
		"complete journal corruption fixture could not be mutated",
		failures
	)
	var journal_corruption: Dictionary = await _expect_start_failure(
		harness,
		JOURNAL_CORRUPT_ROOT.path_join(str(current_fixture.get("manifest", ""))),
		JOURNAL_CORRUPT_ROOT
	)
	_expect(
		bool(journal_corruption.get("rejected", false)),
		"complete-segment journal corruption was not rejected",
		failures
	)
	harness.clear_events()
	_expect(
		await harness.start_manifest(source_manifest, SOURCE_ROOT),
		"valid source did not restart after journal corruption",
		failures
	)
	var replay_sample: Dictionary = await harness.request_sample(SAMPLE_POINT)
	_expect(
		_samples_equal(edited_sample, replay_sample),
		"durable journal replay changed authoritative state",
		failures
	)
	var compacted_manifest := str(compacted.get("manifest_path", ""))
	_expect(
		FileAccess.file_exists(compacted_manifest)
			and not DirAccess.dir_exists_absolute(
				ProjectSettings.globalize_path(COMPACTED_ROOT + ".tmp")
			),
		"compaction did not atomically publish a complete directory",
		failures
	)
	_expect(await harness.stop_world(), "source did not stop after compaction", failures)
	harness.clear_events()
	_expect(
		await harness.start_manifest(compacted_manifest, COMPACTED_ROOT),
		"compacted snapshot did not reopen",
		failures
	)
	var compacted_sample: Dictionary = await harness.request_sample(SAMPLE_POINT)
	_expect(
		_samples_equal(edited_sample, compacted_sample)
			and int(compacted_sample.get("source_revision", -1))
				== COMPACTED_SOURCE_REVISION,
		"compacted snapshot changed authoritative state",
		failures
	)
	var compacted_manifest_signature := _file_signature(compacted_manifest)
	Harness.ensure_directory(INTERRUPTED_ROOT + ".tmp")
	var marker_path := INTERRUPTED_ROOT + ".tmp/interrupted.marker"
	_store_bytes(marker_path, "incomplete".to_utf8_buffer())
	var interrupted: Dictionary = await harness.request_migration(INTERRUPTED_ROOT)
	_expect(
		str(interrupted.get("status", "")) == "FAIL"
			and str(interrupted.get("error", "")) == "world snapshot file writing failed"
			and not DirAccess.dir_exists_absolute(
				ProjectSettings.globalize_path(INTERRUPTED_ROOT)
			)
			and FileAccess.file_exists(marker_path)
			and _file_signature(compacted_manifest) == compacted_manifest_signature,
		"interrupted staging directory did not fail closed",
		failures
	)
	Harness.remove_tree(INTERRUPTED_ROOT + ".tmp")
	harness.snapshot_failures.clear()
	var migrated: Dictionary = await harness.request_migration(MIGRATED_ROOT)
	_expect(
		str(migrated.get("status", "")) == "PASS"
			and int(migrated.get("source_revision", -1)) == COMPACTED_SOURCE_REVISION
			and int(migrated.get("world_revision", -1)) == 13
			and int(migrated.get("page_count", -1)) == 4,
		"current-schema migration metadata changed",
		failures
	)
	var migrated_manifest := str(migrated.get("manifest_path", ""))
	var migrated_manifest_signature := _file_signature(migrated_manifest)
	var output_exists: Dictionary = await harness.request_migration(MIGRATED_ROOT)
	_expect(
		str(output_exists.get("status", "")) == "FAIL"
			and str(output_exists.get("error", ""))
				== "world snapshot output directory already exists"
			and _file_signature(migrated_manifest) == migrated_manifest_signature,
		"existing snapshot output was overwritten or accepted",
		failures
	)
	_expect(
		not DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(MIGRATED_ROOT + ".tmp")
		),
		"migration retained a staging directory",
		failures
	)
	_expect(await harness.stop_world(), "compacted world did not stop", failures)
	harness.clear_events()
	_expect(
		await harness.start_manifest(migrated_manifest, MIGRATED_ROOT),
		"migrated snapshot did not reopen",
		failures
	)
	var migrated_sample: Dictionary = await harness.request_sample(SAMPLE_POINT)
	_expect(
		_samples_equal(edited_sample, migrated_sample),
		"migrated snapshot changed authoritative state",
		failures
	)
	_expect(await harness.stop_world(), "migrated world did not stop", failures)
	var manifest_corruption := await _qualify_manifest_corruption(
		harness, migrated_manifest
	)
	_expect(
		bool(manifest_corruption.get("rejected", false)),
		"corrupted or truncated manifest was accepted",
		failures
	)
	var page_corruption := await _qualify_page_corruption(
		harness, migrated_manifest
	)
	_expect(
		bool(page_corruption.get("rejected", false)),
		"corrupted baked pages were accepted",
		failures
	)
	harness.clear_events()
	_expect(
		await harness.start_manifest(migrated_manifest, MIGRATED_ROOT),
		"valid snapshot did not recover after corruption fixtures",
		failures
	)
	var recovered_sample: Dictionary = await harness.request_sample(SAMPLE_POINT)
	_expect(
		_samples_equal(migrated_sample, recovered_sample),
		"valid snapshot changed after corruption recovery",
		failures
	)
	_expect(await harness.stop_world(), "recovered world did not stop", failures)
	harness.clear_events()
	var legacy_manifest := LEGACY_ROOT.path_join(
		str(legacy_fixture.get("manifest", ""))
	)
	_expect(
		await harness.start_manifest(legacy_manifest, LEGACY_ROOT),
		"legacy fixture did not start",
		failures
	)
	var legacy_sample: Dictionary = await harness.request_sample(SAMPLE_POINT)
	_expect(
		_sample_matches(legacy_sample, -0.25, 7, 9001, 0),
		"legacy authoritative sample changed",
		failures
	)
	var legacy_migrated: Dictionary = await harness.request_migration(
		LEGACY_MIGRATED_ROOT
	)
	_expect(
		str(legacy_migrated.get("status", "")) == "PASS"
			and int(legacy_migrated.get("source_revision", -1)) == 9001
			and int(legacy_migrated.get("world_revision", -1)) == 0,
		"legacy schema migration failed",
		failures
	)
	var legacy_migrated_manifest := str(legacy_migrated.get("manifest_path", ""))
	_expect(await harness.stop_world(), "legacy source did not stop", failures)
	harness.clear_events()
	_expect(
		await harness.start_manifest(legacy_migrated_manifest, LEGACY_MIGRATED_ROOT),
		"migrated legacy snapshot did not reopen",
		failures
	)
	var legacy_replay_sample: Dictionary = await harness.request_sample(SAMPLE_POINT)
	_expect(
		_samples_equal(legacy_sample, legacy_replay_sample),
		"legacy migration changed authoritative state",
		failures
	)
	var evidence := {
		"initial_sample": initial_sample,
		"edited_sample": edited_sample,
		"restart_sample": replay_sample,
		"compacted_sample": compacted_sample,
		"migrated_sample": migrated_sample,
		"recovered_sample": recovered_sample,
		"legacy_sample": legacy_sample,
		"legacy_migrated_sample": legacy_replay_sample,
		"stale_error": stale_error,
		"journal_before_rejection_sha256": journal_before_rejection,
		"journal_after_rejection_sha256": journal_after_rejection,
		"compacted_manifest_sha256": compacted_manifest_signature,
		"migrated_manifest_sha256": migrated_manifest_signature,
		"journal_corruption": journal_corruption,
		"journal_truncated_tail_recovery": journal_recovery,
		"manifest_corruption": manifest_corruption,
		"page_corruption": page_corruption,
		"interrupted_staging": interrupted,
		"existing_output_rejection": output_exists,
		"compacted_page_count": int(compacted.get("page_count", -1)),
		"migrated_page_count": int(migrated.get("page_count", -1)),
		"legacy_migrated_page_count": int(legacy_migrated.get("page_count", -1)),
		"edit_snapshot_ordering_world_revision": int(compacted.get("world_revision", -1)),
	}
	await _dispose_harness(harness)
	Harness.remove_tree(RUNTIME_ROOT)
	return _result(evidence, fixture, failures)


func _qualify_manifest_corruption(harness: Node, valid_manifest: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(valid_manifest)
	if bytes.is_empty():
		return {"rejected": false, "errors": ["valid manifest bytes are empty"]}
	var corrupt_path := MIGRATED_ROOT + "/corrupt.wtworld"
	var truncated_path := MIGRATED_ROOT + "/truncated.wtworld"
	var corrupt := bytes.duplicate()
	corrupt[0] = (int(corrupt[0]) + 1) % 256
	_store_bytes(corrupt_path, corrupt)
	_store_bytes(truncated_path, bytes.slice(0, maxi(1, bytes.size() / 2)))
	var records: Array[Dictionary] = []
	for path in [corrupt_path, truncated_path]:
		harness.clear_events()
		records.append(await _expect_start_failure(harness, path, MIGRATED_ROOT))
	var rejected := true
	for record in records:
		rejected = rejected and bool(record.get("rejected", false))
	return {"rejected": rejected, "records": records}


func _qualify_page_corruption(harness: Node, valid_manifest: String) -> Dictionary:
	if not _copy_tree(MIGRATED_ROOT, PAGE_CORRUPT_ROOT):
		return {"rejected": false, "error": "page fixture copy failed"}
	for file_name in _files_with_extension(PAGE_CORRUPT_ROOT, "wtchunk"):
		var path := PAGE_CORRUPT_ROOT.path_join(file_name)
		var bytes := FileAccess.get_file_as_bytes(path)
		if not bytes.is_empty():
			bytes[0] = (int(bytes[0]) + 1) % 256
			_store_bytes(path, bytes)
	var manifest_path := PAGE_CORRUPT_ROOT.path_join(valid_manifest.get_file())
	harness.clear_events()
	var started: bool = await harness.start_manifest(manifest_path, PAGE_CORRUPT_ROOT)
	var sample: Dictionary = await harness.request_sample(SAMPLE_POINT) if started else {}
	var rejected := not started or str(sample.get("status", "")) == "FAIL"
	var error := (
		str(sample.get("error", "")) if started
		else str(harness.terrain.call("get_world_error"))
	)
	if str(harness.terrain.call("get_world_state_name")) != "stopped":
		await harness.stop_world()
	return {"rejected": rejected, "error": error}


func _qualify_truncated_journal_recovery(
	harness: Node,
	manifest_path: String,
	object_root: String,
	expected_sample: Dictionary
) -> Dictionary:
	harness.clear_events()
	var started: bool = await harness.start_manifest(manifest_path, object_root)
	var sample: Dictionary = await harness.request_sample(SAMPLE_POINT) if started else {}
	var journal_path := object_root + "/world.wtedit"
	var journal_size := -1
	var journal := FileAccess.open(journal_path, FileAccess.READ)
	if journal != null:
		journal_size = journal.get_length()
		journal.close()
	var recovered := (
		started
		and int(harness.terrain.call("get_world_revision")) == 12
		and _samples_equal(expected_sample, sample)
		and journal_size == 0
	)
	if str(harness.terrain.call("get_world_state_name")) != "stopped":
		await harness.stop_world()
	return {
		"recovered": recovered,
		"world_revision": int(sample.get("world_revision", -1)),
		"committed_prefix_bytes": journal_size,
		"sample": sample,
	}


func _expect_start_failure(
	harness: Node,
	manifest_path: String,
	object_root: String
) -> Dictionary:
	var accepted := bool(harness.terrain.call(
		"start_world", manifest_path, ProjectSettings.globalize_path(object_root)
	))
	var rejected := not accepted
	if accepted:
		rejected = await harness.wait_for_failure()
	var error := str(harness.terrain.call("get_world_error"))
	if str(harness.terrain.call("get_world_state_name")) != "stopped":
		await harness.stop_world()
	return {"rejected": rejected, "error": error, "accepted_async": accepted}


static func _copy_fixture_variant(
	variant: Dictionary,
	destination: String,
	failures: Array[String]
) -> bool:
	Harness.ensure_directory(destination)
	var manifest_name := str(variant.get("manifest", ""))
	var manifest_source := FIXTURE_ROOT.path_join(manifest_name)
	if _file_signature(manifest_source) != str(variant.get("manifest_sha256", "")):
		failures.append("retained manifest hash changed: " + manifest_name)
		return false
	if not _copy_file(manifest_source, destination.path_join(manifest_name)):
		return false
	for page_value in variant.get("pages", []):
		var page_name := str(page_value)
		var page_source := FIXTURE_ROOT.path_join(page_name)
		if _file_signature(page_source) != page_name.get_basename():
			failures.append("retained page hash changed: " + page_name)
			return false
		if not _copy_file(page_source, destination.path_join(page_name)):
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
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		var source_child := source.path_join(name)
		var destination_child := destination.path_join(name)
		if directory.current_is_dir():
			if not _copy_tree(source_child, destination_child):
				return false
		elif not _copy_file(source_child, destination_child):
			return false
		name = directory.get_next()
	directory.list_dir_end()
	return true


static func _copy_file(source: String, destination: String) -> bool:
	var bytes := FileAccess.get_file_as_bytes(source)
	if bytes.is_empty() and FileAccess.get_open_error() != OK:
		return false
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	return true


static func _truncate_file(path: String) -> bool:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 2:
		return false
	_store_bytes(path, bytes.slice(0, bytes.size() / 2))
	return true


static func _corrupt_file_byte(path: String) -> bool:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 4:
		return false
	var index := bytes.size() / 2
	bytes[index] = int(bytes[index]) ^ 0x40
	_store_bytes(path, bytes)
	return true


static func _files_with_extension(path: String, extension: String) -> Array[String]:
	var files: Array[String] = []
	var directory := DirAccess.open(path)
	if directory == null:
		return files
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if not directory.current_is_dir() and name.get_extension() == extension:
			files.append(name)
		name = directory.get_next()
	directory.list_dir_end()
	files.sort()
	return files


func _dispose_harness(harness: Node) -> void:
	if harness == null:
		return
	if harness.terrain != null and str(harness.terrain.call("get_world_state_name")) != "stopped":
		await harness.stop_world()
	harness.dispose()
	harness.queue_free()
	await get_tree().process_frame


static func _result(
	evidence: Dictionary,
	fixture: Dictionary,
	failures: Array[String]
) -> Dictionary:
	return {
		"schema": "world_transvoxel.terrain_lab.native_persistence_qualification.v1",
		"milestone": "TQP-16",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"qualification_scope": "native Windows current and legacy schema reference fixtures",
		"explicitly_unqualified_scope": [
			"automatic cleanup of abandoned snapshot staging directories",
			"atomicity guarantees for filesystems outside the declared reference platform",
		],
		"fixture": fixture,
		"evidence": evidence,
		"failures": failures,
	}


static func _sample_matches(
	sample: Dictionary,
	density: float,
	material: int,
	source_revision: int,
	world_revision: int
) -> bool:
	return (
		str(sample.get("status", "")) == "PASS"
		and is_equal_approx(float(sample.get("density", INF)), density)
		and int(sample.get("material", -1)) == material
		and int(sample.get("source_revision", -1)) == source_revision
		and int(sample.get("world_revision", -1)) == world_revision
	)


static func _samples_equal(left: Dictionary, right: Dictionary) -> bool:
	return (
		str(left.get("status", "")) == "PASS"
		and str(right.get("status", "")) == "PASS"
		and is_equal_approx(float(left.get("density", INF)), float(right.get("density", -INF)))
		and int(left.get("material", -1)) == int(right.get("material", -2))
		and int(left.get("world_revision", -1)) == int(right.get("world_revision", -2))
	)


static func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


static func _file_signature(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""


static func _store_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_buffer(bytes)


static func _expect(condition: bool, failure: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(failure)
