@tool
extends Control

const LabScript := preload("res://addons/world_transvoxel_cell_lab/lab/wt_transvoxel_cell_lab.gd")

var plugin: EditorPlugin
var _field_option: OptionButton
var _status_label: Label
var _copy_report_button: Button
var _save_repro_button: Button
var _report_sections: VBoxContainer
var _last_report_json := ""
var _last_saved_repro_path := ""


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

	var report_header := HBoxContainer.new()
	root.add_child(report_header)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.text = "No lab selected"
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report_header.add_child(_status_label)

	_copy_report_button = Button.new()
	_copy_report_button.text = "Copy Report JSON"
	_copy_report_button.disabled = true
	_copy_report_button.pressed.connect(_copy_report_json)
	report_header.add_child(_copy_report_button)

	_save_repro_button = Button.new()
	_save_repro_button.text = "Save Repro"
	_save_repro_button.disabled = true
	_save_repro_button.pressed.connect(_save_repro_snapshot)
	report_header.add_child(_save_repro_button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_report_sections = VBoxContainer.new()
	_report_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_report_sections)


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
		lab.benchmark_rebuild(24)
	_refresh_status()


func _refresh_status() -> void:
	if _status_label == null:
		return
	var lab = _selected_lab()
	if lab == null:
		_status_label.text = "No lab selected"
		_status_label.remove_theme_color_override("font_color")
		_last_report_json = ""
		if _copy_report_button != null:
			_copy_report_button.disabled = true
		if _save_repro_button != null:
			_save_repro_button.disabled = true
		_clear_report_sections()
		return
	_field_option.select(int(lab.field_mode))
	_render_report(lab.get_last_report())


func _copy_report_json() -> void:
	if _last_report_json.is_empty():
		return
	DisplayServer.clipboard_set(_last_report_json)
	_status_label.text = "%s | report JSON copied" % _status_label.text


func _render_report(report: Dictionary) -> void:
	_clear_report_sections()
	_last_report_json = JSON.stringify(_to_json_safe(report), "\t")
	if _copy_report_button != null:
		_copy_report_button.disabled = _last_report_json.is_empty()
	if _save_repro_button != null:
		_save_repro_button.disabled = false
	var status := str(report.get("status", "UNKNOWN"))
	_status_label.text = "Status: %s  Build: %.3f ms  Backend: %s" % [
		status,
		float(report.get("build_ms", 0.0)),
		str(report.get("backend_id", "")),
	]
	_status_label.add_theme_color_override("font_color", Color(0.35, 0.9, 0.55) if status == "PASS" else Color(1.0, 0.45, 0.35))

	var regular_status := "PASS"
	if int(report.get("failed_cells", 0)) > 0:
		regular_status = "FAIL"
	if int(report.get("interior_open_edges", 0)) > 0:
		regular_status = "FAIL"
	if int(report.get("nonmanifold_edges", 0)) > 0:
		regular_status = "FAIL"
	if int(report.get("orientation_conflict_edges", 0)) > 0:
		regular_status = "FAIL"

	var benchmark: Dictionary = report.get("benchmark", {})
	_add_section("Contract", [
		["Scope", report.get("lab_scope", "")],
		["Primary domain", report.get("primary_validation_domain", "")],
		["Primitive", report.get("primitive_scope", "")],
		["Authority", report.get("render_authority", "")],
		["Authority model", report.get("authority_model", "")],
		["Upstream policy", report.get("upstream_correction_policy", "")],
		["Integration role", report.get("integration_game_role", "")],
		["Integration policy", report.get("integration_game_diagnostic_policy", "")],
		["Dependency", report.get("validation_standard", "")],
	])
	_add_section("Regular Patch", [
		["Status", regular_status],
		["Cells", report.get("cells", Vector3i.ZERO)],
		["Active / empty / failed", "%d / %d / %d" % [
			int(report.get("active_cells", 0)),
			int(report.get("empty_cells", 0)),
			int(report.get("failed_cells", 0)),
		]],
		["Vertices / triangles", "%d / %d" % [
			int(report.get("vertices", 0)),
			int(report.get("triangles", 0)),
		]],
		["Interior open edges", report.get("interior_open_edges", 0)],
		["Boundary open edges", report.get("boundary_open_edges", 0)],
		["Nonmanifold edges", report.get("nonmanifold_edges", 0)],
		["Orientation conflicts", report.get("orientation_conflict_edges", 0)],
		["Degenerate triangles", report.get("degenerate_triangles", 0)],
		["Field / edits", "%s / %d" % [
			str(report.get("field_mode", "")),
			int(report.get("edit_count", 0)),
		]],
	])
	_add_section("Transition Cell", [
		["Status", report.get("transition_status", "Unavailable")],
		["Orientation", "%s (%d)" % [
			str(report.get("transition_orientation", "")),
			int(report.get("transition_orientation_index", -1)),
		]],
		["Case code", report.get("transition_case_code", -1)],
		["Vertices / triangles", "%d / %d" % [
			int(report.get("transition_vertices", 0)),
			int(report.get("transition_triangles", 0)),
		]],
		["Open edges", report.get("transition_open_edges", 0)],
		["Nonmanifold edges", report.get("transition_nonmanifold_edges", 0)],
		["Orientation conflicts", report.get("transition_orientation_conflict_edges", 0)],
	])
	_add_section("Production Chunk", [
		["Status", report.get("chunk_probe_status", "Unavailable")],
		["Implementation", report.get("chunk_probe_implementation", "")],
		["Cells / LOD", "%s / %d" % [
			str(report.get("chunk_probe_cells", Vector3i.ZERO)),
			int(report.get("chunk_probe_lod", 0)),
		]],
		["Samples", report.get("chunk_probe_samples", 0)],
		["Vertices / triangles", "%d / %d" % [
			int(report.get("chunk_probe_vertices", 0)),
			int(report.get("chunk_probe_triangles", 0)),
		]],
		["Open edges", report.get("chunk_probe_open_edges", 0)],
		["Nonmanifold edges", report.get("chunk_probe_nonmanifold_edges", 0)],
		["Orientation conflicts", report.get("chunk_probe_orientation_conflict_edges", 0)],
		["Error", report.get("chunk_probe_error", "")],
	])
	if not benchmark.is_empty():
		_add_section("Baseline", [
			["Iterations", benchmark.get("iterations", 0)],
			["Average build", "%.3f ms" % float(benchmark.get("average_build_ms", 0.0))],
			["Maximum build", "%.3f ms" % float(benchmark.get("maximum_build_ms", 0.0))],
			["Average triangles", benchmark.get("average_triangles", 0)],
		])
	if not _last_saved_repro_path.is_empty():
		_add_section("Repro", [
			["Last saved", _last_saved_repro_path],
		])


