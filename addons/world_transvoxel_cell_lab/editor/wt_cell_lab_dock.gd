@tool
extends Control

const LabScript := preload("res://addons/world_transvoxel_cell_lab/lab/wt_transvoxel_cell_lab.gd")
const Contracts := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_contracts.gd")
const ReproStore := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_repro_store.gd")

var plugin: EditorPlugin
var _field_option: OptionButton
var _inspection_option: OptionButton
var _regular_case_spin: SpinBox
var _transition_case_spin: SpinBox
var _transition_orientation_option: OptionButton
var _chunk_lod_spin: SpinBox
var _chunk_face_option: OptionButton
var _status_label: Label
var _copy_report_button: Button
var _save_repro_button: Button
var _report_sections: VBoxContainer
var _repro_name_edit: LineEdit
var _repro_notes_edit: LineEdit
var _repro_expected_option: OptionButton
var _repro_source_option: OptionButton
var _repro_browser: OptionButton
var _integration_path_edit: LineEdit
var _last_report_json := ""
var _last_saved_repro_path := ""
var _last_loaded_repro_path := ""


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

	var inspection_grid := GridContainer.new()
	inspection_grid.columns = 2
	root.add_child(inspection_grid)
	inspection_grid.add_child(_control_label("View"))
	_inspection_option = OptionButton.new()
	for mode_name in LabScript.InspectionMode.keys():
		_inspection_option.add_item(mode_name.capitalize())
	_inspection_option.item_selected.connect(_set_inspection_mode)
	inspection_grid.add_child(_inspection_option)

	inspection_grid.add_child(_control_label("Regular case"))
	_regular_case_spin = SpinBox.new()
	_regular_case_spin.min_value = 0
	_regular_case_spin.max_value = 255
	_regular_case_spin.step = 1
	_regular_case_spin.value_changed.connect(_set_regular_case)
	inspection_grid.add_child(_regular_case_spin)

	inspection_grid.add_child(_control_label("Transition case"))
	_transition_case_spin = SpinBox.new()
	_transition_case_spin.min_value = 0
	_transition_case_spin.max_value = 511
	_transition_case_spin.step = 1
	_transition_case_spin.value_changed.connect(_set_transition_case)
	inspection_grid.add_child(_transition_case_spin)

	inspection_grid.add_child(_control_label("Orientation"))
	_transition_orientation_option = OptionButton.new()
	for orientation_name in Contracts.TRANSITION_ORIENTATION_NAMES:
		_transition_orientation_option.add_item(orientation_name)
	_transition_orientation_option.item_selected.connect(_set_transition_orientation)
	inspection_grid.add_child(_transition_orientation_option)

	inspection_grid.add_child(_control_label("Coarse LOD"))
	_chunk_lod_spin = SpinBox.new()
	_chunk_lod_spin.min_value = 1
	_chunk_lod_spin.max_value = 3
	_chunk_lod_spin.step = 1
	_chunk_lod_spin.value_changed.connect(_set_chunk_lod)
	inspection_grid.add_child(_chunk_lod_spin)

	inspection_grid.add_child(_control_label("Chunk face"))
	_chunk_face_option = OptionButton.new()
	for face_name in Contracts.CHUNK_FACE_NAMES:
		_chunk_face_option.add_item(face_name)
	_chunk_face_option.item_selected.connect(_set_chunk_face)
	inspection_grid.add_child(_chunk_face_option)

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

	var validator_row := GridContainer.new()
	validator_row.columns = 2
	root.add_child(validator_row)
	var regular_corpus_button := Button.new()
	regular_corpus_button.text = "Regular Corpus"
	regular_corpus_button.pressed.connect(_validate_regular_corpus_selected)
	validator_row.add_child(regular_corpus_button)
	var transition_corpus_button := Button.new()
	transition_corpus_button.text = "Transition Corpus"
	transition_corpus_button.pressed.connect(_validate_transition_corpus_selected)
	validator_row.add_child(transition_corpus_button)
	var chunk_lod_button := Button.new()
	chunk_lod_button.text = "Chunk LOD"
	chunk_lod_button.pressed.connect(_validate_chunk_lod_selected)
	validator_row.add_child(chunk_lod_button)
	var edit_sequence_button := Button.new()
	edit_sequence_button.text = "Edit Sequence"
	edit_sequence_button.pressed.connect(_validate_edit_sequence_selected)
	validator_row.add_child(edit_sequence_button)
	var edit_corpus_button := Button.new()
	edit_corpus_button.text = "Edit Corpus"
	edit_corpus_button.pressed.connect(_validate_edit_corpus_selected)
	validator_row.add_child(edit_corpus_button)
	var performance_button := Button.new()
	performance_button.text = "Performance"
	performance_button.pressed.connect(_run_performance_baselines_selected)
	validator_row.add_child(performance_button)
	var standards_button := Button.new()
	standards_button.text = "Standards Corpus"
	standards_button.pressed.connect(_validate_standards_selected)
	validator_row.add_child(standards_button)
	var validate_all_button := Button.new()
	validate_all_button.text = "Run Full Suite"
	validate_all_button.pressed.connect(_validate_all_selected)
	validator_row.add_child(validate_all_button)

	var repro_grid := GridContainer.new()
	repro_grid.columns = 2
	root.add_child(repro_grid)
	repro_grid.add_child(_control_label("Repro name"))
	_repro_name_edit = LineEdit.new()
	_repro_name_edit.placeholder_text = "cell_lab_repro"
	repro_grid.add_child(_repro_name_edit)
	repro_grid.add_child(_control_label("Notes"))
	_repro_notes_edit = LineEdit.new()
	repro_grid.add_child(_repro_notes_edit)
	repro_grid.add_child(_control_label("Expected"))
	_repro_expected_option = OptionButton.new()
	for label in Contracts.EXPECTED_LABELS:
		_repro_expected_option.add_item(label.capitalize())
		_repro_expected_option.set_item_metadata(_repro_expected_option.item_count - 1, label)
	_repro_expected_option.select(Contracts.EXPECTED_LABELS.find("investigation"))
	repro_grid.add_child(_repro_expected_option)
	repro_grid.add_child(_control_label("Source layer"))
	_repro_source_option = OptionButton.new()
	for source_layer in Contracts.SOURCE_LAYERS:
		_repro_source_option.add_item(source_layer.capitalize())
		_repro_source_option.set_item_metadata(_repro_source_option.item_count - 1, source_layer)
	repro_grid.add_child(_repro_source_option)
	repro_grid.add_child(_control_label("Repro browser"))
	_repro_browser = OptionButton.new()
	repro_grid.add_child(_repro_browser)
	var repro_actions := HBoxContainer.new()
	var refresh_repros_button := Button.new()
	refresh_repros_button.text = "Refresh"
	refresh_repros_button.pressed.connect(_refresh_repro_browser)
	repro_actions.add_child(refresh_repros_button)
	var load_repro_button := Button.new()
	load_repro_button.text = "Load"
	load_repro_button.pressed.connect(_load_selected_repro_snapshot)
	repro_actions.add_child(load_repro_button)
	repro_grid.add_child(repro_actions)
	repro_grid.add_child(_control_label("Integration JSON"))
	_integration_path_edit = LineEdit.new()
	_integration_path_edit.placeholder_text = "Path to integration snapshot"
	repro_grid.add_child(_integration_path_edit)
	var import_spacer := Control.new()
	repro_grid.add_child(import_spacer)
	var import_button := Button.new()
	import_button.text = "Import Snapshot"
	import_button.pressed.connect(_import_integration_snapshot)
	repro_grid.add_child(import_button)

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
	_refresh_repro_browser()


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


