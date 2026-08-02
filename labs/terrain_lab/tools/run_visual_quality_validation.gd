extends SceneTree

const VisualQualityQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_visual_quality_qualification.gd"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var result := VisualQualityQualification.run()
	print(JSON.stringify(result, "\t", false))
	if str(result.get("status", "")) != "PASS":
		push_error(
			"WT_TERRAIN_VISUAL_QUALITY_VALIDATION_FAIL: "
			+ str(result.get("failures", []))
		)
		quit(1)
		return
	print("WT_TERRAIN_VISUAL_QUALITY_VALIDATION_PASS")
	quit(0)
