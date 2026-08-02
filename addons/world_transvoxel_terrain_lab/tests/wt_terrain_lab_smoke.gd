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
	if int(validation.get("qualified_milestone_count", 0)) != 17:
		_fail("qualified reference milestone count changed")
		return
	if int(validation.get("specified_milestone_count", 0)) != 2:
		_fail("open specification count changed")
		return
	if int(validation.get("proposed_milestone_count", -1)) != 0:
		_fail("one or more milestones lack a reviewed specification")
		return
	var status_counts: Dictionary = validation.get("status_counts", {})
	if int(status_counts.get("implemented", 0)) != 15:
		_fail("implemented evidence count changed")
		return
	if int(status_counts.get("blocked", 0)) != 12:
		_fail("fail-closed milestone count changed")
		return
	var dependencies: Dictionary = validation.get("dependencies", {})
	if str(dependencies.get("status", "")) != "PASS":
		_fail("terrain lab dependency boundary failed")
		return
	var foundation: Dictionary = validation.get("foundation", {})
	if str(foundation.get("status", "")) != "PASS":
		_fail("Gate A qualification failed: " + str(foundation.get("failures", [])))
		return
	var gates: Dictionary = validation.get("gate_statuses", {})
	if str(gates.get("GATE_A", "")) != "QUALIFIED":
		_fail("Gate A did not close as qualified")
		return
	if str(gates.get("GATE_B", "")) != "QUALIFIED":
		_fail("Gate B did not close as qualified")
		return
	for gate_name in ["GATE_C", "GATE_D"]:
		if str(gates.get(gate_name, "")) != "SPECIFIED":
			_fail(gate_name + " evidence state changed")
			return
	for gate_name in ["GATE_E", "GATE_F"]:
		if str(gates.get(gate_name, "")) != "CLOSED":
			_fail(gate_name + " must fail closed while blockers remain")
			return
	print("WT_TERRAIN_LAB_SMOKE_PASS")
	terrain_lab.free()
	quit(0)


func _fail(message: String) -> void:
	push_error("WT_TERRAIN_LAB_SMOKE_FAIL: " + message)
	quit(1)
