@tool
extends EditorPlugin

const LabScript := preload("res://addons/world_transvoxel_cell_lab/lab/wt_transvoxel_cell_lab.gd")
const DockScript := preload("res://addons/world_transvoxel_cell_lab/editor/wt_cell_lab_dock.gd")

var _dock: Control


func _enter_tree() -> void:
	add_custom_type("WtTransvoxelCellLab", "Node3D", LabScript, null)
	_dock = DockScript.new()
	_dock.plugin = self
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	remove_custom_type("WtTransvoxelCellLab")
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.free()
		_dock = null
