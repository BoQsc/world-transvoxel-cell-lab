@tool
extends Node
class_name WtTerrainLabLargeTerrainSoakQualification

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
	"res://addons/world_transvoxel_terrain_lab/standards/large_terrain_soak_standard.json"
)
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/large_terrain_soak"
const SOURCE_ROOT := RUNTIME_ROOT + "/source"
const COMPACTED_ROOT := RUNTIME_ROOT + "/compacted"
const SOURCE_REVISION := 87001
const COMPACTED_SOURCE_REVISION := 87002
const VIEWER_ID := 27

var _terrain: Node
var _last_frame_usec := 0
var _frame_samples_usec: Array[float] = []
var _viewer_update_samples_usec: Array[float] = []
var _settlement_samples_usec: Array[float] = []
var _edit_samples_usec: Array[float] = []
var _observed_render_chunks := {}
var _observed_collision_chunks := {}
var _maximum_memory_bytes := 0
var _maximum_transient_chunk_records := 0
var _maximum_non_retiring_chunks := 0
var _maximum_render_resources := 0
var _maximum_collision_resources := 0
var _maximum_render_queue := 0
var _maximum_collision_queue := 0
var _viewer_revision := 0
var _movement_count := 0
var _teleport_count := 0
var _edit_count := 0
var _actual_duration_ms := 0
var _snapshot_capacity_control_usec := 0.0
var _restart_settlement_usec := 0.0
var _stale_viewer_rejected := false
var _stale_edit_rejected := false
var _shutdown_clean := false
var _world_page_count := 0
var _post_restart_query_count := 0
var _post_restart_queries_agreed := false
var _edit_records: Array[Dictionary] = []
var _source_metrics := {}
var _restart_metrics := {}
var _snapshot := {}


func run() -> Dictionary:
	_reset_observations()
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var failures: Array[String] = []
	_validate_standard_presence(standard, failures)
	Harness.remove_tree(RUNTIME_ROOT)
	Harness.ensure_directory(SOURCE_ROOT)
	var harness := Harness.new()
	add_child(harness)
	if not harness.create_runtime(int((standard.get("runtime_profile", {}) as Dictionary).get("worker_count", 0))):
		failures.append("native world-transvoxel runtime could not be created")
		return await _finish(harness, standard, failures)
	_terrain = harness.terrain
	_expect(
		str(_terrain.call("get_backend_id")) == "transvoxel_mit_official"
			and str(_terrain.call("get_backend_license")) == "MIT",
		"native world-transvoxel backend identity changed",
		failures
	)
	_start_monitoring()
	if not await _start_large_world(harness, standard):
		failures.append("native procedural world did not reach running")
		return await _finish(harness, standard, failures)
	_world_page_count = int(_terrain.call("get_world_page_count"))
	await _exercise_workload(harness, standard, failures)
	return await _finish(harness, standard, failures)


