extends SceneTree

const SCENE_PATH := "res://labs/terrain_lab/scenes/large_terrain_observatory.tscn"
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/large_terrain_soak_standard.json"
)
const RETAINED_PATH := (
	"res://labs/terrain_lab/results/large_terrain_soak_reference_windows.json"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var standard := _load_json(STANDARD_PATH)
	var retained := _load_json(RETAINED_PATH)
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		_fail("large-terrain observatory scene could not load")
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	var initial: Dictionary = await scene.wait_until_ready()
	_expect(str(initial.get("status", "")) == "PASS", "initial native window did not settle", failures)
	var initial_snapshot: Dictionary = initial.get("snapshot", {})
	_validate_snapshot(initial_snapshot, standard, retained, failures)
	var positions: Array[Dictionary] = []
	for target in [Vector3(1024.0, 8.0, 1024.0), Vector3(1992.0, 8.0, 1992.0)]:
		var viewer_updates_before := int(
			(scene.get_validation_snapshot().get("metrics", {}) as Dictionary).get(
				"viewer_updates", 0
			)
		)
		var settlement: Dictionary = await scene.move_viewer_and_wait(target)
		var snapshot: Dictionary = scene.get_validation_snapshot()
		_expect(str(settlement.get("status", "")) == "PASS", "teleport did not settle", failures)
		_expect((snapshot.get("viewer_position", Vector3.ZERO) as Vector3).is_equal_approx(target), "teleport viewer position changed", failures)
		_expect(int((snapshot.get("metrics", {}) as Dictionary).get("viewer_updates", 0)) > viewer_updates_before, "teleport viewer update was not consumed", failures)
		_validate_runtime_metrics(snapshot.get("metrics", {}), standard, failures)
		positions.append({
			"target": target,
			"settlement_usec": int(settlement.get("elapsed_usec", 0)),
			"active_chunks": int((snapshot.get("metrics", {}) as Dictionary).get("active_chunk_records", 0)),
			"render_resources": int((snapshot.get("metrics", {}) as Dictionary).get("render_resources", 0)),
		})
	var shutdown: Dictionary = await scene.shutdown_for_validation()
	_expect(str(shutdown.get("status", "")) == "PASS", "observatory runtime did not stop", failures)
	var report := {
		"schema": "world_transvoxel.terrain_lab.large_terrain_observatory_validation.v1",
		"milestone": "TQP-27",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"scene": SCENE_PATH,
		"authority": "world_transvoxel_native_runtime",
		"profile": initial_snapshot.get("profile", {}),
		"catalog_page_count": int(initial_snapshot.get("catalog_page_count", 0)),
		"initial_snapshot": initial_snapshot,
		"teleports": positions,
		"shutdown": shutdown,
		"claim": "EDITOR_PRESENTATION_PARITY_ONLY",
		"failures": failures,
	}
	var output_path := _argument_value("--output")
	if not output_path.is_empty():
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file == null:
			_fail("could not open observatory validation output")
			return
		file.store_string(JSON.stringify(report, "\t", false) + "\n")
	print(JSON.stringify(report, "\t", false))
	if not failures.is_empty():
		_fail("large-terrain observatory validation failed: " + str(failures))
		return
	print("WT_TERRAIN_LARGE_OBSERVATORY_PASS")
	quit(0)


static func _validate_snapshot(
	snapshot: Dictionary,
	standard: Dictionary,
	retained: Dictionary,
	failures: Array[String]
) -> void:
	var profile: Dictionary = snapshot.get("profile", {})
	_expect(str(snapshot.get("status", "")) == "READY", "observatory did not report READY", failures)
	_expect(str(snapshot.get("world_state", "")) == "running", "observatory world is not running", failures)
	_expect(str(snapshot.get("backend_id", "")) == "transvoxel_mit_official", "observatory backend changed", failures)
	_expect(str(snapshot.get("backend_license", "")) == "MIT", "observatory backend license changed", failures)
	_expect(str(profile.get("standard_id", "")) == str(standard.get("standard_id", "")), "observatory standard ID changed", failures)
	_expect((profile.get("runtime_profile", {}) as Dictionary) == (standard.get("runtime_profile", {}) as Dictionary), "observatory runtime profile differs from TQP-27", failures)
	var expected_pages := int((retained.get("persistence", {}) as Dictionary).get("catalog_page_count", 0))
	_expect(int(snapshot.get("catalog_page_count", 0)) == expected_pages and expected_pages >= 250000, "observatory catalog page count differs from retained TQP-27", failures)
	_validate_runtime_metrics(snapshot.get("metrics", {}), standard, failures)


static func _validate_runtime_metrics(
	metrics: Dictionary,
	standard: Dictionary,
	failures: Array[String]
) -> void:
	var profile: Dictionary = standard.get("runtime_profile", {})
	var active := int(metrics.get("active_chunk_records", 0))
	var ready := int(metrics.get("non_retiring_fully_ready_chunk_records", 0))
	var non_retiring := int(metrics.get("non_retiring_chunk_records", active))
	_expect(active > 0, "observatory has no active native chunks", failures)
	_expect(active <= int(profile.get("active_chunk_capacity", 0)), "observatory exceeded TQP-27 active capacity", failures)
	_expect(ready == non_retiring, "observatory native chunks are not settled", failures)
	_expect(int(metrics.get("render_resources", 0)) > 0, "observatory has no native render resources", failures)
	_expect(int(metrics.get("collision_resources", 0)) > 0, "observatory has no native collision resources", failures)
	_expect(int(metrics.get("scheduler_queued_jobs", -1)) == 0, "observatory scheduler is not drained", failures)
	_expect(int(metrics.get("storage_queued_requests", -1)) == 0, "observatory storage is not drained", failures)


static func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	return value if value is Dictionary else {}


func _argument_value(name: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size() - 1):
		if arguments[index] == name:
			return arguments[index + 1]
	return ""


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _fail(message: String) -> void:
	push_error("WT_TERRAIN_LARGE_OBSERVATORY_FAIL: " + message)
	quit(1)
