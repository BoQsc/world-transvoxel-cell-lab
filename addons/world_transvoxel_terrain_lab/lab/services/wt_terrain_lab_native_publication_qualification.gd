@tool
extends Node
class_name WtTerrainLabNativePublicationQualification

const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)


func run() -> Dictionary:
	var failures: Array[String] = []
	var result := {
		"schema": "world_transvoxel.terrain_lab.native_publication_qualification.v1",
		"milestone": "TQP-21",
		"status": "FAIL",
		"fixture": "native_m3_publication",
		"checks": 0,
	}
	if not ClassDB.class_exists("WorldTransvoxelTerrain"):
		failures.append("native WorldTransvoxelTerrain is unavailable")
		result["failures"] = failures
		return result
	var terrain: Node = ClassDB.instantiate("WorldTransvoxelTerrain")
	if terrain == null:
		failures.append("native publication fixture could not instantiate terrain")
		result["failures"] = failures
		return result
	add_child(terrain)
	terrain.call("set_render_apply_budget", 0)
	terrain.call("set_collision_apply_budget", 0)
	_expect(
		bool(terrain.call("_m3_test_submit_generation", 1, true)),
		"generation 1 publication submission failed",
		failures
	)
	_expect(
		bool(terrain.call("_m3_test_submit_generation", 2, true)),
		"generation 2 supersession failed",
		failures
	)
	await get_tree().process_frame
	_expect(
		int(terrain.call("get_queued_render_count")) == 2
			and int(terrain.call("get_queued_collision_count")) == 2,
		"zero publication budget changed queue ownership",
		failures
	)
	terrain.call("set_render_apply_budget", 1)
	terrain.call("set_collision_apply_budget", 1)
	await get_tree().process_frame
	_expect(
		int(terrain.call("get_render_resource_count")) == 0
			and int(terrain.call("get_collision_resource_count")) == 0
			and int(terrain.call("get_queued_render_count")) == 1
			and int(terrain.call("get_queued_collision_count")) == 1,
		"stale generation reached Godot or bypassed apply budget",
		failures
	)
	await get_tree().process_frame
	var generation_two_ready := (
		bool(terrain.call("_m3_test_fully_ready"))
		and int(terrain.call("_m3_test_render_generation")) == 2
		and int(terrain.call("_m3_test_collision_generation")) == 2
		and int(terrain.call("get_render_resource_count")) == 1
		and int(terrain.call("get_collision_resource_count")) == 1
	)
	_expect(
		generation_two_ready,
		"render and collision did not publish generation 2 atomically",
		failures
	)
	_expect(
		int(terrain.call("_m3_test_stale_render_count")) == 1
			and int(terrain.call("_m3_test_stale_collision_count")) == 1,
		"stale publication counters changed",
		failures
	)
	_expect(
		bool(terrain.call("_m3_test_submit_generation", 3, true)),
		"teardown generation submission failed",
		failures
	)
	terrain.call("_m3_test_forget_chunk")
	await get_tree().process_frame
	var teardown_clean := (
		int(terrain.call("get_render_resource_count")) == 0
		and int(terrain.call("get_collision_resource_count")) == 0
		and int(terrain.call("get_queued_render_count")) == 0
		and int(terrain.call("get_queued_collision_count")) == 0
		and int(terrain.call("_m3_test_stale_render_count")) == 2
		and int(terrain.call("_m3_test_stale_collision_count")) == 2
	)
	_expect(
		teardown_clean,
		"in-flight teardown retained or published stale resources",
		failures
	)
	var timings: Array[float] = []
	var benchmark_coherent := true
	for iteration in range(110):
		var generation := 100 + iteration
		var started_usec := Time.get_ticks_usec()
		if not bool(terrain.call("_m3_test_submit_generation", generation, true)):
			benchmark_coherent = false
			break
		await get_tree().process_frame
		if int(terrain.call("_m3_test_render_generation")) != generation \
				or int(terrain.call("_m3_test_collision_generation")) != generation \
				or int(terrain.call("get_render_resource_count")) != 1 \
				or int(terrain.call("get_collision_resource_count")) != 1:
			benchmark_coherent = false
			break
		if iteration >= 10:
			timings.append(float(Time.get_ticks_usec() - started_usec))
	_expect(
		benchmark_coherent and timings.size() == 100,
		"native publication benchmark lost generation or resource coherence",
		failures
	)
	result["checks"] = 8
	result["published_generation"] = 2
	result["stale_render_rejections"] = int(
		terrain.call("_m3_test_stale_render_count")
	)
	result["stale_collision_rejections"] = int(
		terrain.call("_m3_test_stale_collision_count")
	)
	result["teardown_clean"] = teardown_clean
	result["performance"] = Statistics.distribution(timings)
	result["performance_scope"] = "NATIVE_DEBUG_REFERENCE_OBSERVATION_NOT_TQP_28"
	result["render_latency_frames_maximum"] = int(
		terrain.call("get_render_latency_frames_maximum")
	)
	result["collision_latency_frames_maximum"] = int(
		terrain.call("get_collision_latency_frames_maximum")
	)
	result["failures"] = failures
	result["status"] = "PASS" if failures.is_empty() else "FAIL"
	terrain.queue_free()
	await get_tree().process_frame
	return result


static func _expect(condition: bool, failure: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(failure)
