extends SceneTree

const Catalog := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_visual_quality_catalog.gd"
)
const REVIEW_SCENE := "res://labs/terrain_lab/scenes/visual_quality_review.tscn"
const REPORT_PATH := (
	"res://labs/terrain_lab/results/visual_quality_corpus_reference_windows.json"
)
const FRAME_ROOT := "res://.godot/tqp25_frames"
const PIXEL_SAMPLE_STEP := 4


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var standard := Catalog.standard()
	var contract: Dictionary = standard.get("capture_contract", {})
	var failures: Array[String] = []
	if root.get_viewport().size != Vector2i(
		int(contract.get("width", 0)), int(contract.get("height", 0))
	):
		failures.append("viewport dimensions do not match the capture contract")
	var packed := load(REVIEW_SCENE) as PackedScene
	if packed == null:
		_fail("visual quality review scene could not load")
		return
	var scene := packed.instantiate()
	print("WT_TERRAIN_VISUAL_QUALITY_PROGRESS scene_add_start")
	root.add_child(scene)
	print("WT_TERRAIN_VISUAL_QUALITY_PROGRESS scene_add_complete")
	scene.set_capture_mode(true)
	scene.call("_set_motion_enabled", false)
	var frame_root_absolute := ProjectSettings.globalize_path(FRAME_ROOT)
	DirAccess.make_dir_recursive_absolute(frame_root_absolute)
	var records: Array[Dictionary] = []
	for fixture_value in standard.get("fixtures", []):
		var fixture: Dictionary = fixture_value
		var record := await _capture_fixture(scene, fixture, contract, failures)
		records.append(record)
	var report := {
		"schema": "world_transvoxel.terrain_lab.visual_quality_corpus_evidence.v1",
		"milestone": "TQP-25",
		"standard_id": str(standard.get("standard_id", "")),
		"status": "PENDING_VIDEO_ENCODING" if failures.is_empty() else "FAIL",
		"review_scene": REVIEW_SCENE,
		"review_contract": scene.get_review_contract(),
		"capture_contract": {
			"platform": OS.get_name(),
			"renderer": RenderingServer.get_current_rendering_method(),
			"driver": RenderingServer.get_current_rendering_driver_name(),
			"gpu": RenderingServer.get_video_adapter_name(),
			"godot": str(Engine.get_version_info().get("string", "")),
			"width": root.get_viewport().size.x,
			"height": root.get_viewport().size.y,
			"motion_frame_count": int(contract.get("motion_frame_count", 0)),
			"motion_fps": int(contract.get("motion_fps", 0)),
			"repeatability_passes": int(contract.get("repeatability_passes", 0)),
		},
		"fixtures": records,
		"finding": {
			"id": str((standard.get("finding_resolution", {}) as Dictionary).get("finding", "")),
			"status": "OPEN_PENDING_HUMAN_VISUAL_REVIEW",
			"automated_result_cannot_close_finding": true,
		},
		"formal_human_review": "PENDING",
		"qualification_status": "IMPLEMENTED_PENDING_HUMAN_VISUAL_ACCEPTANCE",
		"failures": failures,
	}
	_apply_formal_review(report, standard)
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		_fail("could not open visual quality evidence output")
		return
	file.store_string(JSON.stringify(report, "\t", false) + "\n")
	if not failures.is_empty():
		_fail("visual quality capture failed: " + str(failures))
		return
	print("WT_TERRAIN_VISUAL_QUALITY_CAPTURE_PASS")
	quit(0)


static func _apply_formal_review(report: Dictionary, standard: Dictionary) -> void:
	var review: Dictionary = standard.get("formal_review", {})
	if str(review.get("status", "")) != "ACCEPTED":
		return
	var decision := str(review.get("decision", ""))
	if not decision.ends_with("TQP-D015.json"):
		return
	report["formal_human_review"] = "ACCEPTED"
	report["qualification_status"] = "QUALIFIED_REFERENCE_VISUAL_QUALITY_CORPUS_V1"
	report["review_decision"] = decision
	report["human_review"] = review.duplicate(true)
	report["finding"] = {
		"id": "TQP-F001",
		"status": "CLOSED_BOUNDED_TQP25_ACCEPTANCE",
		"automated_result_cannot_close_finding": true,
		"closure_basis": decision,
		"closure_scope": "declared TQP-25 Windows reference visual-quality corpus",
	}