func _set_inspection_mode(index: int) -> void:
	var lab = _selected_lab()
	if lab == null:
		return
	lab.inspection_mode = index
	lab.rebuild()
	_refresh_status()


func _set_regular_case(value: float) -> void:
	var lab = _selected_lab()
	if lab == null:
		return
	lab.selected_regular_case = roundi(value)
	if lab.inspection_mode == LabScript.InspectionMode.REGULAR_CASE:
		lab.rebuild()
	_refresh_status()


func _set_transition_case(value: float) -> void:
	var lab = _selected_lab()
	if lab == null:
		return
	lab.selected_transition_case = roundi(value)
	if lab.inspection_mode == LabScript.InspectionMode.TRANSITION_CASE:
		lab.rebuild()
	_refresh_status()


func _set_transition_orientation(index: int) -> void:
	var lab = _selected_lab()
	if lab == null:
		return
	lab.selected_transition_orientation = index
	if lab.inspection_mode == LabScript.InspectionMode.TRANSITION_CASE:
		lab.rebuild()
	_refresh_status()


func _set_chunk_lod(value: float) -> void:
	var lab = _selected_lab()
	if lab == null:
		return
	lab.selected_chunk_lod = roundi(value)
	if lab.inspection_mode == LabScript.InspectionMode.MIXED_LOD:
		lab.rebuild()
	_refresh_status()


