@tool
extends Control

const LabScript := preload("res://addons/world_transvoxel_cell_lab/lab/wt_transvoxel_cell_lab.gd")

var plugin: EditorPlugin
var _native_toggle: CheckBox
var _field_option: OptionButton
var _status_label: Label


func _ready() -> void:
	name = "World Transvoxel Lab"
	_build_ui()
	_refresh_status()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)

	var create_button := Button.new()
	create_button.text = "Create Lab"
	create_button.pressed.connect(_create_lab)
	root.add_child(create_button)

	_native_toggle = CheckBox.new()
	_native_toggle.text = "Exact backend"
	_native_toggle.button_pressed = true
	_native_toggle.toggled.connect(_set_native_backend)
	root.add_child(_native_toggle)

	_field_option = OptionButton.new()
	for name in LabScript.FieldMode.keys():
		_field_option.add_item(name.capitalize())
	_field_option.item_selected.connect(_set_field_mode)
	root.add_child(_field_option)

	var rebuild_button := Button.new()
	rebuild_button.text = "Rebuild"
	rebuild_button.pressed.connect(_rebuild_selected)
	root.add_child(rebuild_button)

	var grid := GridContainer.new()
	grid.columns = 3
	root.add_child(grid)
	for spec in [
		["-X", "x", -1],
		["+X", "x", 1],
		["-Y", "y", -1],
		["+Y", "y", 1],
		["-Z", "z", -1],
		["+Z", "z", 1],
	]:
		var button := Button.new()
		button.text = str(spec[0])
		button.pressed.connect(_expand_selected.bind(str(spec[1]), int(spec[2])))
		grid.add_child(button)

	var edit_row := HBoxContainer.new()
	root.add_child(edit_row)
	var dig_button := Button.new()
	dig_button.text = "Dig"
	dig_button.pressed.connect(_dig_selected)
	edit_row.add_child(dig_button)
	var construct_button := Button.new()
	construct_button.text = "Construct"
	construct_button.pressed.connect(_construct_selected)
	edit_row.add_child(construct_button)

	var reset_button := Button.new()
	reset_button.text = "Reset Edits"
	reset_button.pressed.connect(_reset_selected)
	root.add_child(reset_button)

	var benchmark_button := Button.new()
	benchmark_button.text = "Baseline"
	benchmark_button.pressed.connect(_benchmark_selected)
	root.add_child(benchmark_button)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.text = "No lab selected"
	root.add_child(_status_label)


func _selected_lab():
	if plugin == null:
		return null
	var selection := plugin.get_editor_interface().get_selection()
	for node in selection.get_selected_nodes():
		if node is WtTransvoxelCellLab:
			return node
	var root := plugin.get_editor_interface().get_edited_scene_root()
	if root == null:
		return null
	return _find_lab(root)


func _find_lab(node: Node):
	if node is WtTransvoxelCellLab:
		return node
	for child in node.get_children():
		var found = _find_lab(child)
		if found != null:
			return found
	return null


func _create_lab() -> void:
	if plugin == null:
		return
	var scene_root := plugin.get_editor_interface().get_edited_scene_root()
	if scene_root == null:
		push_error("Open or create a scene before adding a cell lab.")
		return
	var lab := LabScript.new()
	lab.name = "WtTransvoxelCellLab"
	scene_root.add_child(lab)
	lab.owner = scene_root
	lab.rebuild()
	var selection := plugin.get_editor_interface().get_selection()
	selection.clear()
	selection.add_node(lab)
	_refresh_status()


func _set_field_mode(index: int) -> void:
	var lab = _selected_lab()
	if lab == null:
		_refresh_status()
		return
	lab.field_mode = index
	lab.rebuild()
	_refresh_status()


func _set_native_backend(enabled: bool) -> void:
	var lab = _selected_lab()
	if lab == null:
		_refresh_status()
		return
	lab.prefer_native_cell_probe = enabled
	lab.rebuild()
	_refresh_status()


func _rebuild_selected() -> void:
	var lab = _selected_lab()
	if lab != null:
		lab.rebuild()
	_refresh_status()


func _expand_selected(axis: String, delta: int) -> void:
	var lab = _selected_lab()
	if lab != null:
		lab.expand_cells(axis, delta)
	_refresh_status()


func _dig_selected() -> void:
	var lab = _selected_lab()
	if lab != null:
		lab.apply_dig_at(Vector3.ZERO)
	_refresh_status()


func _construct_selected() -> void:
	var lab = _selected_lab()
	if lab != null:
		lab.apply_construct_at(Vector3.ZERO)
	_refresh_status()


func _reset_selected() -> void:
	var lab = _selected_lab()
	if lab != null:
		lab.clear_edits()
	_refresh_status()


func _benchmark_selected() -> void:
	var lab = _selected_lab()
	if lab != null:
		var result: Dictionary = lab.benchmark_rebuild(24)
		_status_label.text = "baseline avg=%.3fms max=%.3fms tris=%d" % [
			float(result.get("average_build_ms", 0.0)),
			float(result.get("maximum_build_ms", 0.0)),
			int(result.get("average_triangles", 0)),
		]
		return
	_refresh_status()


func _refresh_status() -> void:
	if _status_label == null:
		return
	var lab = _selected_lab()
	if lab == null:
		_status_label.text = "No lab selected"
		return
	_field_option.select(int(lab.field_mode))
	_native_toggle.button_pressed = bool(lab.prefer_native_cell_probe)
	_status_label.text = lab.get_status_line()
