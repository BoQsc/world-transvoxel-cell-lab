extends SceneTree

const REVIEW_SCENE := "res://labs/terrain_lab/scenes/surface_shading_review.tscn"
const OUTPUT_PATH := (
	"res://labs/terrain_lab/results/surface_shadow_resolution_evidence_windows.json"
)
const RESOLUTION_PROFILES := [
	{"id": "coarse_0_5m", "sample_scale_m": 0.5, "chunk_range_xz": 1, "chunk_y_max": 1},
	{"id": "fine_0_25m", "sample_scale_m": 0.25, "chunk_range_xz": 3, "chunk_y_max": 3},
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var records: Array[Dictionary] = []
	var unique_hashes := {}
	for profile in RESOLUTION_PROFILES:
		var record := await _capture_resolution(profile, failures, unique_hashes)
		records.append(record)
	if records.size() == 2:
		var coarse_triangles := int((records[0].get("mesh", {}) as Dictionary).get("triangle_count", 0))
		var fine_triangles := int((records[1].get("mesh", {}) as Dictionary).get("triangle_count", 0))
		if fine_triangles <= coarse_triangles:
			failures.append("fine shadow fixture did not increase native triangle resolution")
	if unique_hashes.size() != RESOLUTION_PROFILES.size() * 2:
		failures.append("shadow resolution/control captures are not distinct")
	var report := {
		"schema": "world_transvoxel.terrain_lab.surface_shadow_resolution_evidence.v1",
		"milestone": "TQP-23",
		"follow_up_milestone": "TQP-25",
		"finding": "TQP-F001",
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
		"resolution_profiles": records,
		"interpretation": {
			"automated_demonstrated": [
				"shadow-enabled and shadow-disabled captures are distinct at both resolutions",
				"halving native sample spacing increases native triangle count",
				"both native resolution fixtures retain zero seam and topology errors"
			],
			"reviewed_visual_interpretation": [
				"the stepped component is associated with the cast-shadow presentation",
				"the visible cast silhouette refines with the finer native fixture"
			],
			"not_demonstrated": [
				"production visual acceptability",
				"cross-hardware shadow stability",
				"all production LOD and lighting combinations"
			]
		},
		"failures": failures,
	}
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		_fail("could not open shadow resolution evidence output")
		return
	file.store_string(JSON.stringify(report, "\t", false) + "\n")
	print(JSON.stringify(report, "\t", false))
	if not failures.is_empty():
		_fail("shadow resolution evidence failed: " + str(failures))
		return
	print("WT_TERRAIN_SURFACE_SHADOW_RESOLUTION_PASS")
	quit(0)


func _capture_resolution(
	profile: Dictionary,
	failures: Array[String],
	unique_hashes: Dictionary
) -> Dictionary:
	var packed := load(REVIEW_SCENE) as PackedScene
	if packed == null:
		failures.append("guided review scene could not load")
		return {}
	var scene := packed.instantiate()
	var observatory: Node = scene.get_node("TerrainObservatory")
	observatory.editor_sample_scale_m = float(profile["sample_scale_m"])
	observatory.editor_chunk_range_xz = int(profile["chunk_range_xz"])
	observatory.editor_chunk_y_max = int(profile["chunk_y_max"])
	root.add_child(scene)
	scene.call("_set_motion_enabled", false)
	scene.editor_diagnostic_mode = 9
	scene.call("_apply_diagnostic_mode")
	scene.set_review_camera_progress(0.35, 0.8)
	scene.get_node("ReviewInterface").visible = false
	var sun := scene.get_node("TerrainObservatory/Sun") as DirectionalLight3D
	var captures: Array[Dictionary] = []
	for shadows_enabled in [true, false]:
		sun.shadow_enabled = shadows_enabled
		for _warmup in range(8):
			await process_frame
			await RenderingServer.frame_post_draw
		var image := root.get_viewport().get_texture().get_image()
		var state_id := "enabled" if shadows_enabled else "disabled"
		var image_path := (
			"res://labs/terrain_lab/results/surface_shadow_%s_%s.png"
			% [str(profile["id"]), state_id]
		)
		if image == null or image.is_empty() or image.save_png(image_path) != OK:
			failures.append("could not save " + str(profile["id"]) + " " + state_id)
			continue
		var image_hash := FileAccess.get_sha256(image_path)
		unique_hashes[image_hash] = true
		captures.append({
			"sun_shadows": shadows_enabled,
			"image": image_path,
			"sha256": image_hash,
		})
	var metrics: Dictionary = observatory.get_mesh_metrics()
	if int(metrics.get("seam_errors", -1)) != 0:
		failures.append(str(profile["id"]) + " has native seam errors")
	if int(metrics.get("interior_open_edges", -1)) != 0:
		failures.append(str(profile["id"]) + " has interior topology openings")
	if int(metrics.get("nonmanifold_edges", -1)) != 0:
		failures.append(str(profile["id"]) + " has nonmanifold topology")
	var record := {
		"id": str(profile["id"]),
		"sample_scale_m": float(profile["sample_scale_m"]),
		"chunk_range_xz": int(profile["chunk_range_xz"]),
		"chunk_y_max": int(profile["chunk_y_max"]),
		"mesh": {
			"chunk_count": int(metrics.get("chunk_count", 0)),
			"vertex_count": int(metrics.get("vertex_count", 0)),
			"triangle_count": int(metrics.get("triangle_count", 0)),
			"seam_errors": int(metrics.get("seam_errors", -1)),
			"interior_open_edges": int(metrics.get("interior_open_edges", -1)),
			"nonmanifold_edges": int(metrics.get("nonmanifold_edges", -1)),
		},
		"captures": captures,
	}
	scene.free()
	await process_frame
	return record


func _fail(message: String) -> void:
	push_error("WT_TERRAIN_SURFACE_SHADOW_RESOLUTION_FAIL: " + message)
	quit(1)