func _set_chunk_face(index: int) -> void:
	var lab = _selected_lab()
	if lab == null:
		return
	lab.selected_chunk_face = index
	if lab.inspection_mode == LabScript.InspectionMode.MIXED_LOD:
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


func _validate_regular_corpus_selected() -> void:
	var lab = _selected_lab()
	if lab != null:
		lab.validate_regular_case_corpus()
	_refresh_status()


func _validate_transition_corpus_selected() -> void:
	var lab = _selected_lab()
	if lab != null:
		lab.validate_transition_case_corpus()
	_refresh_status()


func _validate_chunk_lod_selected() -> void:
	var lab = _selected_lab()
	if lab != null:
		lab.validate_chunk_lod_seams()
	_refresh_status()


func _validate_edit_sequence_selected() -> void:
	var lab = _selected_lab()
	if lab != null:
		lab.validate_edit_sequence()
	_refresh_status()


func _validate_edit_corpus_selected() -> void:
	var lab = _selected_lab()
	if lab != null:
		lab.validate_edit_corpus()
	_refresh_status()


func _validate_standards_selected() -> void:
	var lab = _selected_lab()
	if lab != null:
		lab.validate_standards_corpus()
	_refresh_status()


func _validate_all_selected() -> void:
	var lab = _selected_lab()
	if lab == null:
		return
	lab.validate_regular_case_corpus()
	lab.validate_transition_case_corpus()
	lab.validate_chunk_lod_seams()
	lab.validate_edit_sequence()
	lab.validate_edit_corpus()
	lab.validate_standards_corpus()
	lab.run_performance_baselines(3)
	_refresh_status()


