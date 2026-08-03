extends SceneTree

const SCENE_PATH := "res://labs/terrain_lab/scenes/adaptive_surface_observatory.tscn"
const DEFAULT_OUTPUT := "res://labs/terrain_lab/results/adaptive_surface_continuity_motion_windows.json"
const MODES := ["lit", "material", "provenance"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		_fail("adaptive surface observatory scene could not load")
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	var ready: Dictionary = await scene.wait_until_ready()
	if str(ready.get("status", "")) != "PASS":
		_fail("adaptive surface observatory did not become ready")
		return
	var captures: Array[Dictionary] = []
	for mode in MODES:
		scene.prepare_reference_capture(mode)
		await _wait_for_stable_draw()
		var image := await _capture_synchronized_image()
		if image == null or image.is_empty():
			_fail("graphical viewport did not produce two identical completed UI frames")
			return
		var surface_samples := _count_surface_samples(image)
		if surface_samples < 250:
			_fail("native terrain is absent from capture: " + mode)
			return
		var path := "res://labs/terrain_lab/results/adaptive_surface_%s_windows.png" % mode
		var error := image.save_png(path)
		if error != OK:
			_fail("could not save adaptive surface capture: " + error_string(error))
			return
		captures.append({
			"mode": mode,
			"path": path,
			"sha256": FileAccess.get_sha256(path),
			"width": image.get_width(),
			"height": image.get_height(),
			"surface_samples": surface_samples,
			"snapshot": scene.get_validation_snapshot(),
		})
	var cycle: Dictionary = await scene.cycle_lod_and_wait()
	if str(cycle.get("status", "")) != "PASS":
		_fail("adaptive surface LOD cycle failed")
		return
	if str((await scene.shutdown_for_validation()).get("status", "")) != "PASS":
		_fail("adaptive surface observatory did not shut down")
		return
	var report := {
		"schema": "world_transvoxel.terrain_lab.adaptive_surface_continuity_motion.v1",
		"milestone": "TQP-38",
		"status": "PASS",
		"scene": SCENE_PATH,
		"capture_sequence": MODES,
		"captures": captures,
		"lod_cycle": cycle,
	}
	var output_path := _argument_value("--output", DEFAULT_OUTPUT)
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		_fail("could not open adaptive surface motion output")
		return
	file.store_string(JSON.stringify(report, "\t", false) + "\n")
	file.close()
	print("WT_TERRAIN_ADAPTIVE_SURFACE_CAPTURE_PASS " + output_path)
	quit(0)


static func _count_surface_samples(image: Image) -> int:
	var count := 0
	var start_x := maxi(370, int(float(image.get_width()) * 0.29))
	for y in range(0, image.get_height(), 4):
		for x in range(start_x, image.get_width(), 4):
			var color := image.get_pixel(x, y)
			if color.r + color.g + color.b > 0.24 and maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b)) > 0.025:
				count += 1
	return count


func _wait_for_stable_draw() -> void:
	# Multiple completed draws prevent mode-switch readback from retaining a
	# partially updated editor/UI frame on slower Forward+ drivers.
	for _frame in range(8):
		await process_frame
	for _draw in range(3):
		await process_frame
		await RenderingServer.frame_post_draw


func _capture_synchronized_image() -> Image:
	var previous_ui_signature := ""
	for _attempt in range(8):
		await process_frame
		await RenderingServer.frame_post_draw
		var candidate := root.get_viewport().get_texture().get_image()
		if candidate == null or candidate.is_empty():
			continue
		var ui_signature := _ui_region_signature(candidate, 404)
		if not previous_ui_signature.is_empty() and ui_signature == previous_ui_signature:
			return candidate
		previous_ui_signature = ui_signature
	return null


static func _ui_region_signature(image: Image, requested_width: int) -> String:
	var width := mini(requested_width, image.get_width())
	var region := image.get_region(Rect2i(0, 0, width, image.get_height()))
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(region.get_data())
	return context.finish().hex_encode()


func _argument_value(name: String, fallback: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size() - 1):
		if arguments[index] == name:
			return arguments[index + 1]
	return fallback


func _fail(message: String) -> void:
	push_error("WT_TERRAIN_ADAPTIVE_SURFACE_CAPTURE_FAIL: " + message)
	quit(1)
