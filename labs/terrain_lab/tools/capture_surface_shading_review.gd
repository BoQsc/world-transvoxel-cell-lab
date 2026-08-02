extends SceneTree

const REVIEW_SCENE := "res://labs/terrain_lab/scenes/surface_shading_review.tscn"
const REPORT_PATH := (
	"res://labs/terrain_lab/results/surface_shading_review_automation_windows.json"
)
const CAPTURES := [
	{"id": "lit_motion", "mode": 0, "progress": 0.35, "lateral": 0.8},
	{"id": "mapped_normal", "mode": 2, "progress": 0.35, "lateral": 0.8},
	{"id": "triplanar_weights", "mode": 3, "progress": 0.35, "lateral": 0.8},
	{"id": "detail_fade", "mode": 8, "progress": 0.55, "lateral": -0.6},
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(REVIEW_SCENE) as PackedScene
	if packed == null:
		_fail("guided review scene could not load")
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	scene.call("_set_motion_enabled", false)
	var records: Array[Dictionary] = []
	var unique_hashes := {}
	var failures: Array[String] = []
	for capture in CAPTURES:
		scene.editor_diagnostic_mode = int(capture["mode"])
		scene.call("_apply_diagnostic_mode")
		scene.set_review_camera_progress(
			float(capture["progress"]),
			float(capture["lateral"])
		)
		for _warmup in range(6):
			await process_frame
			await RenderingServer.frame_post_draw
		var image := root.get_viewport().get_texture().get_image()
		var image_path := (
			"res://labs/terrain_lab/results/surface_shading_review_%s.png"
			% str(capture["id"])
		)
		if image == null or image.is_empty() or image.save_png(image_path) != OK:
			failures.append(str(capture["id"]) + " review capture could not be saved")
			continue
		var image_hash := FileAccess.get_sha256(image_path)
		unique_hashes[image_hash] = true
		var metrics := _image_metrics(image)
		if float(metrics.get("luminance_range", 0.0)) < 0.25:
			failures.append(str(capture["id"]) + " review capture lacks visible contrast")
		records.append({
			"id": str(capture["id"]),
			"diagnostic_mode": int(capture["mode"]),
			"camera_progress": float(capture["progress"]),
			"lateral_phase": float(capture["lateral"]),
			"image": image_path,
			"sha256": image_hash,
			"metrics": metrics,
		})
	if unique_hashes.size() != CAPTURES.size():
		failures.append("one or more guided review diagnostic captures are identical")
	var report := {
		"schema": "world_transvoxel.terrain_lab.surface_shading_review_automation.v1",
		"milestone": "TQP-23",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"review_scene": REVIEW_SCENE,
		"capture_contract": {
			"platform": OS.get_name(),
			"renderer": RenderingServer.get_current_rendering_method(),
			"driver": RenderingServer.get_current_rendering_driver_name(),
			"gpu": RenderingServer.get_video_adapter_name(),
			"godot": str(Engine.get_version_info().get("string", "")),
			"width": root.get_viewport().size.x,
			"height": root.get_viewport().size.y,
		},
		"captures": records,
		"unique_capture_hash_count": unique_hashes.size(),
		"formal_human_review": "PENDING",
		"failures": failures,
	}
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		_fail("could not open guided review automation report")
		return
	file.store_string(JSON.stringify(report, "\t", false) + "\n")
	print(JSON.stringify(report, "\t", false))
	if not failures.is_empty():
		_fail("guided review capture failed: " + str(failures))
		return
	print("WT_TERRAIN_SURFACE_REVIEW_CAPTURE_PASS")
	quit(0)


static func _image_metrics(image: Image) -> Dictionary:
	var minimum_luminance := 1.0
	var maximum_luminance := 0.0
	var colorful_samples := 0
	var sample_count := 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var color := image.get_pixel(x, y)
			var luminance := color.get_luminance()
			minimum_luminance = minf(minimum_luminance, luminance)
			maximum_luminance = maxf(maximum_luminance, luminance)
			if maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b)) > 0.12:
				colorful_samples += 1
			sample_count += 1
	return {
		"sample_count": sample_count,
		"luminance_min": minimum_luminance,
		"luminance_max": maximum_luminance,
		"luminance_range": maximum_luminance - minimum_luminance,
		"colorful_samples": colorful_samples,
	}


func _fail(message: String) -> void:
	push_error("WT_TERRAIN_SURFACE_REVIEW_CAPTURE_FAIL: " + message)
	quit(1)