func _exercise_workload(
	harness: Node,
	standard: Dictionary,
	failures: Array[String]
) -> void:
	var workload: Dictionary = standard.get("workload", {})
	var traversal := _continuous_path(int(workload.get("continuous_traversal_steps", 0)))
	var teleports := [
		Vector3(8.0, 8.0, 1992.0),
		Vector3(1992.0, 8.0, 8.0),
		Vector3(1992.0, 8.0, 1992.0),
		Vector3(1000.0, 8.0, 1000.0),
	]
	var soak_started := Time.get_ticks_msec()
	if traversal.is_empty() or not await _move_and_settle(harness, traversal[0]):
		failures.append("initial native terrain window did not settle")
		return
	if traversal.size() < 2 or not await _move_and_settle(harness, traversal[1]):
		failures.append("second native terrain window did not settle")
		return
	_stale_viewer_rejected = await _inject_stale_viewer_revision(teleports[0])
	_expect(_stale_viewer_rejected, "stale viewer revision was accepted", failures)
	for index in range(2, traversal.size()):
		if not await _move_and_settle(harness, traversal[index]):
			failures.append(
				"continuous traversal did not settle at step %d: %s"
				% [index, JSON.stringify(_source_metrics)]
			)
			return
	for index in range(teleports.size()):
		if not await _move_and_settle(harness, teleports[index]):
			failures.append(
				"teleport did not settle at step %d: %s"
				% [index, JSON.stringify(_source_metrics)]
			)
			return
		_teleport_count += 1
		var point := Vector3i(
			roundi(teleports[index].x), 6, roundi(teleports[index].z)
		)
		if not await _commit_material_edit(harness, point, 20 + index, index == 0, failures):
			failures.append("native edit workload failed at teleport %d" % index)
			return
	var repeat_index := 0
	while Time.get_ticks_msec() - soak_started < int(workload.get("minimum_duration_ms", 0)):
		var position: Vector3 = traversal[repeat_index % traversal.size()]
		if repeat_index % 2 == 1:
			position = traversal[traversal.size() - 1 - (repeat_index % traversal.size())]
		if not await _move_and_settle(harness, position):
			failures.append("duration soak traversal did not settle")
			return
		repeat_index += 1
	_actual_duration_ms = Time.get_ticks_msec() - soak_started
	var compact_started := Time.get_ticks_usec()
	_snapshot = await harness.request_compaction(COMPACTED_ROOT, COMPACTED_SOURCE_REVISION)
	_snapshot_capacity_control_usec = float(Time.get_ticks_usec() - compact_started)
	_expect(
		str(_snapshot.get("status", "")) == "FAIL"
			and str(_snapshot.get("error", "")) == str(workload.get("expected_compaction_error", ""))
			and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(COMPACTED_ROOT)),
		"large-volume compaction did not fail closed at the declared capacity boundary",
		failures
	)
	_source_metrics = harness.runtime_metrics()
	_expect(await _remove_viewer_and_empty(), "source viewer removal did not drain resources", failures)
	_expect(await harness.stop_world(), "source native world did not stop cleanly", failures)
	_expect(_resources_are_empty(), "source shutdown retained native resources", failures)
	if not failures.is_empty():
		return
	harness.clear_events()
	var restart_started := Time.get_ticks_usec()
	if not await _start_large_world(harness, standard):
		failures.append("large native world did not restart from its durable journal")
		return
	_viewer_revision = 0
	var restart_position := Vector3(_edit_records[0]["point"]) + Vector3(0.0, 2.0, 0.0)
	if not await _move_and_settle(harness, restart_position):
		failures.append("restarted native terrain window did not settle")
		return
	_restart_settlement_usec = float(Time.get_ticks_usec() - restart_started)
	var restart_queries_agreed := true
	for record in _edit_records:
		var sample: Dictionary = await harness.request_sample(record["point"])
		var agreed := (
			str(sample.get("status", "")) == "PASS"
			and int(sample.get("material", -1)) == int(record["material"])
			and int(sample.get("source_revision", -1)) == SOURCE_REVISION
			and int(sample.get("world_revision", -1)) == _edit_count
		)
		restart_queries_agreed = restart_queries_agreed and agreed
		_post_restart_query_count += 1
		_expect(agreed, "post-restart authoritative sample changed", failures)
	_post_restart_queries_agreed = restart_queries_agreed and _post_restart_query_count == _edit_count
	_restart_metrics = harness.runtime_metrics()
	_expect(await _remove_viewer_and_empty(), "restart viewer removal did not drain resources", failures)
	_expect(await harness.stop_world(), "restarted native world did not stop cleanly", failures)
	_shutdown_clean = _resources_are_empty()
	_expect(_shutdown_clean, "final shutdown retained native resources", failures)


func _move_and_settle(harness: Node, position: Vector3) -> bool:
	_viewer_revision += 1
	var update_started := Time.get_ticks_usec()
	var accepted := bool(_terrain.call(
		"update_viewer", VIEWER_ID, _viewer_revision, position, 1, 1
	))
	_viewer_update_samples_usec.append(float(Time.get_ticks_usec() - update_started))
	if not accepted:
		return false
	await get_tree().process_frame
	var settlement: Dictionary = await harness.wait_for_settled(1)
	_settlement_samples_usec.append(float(settlement.get("elapsed_usec", 0)))
	if str(settlement.get("status", "")) != "PASS":
		_source_metrics = settlement.get("metrics", {})
		return false
	_movement_count += 1
	return true


