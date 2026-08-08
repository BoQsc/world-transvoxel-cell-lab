extends SceneTree

const Evidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_complex_visual_evidence.gd"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var result := Evidence.validate_retained()
	print(JSON.stringify(result, "\t", false))
	if str(result.get("automation_status", "")) != "PASS":
		push_error("WT_TERRAIN_LAB_TQP44_FAIL " + str(result.get("failures", [])))
		quit(1)
		return
	print("WT_TERRAIN_LAB_TQP44_" + str(result.get("status", "")))
	quit(0)