func _capture_fixture(
	scene: Node,
	fixture: Dictionary,
	contract: Dictionary,
	failures: Array[String]
) -> Dictionary:
	var fixture_id := str(fixture.get("id", ""))
	print("WT_TERRAIN_VISUAL_QUALITY_PROGRESS fixture_start " + fixture_id)
	var result := {"status": "PASS"}
	if scene.current_fixture_id() != fixture_id \
		or int((scene.get_geometry_evidence().get("metrics", {}) as Dictionary).get("triangle_count", 0)) <= 0:
		result = scene.set_fixture_by_id(fixture_id)
	print("WT_TERRAIN_VISUAL_QUALITY_PROGRESS fixture_configured " + fixture_id)
	if str(result.get("status", "FAIL")) != "PASS":
		failures.append(fixture_id + " native fixture did not build")
	for _warmup in range(8):
		await process_frame
		await RenderingServer.frame_post_draw
	print("WT_TERRAIN_VISUAL_QUALITY_PROGRESS fixture_warmed " + fixture_id)
	scene.set_shadows_enabled(true)
	scene.set_fixed_camera()
	var still_path := "res://labs/terrain_lab/results/visual_quality_%s.png" % fixture_id
	var still_hashes: Array[String] = []
	var still_metrics := {}
	for pass_index in range(int(contract.get("repeatability_passes", 2))):
		for _warmup in range(2):
			await process_frame
			await RenderingServer.frame_post_draw
		var image := root.get_viewport().get_texture().get_image()
		if image == null or image.is_empty():
			failures.append(fixture_id + " still capture is empty")
			continue
		var image_hash := _bytes_sha256(image.save_png_to_buffer())
		still_hashes.append(image_hash)
		if pass_index == 0:
			still_metrics = _image_metrics(image)
			if image.save_png(still_path) != OK:
				failures.append(fixture_id + " still could not be saved")
	if still_hashes.size() != int(contract.get("repeatability_passes", 2)) \
		or not _all_equal(still_hashes):
		failures.append(fixture_id + " still capture is not exactly repeatable")
	print("WT_TERRAIN_VISUAL_QUALITY_PROGRESS fixture_still " + fixture_id)
	var minimums: Dictionary = fixture.get("minimums", {})
	if int(still_metrics.get("surface_pixels", 0)) < int(minimums.get("surface_pixels", 0)):
		failures.append(fixture_id + " still lacks declared terrain coverage")
	if int(still_metrics.get("colorful_pixels", 0)) < int(minimums.get("colorful_pixels", 0)):
		failures.append(fixture_id + " still lacks declared color coverage")
	var geometry: Dictionary = scene.get_geometry_evidence()
	print("WT_TERRAIN_VISUAL_QUALITY_PROGRESS fixture_meshed " + fixture_id)
	_validate_geometry(fixture_id, geometry, minimums, failures)
	var motion := await _capture_motion(scene, fixture_id, contract, failures)
	var shadow_pair := {}
	if fixture_id == "adversarial":
		shadow_pair = await _capture_shadow_pair(scene, fixture_id, failures)
	return {
		"id": fixture_id,
		"configuration": {
			"sample_scale_m": float(fixture.get("sample_scale_m", 0.0)),
			"chunk_range_xz": int(fixture.get("chunk_range_xz", 0)),
			"chunk_y_max": int(fixture.get("chunk_y_max", 0)),
			"operation_count": (fixture.get("operations", []) as Array).size(),
		},
		"art_direction_target": fixture.get("art_direction_target", {}),
		"still": {
			"image": still_path,
			"sha256": still_hashes[0] if not still_hashes.is_empty() else "",
			"pass_sha256": still_hashes,
			"metrics": still_metrics,
		},
		"geometry": geometry,
		"motion": motion,
		"shadow_pair": shadow_pair,
		"video": {
			"path": "res://labs/terrain_lab/results/visual_quality_%s_motion.mp4" % fixture_id,
			"status": "PENDING_ENCODING",
		},
	}


