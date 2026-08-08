extends SceneTree

const SCENE_PATH := "res://labs/terrain_lab/scenes/sparse_hierarchy_observatory.tscn"
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/sparse_hierarchy_storage_standard.json"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var standard := _load_json(STANDARD_PATH)
	var budgets: Dictionary = standard.get("budgets", {})
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		_fail("sparse hierarchy observatory scene could not load")
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	var ready: Dictionary = await scene.wait_until_ready()
	var source: Dictionary = ready.get("snapshot", {})
	_expect(str(ready.get("status", "")) == "PASS", "source preview did not settle", failures)
	_validate_snapshot(source, budgets, false, failures)
	var edit: Dictionary = await scene.apply_localized_edit()
	_expect(str(edit.get("status", "")) == "PASS", "observatory edit failed", failures)
	var reopened: Dictionary = await scene.compact_and_reopen()
	var sparse: Dictionary = reopened.get("snapshot", {})
	_expect(str(reopened.get("status", "")) == "PASS", "observatory compact/reopen failed", failures)
	_validate_snapshot(sparse, budgets, true, failures)
	var shutdown: Dictionary = await scene.shutdown_for_validation()
	_expect(str(shutdown.get("status", "")) == "PASS", "observatory did not stop", failures)
	var report := {
		"schema": "world_transvoxel.terrain_lab.sparse_hierarchy_observatory_validation.v1",
		"milestone": "TQP-42",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"scene": SCENE_PATH,
		"authority": standard.get("authority", ""),
		"source_snapshot": source,
		"sparse_snapshot": sparse,
		"shutdown": shutdown,
		"claim": "EDITOR_LIVE_AUTHORITY_PRESENTATION",
		"failures": failures,
	}
	var output_path := _argument_value("--output")
	if not output_path.is_empty():
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file == null:
			_fail("could not write sparse observatory report")
			return
		file.store_string(JSON.stringify(report, "\t", false) + "\n")
	if not failures.is_empty():
		_fail("sparse observatory validation failed: " + str(failures))
		return
	print("WT_TERRAIN_LAB_SPARSE_OBSERVATORY_PASS")
	quit(0)


static func _validate_snapshot(
	snapshot: Dictionary,
	budgets: Dictionary,
	require_overlay: bool,
	failures: Array[String]
) -> void:
	_expect(str(snapshot.get("status", "")) == "PASS", "observatory status changed", failures)
	_expect(int(snapshot.get("declared_pages", 0)) == int(budgets.get("expected_declared_page_count", -1)), "declared page count changed", failures)
	_expect(int(snapshot.get("explicit_index_entries", -1)) == 0, "observatory materialized explicit page keys", failures)
	_expect(int(snapshot.get("hierarchy_index_bytes", 0)) <= int(budgets.get("maximum_hierarchy_index_bytes", -1)), "hierarchy index exceeded ceiling", failures)
	_expect(int(snapshot.get("active_chunks", 0)) > 0, "observatory has no active chunks", failures)
	_expect(int(snapshot.get("render_resources", 0)) > 0, "observatory has no render resources", failures)
	if require_overlay:
		_expect(int(snapshot.get("overlay_pages", 0)) > 0, "reopened observatory has no sparse overlay", failures)


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
	push_error("WT_TERRAIN_LAB_SPARSE_OBSERVATORY_FAIL " + message)
	quit(1)
