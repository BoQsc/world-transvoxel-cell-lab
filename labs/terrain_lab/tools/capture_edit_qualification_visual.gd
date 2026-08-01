extends SceneTree

const VisualEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_edit_visual_evidence.gd"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_path := "res://labs/terrain_lab/results/edit_qualification_reference.png"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("output="):
			output_path = argument.trim_prefix("output=")
	var image := VisualEvidence.build_image()
	var error := image.save_png(output_path)
	if error != OK:
		push_error("WT_TERRAIN_EDIT_VISUAL_CAPTURE_FAIL error=%d" % error)
		quit(1)
		return
	print("WT_TERRAIN_EDIT_VISUAL_CAPTURE_PASS path=%s signature=%s" % [
		output_path,
		VisualEvidence.pixel_signature(image),
	])
	quit(0)
