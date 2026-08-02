@tool
extends Node
class_name WtTerrainLabTemporalEditQualification

const Harness := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_runtime_harness.gd"
)

const FIXTURE_ROOT := "user://world_transvoxel_terrain_lab/temporal_edits"
const SOURCE_REVISION := 8101
const VIEWER_ID := 1
const TARGET_POINT := Vector3i(40, 6, 40)
const TARGET_CHUNK := Vector3i(2, 0, 2)
const TARGET_CHUNK_NAME := "WT_Render_2_0_2_L0"


func run() -> Dictionary:
	var failures: Array[String] = []
	Harness.remove_tree(FIXTURE_ROOT)
	var harness := Harness.new()
	add_child(harness)
	if not harness.create_runtime(2):
		failures.append("TQP-21: native runtime harness could not be created")
		await _dispose_harness(harness)
		return _result({}, {}, failures)
	if not await harness.start_flat_world(FIXTURE_ROOT, SOURCE_REVISION):
		failures.append("TQP-21: native flat world did not reach running")
		await _dispose_harness(harness)
		return _result({}, {}, failures)
	var terrain := harness.terrain
	for update in [
		[1, Vector3(16, 8, 16)],
		[2, Vector3(104, 8, 104)],
		[3, Vector3(40, 8, 40)],
	]:
		_expect(
			bool(terrain.call("update_viewer", VIEWER_ID, update[0], update[1], 0, 0)),
			"TQP-21: rapid native viewer update was rejected",
			failures
		)
	var initial_settlement: Dictionary = await harness.wait_for_settled(1)
	_expect(
		str(initial_settlement.get("status", "")) == "PASS",
		"TQP-21: native worker pipeline did not settle",
		failures
	)
	var initial_metrics: Dictionary = initial_settlement.get("metrics", {})
	_expect(
		int(initial_metrics.get("storage_worker_count", 0)) == 2,
		"TQP-21: configured native worker count was not active",
		failures
	)
	_expect(
		int(initial_metrics.get("sample_jobs", 0)) > 0
			and int(initial_metrics.get("mesh_jobs", 0)) > 0
			and int(initial_metrics.get("published_events", 0)) > 0,
		"TQP-21: native sampling, meshing, or publication work was not observed",
		failures
	)
	_expect(
		int(initial_metrics.get("scheduler_failed_records", 0)) == 0
			and int(initial_metrics.get("scheduler_queue_rejections", 0)) == 0,
		"TQP-21: native scheduler reported failed or rejected records",
		failures
	)
	_expect(
		int(initial_metrics.get("coalesced_viewer_events", 0)) > 0,
		"TQP-21: rapid viewer revisions did not coalesce superseded work",
		failures
	)
	var initial_sample: Dictionary = await harness.request_sample(TARGET_POINT)
	_expect(
		str(initial_sample.get("status", "")) == "PASS"
			and int(initial_sample.get("world_revision", -1)) == 0,
		"TQP-13: initial authoritative sample failed",
		failures
	)
	var valid: RefCounted = terrain.call("begin_edit_transaction", 1301)
	var stale: RefCounted = terrain.call("begin_edit_transaction", 1302)
	_expect(valid != null and stale != null, "TQP-13: edit transactions were not created", failures)
	if valid == null or stale == null:
		await _dispose_harness(harness)
		return _result({}, {}, failures)
	_expect(
		bool(valid.call(
			"carve_smooth_sdf_sphere", Vector3(TARGET_POINT), 4.0, 1.0, 0.75
		)),
		"TQP-13: carve command construction failed",
		failures
	)
	_expect(
		bool(stale.call(
			"construct_material_smooth_sdf_sphere",
			Vector3(TARGET_POINT), 2.0, 1.0, 7, 0.5
		)),
		"TQP-13: stale construction command construction failed",
		failures
	)
	_expect(
		bool(terrain.call("commit_edit_transaction", valid)),
		"TQP-13: carve transaction submission failed",
		failures
	)
	_expect(
		bool(terrain.call("update_viewer", VIEWER_ID, 4, Vector3(104, 8, 40), 0, 0))
			and bool(terrain.call("update_viewer", VIEWER_ID, 5, Vector3(40, 8, 40), 0, 1))
			and bool(terrain.call("update_viewer", VIEWER_ID, 6, Vector3(40, 8, 40), 0, 0)),
		"TQP-13: streaming/LOD overlap updates were rejected",
		failures
	)
	var carved_sample: Dictionary = await harness.request_sample(TARGET_POINT)
	_expect(
		await harness.wait_for_commit(1)
			and str(carved_sample.get("status", "")) == "PASS"
			and int(carved_sample.get("world_revision", -1)) == 1
			and float(carved_sample.get("density", -INF))
				> float(initial_sample.get("density", INF)),
		"TQP-13: edit/query ordering did not expose committed carve revision",
		failures
	)
	var journal_path := FIXTURE_ROOT + "/world.wtedit"
	var journal_after_carve := _file_signature(journal_path)
	_expect(
		not journal_after_carve.is_empty(),
		"TQP-13: committed carve did not create a durable journal",
		failures
	)
	var failure_count := harness.edit_failures.size()
	_expect(
		bool(terrain.call("commit_edit_transaction", stale)),
		"TQP-13: stale transaction was not accepted for asynchronous validation",
		failures
	)
	var stale_error: String = await harness.wait_for_edit_failure(failure_count)
	_expect(
		stale_error == "edit transaction world revision is stale"
			and int(terrain.call("get_world_revision")) == 1,
		"TQP-13: stale transaction was not rejected at revision 1",
		failures
	)
	var journal_after_rejection := _file_signature(journal_path)
	_expect(
		journal_after_rejection == journal_after_carve,
		"TQP-13: stale rejection mutated durable journal bytes",
		failures
	)
	var construction: RefCounted = terrain.call("begin_edit_transaction", 1303)
	_expect(construction != null, "TQP-13: construction transaction was not created", failures)
	if construction == null:
		await _dispose_harness(harness)
		return _result({}, {}, failures)
	_expect(
		bool(construction.call(
			"construct_material_smooth_sdf_sphere",
			Vector3(TARGET_POINT), 2.5, 1.0, 7, 0.5
		)),
		"TQP-13: construction command failed",
		failures
	)
	_expect(
		bool(terrain.call("commit_edit_transaction", construction)),
		"TQP-13: construction transaction submission failed",
		failures
	)
	_expect(
		bool(terrain.call("update_viewer", VIEWER_ID, 7, Vector3(72, 8, 40), 0, 1))
			and bool(terrain.call("update_viewer", VIEWER_ID, 8, Vector3(40, 8, 40), 0, 0)),
		"TQP-13: construction overlap viewer updates failed",
		failures
	)
	var final_sample: Dictionary = await harness.request_sample(TARGET_POINT)
	_expect(
		await harness.wait_for_commit(2)
			and str(final_sample.get("status", "")) == "PASS"
			and int(final_sample.get("world_revision", -1)) == 2
			and float(final_sample.get("density", INF)) < 0.0
			and int(final_sample.get("material", 0)) == 7,
		"TQP-13: authoritative construction density/material mismatch",
		failures
	)
	var final_settlement: Dictionary = await harness.wait_for_settled(1)
	var target_state: RefCounted = terrain.call("query_chunk_state", TARGET_CHUNK, 0)
	var target_snapshot: Dictionary = (
		Harness.chunk_state(target_state) if target_state != null else {}
	)
	_expect(
		str(final_settlement.get("status", "")) == "PASS"
			and not target_snapshot.is_empty()
			and int(target_snapshot.get("generation", -1))
				== int(target_snapshot.get("render_generation", -2))
			and int(target_snapshot.get("generation", -1))
				== int(target_snapshot.get("collision_generation", -2)),
		"TQP-21: edited target render/collision generations did not settle coherently",
		failures
	)
	var final_metrics: Dictionary = final_settlement.get("metrics", {})
	_expect(
		int(final_metrics.get("edit_commits", 0)) == 2
			and int(final_metrics.get("edit_rejections", 0)) == 1
			and int(final_metrics.get("edit_replacements", 0)) > 0,
		"TQP-13: native edit commit/rejection/replacement metrics mismatch",
		failures
	)
	var mesh_signature := harness.mesh_signature(TARGET_CHUNK_NAME)
	_expect(mesh_signature != "EMPTY", "TQP-21: edited target mesh is empty", failures)
	var journal_final := _file_signature(journal_path)
	_expect(
		not journal_final.is_empty() and journal_final != journal_after_carve,
		"TQP-13: second committed edit did not advance journal bytes",
		failures
	)
	_expect(await harness.stop_world(), "TQP-13: edited world did not stop", failures)
	harness.clear_events()
	_expect(
		await harness.start_flat_world(FIXTURE_ROOT, SOURCE_REVISION),
		"TQP-13: edited procedural world did not restart",
		failures
	)
	var replay_sample: Dictionary = await harness.request_sample(TARGET_POINT)
	_expect(
		_samples_equal(final_sample, replay_sample)
			and int(harness.terrain.call("get_world_revision")) == 2,
		"TQP-13: restart did not replay the committed temporal edits",
		failures
	)
	_expect(
		bool(harness.terrain.call(
			"update_viewer", VIEWER_ID, 1, Vector3(40, 8, 40), 0, 0
		)),
		"TQP-21: replay viewer update failed",
		failures
	)
	var replay_settlement: Dictionary = await harness.wait_for_settled(1)
	var replay_mesh_signature := harness.mesh_signature(TARGET_CHUNK_NAME)
	_expect(
		str(replay_settlement.get("status", "")) == "PASS"
			and replay_mesh_signature == mesh_signature,
		"TQP-13/TQP-21: restart changed settled edited mesh bytes",
		failures
	)
	var scheduling := {
		"status": "PASS" if not _has_failure(failures, "TQP-21") else "FAIL",
		"fixture": "native_production_worker_runtime",
		"worker_count": int(initial_metrics.get("storage_worker_count", 0)),
		"sample_jobs": int(final_metrics.get("sample_jobs", 0)),
		"mesh_jobs": int(final_metrics.get("mesh_jobs", 0)),
		"published_events": int(final_metrics.get("published_events", 0)),
		"coalesced_viewer_events": int(initial_metrics.get("coalesced_viewer_events", 0)),
		"initial_settlement_frames": int(initial_settlement.get("frames", -1)),
		"final_settlement_frames": int(final_settlement.get("frames", -1)),
		"target_chunk": target_snapshot,
		"target_mesh_signature": mesh_signature,
	}
	var temporal := {
		"status": "PASS" if not _has_failure(failures, "TQP-13") else "FAIL",
		"commits": int(final_metrics.get("edit_commits", 0)),
		"stale_rejections": int(final_metrics.get("edit_rejections", 0)),
		"chunk_replacements": int(final_metrics.get("edit_replacements", 0)),
		"initial_sample": initial_sample,
		"carved_sample": carved_sample,
		"constructed_sample": final_sample,
		"restart_sample": replay_sample,
		"stale_error": stale_error,
		"streaming_and_lod_overlap": true,
		"journal_after_carve_sha256": journal_after_carve,
		"journal_after_rejection_sha256": journal_after_rejection,
		"journal_final_sha256": journal_final,
		"restart_mesh_signature": replay_mesh_signature,
	}
	await _dispose_harness(harness)
	Harness.remove_tree(FIXTURE_ROOT)
	return _result(scheduling, temporal, failures)


