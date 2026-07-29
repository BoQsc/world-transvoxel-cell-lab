@tool
extends RefCounted
class_name WtCellLabReproStore

const Contracts := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_contracts.gd")
const FIELD_MODE_NAMES := ["PLANE", "SPHERE", "TUNNEL", "SADDLE", "WAVES"]
const USER_REPRO_DIRECTORY := "user://world_transvoxel_cell_lab/repros"
const COMMITTED_REPRO_DIRECTORY := "res://addons/world_transvoxel_cell_lab/standards/repros"


static func make_snapshot(lab: Object, metadata: Dictionary = {}) -> Dictionary:
	var repro_metadata := {
		"name": str(metadata.get("name", "cell_lab_repro")),
		"notes": str(metadata.get("notes", "")),
		"expected_label": _validated_label(
			str(metadata.get("expected_label", "investigation")),
			Contracts.EXPECTED_LABELS,
			"investigation"
		),
		"source_layer": _validated_label(
			str(metadata.get("source_layer", "unknown")),
			Contracts.SOURCE_LAYERS,
			"unknown"
		),
		"source_reference": str(metadata.get("source_reference", "")),
	}
	var snapshot := {
		"schema": Contracts.REPRO_SCHEMA,
		"created_unix_time": Time.get_unix_time_from_system(),
		"metadata": repro_metadata,
		"parameters": {
			"cells": Vector3i(lab.cells_x, lab.cells_y, lab.cells_z),
			"cell_size": lab.cell_size,
			"field_mode": FIELD_MODE_NAMES[clampi(lab.field_mode, 0, FIELD_MODE_NAMES.size() - 1)],
			"isovalue": lab.isovalue,
			"surface_height": lab.surface_height,
			"sphere_radius": lab.sphere_radius,
			"edit_radius": lab.edit_radius,
			"construct_material": lab.construct_material,
			"show_transition_frame": lab.show_transition_frame,
			"show_chunk_probe": lab.show_chunk_probe,
			"show_probe_labels": lab.show_probe_labels,
			"wireframe": lab.wireframe,
			"inspection_mode": int(lab.get("inspection_mode")),
			"selected_regular_case": int(lab.get("selected_regular_case")),
			"selected_transition_case": int(lab.get("selected_transition_case")),
			"selected_transition_orientation": int(lab.get("selected_transition_orientation")),
			"selected_chunk_lod": int(lab.get("selected_chunk_lod")),
			"selected_reference_chunk": int(lab.get("selected_reference_chunk")),
			"reference_edit_cursor": lab.get("reference_edit_cursor"),
			"reference_view_mode": int(lab.get("reference_view_mode")),
			"reference_isolate_selected_chunk": bool(lab.get("reference_isolate_selected_chunk")),
			"show_reference_chunk_bounds": bool(lab.get("show_reference_chunk_bounds")),
			"show_reference_transitions": bool(lab.get("show_reference_transitions")),
			"show_reference_feature_labels": bool(lab.get("show_reference_feature_labels")),
			"show_reference_normals": bool(lab.get("show_reference_normals")),
			"show_reference_seams": bool(lab.get("show_reference_seams")),
			"show_reference_density_slice": bool(lab.get("show_reference_density_slice")),
			"show_reference_sample_grid": bool(lab.get("show_reference_sample_grid")),
			"reference_slice_axis": int(lab.get("reference_slice_axis")),
			"reference_slice_position": float(lab.get("reference_slice_position")),
		},
		"edits": lab.edits.duplicate(true),
		"reference_terrain_edits": lab.call("get_reference_terrain_edits") \
			if lab.has_method("get_reference_terrain_edits") else [],
		"report": lab.get_last_report(),
	}
	snapshot.merge(Contracts.authority_metadata())
	return snapshot


