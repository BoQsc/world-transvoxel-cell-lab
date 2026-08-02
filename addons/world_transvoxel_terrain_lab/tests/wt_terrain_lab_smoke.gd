extends SceneTree

const TerrainLabScript := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/wt_transvoxel_terrain_lab.gd"
)
const TerrainObservatoryScene := preload(
	"res://labs/terrain_lab/scenes/terrain_observatory.tscn"
)
const NativeEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_edit_native_evidence.gd"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ClassDB.class_exists("WorldTransvoxelCellProbe"):
		_fail("pinned world-transvoxel dependency is unavailable")
		return
	var observatory_script := load(
		"res://labs/terrain_lab/scenes/terrain_observatory.gd"
	) as Script
	if observatory_script == null or not observatory_script.is_tool():
		_fail("Terrain Observatory must execute as an editor tool")
		return
	var observatory_property_names := PackedStringArray()
	for property in observatory_script.get_script_property_list():
		observatory_property_names.append(str(property.get("name", "")))
	for required_property in [
		"editor_preview_enabled",
		"editor_auto_rebuild",
		"editor_show_chunk_bounds",
		"editor_rebuild_now",
		"editor_reset_now",
		"editor_dig_now",
		"editor_construct_now",
	]:
		if not observatory_property_names.has(required_property):
			_fail("Terrain Observatory editor contract lacks " + required_property)
			return
	var observatory := TerrainObservatoryScene.instantiate()
	root.add_child(observatory)
	var observatory_metrics: Dictionary = observatory.get_mesh_metrics()
	if int(observatory_metrics.get("chunk_count", 0)) <= 0:
		_fail("Terrain Observatory editor preview generated no native chunks")
		return
	if int(observatory_metrics.get("bounds_errors", -1)) != 0:
		_fail("Terrain Observatory editor preview has local bounds errors")
		return
	if int(observatory_metrics.get("surface_seam_pair_count", 0)) <= 0:
		_fail("Terrain Observatory canonical fixture exercises no surface seams")
		return
	if int(observatory_metrics.get("seam_errors", -1)) != 0:
		_fail(
			"Terrain Observatory canonical fixture has mismatched chunk seams: "
			+ str(observatory.get_seam_report())
		)
		return
	if int(observatory_metrics.get("interior_open_edges", -1)) != 0 \
			or int(observatory_metrics.get("nonmanifold_edges", -1)) != 0:
		_fail(
			"Terrain Observatory canonical fixture has invalid window topology: "
			+ str(observatory.get_topology_report())
		)
		return
	if not _window_topology_negative_control_passes():
		_fail("window topology audit did not detect an injected interior opening")
		return
	var canonical_edit_count := int(observatory_metrics.get("edit_count", 0))
	observatory.call("_apply_editor_operation", "dig")
	var edited_observatory_metrics: Dictionary = observatory.get_mesh_metrics()
	if int(edited_observatory_metrics.get("edit_count", 0)) != canonical_edit_count + 1:
		_fail("Terrain Observatory editor dig control did not rebuild the fixture")
		return
	observatory.call("_reset_field")
	if int(observatory.get_mesh_metrics().get("edit_count", 0)) != canonical_edit_count:
		_fail("Terrain Observatory editor reset did not restore the canonical fixture")
		return
	observatory.free()
	var terrain_lab := TerrainLabScript.new()
	root.add_child(terrain_lab)
	var validation: Dictionary = terrain_lab.validate_program_boundary()
	if str(validation.get("status", "")) != "PASS":
		_fail("terrain lab boundary failed: " + str(validation.get("failures", [])))
		return
	if int(validation.get("milestone_count", 0)) != 46:
		_fail("terrain program milestone count changed")
		return
	if int(validation.get("qualified_milestone_count", 0)) != 21:
		_fail("qualified reference milestone count changed")
		return
	if int(validation.get("specified_milestone_count", 0)) != 2:
		_fail("open specification count changed")
		return
	if int(validation.get("proposed_milestone_count", -1)) != 0:
		_fail("one or more milestones lack a reviewed specification")
		return
	var status_counts: Dictionary = validation.get("status_counts", {})
	if int(status_counts.get("implemented", 0)) != 11:
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
	print(
		"WT_TERRAIN_LAB_SMOKE_PASS topology="
		+ JSON.stringify(observatory_metrics)
	)
	terrain_lab.free()
	quit(0)


func _window_topology_negative_control_passes() -> bool:
	var vertices := PackedVector3Array([
		Vector3(4.0, 4.0, 4.0),
		Vector3(8.0, 4.0, 4.0),
		Vector3(6.0, 8.0, 4.0),
		Vector3(6.0, 6.0, 8.0),
	])
	var closed_chunk := {
		"ok": true,
		"lod": 0,
		"world_origin_x": 0.0,
		"world_origin_y": 0.0,
		"world_origin_z": 0.0,
		"regular": {
			"vertices": vertices,
			"indices": PackedInt32Array([
				0, 2, 1,
				0, 1, 3,
				1, 2, 3,
				2, 0, 3,
			]),
		},
	}
	var closed_report := NativeEvidence.same_lod_window_topology([closed_chunk])
	var open_chunk: Dictionary = closed_chunk.duplicate(true)
	open_chunk["regular"]["indices"] = PackedInt32Array([
		0, 2, 1,
		0, 1, 3,
		1, 2, 3,
	])
	var open_report := NativeEvidence.same_lod_window_topology([open_chunk])
	return (
		str(closed_report.get("status", "")) == "PASS"
		and str(open_report.get("status", "")) == "FAIL"
		and int(open_report.get("interior_open_edge_count", 0)) == 3
	)


func _fail(message: String) -> void:
	push_error("WT_TERRAIN_LAB_SMOKE_FAIL: " + message)
	quit(1)
