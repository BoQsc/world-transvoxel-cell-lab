extends Node3D

const LabScript := preload("res://addons/world_transvoxel_cell_lab/lab/wt_transvoxel_cell_lab.gd")

@onready var lab: WtTransvoxelCellLab = $WtTransvoxelCellLab
@onready var status_label: Label = $Overlay/StatusLabel


func _ready() -> void:
	_update_status()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		match key.keycode:
			KEY_1:
				lab.field_mode = LabScript.FieldMode.PLANE
			KEY_2:
				lab.field_mode = LabScript.FieldMode.SPHERE
			KEY_3:
				lab.field_mode = LabScript.FieldMode.TUNNEL
			KEY_4:
				lab.field_mode = LabScript.FieldMode.SADDLE
			KEY_5:
				lab.field_mode = LabScript.FieldMode.WAVES
			KEY_X:
				lab.expand_cells("x", 1)
			KEY_Y:
				lab.expand_cells("y", 1)
			KEY_Z:
				lab.expand_cells("z", 1)
			KEY_D:
				lab.apply_dig_at(Vector3.ZERO)
			KEY_C:
				lab.apply_construct_at(Vector3.ZERO)
			KEY_R:
				lab.clear_edits()
			KEY_W:
				lab.wireframe = not lab.wireframe
				lab.rebuild()
		_update_status()


func _update_status() -> void:
	if lab == null or status_label == null:
		return
	var report := lab.get_last_report()
	status_label.text = "Render authority: %s\nClaim: %s\n%s\nWorldTransvoxelCellProbe is required; no fallback mesher is used.\nBoundary open edges are expected when a surface is cut by the finite patch.\n1-5 field  X/Y/Z expand  D dig  C construct  R reset  W wire" % [
		str(report.get("render_authority", "unknown")),
		str(report.get("correctness_claim", "unknown")),
		lab.get_status_line(),
	]