static func apply_snapshot(lab: Object, snapshot: Dictionary) -> Dictionary:
	var schema := str(snapshot.get("schema", ""))
	if schema != Contracts.REPRO_SCHEMA and schema != Contracts.LEGACY_REPRO_SCHEMA:
		return {"ok": false, "error": "unexpected_repro_schema"}
	var parameters: Dictionary = snapshot.get("parameters", {})
	var previous_auto_rebuild: bool = lab.auto_rebuild
	lab.auto_rebuild = false
	var default_extent := Vector3i(lab.cells_x, lab.cells_y, lab.cells_z)
	var extent := vector3i_from_variant(parameters.get("cells", default_extent), default_extent)
	lab.cells_x = extent.x
	lab.cells_y = extent.y
	lab.cells_z = extent.z
	lab.cell_size = float(parameters.get("cell_size", lab.cell_size))
	lab.field_mode = field_mode_from_variant(parameters.get("field_mode", FIELD_MODE_NAMES[lab.field_mode]), lab.field_mode)
	lab.isovalue = float(parameters.get("isovalue", lab.isovalue))
	lab.surface_height = float(parameters.get("surface_height", lab.surface_height))
	lab.sphere_radius = float(parameters.get("sphere_radius", lab.sphere_radius))
	lab.edit_radius = float(parameters.get("edit_radius", lab.edit_radius))
	lab.construct_material = int(parameters.get("construct_material", lab.construct_material))
	lab.show_transition_frame = bool(parameters.get("show_transition_frame", lab.show_transition_frame))
	lab.show_chunk_probe = bool(parameters.get("show_chunk_probe", lab.show_chunk_probe))
	lab.show_probe_labels = bool(parameters.get("show_probe_labels", lab.show_probe_labels))
	lab.wireframe = bool(parameters.get("wireframe", lab.wireframe))
	if _has_property(lab, "inspection_mode"):
		lab.set("inspection_mode", str(parameters.get("inspection_mode", lab.get("inspection_mode"))))
	if _has_property(lab, "selected_regular_case"):
		lab.set("selected_regular_case", int(parameters.get("selected_regular_case", lab.get("selected_regular_case"))))
	if _has_property(lab, "selected_transition_case"):
		lab.set("selected_transition_case", int(parameters.get("selected_transition_case", lab.get("selected_transition_case"))))
	if _has_property(lab, "selected_transition_orientation"):
		lab.set(
			"selected_transition_orientation",
			int(parameters.get("selected_transition_orientation", lab.get("selected_transition_orientation")))
		)
	if _has_property(lab, "selected_chunk_lod"):
		lab.set("selected_chunk_lod", int(parameters.get("selected_chunk_lod", lab.get("selected_chunk_lod"))))
	if _has_property(lab, "selected_reference_chunk"):
		lab.set(
			"selected_reference_chunk",
			int(parameters.get("selected_reference_chunk", lab.get("selected_reference_chunk")))
		)
	if _has_property(lab, "reference_edit_cursor"):
		lab.set(
			"reference_edit_cursor",
			vector3_from_variant(
				parameters.get("reference_edit_cursor", lab.get("reference_edit_cursor")),
				lab.get("reference_edit_cursor")
			)
		)
	if _has_property(lab, "show_reference_chunk_bounds"):
		lab.set(
			"show_reference_chunk_bounds",
			bool(parameters.get("show_reference_chunk_bounds", lab.get("show_reference_chunk_bounds")))
		)
	for property_name in [
		"reference_isolate_selected_chunk",
		"show_reference_transitions",
		"show_reference_feature_labels",
		"show_reference_normals",
		"show_reference_seams",
		"show_reference_density_slice",
		"show_reference_sample_grid",
	]:
		if _has_property(lab, property_name):
			lab.set(
				property_name,
				bool(parameters.get(property_name, lab.get(property_name)))
			)
	for property_name in ["reference_view_mode", "reference_slice_axis"]:
		if _has_property(lab, property_name):
			lab.set(
				property_name,
				int(parameters.get(property_name, lab.get(property_name)))
			)
	if _has_property(lab, "reference_slice_position"):
		lab.set(
			"reference_slice_position",
			float(parameters.get(
				"reference_slice_position",
				lab.get("reference_slice_position")
			))
		)
	lab.edits.clear()
	var raw_edits: Array = snapshot.get("edits", [])
	for raw_edit in raw_edits:
		var edit: Dictionary = raw_edit
		lab.edits.append({
			"mode": str(edit.get("mode", "")),
			"center": vector3_from_variant(edit.get("center", Vector3.ZERO), Vector3.ZERO),
			"radius": float(edit.get("radius", lab.edit_radius)),
			"material": int(edit.get("material", lab.construct_material)),
		})
	if lab.has_method("set_reference_terrain_edits"):
		var terrain_edits: Array = snapshot.get("reference_terrain_edits", [])
		lab.call("set_reference_terrain_edits", terrain_edits)
	lab.auto_rebuild = previous_auto_rebuild
	var report: Dictionary = lab.rebuild()
	report["loaded_repro_metadata"] = normalized_metadata(snapshot.get("metadata", {}))
	return report


static func save_snapshot(snapshot: Dictionary, file_name: String = "") -> Dictionary:
	var absolute_dir_path := ProjectSettings.globalize_path(USER_REPRO_DIRECTORY)
	var error := DirAccess.make_dir_recursive_absolute(absolute_dir_path)
	if error != OK:
		return {
			"ok": false,
			"error": "could_not_create_repro_directory",
			"path": absolute_dir_path,
		}
	if file_name.is_empty():
		var metadata: Dictionary = snapshot.get("metadata", {})
		var stem := safe_file_stem(str(metadata.get("name", "cell_lab_repro")))
		file_name = "%s_%d_%d.json" % [
			stem,
			int(Time.get_unix_time_from_system()),
			Time.get_ticks_usec(),
		]
	elif not file_name.ends_with(".json"):
		file_name += ".json"
	var path := "%s/%s" % [USER_REPRO_DIRECTORY, safe_file_name(file_name)]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "could_not_write_repro", "path": path}
	file.store_string(JSON.stringify(to_json_safe(snapshot), "\t"))
	file.close()
	return {
		"ok": true,
		"path": path,
		"absolute_path": ProjectSettings.globalize_path(path),
	}


