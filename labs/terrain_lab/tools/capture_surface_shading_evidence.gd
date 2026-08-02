extends SceneTree

const OBSERVATORY_SCENE := "res://labs/terrain_lab/scenes/terrain_observatory.tscn"
const OUTPUT_PATH := "res://labs/terrain_lab/results/surface_shading_evidence_windows.json"
const FRAMES_PER_PASS := 8
const PASSES_PER_CAMERA := 2


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var cameras := {}
	for camera_id in ["near", "far"]:
		var record := await _capture_camera(camera_id, failures)
		cameras[camera_id] = record
	var report := {
		"schema": "world_transvoxel.terrain_lab.surface_shading_evidence.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"capture_contract": {
			"platform": OS.get_name(),
			"renderer": RenderingServer.get_current_rendering_method(),
			"driver": RenderingServer.get_current_rendering_driver_name(),
			"gpu": RenderingServer.get_video_adapter_name(),
			"godot": str(Engine.get_version_info().get("string", "")),
			"width": root.get_viewport().size.x,
			"height": root.get_viewport().size.y,
		},
		"cameras": cameras,
		"human_review": {"status": "PENDING", "required_for": ["TQP-23"]},
		"failures": failures,
	}
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		_fail("could not open surface evidence output")
		return
	file.store_string(JSON.stringify(report, "\t", false) + "\n")
	print(JSON.stringify(report, "\t", false))
	if not failures.is_empty():
		_fail("surface shading capture failed: " + str(failures))
		return
	print("WT_TERRAIN_SURFACE_SHADING_CAPTURE_PASS")
	quit(0)


func _capture_camera(camera_id: String, failures: Array[String]) -> Dictionary:
	var pass_hashes: Array[String] = []
	var unique_frame_hashes := {}
	var retained_image: Image
	var pixel_metrics := {}
	for pass_index in range(PASSES_PER_CAMERA):
		var packed := load(OBSERVATORY_SCENE) as PackedScene
		var scene := packed.instantiate()
		root.add_child(scene)
		scene.call("prepare_surface_shading_capture", camera_id)
		for _warmup in range(12):
			await process_frame
			await RenderingServer.frame_post_draw
		var frame_hashes: Array[String] = []
		for _frame in range(FRAMES_PER_PASS):
			await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_viewport().get_texture().get_image()
			var frame_hash := _bytes_sha256(image.get_data())
			frame_hashes.append(frame_hash)
			unique_frame_hashes[frame_hash] = true
			if retained_image == null:
				retained_image = image
				pixel_metrics = _pixel_metrics(image)
		pass_hashes.append(frame_hashes[0] if not frame_hashes.is_empty() else "")
		scene.free()
		await process_frame
	var image_path := "res://labs/terrain_lab/results/surface_shading_%s.png" % camera_id
	if retained_image == null or retained_image.save_png(image_path) != OK:
		failures.append(camera_id + " surface image could not be saved")
	var image_hash := FileAccess.get_sha256(image_path) if FileAccess.file_exists(image_path) else ""
	var cold_warm_identity := pass_hashes.size() == 2 and pass_hashes[0] == pass_hashes[1]
	if unique_frame_hashes.size() != 1:
		failures.append(camera_id + " temporal frames are not byte-identical")
	if not cold_warm_identity:
		failures.append(camera_id + " cold/warm captures differ")
	if int(pixel_metrics.get("surface_pixels", 0)) < 400:
		failures.append(camera_id + " terrain surface is absent")
	if int(pixel_metrics.get("decal_pixels", 0)) < 8:
		failures.append(camera_id + " projected decal is absent")
	if int(pixel_metrics.get("wet_pixels", 0)) < 8:
		failures.append(camera_id + " wetness response is absent")
	return {
		"image": image_path,
		"sha256": image_hash,
		"pass_count": PASSES_PER_CAMERA,
		"frames_per_pass": FRAMES_PER_PASS,
		"pass_hashes": pass_hashes,
		"unique_frame_hash_count": unique_frame_hashes.size(),
		"cold_warm_identity": cold_warm_identity,
		"surface_pixels": int(pixel_metrics.get("surface_pixels", 0)),
		"decal_pixels": int(pixel_metrics.get("decal_pixels", 0)),
		"wet_pixels": int(pixel_metrics.get("wet_pixels", 0)),
	}


static func _pixel_metrics(image: Image) -> Dictionary:
	var surface_pixels := 0
	var decal_pixels := 0
	var wet_pixels := 0
	for y in range(0, image.get_height(), 3):
		for x in range(0, image.get_width(), 3):
			var color := image.get_pixel(x, y)
			if color.g > color.r * 1.04 and color.g > color.b * 1.04 and color.g > 0.34:
				surface_pixels += 1
			if color.r > 0.65 and color.g > 0.20 and color.g < 0.62 and color.b < 0.28:
				decal_pixels += 1
			if color.b > color.r * 1.05 and color.b > color.g * 0.92 and color.b > 0.18:
				wet_pixels += 1
	return {"surface_pixels": surface_pixels, "decal_pixels": decal_pixels, "wet_pixels": wet_pixels}


static func _bytes_sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _fail(message: String) -> void:
	push_error("WT_TERRAIN_SURFACE_SHADING_CAPTURE_FAIL: " + message)
	quit(1)
