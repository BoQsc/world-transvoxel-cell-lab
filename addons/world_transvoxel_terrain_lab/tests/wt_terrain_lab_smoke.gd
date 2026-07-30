extends SceneTree

const TerrainLabScript := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/wt_transvoxel_terrain_lab.gd"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ClassDB.class_exists("WorldTransvoxelCellProbe"):
		_fail("pinned world-transvoxel dependency is unavailable")
		return
	var terrain_lab := TerrainLabScript.new()
	root.add_child(terrain_lab)
	var validation: Dictionary = terrain_lab.validate_program_boundary()
	if str(validation.get("status", "")) != "PASS":
		_fail("terrain lab boundary failed: " + str(validation.get("failures", [])))
		return
	if int(validation.get("milestone_count", 0)) != 46:
		_fail("terrain program milestone count changed")
		return
	if int(validation.get("proposed_milestone_count", 0)) != 46:
		_fail("terrain milestone advanced without qualification")
		return
	var dependencies: Dictionary = validation.get("dependencies", {})
	if str(dependencies.get("status", "")) != "PASS":
		_fail("terrain lab dependency boundary failed")
		return
	print("WT_TERRAIN_LAB_SMOKE_PASS")
	terrain_lab.free()
	quit(0)


func _fail(message: String) -> void:
	push_error("WT_TERRAIN_LAB_SMOKE_FAIL: " + message)
	quit(1)