func _commit_material_edit(
	harness: Node,
	point: Vector3i,
	material: int,
	inject_stale: bool,
	failures: Array[String]
) -> bool:
	var valid: RefCounted = _terrain.call("begin_edit_transaction", 2700 + _edit_count)
	var stale: RefCounted = (
		_terrain.call("begin_edit_transaction", 2800 + _edit_count)
		if inject_stale else null
	)
	if valid == null or (inject_stale and stale == null):
		failures.append("native edit transaction could not be created")
		return false
	var minimum := Vector3(point) - Vector3(2.0, 2.0, 2.0)
	var maximum := Vector3(point) + Vector3(2.0, 2.0, 2.0)
	if not bool(valid.call("paint_material_box", minimum, maximum, material)):
		failures.append("native material edit command was rejected: " + str(valid.call("get_error")))
		return false
	if stale != null and not bool(stale.call("paint_material_box", minimum, maximum, material + 10)):
		failures.append("stale native material command was rejected before submission: " + str(stale.call("get_error")))
		return false
	var edit_started := Time.get_ticks_usec()
	if not bool(_terrain.call("commit_edit_transaction", valid)):
		failures.append("native edit submission was rejected: " + str(_terrain.call("get_world_error")))
		return false
	var expected_revision := _edit_count + 1
	if not await harness.wait_for_commit(expected_revision):
		failures.append("native edit did not commit revision %d" % expected_revision)
		return false
	var sample: Dictionary = await harness.request_sample(point)
	if str(sample.get("status", "")) != "PASS" \
			or int(sample.get("material", -1)) != material \
			or int(sample.get("world_revision", -1)) != expected_revision:
		failures.append("native edited authoritative sample diverged: " + str(sample))
		return false
	await get_tree().process_frame
	var settlement: Dictionary = await harness.wait_for_settled(1)
	if str(settlement.get("status", "")) != "PASS":
		failures.append("native edited terrain did not settle: " + str(settlement))
		return false
	_edit_samples_usec.append(float(Time.get_ticks_usec() - edit_started))
	_edit_count = expected_revision
	_edit_records.append({"point": point, "material": material})
	if stale != null:
		var previous_failures: int = harness.edit_failures.size()
		if not bool(_terrain.call("commit_edit_transaction", stale)):
			failures.append("stale native edit was rejected before asynchronous validation")
			return false
		_stale_edit_rejected = (
			await harness.wait_for_edit_failure(previous_failures)
			== "edit transaction world revision is stale"
		)
		if not _stale_edit_rejected:
			failures.append("stale native edit did not produce the required rejection")
	return not inject_stale or _stale_edit_rejected


func _remove_viewer_and_empty() -> bool:
	_viewer_revision += 1
	if not bool(_terrain.call("remove_viewer", VIEWER_ID, _viewer_revision)):
		return false
	for _frame in range(Harness.MAX_WAIT_FRAMES):
		var metrics: Dictionary = _terrain.call("get_runtime_metrics")
		if int(metrics.get("active_chunk_records", -1)) == 0 \
				and int(metrics.get("render_resources", -1)) == 0 \
				and int(metrics.get("collision_resources", -1)) == 0 \
				and int(metrics.get("queued_render", -1)) == 0 \
				and int(metrics.get("queued_collision", -1)) == 0 \
				and int(metrics.get("pending_chunk_retirements", -1)) == 0:
			return true
		await get_tree().process_frame
	return false


func _inject_stale_viewer_revision(position: Vector3) -> bool:
	var before: Dictionary = _terrain.call("get_runtime_metrics")
	var rejected_before := int(before.get("rejected_events", 0))
	var updates_before := int(before.get("viewer_updates", 0))
	if not bool(_terrain.call(
		"update_viewer", VIEWER_ID, _viewer_revision - 1, position, 1, 1
	)):
		return true
	for _frame in range(240):
		await get_tree().process_frame
		var metrics: Dictionary = _terrain.call("get_runtime_metrics")
		if int(metrics.get("rejected_events", 0)) > rejected_before:
			return true
		if int(metrics.get("viewer_updates", 0)) > updates_before:
			return false
	return false


