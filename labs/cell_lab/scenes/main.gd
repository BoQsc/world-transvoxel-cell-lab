extends Node3D

const LabScript := preload("res://addons/world_transvoxel_cell_lab/lab/wt_transvoxel_cell_lab.gd")

@onready var lab: WtTransvoxelCellLab = $WtTransvoxelCellLab
@onready var status_label: Label = $Overlay/StatusLabel
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	_configure_presentation()
	_update_status()


func _configure_presentation() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.055, 0.07, 0.085)
	environment.background_energy_multiplier = 0.72
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.52, 0.60, 0.68)
	environment.ambient_light_energy = 0.58
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	camera.position = Vector3(8.4, 5.8, 8.8)
	camera.look_at(Vector3(0.0, 0.15, 0.0), Vector3.UP)


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
			KEY_T:
				lab.inspection_mode = LabScript.InspectionMode.REFERENCE_TERRAIN
			KEY_V:
				lab.reference_view_mode = (
					int(lab.reference_view_mode) + 1
				) % LabScript.ReferenceViewMode.size()
			KEY_I:
				lab.reference_isolate_selected_chunk = \
					not lab.reference_isolate_selected_chunk
			KEY_B:
				lab.show_reference_chunk_bounds = not lab.show_reference_chunk_bounds
			KEY_N:
				lab.show_reference_normals = not lab.show_reference_normals
			KEY_S:
				lab.show_reference_seams = not lab.show_reference_seams
			KEY_G:
				lab.show_reference_density_slice = not lab.show_reference_density_slice
				lab.show_reference_sample_grid = lab.show_reference_density_slice
			KEY_X:
				lab.expand_cells("x", 1)
			KEY_Y:
				lab.expand_cells("y", 1)
			KEY_Z:
				lab.expand_cells("z", 1)
			KEY_D:
				if lab.inspection_mode == LabScript.InspectionMode.REFERENCE_TERRAIN:
					lab.apply_reference_terrain_dig()
				else:
					lab.apply_dig_at(Vector3.ZERO)
			KEY_C:
				if lab.inspection_mode == LabScript.InspectionMode.REFERENCE_TERRAIN:
					lab.apply_reference_terrain_construct()
				else:
					lab.apply_construct_at(Vector3.ZERO)
			KEY_R:
				if lab.inspection_mode == LabScript.InspectionMode.REFERENCE_TERRAIN:
					lab.clear_reference_terrain_edits()
				else:
					lab.clear_edits()
			KEY_W:
				lab.wireframe = not lab.wireframe
				lab.rebuild()
		_update_status()


func _update_status() -> void:
	if lab == null or status_label == null:
		return
	var report := lab.get_last_report()
	var inspection: Dictionary = report.get("inspection", {})
	var lines := PackedStringArray([
		"Status: %s" % str(report.get("status", "UNKNOWN")),
		"Authority: %s" % str(report.get("render_authority", "unknown")),
		"Qualification: %s" % str(report.get("qualification_status", "NOT_RUN")),
		"Scope claim: %s" % str(report.get("correctness_claim", "unknown")),
		"Regular patch: %s cells, %d tris, %d interior open, %d nonmanifold" % [
			str(report.get("cells", Vector3i.ZERO)),
			int(report.get("triangles", 0)),
			int(report.get("interior_open_edges", 0)),
			int(report.get("nonmanifold_edges", 0)),
		],
		"Transition cell: %s, case %d, %d tris" % [
			str(report.get("transition_status", "Unavailable")),
			int(report.get("transition_case_code", -1)),
			int(report.get("transition_triangles", 0)),
		],
		"Production chunk: LOD%d, %d samples, %d tris" % [
			int(report.get("chunk_probe_lod", 0)),
			int(report.get("chunk_probe_samples", 0)),
			int(report.get("chunk_probe_triangles", 0)),
		],
		"Inspection: %s %s" % [
			str(report.get("inspection_mode", "PATCH")),
			str(inspection.get("status", "")),
		],
	])
	if str(report.get("inspection_mode", "")) == "REFERENCE_TERRAIN":
		lines.append("Reference terrain: %s view, %s chunks, %s tris, %s edits, %s ms" % [
			str(inspection.get("observatory_view", "")),
			str(inspection.get("chunk_count", "")),
			str(inspection.get("triangles", "")),
			str(inspection.get("edit_count", "")),
			str(inspection.get("build_ms", "")),
		])
	status_label.text = "\n".join(lines)
