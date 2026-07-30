extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://labs/cell_lab/scenes/main.tscn")
	if scene == null:
		_fail("main scene could not be loaded")
		return
	var node: Node = scene.instantiate()
	root.add_child(node)
	await process_frame
	await process_frame
	await process_frame
	var texture := root.get_viewport().get_texture()
	if texture == null:
		_fail("viewport texture is unavailable; run this capture without --headless")
		return
	var image := texture.get_image()
	if image == null:
		_fail("viewport image is unavailable")
		return
	var output_path := "user://cell_lab_preview.png"
	var error := image.save_png(output_path)
	if error != OK:
		_fail("screenshot save failed: %d" % error)
		return
	var global_path := ProjectSettings.globalize_path(output_path)
	print("WT_CELL_LAB_CAPTURE_PASS path=%s size=%dx%d" % [
		global_path,
		image.get_width(),
		image.get_height(),
	])
	quit(0)


func _fail(message: String) -> void:
	push_error("WT_CELL_LAB_CAPTURE_FAIL: " + message)
	quit(1)
