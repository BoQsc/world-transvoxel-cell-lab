extends SceneTree

const OBSERVATORY_SCENE := (
	"res://labs/terrain_lab/scenes/terrain_observatory.tscn"
)
const DEFAULT_OUTPUT := (
	"res://labs/terrain_lab/results/terrain_observatory_reference.png"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(OBSERVATORY_SCENE) as PackedScene
	if packed == null:
		_fail("observatory scene could not load")
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	if scene.has_method("prepare_reference_capture"):
		scene.call("prepare_reference_capture")
	var image: Image
	var visible_surface_pixels := 0
	for frame in range(90):
		await process_frame
		await RenderingServer.frame_post_draw
		image = root.get_viewport().get_texture().get_image()
		visible_surface_pixels = _count_surface_pixels(image)
		if frame >= 7 and visible_surface_pixels >= 400:
			break
	if image == null or image.is_empty():
		_fail("graphical viewport capture is unavailable")
		return
	if visible_surface_pixels < 400:
		var diagnostic_path := _argument_value("--diagnostic-output", "")
		if not diagnostic_path.is_empty():
			var diagnostic_error := image.save_png(diagnostic_path)
			if diagnostic_error != OK:
				_fail("could not save failed-capture diagnostic: %s" % error_string(diagnostic_error))
				return
		_fail(
			"rendered terrain surface is absent from the capture "
			+ "(surface pixels=%d, diagnostic=%s)" % [visible_surface_pixels, diagnostic_path]
		)
		return
	var output_path := _argument_value("--output", DEFAULT_OUTPUT)
	var error := image.save_png(output_path)
	if error != OK:
		_fail("could not save capture: %s" % error_string(error))
		return
	print("WT_TERRAIN_OBSERVATORY_CAPTURE_PASS " + output_path)
	quit(0)


func _count_surface_pixels(image: Image) -> int:
	if image == null or image.is_empty():
		return 0
	var count := 0
	var start_x := int(float(image.get_width()) * 0.28)
	for y in range(0, image.get_height(), 6):
		for x in range(start_x, image.get_width(), 6):
			var color := image.get_pixel(x, y)
			var green_surface := (
				color.r > 0.35 and color.g > 0.55 and color.b > 0.28
				and color.g > color.r * 1.08
			)
			var construct_surface := (
				color.r > 0.62 and color.g > 0.42 and color.b < 0.42
			)
			if green_surface or construct_surface:
				count += 1
	return count


func _argument_value(name: String, fallback: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size() - 1):
		if arguments[index] == name:
			return arguments[index + 1]
	return fallback


func _fail(message: String) -> void:
	push_error("WT_TERRAIN_OBSERVATORY_CAPTURE_FAIL: " + message)
	quit(1)
