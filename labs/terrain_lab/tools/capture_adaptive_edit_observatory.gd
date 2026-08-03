extends SceneTree

const SCENE_PATH := "res://labs/terrain_lab/scenes/adaptive_edit_observatory.tscn"
const DEFAULT_OUTPUT := "res://labs/terrain_lab/results/adaptive_edit_motion_windows.json"
const ACTIONS := [
	"transition_face_carve",
	"chunk_edge_corner_construction",
	"under_resolved_refined",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		_fail("adaptive edit observatory scene could not load")
		return
	var scene := packed.instantiate()
	if not scene.has_method("wait_until_ready") \
			or not scene.has_method("run_action_and_wait") \
			or not scene.has_method("prepare_reference_capture"):
		_fail("adaptive edit observatory script did not load")
		return
	root.add_child(scene)
	var ready: Dictionary = await scene.wait_until_ready()
	if str(ready.get("status", "")) != "PASS":
		_fail("adaptive edit observatory did not become ready")
		return
	var captures: Array[Dictionary] = []
	for action in ACTIONS:
		var result: Dictionary = await scene.run_action_and_wait(action)
		if str(result.get("status", "")) != "PASS":
			_fail("adaptive edit action failed: %s %s" % [
				action, JSON.stringify(result)
			])
			return
		scene.prepare_reference_capture(action)
		for _frame in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_viewport().get_texture().get_image()
		if image == null or image.is_empty():
			_fail("graphical viewport capture is unavailable")
			return
		var surface_samples := _count_surface_samples(image)
		if surface_samples < 250:
			_fail("native terrain is absent from capture: " + action)
			return
		var path := "res://labs/terrain_lab/results/adaptive_edit_%s_windows.png" % action
		var error := image.save_png(path)
		if error != OK:
			_fail("could not save adaptive edit capture: " + error_string(error))
			return
		captures.append({
			"action": action,
			"path": path,
			"sha256": FileAccess.get_sha256(path),
			"width": image.get_width(),
			"height": image.get_height(),
			"surface_samples": surface_samples,
			"snapshot": scene.get_validation_snapshot(),
		})
	var shutdown: Dictionary = await scene.shutdown_for_validation()
	if str(shutdown.get("status", "")) != "PASS":
		_fail("adaptive edit observatory did not shut down cleanly")
		return
	var report := {
		"schema": "world_transvoxel.terrain_lab.adaptive_edit_motion.v1",
		"milestone": "TQP-37",
		"status": "PASS",
		"scene": SCENE_PATH,
		"capture_sequence": ACTIONS,
		"captures": captures,
	}
	var output_path := _argument_value("--output", DEFAULT_OUTPUT)
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		_fail("could not open adaptive edit motion output")
		return
	file.store_string(JSON.stringify(report, "\t", false) + "\n")
	print("WT_TERRAIN_ADAPTIVE_EDIT_CAPTURE_PASS " + output_path)
	quit(0)


static func _count_surface_samples(image: Image) -> int:
	var count := 0
	var start_x := maxi(380, int(float(image.get_width()) * 0.3))
	for y in range(0, image.get_height(), 4):
		for x in range(start_x, image.get_width(), 4):
			var color := image.get_pixel(x, y)
			if color.g > 0.12 and color.g > color.r * 1.03:
				count += 1
	return count


func _argument_value(name: String, fallback: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size() - 1):
		if arguments[index] == name:
			return arguments[index + 1]
	return fallback


func _fail(message: String) -> void:
	push_error("WT_TERRAIN_ADAPTIVE_EDIT_CAPTURE_FAIL: " + message)
	quit(1)