func _save_repro_snapshot() -> void:
	var lab = _selected_lab()
	if lab == null:
		_refresh_status()
		return
	var path := _write_repro_snapshot(lab.make_repro_snapshot())
	if path.is_empty():
		return
	_last_saved_repro_path = path
	_refresh_status()


func _write_repro_snapshot(snapshot: Dictionary) -> String:
	var dir_path := "user://world_transvoxel_cell_lab/repros"
	var absolute_dir_path := ProjectSettings.globalize_path(dir_path)
	var error := DirAccess.make_dir_recursive_absolute(absolute_dir_path)
	if error != OK:
		push_error("Could not create cell lab repro directory: %s" % absolute_dir_path)
		return ""
	var file_name := "cell_lab_repro_%d.json" % int(Time.get_unix_time_from_system())
	var path := "%s/%s" % [dir_path, file_name]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write cell lab repro: %s" % path)
		return ""
	file.store_string(JSON.stringify(_to_json_safe(snapshot), "\t"))
	file.close()
	return ProjectSettings.globalize_path(path)


func _add_section(title: String, rows: Array) -> void:
	if _report_sections == null:
		return
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 14)
	_report_sections.add_child(title_label)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_report_sections.add_child(grid)
	for row in rows:
		var key_label := Label.new()
		key_label.text = str(row[0])
		key_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		grid.add_child(key_label)

		var value_label := Label.new()
		value_label.text = _format_value(row[1])
		value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(value_label)


func _clear_report_sections() -> void:
	if _report_sections == null:
		return
	for child in _report_sections.get_children():
		child.queue_free()


func _format_value(value: Variant) -> String:
	match typeof(value):
		TYPE_FLOAT:
			return "%.3f" % float(value)
		TYPE_BOOL:
			return "true" if bool(value) else "false"
		_:
			return str(value)


func _to_json_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value
			var converted := {}
			for key in dictionary.keys():
				converted[str(key)] = _to_json_safe(dictionary[key])
			return converted
		TYPE_ARRAY:
			var array: Array = value
			var converted: Array = []
			for item in array:
				converted.append(_to_json_safe(item))
			return converted
		TYPE_VECTOR2:
			var vector2: Vector2 = value
			return {"x": vector2.x, "y": vector2.y}
		TYPE_VECTOR2I:
			var vector2i: Vector2i = value
			return {"x": vector2i.x, "y": vector2i.y}
		TYPE_VECTOR3:
			var vector3: Vector3 = value
			return {"x": vector3.x, "y": vector3.y, "z": vector3.z}
		TYPE_VECTOR3I:
			var vector3i: Vector3i = value
			return {"x": vector3i.x, "y": vector3i.y, "z": vector3i.z}
		TYPE_PACKED_INT32_ARRAY:
			var packed_ints: PackedInt32Array = value
			var converted: Array = []
			for item in packed_ints:
				converted.append(item)
			return converted
		TYPE_PACKED_FLOAT32_ARRAY:
			var packed_floats: PackedFloat32Array = value
			var converted: Array = []
			for item in packed_floats:
				converted.append(item)
			return converted
		TYPE_PACKED_VECTOR3_ARRAY:
			var packed_vectors: PackedVector3Array = value
			var converted: Array = []
			for item in packed_vectors:
				converted.append({"x": item.x, "y": item.y, "z": item.z})
			return converted
		TYPE_OBJECT:
			return str(value)
		_:
			return value