static func _result(
	scheduling: Dictionary,
	temporal: Dictionary,
	failures: Array[String]
) -> Dictionary:
	return {
		"schema": "world_transvoxel.terrain_lab.temporal_edit_qualification.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"scheduling": scheduling,
		"temporal_edits": temporal,
		"failures": failures,
	}


func _dispose_harness(harness: Node) -> void:
	if harness == null:
		return
	if harness.terrain != null and str(harness.terrain.call("get_world_state_name")) != "stopped":
		await harness.stop_world()
	harness.dispose()
	harness.queue_free()
	await get_tree().process_frame


static func _samples_equal(left: Dictionary, right: Dictionary) -> bool:
	return (
		str(left.get("status", "")) == "PASS"
		and str(right.get("status", "")) == "PASS"
		and is_equal_approx(float(left.get("density", INF)), float(right.get("density", -INF)))
		and int(left.get("material", -1)) == int(right.get("material", -2))
		and int(left.get("world_revision", -1)) == int(right.get("world_revision", -2))
	)


static func _file_signature(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""


static func _has_failure(failures: Array[String], milestone: String) -> bool:
	for failure in failures:
		if failure.begins_with(milestone + ":") or failure.begins_with(milestone + "/"):
			return true
	return false


static func _expect(condition: bool, failure: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(failure)
