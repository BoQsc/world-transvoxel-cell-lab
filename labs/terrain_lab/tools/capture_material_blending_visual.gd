extends SceneTree

const MaterialBlendingQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_material_blending_qualification.gd"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_path := "res://labs/terrain_lab/results/material_blending_reference.png"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("output="):
			output_path = argument.trim_prefix("output=")
	var image := MaterialBlendingQualification.build_visual_image()
	var error := image.save_png(output_path)
	if error != OK:
		push_error("WT_TQP18_VISUAL_CAPTURE_FAIL error=%d" % error)
		quit(1)
		return
	print("WT_TQP18_VISUAL_CAPTURE_PASS path=%s pixel_signature=%s file_sha256=%s" % [
		output_path,
		MaterialBlendingQualification.pixel_signature(image),
		FileAccess.get_sha256(output_path),
	])
	quit(0)
