extends SceneTree

const SCENE_PATH := "res://labs/terrain_lab/scenes/fault_order_observatory.tscn"
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/fault_order_determinism_standard.json"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var standard := _load_json(STANDARD_PATH)
	var expected: Dictionary = standard.get("stable_expected", {})
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		_fail("fault-order observatory scene could not load")
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	var ready: Dictionary = await scene.wait_until_ready()
	var initial: Dictionary = ready.get("snapshot", {})
	_expect(str(ready.get("status", "")) == "PASS", "initial preview did not settle", failures)
	_validate_snapshot(initial, expected, false, failures)
	var storm: Dictionary = await scene.run_motion_storm_and_wait(2)
	var storm_snapshot: Dictionary = storm.get("snapshot", {})
	_expect(str(storm.get("status", "")) == "PASS", "motion storm failed", failures)
	_validate_snapshot(storm_snapshot, expected, true, failures)
	var comparison: Dictionary = await scene.compare_reverse_and_wait()
	var comparison_snapshot: Dictionary = comparison.get("snapshot", {})
	_expect(str(comparison.get("status", "")) == "PASS", "reverse replay comparison failed", failures)
	_expect(str((comparison.get("comparison", {}) as Dictionary).get("status", "")) == "PASS", "state or geometry diverged", failures)
	_validate_snapshot(comparison_snapshot, expected, true, failures)
	var shutdown: Dictionary = await scene.shutdown_for_validation()
	_expect(str(shutdown.get("status", "")) == "PASS", "observatory did not stop with drained queues", failures)
	var report := {
		"schema": "world_transvoxel.terrain_lab.fault_order_observatory_validation.v1",
		"milestone": "TQP-43",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"scene": SCENE_PATH,
		"authority": standard.get("authority", ""),
		"initial_snapshot": initial,
		"storm": storm,
		"storm_snapshot": storm_snapshot,
		"comparison_snapshot": comparison_snapshot,
		"comparison": comparison.get("comparison", {}),
		"shutdown": shutdown,
		"claim": "EDITOR_LIVE_AUTHORITY_PRESENTATION",
		"failures": failures,
	}
	var output_path := _argument_value("--output")
	if not output_path.is_empty():
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file == null:
			_fail("could not write fault-order observatory report")
			return
		file.store_string(JSON.stringify(report, "\t", false) + "\n")
	if not failures.is_empty():
		_fail("fault-order observatory validation failed: " + str(failures))
		return
	print("WT_TERRAIN_LAB_FAULT_ORDER_OBSERVATORY_PASS")
	quit(0)


static func _validate_snapshot(
	snapshot: Dictionary,
	expected: Dictionary,
	require_fault_events: bool,
	failures: Array[String]
) -> void:
	_expect(str(snapshot.get("status", "")) == "PASS", "observatory status changed", failures)
	_expect(str(snapshot.get("backend_id", "")) == "transvoxel_mit_official", "observatory backend changed", failures)
	_expect(int(snapshot.get("native_runs", 0)) >= 15, "retained native run count changed", failures)
	_expect(int(snapshot.get("native_orders", 0)) == int(expected.get("orders", -1)), "native order count changed", failures)
	_expect(int(snapshot.get("allocation_faults", 0)) == int(expected.get("allocation_faults", -1)), "allocation controls changed", failures)
	_expect(int(snapshot.get("interruption_controls", 0)) == int(expected.get("interruption", -1)), "interruption controls changed", failures)
	_expect(int(snapshot.get("malformed_controls", 0)) == int(expected.get("malformed", -1)), "malformed controls changed", failures)
	_expect(int(snapshot.get("first_divergence_generation", -1)) == int(expected.get("first_divergence_generation", -2)), "first divergent generation changed", failures)
	_expect(int(snapshot.get("active_chunks", 0)) > 0 and int(snapshot.get("render_resources", 0)) > 0, "observatory terrain is absent", failures)
	if require_fault_events:
		_expect(int(snapshot.get("coalesced_viewer_events", 0)) > 0, "motion supersession did not coalesce", failures)
		_expect(int(snapshot.get("rejected_events", 0)) > 0, "stale revision was not rejected", failures)


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
	push_error("WT_TERRAIN_LAB_FAULT_ORDER_OBSERVATORY_FAIL " + message)
	quit(1)