func _capture_motion(
	scene: Node,
	fixture_id: String,
	contract: Dictionary,
	failures: Array[String]
) -> Dictionary:
	var frame_count := int(contract.get("motion_frame_count", 48))
	var repeatability_passes := int(contract.get("repeatability_passes", 2))
	var reference_hashes: Array[String] = []
	var pass_hashes: Array[Array] = []
	var temporal_differences: Array[float] = []
	var frame_directory := FRAME_ROOT + "/" + fixture_id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(frame_directory))
	for pass_index in range(repeatability_passes):
		var hashes: Array[String] = []
		var previous_image: Image = null
		for frame_index in range(frame_count):
			var path_progress := float(frame_index) / float(maxi(frame_count - 1, 1))
			scene.set_motion_path_progress(path_progress)
			await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_viewport().get_texture().get_image()
			if image == null or image.is_empty():
				failures.append("%s motion frame %d is empty" % [fixture_id, frame_index])
				continue
			var image_hash := _bytes_sha256(image.save_png_to_buffer())
			hashes.append(image_hash)
			if pass_index == 0:
				var frame_path := "%s/%03d.png" % [frame_directory, frame_index]
				if image.save_png(frame_path) != OK:
					failures.append("%s motion frame %d could not be saved" % [fixture_id, frame_index])
				if previous_image != null:
					temporal_differences.append(_image_difference(previous_image, image))
				previous_image = image
		if pass_index == 0:
			reference_hashes = hashes.duplicate()
		elif hashes != reference_hashes:
			failures.append(fixture_id + " motion frames differ between repeatability passes")
		pass_hashes.append(hashes)
	var unique_hashes := {}
	for image_hash in reference_hashes:
		unique_hashes[image_hash] = true
	if unique_hashes.size() < int(contract.get("minimum_unique_motion_frames", 40)):
		failures.append(fixture_id + " motion sequence lacks distinct viewpoints")
	var positive_differences := 0
	for difference in temporal_differences:
		if difference > 0.001:
			positive_differences += 1
	if positive_differences < maxi(1, temporal_differences.size() - 2):
		failures.append(fixture_id + " motion sequence contains static or near-static intervals")
	var sequence_hash := _text_sha256("\n".join(reference_hashes))
	var keyframes := {}
	for frame_index in [0, 12, 24, 36, frame_count - 1]:
		if frame_index >= 0 and frame_index < reference_hashes.size():
			keyframes[str(frame_index)] = reference_hashes[frame_index]
	return {
		"frame_count": reference_hashes.size(),
		"fps": int(contract.get("motion_fps", 24)),
		"sequence_sha256": sequence_hash,
		"repeatability_pass_sha256": [
			_text_sha256("\n".join(pass_hashes[0])) if pass_hashes.size() > 0 else "",
			_text_sha256("\n".join(pass_hashes[1])) if pass_hashes.size() > 1 else "",
		],
		"frame_sha256": reference_hashes,
		"keyframe_sha256": keyframes,
		"unique_frame_count": unique_hashes.size(),
		"adjacent_difference_min": temporal_differences.min() if not temporal_differences.is_empty() else 0.0,
		"adjacent_difference_max": temporal_differences.max() if not temporal_differences.is_empty() else 0.0,
		"adjacent_difference_mean": _mean(temporal_differences),
	}


func _capture_shadow_pair(
	scene: Node,
	fixture_id: String,
	failures: Array[String]
) -> Dictionary:
	scene.set_motion_phase(0.35)
	var images: Array[Image] = []
	var captures: Array[Dictionary] = []
	for enabled in [true, false]:
		scene.set_shadows_enabled(enabled)
		for _warmup in range(8):
			await process_frame
			await RenderingServer.frame_post_draw
		var image := root.get_viewport().get_texture().get_image()
		var state_id := "enabled" if enabled else "disabled"
		var path := "res://labs/terrain_lab/results/visual_quality_%s_shadow_%s.png" % [
			fixture_id, state_id
		]
		if image == null or image.is_empty() or image.save_png(path) != OK:
			failures.append(fixture_id + " shadow " + state_id + " capture failed")
			continue
		images.append(image)
		captures.append({
			"sun_shadows": enabled,
			"image": path,
			"sha256": FileAccess.get_sha256(path),
			"metrics": _image_metrics(image),
		})
	var difference := _image_difference(images[0], images[1]) if images.size() == 2 else 0.0
	if captures.size() != 2 or str(captures[0].get("sha256", "")) == str(captures[1].get("sha256", "")):
		failures.append(fixture_id + " shadow control images are not distinct")
	if difference < 0.002:
		failures.append(fixture_id + " shadow control has insufficient visible effect")
	scene.set_shadows_enabled(true)
	return {
		"motion_phase": 0.35,
		"captures": captures,
		"mean_absolute_difference": difference,
	}