static func load_snapshot(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "could_not_read_repro", "path": path}
	var parsed := JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "repro_is_not_dictionary", "path": path}
	var snapshot: Dictionary = parsed
	var schema := str(snapshot.get("schema", ""))
	if schema != Contracts.REPRO_SCHEMA and schema != Contracts.LEGACY_REPRO_SCHEMA:
		return {"ok": false, "error": "unexpected_repro_schema", "path": path}
	return {
		"ok": true,
		"path": path,
		"absolute_path": ProjectSettings.globalize_path(path),
		"snapshot": snapshot,
	}


static func list_repros(include_committed: bool = true) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	_append_directory_entries(entries, USER_REPRO_DIRECTORY, false)
	if include_committed:
		_append_directory_entries(entries, COMMITTED_REPRO_DIRECTORY, true)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.get("committed", false)) != bool(b.get("committed", false)):
			return not bool(a.get("committed", false))
		return str(a.get("path", "")) > str(b.get("path", ""))
	)
	return entries


static func latest_repro_path() -> String:
	var entries := list_repros(false)
	return str(entries[0].get("path", "")) if not entries.is_empty() else ""


static func normalized_metadata(value: Variant) -> Dictionary:
	var metadata: Dictionary = value if typeof(value) == TYPE_DICTIONARY else {}
	return {
		"name": str(metadata.get("name", "cell_lab_repro")),
		"notes": str(metadata.get("notes", "")),
		"expected_label": _validated_label(
			str(metadata.get("expected_label", "investigation")),
			Contracts.EXPECTED_LABELS,
			"investigation"
		),
		"source_layer": _validated_label(
			str(metadata.get("source_layer", "unknown")),
			Contracts.SOURCE_LAYERS,
			"unknown"
		),
		"source_reference": str(metadata.get("source_reference", "")),
	}


static func field_mode_from_variant(value: Variant, default_value: int) -> int:
	if typeof(value) == TYPE_INT:
		return clampi(int(value), 0, FIELD_MODE_NAMES.size() - 1)
	var index := FIELD_MODE_NAMES.find(str(value).to_upper())
	return default_value if index < 0 else index


static func vector3i_from_variant(value: Variant, default_value: Vector3i) -> Vector3i:
	match typeof(value):
		TYPE_VECTOR3I:
			return value
		TYPE_VECTOR3:
			return Vector3i(roundi(value.x), roundi(value.y), roundi(value.z))
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value
			return Vector3i(
				int(dictionary.get("x", default_value.x)),
				int(dictionary.get("y", default_value.y)),
				int(dictionary.get("z", default_value.z))
			)
	return default_value


static func vector3_from_variant(value: Variant, default_value: Vector3) -> Vector3:
	match typeof(value):
		TYPE_VECTOR3:
			return value
		TYPE_VECTOR3I:
			return Vector3(value)
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value
			return Vector3(
				float(dictionary.get("x", default_value.x)),
				float(dictionary.get("y", default_value.y)),
				float(dictionary.get("z", default_value.z))
			)
	return default_value


static func to_json_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var converted := {}
			for key in value.keys():
				converted[str(key)] = to_json_safe(value[key])
			return converted
		TYPE_ARRAY:
			var converted: Array = []
			for item in value:
				converted.append(to_json_safe(item))
			return converted
		TYPE_VECTOR2:
			return {"x": value.x, "y": value.y}
		TYPE_VECTOR2I:
			return {"x": value.x, "y": value.y}
		TYPE_VECTOR3:
			return {"x": value.x, "y": value.y, "z": value.z}
		TYPE_VECTOR3I:
			return {"x": value.x, "y": value.y, "z": value.z}
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY:
			var converted: Array = []
			for item in value:
				converted.append(item)
			return converted
		TYPE_PACKED_VECTOR3_ARRAY:
			var converted: Array = []
			for item in value:
				converted.append({"x": item.x, "y": item.y, "z": item.z})
			return converted
		TYPE_OBJECT:
			return str(value)
	return value


static func safe_file_stem(value: String) -> String:
	var result := ""
	for character in value.to_lower():
		if character.is_valid_identifier() or character.is_valid_int():
			result += character
		elif character in [" ", "-", "."]:
			result += "_"
	while "__" in result:
		result = result.replace("__", "_")
	result = result.trim_prefix("_").trim_suffix("_")
	return result if not result.is_empty() else "cell_lab_repro"


static func safe_file_name(value: String) -> String:
	return value.get_file().replace("\\", "_").replace("/", "_")


static func _append_directory_entries(
	entries: Array[Dictionary],
	directory_path: String,
	committed: bool
) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			var path := "%s/%s" % [directory_path, file_name]
			var loaded := load_snapshot(path)
			if bool(loaded.get("ok", false)):
				var snapshot: Dictionary = loaded.get("snapshot", {})
				entries.append({
					"path": path,
					"absolute_path": ProjectSettings.globalize_path(path),
					"file_name": file_name,
					"committed": committed,
					"metadata": normalized_metadata(snapshot.get("metadata", {})),
					"schema": str(snapshot.get("schema", "")),
				})
		file_name = directory.get_next()
	directory.list_dir_end()


static func _validated_label(value: String, allowed: Array, fallback: String) -> String:
	return value if value in allowed else fallback


static func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false
