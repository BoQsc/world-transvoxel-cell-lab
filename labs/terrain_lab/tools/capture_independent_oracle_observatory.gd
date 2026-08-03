extends SceneTree

const SCENE_PATH := (
	"res://labs/terrain_lab/scenes/independent_oracle_observatory.tscn"
)
const DEFAULT_OUTPUT := (
	"res://labs/terrain_lab/results/independent_oracle_observatory_reference_windows.png"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		_fail("independent-oracle observatory scene could not load")
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	var image: Image
	var surface_samples := 0
	for frame in range(90):
		await process_frame
		await RenderingServer.frame_post_draw
		image = root.get_viewport().get_texture().get_image()
		surface_samples = _count_surface_samples(image)
		if frame >= 8 and surface_samples >= 400:
			break
	if image == null or image.is_empty():
		_fail("graphical viewport capture is unavailable")
		return
	if surface_samples < 400:
		_fail("independent-oracle fixture is absent from capture")
		return
	var output_path := _argument_value("--output", DEFAULT_OUTPUT)
	var error := image.save_png(output_path)
	if error != OK:
		_fail("could not save independent-oracle capture: " + error_string(error))
		return
	print(
		"WT_TERRAIN_INDEPENDENT_ORACLE_CAPTURE_PASS %s samples=%d"
		% [output_path, surface_samples]
	)
	quit(0)


static func _count_surface_samples(image: Image) -> int:
	if image == null or image.is_empty():
		return 0
	var count := 0
	var start_x := maxi(360, int(float(image.get_width()) * 0.29))
	for y in range(0, image.get_height(), 4):
		for x in range(start_x, image.get_width(), 4):
			var color := image.get_pixel(x, y)
			if color.g > 0.16 and color.g > color.r * 1.08:
				count += 1
	return count


func _argument_value(name: String, fallback: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size() - 1):
		if arguments[index] == name:
			return arguments[index + 1]
	return fallback


func _fail(message: String) -> void:
	push_error("WT_TERRAIN_INDEPENDENT_ORACLE_CAPTURE_FAIL: " + message)
	quit(1)