func _finish(
	harness: Node,
	standard: Dictionary,
	failures: Array[String]
) -> Dictionary:
	_stop_monitoring()
	if _source_metrics.is_empty() and harness != null and harness.terrain != null:
		_source_metrics = harness.runtime_metrics()
	if harness != null and harness.terrain != null:
		if str(harness.terrain.call("get_world_state_name")) != "stopped":
			await harness.stop_world()
		harness.dispose()
		harness.queue_free()
		await get_tree().process_frame
	Harness.remove_tree(RUNTIME_ROOT)
	var frame_distribution := Statistics.distribution(_frame_samples_usec)
	var update_distribution := Statistics.distribution(_viewer_update_samples_usec)
	var settlement_distribution := Statistics.distribution(_settlement_samples_usec)
	var edit_distribution := Statistics.distribution(_edit_samples_usec)
	var duration_seconds := float(_actual_duration_ms) / 1000.0
	var throughput := float(_movement_count) / maxf(duration_seconds, 0.001)
	var report := {
		"schema": "world_transvoxel.terrain_lab.large_terrain_soak_qualification.v1",
		"milestone": "TQP-27",
		"standard_id": str(standard.get("standard_id", "")),
		"authority": str(standard.get("authority", "")),
		"status": "PENDING_BUDGET_EVALUATION",
		"provenance": Statistics.provenance("tqp27_native_large_terrain_soak_windows_v1"),
		"coverage": {
			"requested_duration_ms": int((standard.get("workload", {}) as Dictionary).get("minimum_duration_ms", 0)),
			"actual_duration_ms": _actual_duration_ms,
			"movement_settlements": _movement_count,
			"continuous_traversal_steps": int((standard.get("workload", {}) as Dictionary).get("continuous_traversal_steps", 0)),
			"teleports": _teleport_count,
			"committed_edits": _edit_count,
			"virtual_span_m": 1984.0,
			"unique_render_chunks": _observed_render_chunks.size(),
			"unique_collision_chunks": _observed_collision_chunks.size(),
			"stale_viewer_revision_rejected": _stale_viewer_rejected,
			"stale_edit_transaction_rejected": _stale_edit_rejected,
			"post_restart_query_count": _post_restart_query_count,
			"shutdown_clean": _shutdown_clean,
		},
		"performance": {
			"frame": frame_distribution,
			"viewer_update": update_distribution,
			"window_settlement": settlement_distribution,
			"edit_commit_to_settlement": edit_distribution,
			"settled_windows_per_second": throughput,
			"snapshot_capacity_control_usec": _snapshot_capacity_control_usec,
			"restart_to_settlement_usec": _restart_settlement_usec,
		},
		"resources": {
			"maximum_memory_bytes": _maximum_memory_bytes,
			"maximum_transient_chunk_records": _maximum_transient_chunk_records,
			"maximum_non_retiring_chunks": _maximum_non_retiring_chunks,
			"maximum_render_resources": _maximum_render_resources,
			"maximum_collision_resources": _maximum_collision_resources,
			"maximum_render_queue": _maximum_render_queue,
			"maximum_collision_queue": _maximum_collision_queue,
		},
		"persistence": {
			"save_mode": "durable_edit_journal_replay",
			"catalog_page_count": _world_page_count,
			"journal_restart_status": "PASS" if _post_restart_queries_agreed else "FAIL",
			"post_restart_query_count": _post_restart_query_count,
			"post_restart_queries_agreed": _post_restart_queries_agreed,
			"large_volume_compaction_status": "EXPECTED_CAPACITY_REJECTION" if str(_snapshot.get("status", "")) == "FAIL" else "UNEXPECTED",
			"large_volume_compaction_error": str(_snapshot.get("error", "")),
			"partial_compaction_output_exists": DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(COMPACTED_ROOT)),
		},
		"runtime_metrics": {"source": _source_metrics, "restart": _restart_metrics},
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}
	_validate_budgets(report, standard, failures)
	report["status"] = "PASS" if failures.is_empty() else "FAIL"
	report["failures"] = failures
	return report


