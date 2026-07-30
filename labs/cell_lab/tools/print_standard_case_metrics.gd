extends SceneTree

const LabScript := preload("res://addons/world_transvoxel_cell_lab/lab/wt_transvoxel_cell_lab.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab := LabScript.new()
	root.add_child(lab)
	var cases: Array = []
	for case_code in [0, 1, 3, 15, 42, 90, 165, 254, 255]:
		var description: Dictionary = lab.describe_regular_case(case_code)
		var mesh: Dictionary = description.get("mesh", {})
		cases.append({
			"id": "regular_%03d" % case_code,
			"cell_type": "regular",
			"case_code": case_code,
			"status": mesh.get("status", "Unavailable"),
			"vertices": mesh.get("vertex_count", 0),
			"triangles": mesh.get("triangle_count", 0),
		})
	for case_code in [0, 1, 3, 17, 85, 170, 341, 510, 511]:
		for orientation in [0, 4, 5]:
			var description: Dictionary = lab.describe_transition_case(case_code, orientation)
			var mesh: Dictionary = description.get("mesh", {})
			cases.append({
				"id": "transition_%03d_o%d" % [case_code, orientation],
				"cell_type": "transition",
				"case_code": case_code,
				"orientation": orientation,
				"status": mesh.get("status", "Unavailable"),
				"vertices": mesh.get("vertex_count", 0),
				"triangles": mesh.get("triangle_count", 0),
			})
	print(JSON.stringify({"schema": "world_transvoxel.cell_lab.case_standards.v1", "cases": cases}, "\t"))
	lab.free()
	quit(0)
