extends SceneTree

const REVIEW_SCENE := "res://labs/terrain_lab/scenes/surface_shading_review.tscn"
const PROFILES := [
	{"id": "reference", "enabled": true},
	{"id": "disabled", "enabled": false},
	{"id": "short_range_4_split", "enabled": true, "mode": 2, "max_distance": 90.0, "blend": true},
	{"id": "orthogonal", "enabled": true, "mode": 0, "max_distance": 90.0},
	{"id": "soft_1_degree", "enabled": true, "angular_distance": 1.0},
	{"id": "low_bias", "enabled": true, "bias": 0.03, "normal_bias": 0.5},
	{
		"id": "tuned",
		"enabled": true,
		"mode": 2,
		"max_distance": 90.0,
		"blend": true,
		"angular_distance": 1.0,
		"bias": 0.05,
		"normal_bias": 1.0
	},
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(REVIEW_SCENE) as PackedScene
	if packed == null:
		_fail("surface review scene could not load")
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	scene.call("_set_motion_enabled", false)
	scene.editor_diagnostic_mode = 9
	scene.call("_apply_diagnostic_mode")
	scene.set_review_camera_progress(0.35, 0.8)
	scene.get_node("ReviewInterface").visible = false
	var sun := scene.get_node("TerrainObservatory/Sun") as DirectionalLight3D
	var reference := {
		"mode": sun.directional_shadow_mode,
		"max_distance": sun.directional_shadow_max_distance,
		"blend": sun.directional_shadow_blend_splits,
		"angular_distance": sun.light_angular_distance,
		"bias": sun.shadow_bias,
		"normal_bias": sun.shadow_normal_bias,
		"shadow_map_size": ProjectSettings.get_setting(
			"rendering/lights_and_shadows/directional_shadow/size",
			0
		),
	}
	var light_properties := {}
	for property in sun.get_property_list():
		var property_name := str(property.get("name", ""))
		if "shadow" in property_name or "angular" in property_name:
			light_properties[property_name] = sun.get(property_name)
	var output_directory := OS.get_temp_dir().path_join("tqp23_shadow_profiles")
	DirAccess.make_dir_recursive_absolute(output_directory)
	var records: Array[Dictionary] = []
	for profile in PROFILES:
		sun.shadow_enabled = bool(profile["enabled"])
		sun.directional_shadow_mode = int(profile.get("mode", reference["mode"]))
		sun.directional_shadow_max_distance = float(
			profile.get("max_distance", reference["max_distance"])
		)
		sun.directional_shadow_blend_splits = bool(profile.get("blend", reference["blend"]))
		sun.light_angular_distance = float(
			profile.get("angular_distance", reference["angular_distance"])
		)
		sun.shadow_bias = float(profile.get("bias", reference["bias"]))
		sun.shadow_normal_bias = float(profile.get("normal_bias", reference["normal_bias"]))
		for _warmup in range(8):
			await process_frame
			await RenderingServer.frame_post_draw
		var image := root.get_viewport().get_texture().get_image()
		var output_path := output_directory.path_join(str(profile["id"]) + ".png")
		if image == null or image.is_empty() or image.save_png(output_path) != OK:
			_fail("could not save shadow profile " + str(profile["id"]))
			return
		records.append({
			"id": str(profile["id"]),
			"image": output_path,
			"sha256": FileAccess.get_sha256(output_path),
			"shadow_enabled": sun.shadow_enabled,
			"shadow_mode": sun.directional_shadow_mode,
			"max_distance": sun.directional_shadow_max_distance,
			"blend_splits": sun.directional_shadow_blend_splits,
			"angular_distance": sun.light_angular_distance,
			"bias": sun.shadow_bias,
			"normal_bias": sun.shadow_normal_bias,
		})
	var report_path := output_directory.path_join("report.json")
	var report := {
		"schema": "world_transvoxel.terrain_lab.surface_shadow_investigation.v1",
		"status": "PASS",
		"reference": reference,
		"light_properties": light_properties,
		"captures": records,
	}
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		_fail("could not save shadow investigation report")
		return
	file.store_string(JSON.stringify(report, "\t", false) + "\n")
	print(JSON.stringify(report, "\t", false))
	print("WT_TERRAIN_SURFACE_SHADOW_INVESTIGATION_PASS " + report_path)
	quit(0)


func _fail(message: String) -> void:
	push_error("WT_TERRAIN_SURFACE_SHADOW_INVESTIGATION_FAIL: " + message)
	quit(1)