func _validate_budgets(
	report: Dictionary,
	standard: Dictionary,
	failures: Array[String]
) -> void:
	var workload: Dictionary = standard.get("workload", {})
	var budgets: Dictionary = standard.get("budgets", {})
	var coverage: Dictionary = report.get("coverage", {})
	var performance: Dictionary = report.get("performance", {})
	var frame: Dictionary = performance.get("frame", {})
	var update: Dictionary = performance.get("viewer_update", {})
	var settlement: Dictionary = performance.get("window_settlement", {})
	var resources: Dictionary = report.get("resources", {})
	_expect(int(coverage.get("actual_duration_ms", 0)) >= int(workload.get("minimum_duration_ms", 0)), "soak duration budget was not met", failures)
	_expect(int(coverage.get("movement_settlements", 0)) >= int(workload.get("continuous_traversal_steps", 0)) + int(workload.get("minimum_teleports", 0)), "movement coverage is incomplete", failures)
	_expect(int(coverage.get("teleports", 0)) >= int(workload.get("minimum_teleports", 0)), "teleport coverage is incomplete", failures)
	_expect(int(coverage.get("committed_edits", 0)) >= int(workload.get("minimum_committed_edits", 0)), "edit coverage is incomplete", failures)
	_expect(float(coverage.get("virtual_span_m", 0.0)) >= float(workload.get("minimum_virtual_span_m", 0.0)), "large-terrain span is incomplete", failures)
	_expect(int(coverage.get("unique_render_chunks", 0)) >= int(workload.get("minimum_unique_render_chunks", 0)), "large-terrain chunk coverage is incomplete", failures)
	_expect(bool(coverage.get("stale_viewer_revision_rejected", false)) and bool(coverage.get("stale_edit_transaction_rejected", false)), "failure-injection coverage is incomplete", failures)
	_expect(bool(coverage.get("shutdown_clean", false)), "native resources did not shut down cleanly", failures)
	_expect(int(coverage.get("post_restart_query_count", 0)) == int(coverage.get("committed_edits", -1)), "post-restart query coverage does not match committed edits", failures)
	_expect(int(frame.get("sample_count", 0)) >= int(budgets.get("minimum_frame_samples", 0)), "frame sample coverage is incomplete", failures)
	_expect(float(frame.get("p99_usec", INF)) <= float(budgets.get("maximum_frame_p99_usec", 0.0)), "frame p99 ceiling exceeded", failures)
	_expect(float(frame.get("worst_usec", INF)) <= float(budgets.get("maximum_frame_usec", 0.0)), "maximum frame ceiling exceeded", failures)
	_expect(float(update.get("p95_usec", INF)) <= float(budgets.get("maximum_viewer_update_p95_usec", 0.0)), "viewer update p95 ceiling exceeded", failures)
	_expect(float(settlement.get("p95_usec", INF)) <= float(budgets.get("maximum_settlement_p95_usec", 0.0)), "window settlement p95 ceiling exceeded", failures)
	_expect(float(performance.get("settled_windows_per_second", 0.0)) >= float(budgets.get("minimum_settled_windows_per_second", INF)), "settled-window throughput floor was not met", failures)
	_expect(float(performance.get("snapshot_capacity_control_usec", INF)) <= float(budgets.get("maximum_snapshot_capacity_control_usec", 0.0)), "snapshot capacity-control ceiling exceeded", failures)
	_expect(float(performance.get("restart_to_settlement_usec", INF)) <= float(budgets.get("maximum_restart_settlement_usec", 0.0)), "restart settlement ceiling exceeded", failures)
	for pair in [
		["maximum_memory_bytes", "maximum_memory_bytes"],
		["maximum_transient_chunk_records", "maximum_transient_chunk_records"],
		["maximum_non_retiring_chunks", "maximum_non_retiring_chunks"],
		["maximum_render_resources", "maximum_render_resources"],
		["maximum_collision_resources", "maximum_collision_resources"],
		["maximum_render_queue", "maximum_render_queue"],
		["maximum_collision_queue", "maximum_collision_queue"],
	]:
		_expect(int(resources.get(pair[0], 0)) <= int(budgets.get(pair[1], -1)), str(pair[0]) + " ceiling exceeded", failures)
	var persistence: Dictionary = report.get("persistence", {})
	_expect(int(persistence.get("catalog_page_count", 0)) >= int(workload.get("minimum_catalog_pages", 0)), "large-world catalog coverage is incomplete", failures)
	_expect(int(persistence.get("post_restart_query_count", 0)) == int(coverage.get("committed_edits", -1)), "persistent query coverage does not match committed edits", failures)
	_expect(str(persistence.get("journal_restart_status", "")) == "PASS" and bool(persistence.get("post_restart_queries_agreed", false)), "durable journal restart did not qualify", failures)
	_expect(str(persistence.get("large_volume_compaction_status", "")) == "EXPECTED_CAPACITY_REJECTION" and str(persistence.get("large_volume_compaction_error", "")) == str(workload.get("expected_compaction_error", "")) and not bool(persistence.get("partial_compaction_output_exists", true)), "large-volume compaction capacity control changed", failures)


func _start_monitoring() -> void:
	_last_frame_usec = Time.get_ticks_usec()
	var callback := Callable(self, "_record_frame")
	if not get_tree().process_frame.is_connected(callback):
		get_tree().process_frame.connect(callback)


