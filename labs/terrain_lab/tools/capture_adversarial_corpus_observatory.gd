extends SceneTree

const SCENE_PATH := (
	"res://labs/terrain_lab/scenes/adversarial_corpus_observatory.tscn"
)
const DEFAULT_OUTPUT := (
	"res://labs/terrain_lab/results/adversarial_corpus_observatory_reference_windows.png"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		_fail("adversarial corpus observatory scene could not load")
		return
	var scene := packed.instantiate()
	scene.editor_case_index = int(_argument_value("--case-index", "0"))
	scene.editor_replay_mode = int(_argument_value("--replay-index", "0"))
	scene.editor_seed_override = int(_argument_value("--seed", "0"))
	root.add_child(scene)
	var image: Image
	var surface_samples := 0
	for frame in range(120):
		await process_frame
		await RenderingServer.frame_post_draw
		image = root.get_viewport().get_texture().get_image()
		surface_samples = _count_surface_samples(image)
		if frame >= 8 and surface_samples >= 250:
			break
	if image == null or image.is_empty():
		_fail("graphical viewport capture is unavailable")
		return
	if surface_samples < 250:
		_fail("adversarial native fixture is absent from capture")
		return
	var snapshot: Dictionary = scene.get_validation_snapshot()
	if str(snapshot.get("status", "")) != "PASS":
		_fail("adversarial observatory default case failed")
		return
	var output_path := _argument_value("--output", DEFAULT_OUTPUT)
	var error := image.save_png(output_path)
	if error != OK:
		_fail("could not save adversarial corpus capture: " + error_string(error))
		return
	print(
		"WT_TERRAIN_ADVERSARIAL_CORPUS_CAPTURE_PASS %s samples=%d"
		% [output_path, surface_samples]
	)
	quit(0)


static func _count_surface_samples(image: Image) -> int:
	if image == null or image.is_empty():
		return 0
	var count := 0
	var start_x := maxi(390, int(float(image.get_width()) * 0.31))
	for y in range(0, image.get_height(), 4):
		for x in range(start_x, image.get_width(), 4):
			var color := image.get_pixel(x, y)
			if color.g > 0.15 and color.g > color.r * 1.04:
				count += 1
	return count


func _argument_value(name: String, fallback: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size() - 1):
		if arguments[index] == name:
			return arguments[index + 1]
	return fallback


func _fail(message: String) -> void:
	push_error("WT_TERRAIN_ADVERSARIAL_CORPUS_CAPTURE_FAIL: " + message)
	quit(1)