func _run_performance_baselines_selected() -> void:
	var lab = _selected_lab()
	if lab != null:
		lab.run_performance_baselines(3)
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
	_inspection_option.select(int(lab.inspection_mode))
	_regular_case_spin.set_value_no_signal(float(lab.selected_regular_case))
	_transition_case_spin.set_value_no_signal(float(lab.selected_transition_case))
	_transition_orientation_option.select(int(lab.selected_transition_orientation))
	_chunk_lod_spin.set_value_no_signal(float(lab.selected_chunk_lod))
	_chunk_face_option.select(int(lab.selected_chunk_face))
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
	var inspection: Dictionary = report.get("inspection", {})
	if not inspection.is_empty():
		_add_section("Inspection", [
			["Mode", inspection.get("mode", report.get("inspection_mode", "PATCH"))],
			["Status", inspection.get("status", "Unavailable")],
			["Case", inspection.get("case_code", "")],
			["Binary", inspection.get("case_code_binary", "")],
			["Orientation", inspection.get("orientation", "")],
			["LOD", "%s -> %s" % [
				str(inspection.get("coarse_lod", "")),
				str(inspection.get("fine_lod", "")),
			]],
			["Face", inspection.get("face", "")],
			["Vertices / triangles", "%s / %s" % [
				str(inspection.get("vertices", "")),
				str(inspection.get("triangles", "")),
			]],
			["Endpoint provenance", inspection.get("backend_endpoint_provenance", [])],
			["Seam comparison", inspection.get("comparison", {})],
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
		["Affected cells", report.get("affected_cell_count", 0)],
		["Dirty region", report.get("dirty_region", AABB())],
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
	var regular_corpus: Dictionary = report.get("regular_case_corpus", {})
	if not regular_corpus.is_empty():
		_add_section("Regular Corpus", [
			["Status", regular_corpus.get("status", "Unavailable")],
			["Cases", regular_corpus.get("case_count", 0)],
			["Ok / empty / failed", "%d / %d / %d" % [
				int(regular_corpus.get("ok_cases", 0)),
				int(regular_corpus.get("empty_cases", 0)),
				int(regular_corpus.get("failed_cases", 0)),
			]],
			["Expected empty mismatches", regular_corpus.get("expected_empty_mismatches", 0)],
			["Determinism failures", regular_corpus.get("determinism_failures", 0)],
			["Buffer failures", regular_corpus.get("buffer_failures", 0)],
			["Vertices / triangles", "%d / %d" % [
				int(regular_corpus.get("total_vertices", 0)),
				int(regular_corpus.get("total_triangles", 0)),
			]],
			["Elapsed", "%.3f ms" % float(regular_corpus.get("elapsed_ms", 0.0))],
			["Sample failures", _format_sample_failures(regular_corpus.get("sample_failures", []))],
		])
	var transition_corpus: Dictionary = report.get("transition_case_corpus", {})
	if not transition_corpus.is_empty():
		_add_section("Transition Corpus", [
			["Status", transition_corpus.get("status", "Unavailable")],
			["Cases / orientations / probes", "%d / %d / %d" % [
				int(transition_corpus.get("case_count", 0)),
				int(transition_corpus.get("orientation_count", 0)),
				int(transition_corpus.get("probe_count", 0)),
			]],
			["Ok / empty / failed", "%d / %d / %d" % [
				int(transition_corpus.get("ok_cases", 0)),
				int(transition_corpus.get("empty_cases", 0)),
				int(transition_corpus.get("failed_cases", 0)),
			]],
			["Expected empty mismatches", transition_corpus.get("expected_empty_mismatches", 0)],
			["Orientation status mismatches", transition_corpus.get("orientation_status_mismatches", 0)],
			["Orientation count mismatches", transition_corpus.get("orientation_count_mismatches", 0)],
			["Determinism failures", transition_corpus.get("determinism_failures", 0)],
			["Buffer failures", transition_corpus.get("buffer_failures", 0)],
			["Bounds failures", transition_corpus.get("bounds_failures", 0)],
			["Vertices / triangles", "%d / %d" % [
				int(transition_corpus.get("total_vertices", 0)),
				int(transition_corpus.get("total_triangles", 0)),
			]],
			["Elapsed", "%.3f ms" % float(transition_corpus.get("elapsed_ms", 0.0))],
			["Sample failures", _format_sample_failures(transition_corpus.get("sample_failures", []))],
		])
	var chunk_lod: Dictionary = report.get("chunk_lod_validation", {})
	if not chunk_lod.is_empty():
		_add_section("Chunk LOD", [
			["Status", chunk_lod.get("status", "Unavailable")],
			["Same LOD pairs", "%d / %d matching" % [
				int(chunk_lod.get("same_lod_matching_pairs", 0)),
				int(chunk_lod.get("same_lod_pairs", 0)),
			]],
			["Same LOD mismatches", chunk_lod.get("same_lod_mismatched_pairs", 0)],
			["Left / right only seam edges", "%d / %d" % [
				int(chunk_lod.get("same_lod_left_only_edges", 0)),
				int(chunk_lod.get("same_lod_right_only_edges", 0)),
			]],
			["LOD transition status", chunk_lod.get("lod_transition_probe_status", "Unavailable")],
			["LOD transition faces", chunk_lod.get("lod_transition_faces_with_geometry", 0)],
			["LOD transition triangles", chunk_lod.get("lod_transition_triangles", 0)],
			["LOD transition nonmanifold", chunk_lod.get("lod_transition_nonmanifold_edges", 0)],
			["LOD transition orientation", chunk_lod.get("lod_transition_orientation_conflict_edges", 0)],
			["Mixed LOD pairs", "%d / %d matching" % [
				int(chunk_lod.get("mixed_lod_matching_pairs", 0)),
				int(chunk_lod.get("mixed_lod_pairs", 0)),
			]],
			["Mixed LOD mismatches", chunk_lod.get("mixed_lod_mismatched_pairs", 0)],
			["Coarse / fine only edges", "%d / %d" % [
				int(chunk_lod.get("mixed_lod_coarse_only_edges", 0)),
				int(chunk_lod.get("mixed_lod_fine_only_edges", 0)),
			]],
			["Visible cracks", chunk_lod.get("visible_crack_count", 0)],
			["Mixed LOD scope", chunk_lod.get("mixed_lod_scope", "")],
			["Elapsed", "%.3f ms" % float(chunk_lod.get("elapsed_ms", 0.0))],
			["Sample failures", _format_sample_failures(chunk_lod.get("sample_failures", []))],
		])
	var edit_sequence: Dictionary = report.get("edit_sequence_validation", {})
	if not edit_sequence.is_empty():
		_add_section("Edit Sequence", [
			["Status", edit_sequence.get("status", "Unavailable")],
			["Passing / failing steps", "%d / %d" % [
				int(edit_sequence.get("passing_steps", 0)),
				int(edit_sequence.get("failing_steps", 0)),
			]],
			["Triangle counts", edit_sequence.get("triangle_counts", [])],
			["Edit counts", edit_sequence.get("edit_counts", [])],
			["Affected cells", edit_sequence.get("affected_cell_counts", [])],
			["Step deltas", edit_sequence.get("step_deltas", [])],
			["Material IDs", edit_sequence.get("material_ids", [])],
			["Determinism failures", edit_sequence.get("determinism_failures", 0)],
			["Elapsed", "%.3f ms" % float(edit_sequence.get("elapsed_ms", 0.0))],
			["Sample failures", _format_sample_failures(edit_sequence.get("sample_failures", []))],
		])
	var edit_corpus: Dictionary = report.get("edit_corpus", {})
	if not edit_corpus.is_empty():
		_add_section("Edit Corpus", [
			["Status", edit_corpus.get("status", "Unavailable")],
			["Passing / failing fixtures", "%d / %d" % [
				int(edit_corpus.get("passing_fixtures", 0)),
				int(edit_corpus.get("failing_fixtures", 0)),
			]],
			["Fixtures", edit_corpus.get("fixtures", [])],
			["Elapsed", "%.3f ms" % float(edit_corpus.get("elapsed_ms", 0.0))],
			["Sample failures", _format_sample_failures(edit_corpus.get("sample_failures", []))],
		])
	var performance: Dictionary = report.get("performance_baselines", {})
	if not performance.is_empty():
		_add_section("Performance", [
			["Status", performance.get("status", "Unavailable")],
			["Iterations", performance.get("iterations", 0)],
			["Patch rebuild avg / max", "%.3f / %.3f ms" % [
				float(performance.get("patch_rebuild_average_ms", 0.0)),
				float(performance.get("patch_rebuild_maximum_ms", 0.0)),
			]],
			["Regular / transition cell", "%.3f / %.3f us" % [
				float(performance.get("regular_cell_average_us", 0.0)),
				float(performance.get("transition_cell_average_us", 0.0)),
			]],
			["Chunk average", "%.3f ms" % float(performance.get("chunk_average_ms", 0.0))],
			["Edit rebuild average", "%.3f ms" % float(performance.get("edit_rebuild_average_ms", 0.0))],
			["Triangles / ms", performance.get("triangles_per_ms", 0.0)],
			["Samples / ms", performance.get("samples_per_ms", 0.0)],
			["Edit rebuild cost", "%.3f ms" % float(performance.get("edit_rebuild_cost_ms", 0.0))],
			["Chunk LOD validation", "%.3f ms" % float(performance.get("chunk_lod_validation_ms", 0.0))],
			["Edit sequence validation", "%.3f ms" % float(performance.get("edit_sequence_validation_ms", 0.0))],
			["Regular corpus", "%.3f ms" % float(performance.get("regular_case_corpus_ms", 0.0))],
			["Transition corpus", "%.3f ms" % float(performance.get("transition_case_corpus_ms", 0.0))],
			["Regression warnings", performance.get("regression_warnings", [])],
			["History entries", performance.get("history_count", 0)],
		])
	var standards: Dictionary = report.get("standards_corpus", {})
	if not standards.is_empty():
		_add_section("Standards Corpus", [
			["Status", standards.get("status", "Unavailable")],
			["Repros pass / fail", "%d / %d" % [
				int(standards.get("passing_repros", 0)),
				int(standards.get("failing_repros", 0)),
			]],
			["Cases pass / fail", "%d / %d" % [
				int(standards.get("passing_case_standards", 0)),
				int(standards.get("failing_case_standards", 0)),
			]],
			["Visuals pass / fail", "%d / %d" % [
				int(standards.get("passing_visual_standards", 0)),
				int(standards.get("failing_visual_standards", 0)),
			]],
			["Elapsed", "%.3f ms" % float(standards.get("elapsed_ms", 0.0))],
			["Sample failures", _format_sample_failures(standards.get("sample_failures", []))],
		])
	var integration: Dictionary = report.get("integration_comparison", {})
	if not integration.is_empty():
		_add_section("Integration Reduction", [
			["Lab status", integration.get("lab_status", "UNKNOWN")],
			["Source artifact", integration.get("source_reports_artifact", false)],
			["Suspected layer", integration.get("suspected_fix_layer", "none")],
			["Reason", integration.get("reason", "")],
		])
	if not _last_saved_repro_path.is_empty():
		_add_section("Repro", [
			["Last saved", _last_saved_repro_path],
		])
	if not _last_loaded_repro_path.is_empty():
		_add_section("Loaded Repro", [
			["Last loaded", _last_loaded_repro_path],
		])


func _save_repro_snapshot() -> void:
	var lab = _selected_lab()
	if lab == null:
		_refresh_status()
		return
	var metadata := {
		"name": _repro_name_edit.text if not _repro_name_edit.text.is_empty() else "cell_lab_repro",
		"notes": _repro_notes_edit.text,
		"expected_label": str(_repro_expected_option.get_selected_metadata()),
		"source_layer": str(_repro_source_option.get_selected_metadata()),
	}
	var saved: Dictionary = lab.save_repro_snapshot(metadata)
	if not bool(saved.get("ok", false)):
		push_error("Could not save cell lab repro: %s" % str(saved.get("error", "unknown")))
		return
	_last_saved_repro_path = str(saved.get("absolute_path", saved.get("path", "")))
	_refresh_repro_browser()
	_refresh_status()


func _load_selected_repro_snapshot() -> void:
	var lab = _selected_lab()
	if lab == null:
		_refresh_status()
		return
	var path := ""
	if _repro_browser != null and _repro_browser.selected >= 0:
		path = str(_repro_browser.get_item_metadata(_repro_browser.selected))
	if path.is_empty():
		push_error("No cell lab repro selected.")
		return
	var loaded: Dictionary = lab.load_repro_snapshot(path)
	if not bool(loaded.get("ok", false)):
		push_error("Could not load cell lab repro: %s" % str(loaded.get("error", "unknown")))
		return
	_last_loaded_repro_path = ProjectSettings.globalize_path(path)
	_refresh_status()


func _refresh_repro_browser() -> void:
	if _repro_browser == null:
		return
	_repro_browser.clear()
	for entry in ReproStore.list_repros(true):
		var metadata: Dictionary = entry.get("metadata", {})
		var prefix := "[standard] " if bool(entry.get("committed", false)) else ""
		var label := prefix + str(metadata.get("name", entry.get("file_name", "repro")))
		_repro_browser.add_item(label)
		_repro_browser.set_item_metadata(
			_repro_browser.item_count - 1,
			str(entry.get("path", ""))
		)


func _import_integration_snapshot() -> void:
	var lab = _selected_lab()
	if lab == null:
		return
	var path := _integration_path_edit.text.strip_edges()
	if path.is_empty():
		push_error("Choose an integration snapshot JSON path.")
		return
	var result: Dictionary = lab.import_integration_snapshot_file(path)
	if not bool(result.get("ok", false)):
		push_error("Could not import integration snapshot: %s" % str(result.get("error", "unknown")))
		return
	var repro: Dictionary = result.get("repro", {})
	var saved := ReproStore.save_snapshot(repro)
	if bool(saved.get("ok", false)):
		_last_saved_repro_path = str(saved.get("absolute_path", saved.get("path", "")))
	_refresh_repro_browser()
	_refresh_status()


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


func _control_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return label


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


func _format_sample_failures(value: Variant) -> String:
	var failures: Array = value
	if failures.is_empty():
		return "none"
	var lines: Array[String] = []
	for failure in failures:
		lines.append(str(failure))
	return "\n".join(lines)


func _to_json_safe(value: Variant) -> Variant:
	return ReproStore.to_json_safe(value)