func _stop_monitoring() -> void:
	var callback := Callable(self, "_record_frame")
	if get_tree() != null and get_tree().process_frame.is_connected(callback):
		get_tree().process_frame.disconnect(callback)


func _record_frame() -> void:
	var now := Time.get_ticks_usec()
	if _last_frame_usec > 0:
		_frame_samples_usec.append(float(now - _last_frame_usec))
	_last_frame_usec = now
	_maximum_memory_bytes = maxi(_maximum_memory_bytes, int(OS.get_static_memory_peak_usage()))
	if _terrain == null:
		return
	var metrics: Dictionary = _terrain.call("get_runtime_metrics")
	_maximum_transient_chunk_records = maxi(_maximum_transient_chunk_records, int(metrics.get("active_chunk_records", 0)))
	_maximum_non_retiring_chunks = maxi(_maximum_non_retiring_chunks, int(metrics.get("non_retiring_chunk_records", 0)))
	_maximum_render_resources = maxi(_maximum_render_resources, int(metrics.get("render_resources", 0)))
	_maximum_collision_resources = maxi(_maximum_collision_resources, int(metrics.get("collision_resources", 0)))
	_maximum_render_queue = maxi(_maximum_render_queue, int(metrics.get("queued_render", 0)))
	_maximum_collision_queue = maxi(_maximum_collision_queue, int(metrics.get("queued_collision", 0)))
	for child in _terrain.get_children():
		var child_name := str(child.name)
		if child_name.begins_with("WT_Render_"):
			_observed_render_chunks[child_name] = true
		elif child_name.begins_with("WT_Collision_"):
			_observed_collision_chunks[child_name] = true


func _resources_are_empty() -> bool:
	return _terrain != null \
		and int(_terrain.call("get_render_resource_count")) == 0 \
		and int(_terrain.call("get_collision_resource_count")) == 0 \
		and int(_terrain.call("get_queued_render_count")) == 0 \
		and int(_terrain.call("get_queued_collision_count")) == 0


func _start_large_world(harness: Node, standard: Dictionary) -> bool:
	var runtime_profile: Dictionary = standard.get("runtime_profile", {})
	var volume_chunks: Array = runtime_profile.get("volume_chunks", [])
	if volume_chunks.size() != 3:
		return false
	return await harness.start_flat_world(
		SOURCE_ROOT,
		SOURCE_REVISION,
		int(volume_chunks[0]),
		int(volume_chunks[1]),
		int(runtime_profile.get("vertical_chunk_origin", 0)),
		int(volume_chunks[2])
	)


static func _continuous_path(step_count: int) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for index in range(step_count):
		positions.append(Vector3(8.0 + float(index * 32), 8.0, 8.0 + float((index / 6) % 2) * 64.0))
	return positions


func _reset_observations() -> void:
	_terrain = null
	_last_frame_usec = 0
	_frame_samples_usec.clear()
	_viewer_update_samples_usec.clear()
	_settlement_samples_usec.clear()
	_edit_samples_usec.clear()
	_observed_render_chunks.clear()
	_observed_collision_chunks.clear()
	_maximum_memory_bytes = 0
	_maximum_transient_chunk_records = 0
	_maximum_non_retiring_chunks = 0
	_maximum_render_resources = 0
	_maximum_collision_resources = 0
	_maximum_render_queue = 0
	_maximum_collision_queue = 0
	_viewer_revision = 0
	_movement_count = 0
	_teleport_count = 0
	_edit_count = 0
	_actual_duration_ms = 0
	_snapshot_capacity_control_usec = 0.0
	_restart_settlement_usec = 0.0
	_stale_viewer_rejected = false
	_stale_edit_rejected = false
	_shutdown_clean = false
	_world_page_count = 0
	_post_restart_query_count = 0
	_post_restart_queries_agreed = false
	_edit_records.clear()
	_source_metrics = {}
	_restart_metrics = {}
	_snapshot = {}


static func _validate_standard_presence(
	standard: Dictionary,
	failures: Array[String]
) -> void:
	_expect(str(standard.get("schema", "")) == "world_transvoxel.terrain_lab.large_terrain_soak_standard.v1", "large-terrain soak standard is missing", failures)
	_expect(str(standard.get("milestone", "")) == "TQP-27", "large-terrain soak milestone changed", failures)
	_expect(str(standard.get("authority", "")) == "world_transvoxel_native_runtime", "large-terrain soak authority changed", failures)


static func _expect(condition: bool, failure: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(failure)
