extends SceneTree

const SCENE_PATH := "res://labs/terrain_lab/scenes/large_terrain_observatory.tscn"
const DEFAULT_OUTPUT := (
	"res://labs/terrain_lab/results/large_terrain_observatory_reference_windows.png"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		_fail("large-terrain observatory scene could not load")
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	var ready: Dictionary = await scene.wait_until_ready()
	if str(ready.get("status", "")) != "PASS":
		_fail("large-terrain observatory did not settle before capture")
		return
	var capture_mode := _argument_value("--mode", "local")
	if capture_mode == "overview":
		var settlement: Dictionary = await scene.move_viewer_and_wait(
			Vector3(1024.0, 8.0, 1024.0)
		)
		if str(settlement.get("status", "")) != "PASS":
			_fail("overview resident window did not settle")
			return
		scene.prepare_world_overview_capture()
	else:
		scene.prepare_reference_capture()
	var image: Image
	var terrain_samples := 0
	var envelope_samples := 0
	for frame in range(90):
		await process_frame
		await RenderingServer.frame_post_draw
		image = root.get_viewport().get_texture().get_image()
		terrain_samples = _count_terrain_samples(image)
		envelope_samples = _count_envelope_samples(image)
		var visible := (
			terrain_samples >= 20 and envelope_samples >= 40
			if capture_mode == "overview"
			else terrain_samples >= 1200
		)
		if frame >= 8 and visible:
			break
	if image == null or image.is_empty():
		_fail("graphical viewport capture is unavailable")
		return
	if capture_mode != "overview" and terrain_samples < 1200:
		_fail("native terrain is absent from observatory capture: %d samples" % terrain_samples)
		return
	if capture_mode == "overview" and (terrain_samples < 20 or envelope_samples < 40):
		_fail("world overview lacks terrain or envelope: terrain=%d envelope=%d" % [terrain_samples, envelope_samples])
		return
	var output_path := _argument_value("--output", DEFAULT_OUTPUT)
	var error := image.save_png(output_path)
	if error != OK:
		_fail("could not save observatory capture: " + error_string(error))
		return
	await scene.shutdown_for_validation()
	print("WT_TERRAIN_LARGE_OBSERVATORY_CAPTURE_PASS %s terrain=%d envelope=%d" % [
		output_path,
		terrain_samples,
		envelope_samples,
	])
	quit(0)


static func _count_terrain_samples(image: Image) -> int:
	if image == null or image.is_empty():
		return 0
	var count := 0
	var start_x := maxi(380, int(float(image.get_width()) * 0.28))
	for y in range(0, image.get_height(), 4):
		for x in range(start_x, image.get_width(), 4):
			var color := image.get_pixel(x, y)
			var green_surface := (
				color.g > 0.16
				and color.g > color.r * 1.08
				and color.g > color.b * 1.02
			)
			var lod_surface := (
				color.r > 0.22 and color.g > 0.2 and color.b < 0.24
			)
			if green_surface or lod_surface:
				count += 1
	return count


static func _count_envelope_samples(image: Image) -> int:
	if image == null or image.is_empty():
		return 0
	var count := 0
	var start_x := maxi(380, int(float(image.get_width()) * 0.28))
	for y in range(0, image.get_height(), 3):
		for x in range(start_x, image.get_width(), 3):
			var color := image.get_pixel(x, y)
			if color.r > 0.45 and color.g > 0.28 and color.r > color.b * 1.35:
				count += 1
	return count


func _argument_value(name: String, fallback: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size() - 1):
		if arguments[index] == name:
			return arguments[index + 1]
	return fallback


func _fail(message: String) -> void:
	push_error("WT_TERRAIN_LARGE_OBSERVATORY_CAPTURE_FAIL: " + message)
	quit(1)