static func _validate_geometry(
	fixture_id: String,
	geometry: Dictionary,
	minimums: Dictionary,
	failures: Array[String]
) -> void:
	var metrics: Dictionary = geometry.get("metrics", {})
	var seams: Dictionary = geometry.get("seams", {})
	var topology: Dictionary = geometry.get("topology", {})
	if int(metrics.get("triangle_count", 0)) < int(minimums.get("triangle_count", 0)):
		failures.append(fixture_id + " triangle count is below the fixture minimum")
	if int(metrics.get("surface_seam_pair_count", 0)) < int(minimums.get("surface_seam_pairs", 0)):
		failures.append(fixture_id + " does not exercise enough surface seam pairs")
	if int(metrics.get("seam_errors", -1)) != 0 or int(seams.get("failure_count", -1)) != 0:
		failures.append(fixture_id + " has native seam errors")
	if int(metrics.get("interior_open_edges", -1)) != 0 \
		or int(topology.get("interior_open_edge_count", -1)) != 0:
		failures.append(fixture_id + " has interior topology openings")
	if int(metrics.get("nonmanifold_edges", -1)) != 0 \
		or int(topology.get("nonmanifold_edge_count", -1)) != 0:
		failures.append(fixture_id + " has non-manifold topology")
	if str(metrics.get("geometry_signature", "")).length() != 64:
		failures.append(fixture_id + " lacks a native geometry signature")


static func _image_metrics(image: Image) -> Dictionary:
	var minimum_luminance := 1.0
	var maximum_luminance := 0.0
	var colorful_pixels := 0
	var surface_pixels := 0
	var sample_count := 0
	for y in range(0, image.get_height(), PIXEL_SAMPLE_STEP):
		for x in range(0, image.get_width(), PIXEL_SAMPLE_STEP):
			var color := image.get_pixel(x, y)
			var luminance := color.get_luminance()
			var chroma := maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b))
			minimum_luminance = minf(minimum_luminance, luminance)
			maximum_luminance = maxf(maximum_luminance, luminance)
			if chroma > 0.12:
				colorful_pixels += 1
			if color.g > color.r * 1.03 and color.g > color.b * 0.92 and luminance > 0.04:
				surface_pixels += 1
			sample_count += 1
	return {
		"sample_count": sample_count,
		"surface_pixels": surface_pixels,
		"colorful_pixels": colorful_pixels,
		"luminance_min": minimum_luminance,
		"luminance_max": maximum_luminance,
		"luminance_range": maximum_luminance - minimum_luminance,
	}


static func _image_difference(first: Image, second: Image) -> float:
	if first == null or second == null or first.get_size() != second.get_size():
		return 0.0
	var total := 0.0
	var count := 0
	for y in range(0, first.get_height(), PIXEL_SAMPLE_STEP):
		for x in range(0, first.get_width(), PIXEL_SAMPLE_STEP):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			total += (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
			count += 1
	return total / float(maxi(count, 1))


static func _all_equal(values: Array[String]) -> bool:
	if values.is_empty():
		return false
	for value in values:
		if value != values[0]:
			return false
	return true


static func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())


static func _bytes_sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


static func _text_sha256(value: String) -> String:
	return _bytes_sha256(value.to_utf8_buffer())


func _fail(message: String) -> void:
	push_error("WT_TERRAIN_VISUAL_QUALITY_CAPTURE_FAIL: " + message)
	quit(1)
