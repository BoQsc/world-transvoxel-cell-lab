@tool
extends RefCounted
class_name WtCellLabTerrainObservatory

const Contracts := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_contracts.gd")
const MeshAnalysis := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_mesh_analysis.gd")

const VIEW_NAMES := [
	"SURFACE",
	"LOD",
	"MATERIAL",
	"TRIANGLES",
	"NORMALS",
	"SEAMS",
	"DENSITY",
]
const DISPLAY_CENTER := Vector3(16.0, 10.0, 16.0)
const DISPLAY_SCALE := 0.12
const SLICE_RESOLUTION := 32
const MAX_NORMAL_LINES := 640
const SEAM_POSITION_SCALE := 10000.0


func build(lab: Object, fixture: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var view_mode := clampi(
		int(overrides.get("view_mode", lab.get("reference_view_mode"))),
		0,
		VIEW_NAMES.size() - 1
	)
	var isolate := bool(
		overrides.get("isolate", lab.get("reference_isolate_selected_chunk"))
	)
	var show_transitions := bool(
		overrides.get("show_transitions", lab.get("show_reference_transitions"))
	)
	var show_normals := bool(
		overrides.get("show_normals", lab.get("show_reference_normals"))
	) or view_mode == 4
	var show_seams := bool(
		overrides.get("show_seams", lab.get("show_reference_seams"))
	) or view_mode == 5
	var show_slice := bool(
		overrides.get("show_slice", lab.get("show_reference_density_slice"))
	) or view_mode == 6
	var show_samples := bool(
		overrides.get("show_samples", lab.get("show_reference_sample_grid"))
	) or view_mode == 6
	var selected_index := clampi(
		int(overrides.get("selected_chunk", lab.get("selected_reference_chunk"))),
		0,
		11
	)
	var chunks: Array = fixture.get("chunks", [])
	if chunks.is_empty():
		return _unavailable_result(view_mode, "reference terrain fixture has no chunks")
	selected_index = clampi(selected_index, 0, chunks.size() - 1)
	var selected_chunk: Dictionary = chunks[selected_index]
	var selected_id := str(selected_chunk.get("fixture_chunk_id", ""))
	var display_buffers: Array = []
	var visible_chunk_ids: Array[String] = []
	var transition_buffer_count := 0
	for buffer_value in fixture.get("buffers", []):
		var buffer: Dictionary = buffer_value
		var chunk_id := str(buffer.get("chunk_id", ""))
		if isolate and chunk_id != selected_id:
			continue
		if str(buffer.get("kind", "")) == "transition" and not show_transitions:
			continue
		if chunk_id not in visible_chunk_ids:
			visible_chunk_ids.append(chunk_id)
		if str(buffer.get("kind", "")) == "transition":
			transition_buffer_count += 1
		display_buffers.append(_display_buffer(buffer, view_mode))
	var normal_data := _normal_lines(display_buffers) if show_normals else _empty_lines()
	var seam_data := _seam_lines(fixture, isolate, selected_id) if show_seams else _empty_seams()
	var slice_data := _density_slice(lab, overrides) if show_slice else _empty_slice()
	var sample_data := _sample_grid(slice_data) if show_samples else _empty_lines()
	var feature_labels: Array = []
	if bool(overrides.get("show_features", lab.get("show_reference_feature_labels"))):
		for feature_value in fixture.get("feature_catalog", []):
			var feature: Dictionary = feature_value
			var world_position: Vector3 = feature.get("position", Vector3.ZERO)
			feature_labels.append({
				"id": str(feature.get("id", "")),
				"label": str(feature.get("label", "")),
				"position": _display_position(world_position) + Vector3.UP * 0.2,
			})
	var vertex_count := 0
	var triangle_count := 0
	var represented_material_ids: Array[int] = []
	for display_buffer_value in display_buffers:
		var display_buffer: Dictionary = display_buffer_value
		vertex_count += (
			display_buffer.get("vertices", PackedVector3Array()) as PackedVector3Array
		).size()
		triangle_count += int(
			(display_buffer.get("indices", PackedInt32Array()) as PackedInt32Array).size() / 3
		)
		for material in display_buffer.get("source_material_ids", []):
			if int(material) > 0 and int(material) not in represented_material_ids:
				represented_material_ids.append(int(material))
	represented_material_ids.sort()
	return {
		"schema": Contracts.TERRAIN_OBSERVATORY_SCHEMA,
		"authority": Contracts.NATIVE_AUTHORITY,
		"status": "PASS" if bool(fixture.get("ok", false)) else "FAIL",
		"view_mode": view_mode,
		"view_name": VIEW_NAMES[view_mode],
		"selected_chunk_index": selected_index,
		"selected_chunk_id": selected_id,
		"isolate_selected_chunk": isolate,
		"show_transitions": show_transitions,
		"display_buffers": display_buffers,
		"display_buffer_count": display_buffers.size(),
		"visible_chunk_ids": visible_chunk_ids,
		"visible_chunk_count": visible_chunk_ids.size(),
		"transition_buffer_count": transition_buffer_count,
		"vertex_count": vertex_count,
		"triangle_count": triangle_count,
		"represented_material_ids": represented_material_ids,
		"normal_lines": normal_data,
		"seam_lines": seam_data,
		"density_slice": slice_data,
		"sample_grid": sample_data,
		"feature_labels": feature_labels,
		"force_wireframe": view_mode == 3,
		"elapsed_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
	}


func validate(lab: Object, fixture: Dictionary) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var view_results: Array = []
	var passing_views := 0
	for view_mode in range(VIEW_NAMES.size()):
		var view := build(lab, fixture, {
			"view_mode": view_mode,
			"show_normals": view_mode == 4,
			"show_seams": view_mode == 5,
			"show_slice": view_mode == 6,
			"show_samples": view_mode == 6,
			"show_features": false,
		})
		var view_ok := str(view.get("status", "")) == "PASS" \
			and int(view.get("display_buffer_count", 0)) > 0 \
			and int(view.get("vertex_count", 0)) > 0 \
			and int(view.get("triangle_count", 0)) > 0
		if view_mode == 2:
			view_ok = view_ok and (
				view.get("represented_material_ids", []) == fixture.get("material_ids", [])
			)
		if view_mode == 3:
			view_ok = view_ok and bool(view.get("force_wireframe", false))
		if view_mode == 4:
			view_ok = view_ok and int(
				view.get("normal_lines", {}).get("line_count", 0)
			) > 0
		if view_mode == 5:
			var seams: Dictionary = view.get("seam_lines", {})
			view_ok = view_ok \
				and int(seams.get("passing_overlay_count", 0)) > 0 \
				and int(seams.get("passing_edge_count", 0)) > 0 \
				and int(seams.get("failing_overlay_count", -1)) == 0 \
				and int(seams.get("failing_edge_count", -1)) == 0
		if view_mode == 6:
			var slice: Dictionary = view.get("density_slice", {})
			view_ok = view_ok \
				and int(slice.get("sample_count", 0)) == (
					(SLICE_RESOLUTION + 1) * (SLICE_RESOLUTION + 1)
				) \
				and int(slice.get("solid_samples", 0)) > 0 \
				and int(slice.get("air_samples", 0)) > 0 \
				and int(view.get("sample_grid", {}).get("line_count", 0)) > 0
		passing_views += 1 if view_ok else 0
		view_results.append({
			"view": VIEW_NAMES[view_mode],
			"status": "PASS" if view_ok else "FAIL",
			"display_buffers": int(view.get("display_buffer_count", 0)),
			"vertices": int(view.get("vertex_count", 0)),
			"triangles": int(view.get("triangle_count", 0)),
		})
	var isolated := build(lab, fixture, {
		"view_mode": 1,
		"isolate": true,
		"selected_chunk": 8,
		"show_features": false,
	})
	var transitions_hidden := build(lab, fixture, {
		"view_mode": 1,
		"show_transitions": false,
		"show_features": false,
	})
	var isolation_ok: bool = int(isolated.get("visible_chunk_count", 0)) == 1 \
		and isolated.get("visible_chunk_ids", []) == ["fine_00"]
	var transition_toggle_ok: bool = int(
		transitions_hidden.get("transition_buffer_count", -1)
	) == 0
	var status := "PASS"
	var failures: Array = []
	if passing_views != VIEW_NAMES.size():
		status = "FAIL"
		failures.append("one or more terrain observatory views failed")
	if not isolation_ok:
		status = "FAIL"
		failures.append("selected chunk isolation did not reduce the view to one chunk")
	if not transition_toggle_ok:
		status = "FAIL"
		failures.append("transition visibility toggle did not hide transition buffers")
	var standard := standard_signature(lab, fixture)
	return {
		"schema": Contracts.TERRAIN_OBSERVATORY_VALIDATION_SCHEMA,
		"authority": Contracts.NATIVE_AUTHORITY,
		"status": status,
		"view_count": VIEW_NAMES.size(),
		"passing_views": passing_views,
		"failing_views": VIEW_NAMES.size() - passing_views,
		"views": view_results,
		"isolation_status": "PASS" if isolation_ok else "FAIL",
		"transition_toggle_status": "PASS" if transition_toggle_ok else "FAIL",
		"standard_signature": standard,
		"sample_failures": failures,
		"elapsed_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
	}


func benchmark(lab: Object, fixture: Dictionary, iterations: int = 2) -> Dictionary:
	iterations = clampi(iterations, 1, 12)
	var timings: Array[float] = []
	var status := "PASS"
	for iteration in range(iterations):
		var started_usec := Time.get_ticks_usec()
		for view_mode in range(VIEW_NAMES.size()):
			var result := build(lab, fixture, {
				"view_mode": view_mode,
				"show_normals": view_mode == 4,
				"show_seams": view_mode == 5,
				"show_slice": view_mode == 6,
				"show_samples": view_mode == 6,
				"show_features": false,
			})
			if str(result.get("status", "")) != "PASS":
				status = "FAIL"
		timings.append(float(Time.get_ticks_usec() - started_usec) / 1000.0)
	var total_ms := 0.0
	for timing in timings:
		total_ms += timing
	return {
		"status": status,
		"iterations": iterations,
		"view_count": VIEW_NAMES.size(),
		"average_all_views_ms": total_ms / float(timings.size()) \
			if not timings.is_empty() else 0.0,
		"maximum_all_views_ms": timings.max() if not timings.is_empty() else 0.0,
	}


func standard_signature(lab: Object, fixture: Dictionary) -> Dictionary:
	var density_view := build(lab, fixture, {
		"view_mode": 6,
		"show_slice": true,
		"show_samples": true,
		"show_features": false,
	})
	var normal_view := build(lab, fixture, {
		"view_mode": 4,
		"show_normals": true,
		"show_features": false,
	})
	var seam_view := build(lab, fixture, {
		"view_mode": 5,
		"show_seams": true,
		"show_features": false,
	})
	return {
		"view_count": VIEW_NAMES.size(),
		"view_names": VIEW_NAMES,
		"density_slice_samples": int(
			density_view.get("density_slice", {}).get("sample_count", 0)
		),
		"density_slice_triangles": int(
			density_view.get("density_slice", {}).get("triangle_count", 0)
		),
		"sample_grid_lines": int(
			density_view.get("sample_grid", {}).get("line_count", 0)
		),
		"normal_lines": int(normal_view.get("normal_lines", {}).get("line_count", 0)),
		"passing_seam_overlays": int(
			seam_view.get("seam_lines", {}).get("passing_overlay_count", 0)
		),
		"failing_seam_overlays": int(
			seam_view.get("seam_lines", {}).get("failing_overlay_count", 0)
		),
		"passing_seam_edges": int(
			seam_view.get("seam_lines", {}).get("passing_edge_count", 0)
		),
		"failing_seam_edges": int(
			seam_view.get("seam_lines", {}).get("failing_edge_count", 0)
		),
		"transition_overlays": int(
			seam_view.get("seam_lines", {}).get("transition_overlay_count", 0)
		),
	}


func _display_buffer(buffer: Dictionary, view_mode: int) -> Dictionary:
	var origin: Vector3 = buffer.get("origin", Vector3.ZERO)
	var source_vertices: PackedVector3Array = buffer.get("vertices", PackedVector3Array())
	var source_normals: PackedVector3Array = buffer.get("normals", PackedVector3Array())
	var source_materials: PackedInt32Array = buffer.get("materials", PackedInt32Array())
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var material_ids: Array[int] = []
	for index in range(source_vertices.size()):
		var world_position := source_vertices[index] + origin
		vertices.append(_display_position(world_position))
		var material_id := int(source_materials[index]) if index < source_materials.size() else 1
		if material_id > 0 and material_id not in material_ids:
			material_ids.append(material_id)
		var normal := source_normals[index] if index < source_normals.size() else Vector3.UP
		colors.append(
			_vertex_color(buffer, material_id, normal, world_position, view_mode)
		)
	material_ids.sort()
	return {
		"chunk_id": str(buffer.get("chunk_id", "")),
		"coordinate": buffer.get("coordinate", Vector3i.ZERO),
		"lod": int(buffer.get("lod", 0)),
		"kind": str(buffer.get("kind", "")),
		"face": int(buffer.get("face", -1)),
		"vertices": vertices,
		"normals": source_normals,
		"indices": buffer.get("indices", PackedInt32Array()),
		"colors": colors,
		"source_material_ids": material_ids,
	}


func _vertex_color(
	buffer: Dictionary,
	material_id: int,
	normal: Vector3,
	world_position: Vector3,
	view_mode: int
) -> Color:
	var is_transition := str(buffer.get("kind", "")) == "transition"
	match view_mode:
		0:
			return _surface_color(world_position, normal)
		1:
			if is_transition:
				return Color(0.96, 0.42, 0.12, 1.0)
			return Color(0.14, 0.63, 0.88, 1.0) \
				if int(buffer.get("lod", 0)) == 0 else Color(0.28, 0.72, 0.42, 1.0)
		2:
			return _diagnostic_material_color(material_id)
		3:
			return Color(0.38, 0.43, 0.48, 1.0)
		4:
			return Color(
				normal.x * 0.5 + 0.5,
				normal.y * 0.5 + 0.5,
				normal.z * 0.5 + 0.5,
				1.0
			)
		5:
			return Color(0.25, 0.29, 0.33, 0.72)
		6:
			var color := _natural_material_color(material_id)
			color.a = 0.38
			return color
	return Color.WHITE


func _surface_color(world_position: Vector3, normal: Vector3) -> Color:
	var elevation := clampf((world_position.y - 3.0) / 15.0, 0.0, 1.0)
	var base := Color(0.16, 0.20, 0.23).lerp(
		Color(0.16, 0.31, 0.20),
		elevation
	)
	var normalized := normal.normalized()
	var slope := 1.0 - clampf(absf(normalized.y), 0.0, 1.0)
	return base.lerp(Color(0.30, 0.21, 0.15), slope * 0.80)


func _natural_material_color(material_id: int) -> Color:
	match material_id:
		1:
			return Color(0.36, 0.39, 0.41, 1.0)
		2:
			return Color(0.22, 0.48, 0.27, 1.0)
		3:
			return Color(0.15, 0.20, 0.27, 1.0)
		4:
			return Color(0.54, 0.36, 0.21, 1.0)
		5:
			return Color(0.12, 0.46, 0.74, 1.0)
		6:
			return Color(0.43, 0.29, 0.50, 1.0)
	return Color(0.58, 0.60, 0.62, 1.0)


func _diagnostic_material_color(material_id: int) -> Color:
	match material_id:
		1:
			return Color(0.88, 0.88, 0.88, 1.0)
		2:
			return Color(0.12, 0.82, 0.34, 1.0)
		3:
			return Color(0.18, 0.28, 0.92, 1.0)
		4:
			return Color(0.96, 0.54, 0.10, 1.0)
		5:
			return Color(0.10, 0.78, 0.92, 1.0)
		6:
			return Color(0.74, 0.22, 0.86, 1.0)
	return Color(1.0, 0.2, 0.2, 1.0)


func _normal_lines(display_buffers: Array) -> Dictionary:
	var total_vertices := 0
	for buffer_value in display_buffers:
		var buffer: Dictionary = buffer_value
		total_vertices += (
			buffer.get("vertices", PackedVector3Array()) as PackedVector3Array
		).size()
	var stride := maxi(1, ceili(float(total_vertices) / float(MAX_NORMAL_LINES)))
	var lines := PackedVector3Array()
	var colors := PackedColorArray()
	var global_index := 0
	for buffer_value in display_buffers:
		var buffer: Dictionary = buffer_value
		var vertices: PackedVector3Array = buffer.get("vertices", PackedVector3Array())
		var normals: PackedVector3Array = buffer.get("normals", PackedVector3Array())
		for index in range(mini(vertices.size(), normals.size())):
			if global_index % stride == 0:
				var normal := normals[index].normalized()
				lines.append(vertices[index])
				lines.append(vertices[index] + normal * 0.28)
				var color := Color(
					normal.x * 0.5 + 0.5,
					normal.y * 0.5 + 0.5,
					normal.z * 0.5 + 0.5,
					1.0
				)
				colors.append(color)
				colors.append(color)
			global_index += 1
	return {
		"vertices": lines,
		"colors": colors,
		"line_count": int(lines.size() / 2),
		"stride": stride,
	}


func _seam_lines(fixture: Dictionary, isolate: bool, selected_id: String) -> Dictionary:
	var chunks_by_id := {}
	for chunk_value in fixture.get("chunks", []):
		var chunk: Dictionary = chunk_value
		chunks_by_id[str(chunk.get("fixture_chunk_id", ""))] = chunk
	var passing_lines := PackedVector3Array()
	var passing_colors := PackedColorArray()
	var failing_lines := PackedVector3Array()
	var failing_colors := PackedColorArray()
	var transition_lines := PackedVector3Array()
	var transition_colors := PackedColorArray()
	var passing_overlays := 0
	var failing_overlays := 0
	var seam_validation: Dictionary = fixture.get("seam_validation", {})
	for interface_value in seam_validation.get("same_interfaces", []):
		var interface: Dictionary = interface_value
		var left_id := str(interface.get("left_chunk", ""))
		var right_id := str(interface.get("right_chunk", ""))
		if isolate and selected_id not in [left_id, right_id]:
			continue
		if bool(interface.get("matches", false)):
			_append_signature_lines(
				interface.get("matching_signatures", []),
				int(interface.get("axis", 0)),
				float(interface.get("plane", 0.0)),
				passing_lines,
				passing_colors,
				Color(0.20, 0.94, 0.46, 1.0)
			)
			passing_overlays += 1
		else:
			_append_signature_lines(
				interface.get("left_only_signatures", []),
				int(interface.get("axis", 0)),
				float(interface.get("plane", 0.0)),
				failing_lines,
				failing_colors,
				Color(1.0, 0.08, 0.05, 1.0)
			)
			_append_signature_lines(
				interface.get("right_only_signatures", []),
				int(interface.get("axis", 0)),
				float(interface.get("plane", 0.0)),
				failing_lines,
				failing_colors,
				Color(1.0, 0.12, 0.78, 1.0)
			)
			failing_overlays += 1
	for interface_value in seam_validation.get("interfaces", []):
		var interface: Dictionary = interface_value
		var coarse_id := str(interface.get("coarse_chunk", ""))
		var fine_ids: Array = interface.get("fine_chunks", [])
		if isolate and selected_id != coarse_id and selected_id not in fine_ids:
			continue
		if bool(interface.get("matches", false)):
			_append_signature_lines(
				interface.get("matching_signatures", []),
				int(interface.get("axis", 0)),
				float(interface.get("plane", 0.0)),
				passing_lines,
				passing_colors,
				Color(0.10, 0.88, 0.82, 1.0)
			)
			passing_overlays += 1
		else:
			_append_signature_lines(
				interface.get("coarse_only_signatures", []),
				int(interface.get("axis", 0)),
				float(interface.get("plane", 0.0)),
				failing_lines,
				failing_colors,
				Color(1.0, 0.08, 0.05, 1.0)
			)
			_append_signature_lines(
				interface.get("fine_only_signatures", []),
				int(interface.get("axis", 0)),
				float(interface.get("plane", 0.0)),
				failing_lines,
				failing_colors,
				Color(1.0, 0.12, 0.78, 1.0)
			)
			failing_overlays += 1
		_append_chunk_face(
			transition_lines,
			transition_colors,
			chunks_by_id.get(coarse_id, {}),
			int(interface.get("coarse_face_index", 0)),
			Color(1.0, 0.58, 0.08, 1.0)
		)
	return {
		"passing_vertices": passing_lines,
		"passing_colors": passing_colors,
		"failing_vertices": failing_lines,
		"failing_colors": failing_colors,
		"transition_vertices": transition_lines,
		"transition_colors": transition_colors,
		"passing_overlay_count": passing_overlays,
		"failing_overlay_count": failing_overlays,
		"passing_interface_count": passing_overlays,
		"failing_interface_count": failing_overlays,
		"passing_edge_count": int(passing_lines.size() / 2),
		"failing_edge_count": int(failing_lines.size() / 2),
		"transition_overlay_count": int(transition_lines.size() / 8),
	}


func _density_slice(lab: Object, overrides: Dictionary) -> Dictionary:
	var axis := clampi(
		int(overrides.get("slice_axis", lab.get("reference_slice_axis"))),
		0,
		2
	)
	var position := float(
		overrides.get("slice_position", lab.get("reference_slice_position"))
	)
	var bounds := AABB(Vector3(-32.0, 0.0, -32.0), Vector3(96.0, 32.0, 96.0))
	position = clampf(
		position,
		bounds.position[axis],
		(bounds.position + bounds.size)[axis]
	)
	var variable_axes: Array[int] = []
	for candidate in range(3):
		if candidate != axis:
			variable_axes.append(candidate)
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var densities := PackedFloat32Array()
	var solid_samples := 0
	var air_samples := 0
	var near_surface_samples := 0
	var minimum_density := INF
	var maximum_density := -INF
	for second_index in range(SLICE_RESOLUTION + 1):
		for first_index in range(SLICE_RESOLUTION + 1):
			var point := Vector3.ZERO
			point[axis] = position
			point[variable_axes[0]] = bounds.position[variable_axes[0]] \
				+ bounds.size[variable_axes[0]] * float(first_index) / float(SLICE_RESOLUTION)
			point[variable_axes[1]] = bounds.position[variable_axes[1]] \
				+ bounds.size[variable_axes[1]] * float(second_index) / float(SLICE_RESOLUTION)
			var sample: Dictionary = lab.sample_reference_terrain(point)
			var density_value := float(sample.get("density", 0.0))
			vertices.append(_display_position(point))
			colors.append(_density_color(density_value))
			densities.append(density_value)
			minimum_density = minf(minimum_density, density_value)
			maximum_density = maxf(maximum_density, density_value)
			if density_value < 0.0:
				solid_samples += 1
			else:
				air_samples += 1
			if absf(density_value) <= 0.5:
				near_surface_samples += 1
	for second_index in range(SLICE_RESOLUTION):
		for first_index in range(SLICE_RESOLUTION):
			var row := SLICE_RESOLUTION + 1
			var a := second_index * row + first_index
			var b := a + 1
			var d := (second_index + 1) * row + first_index
			var c := d + 1
			indices.append_array(PackedInt32Array([a, b, c, a, c, d]))
	return {
		"available": true,
		"axis": axis,
		"axis_name": ["X", "Y", "Z"][axis],
		"position": position,
		"resolution": SLICE_RESOLUTION,
		"vertices": vertices,
		"colors": colors,
		"indices": indices,
		"densities": densities,
		"sample_count": vertices.size(),
		"triangle_count": int(indices.size() / 3),
		"solid_samples": solid_samples,
		"air_samples": air_samples,
		"near_surface_samples": near_surface_samples,
		"minimum_density": minimum_density,
		"maximum_density": maximum_density,
	}


func _sample_grid(slice_data: Dictionary) -> Dictionary:
	if not bool(slice_data.get("available", false)):
		return _empty_lines()
	var source_vertices: PackedVector3Array = slice_data.get("vertices", PackedVector3Array())
	var source_colors: PackedColorArray = slice_data.get("colors", PackedColorArray())
	var lines := PackedVector3Array()
	var colors := PackedColorArray()
	var row := SLICE_RESOLUTION + 1
	for second_index in range(0, SLICE_RESOLUTION + 1, 4):
		for first_index in range(0, SLICE_RESOLUTION + 1, 4):
			var index := second_index * row + first_index
			if index >= source_vertices.size():
				continue
			var point := source_vertices[index]
			var color := source_colors[index] if index < source_colors.size() else Color.WHITE
			for direction in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
				lines.append(point - direction * 0.055)
				lines.append(point + direction * 0.055)
				colors.append(color)
				colors.append(color)
	return {
		"vertices": lines,
		"colors": colors,
		"line_count": int(lines.size() / 2),
	}


func _density_color(density_value: float) -> Color:
	if absf(density_value) <= 0.5:
		return Color(1.0, 0.82, 0.08, 0.78)
	if density_value < 0.0:
		var strength := clampf(-density_value / 8.0, 0.0, 1.0)
		return Color(0.08, 0.42 + 0.28 * strength, 0.95, 0.56)
	var strength := clampf(density_value / 8.0, 0.0, 1.0)
	return Color(0.95, 0.18 + 0.20 * strength, 0.12, 0.24)


func _append_signature_lines(
	signatures: Array,
	axis: int,
	plane: float,
	lines: PackedVector3Array,
	colors: PackedColorArray,
	color: Color
) -> void:
	axis = clampi(axis, 0, 2)
	var variable_axes: Array[int] = []
	for candidate in range(3):
		if candidate != axis:
			variable_axes.append(candidate)
	for signature_value in signatures:
		var endpoints := str(signature_value).split("|")
		if endpoints.size() != 2:
			continue
		var points: Array[Vector3] = []
		for endpoint in endpoints:
			var coordinates := str(endpoint).split(",")
			if coordinates.size() != 2:
				continue
			var point := Vector3.ZERO
			point[axis] = plane
			point[variable_axes[0]] = float(coordinates[0]) / SEAM_POSITION_SCALE
			point[variable_axes[1]] = float(coordinates[1]) / SEAM_POSITION_SCALE
			points.append(_display_position(point))
		if points.size() != 2:
			continue
		lines.append(points[0])
		lines.append(points[1])
		colors.append(color)
		colors.append(color)


func _append_chunk_face(
	lines: PackedVector3Array,
	colors: PackedColorArray,
	chunk: Dictionary,
	face: int,
	color: Color
) -> void:
	if chunk.is_empty():
		return
	var bounds := _chunk_bounds(chunk)
	var axis := 0 if face <= 1 else (1 if face <= 3 else 2)
	var position := bounds.position
	var size := bounds.size
	if face in [1, 3, 5]:
		position[axis] += size[axis]
	size[axis] = 0.0
	_append_flat_aabb(lines, colors, AABB(position, size), color)


func _append_flat_aabb(
	lines: PackedVector3Array,
	colors: PackedColorArray,
	bounds: AABB,
	color: Color
) -> void:
	var flat_axis := -1
	for axis in range(3):
		if absf(bounds.size[axis]) <= 0.0001:
			flat_axis = axis
			break
	if flat_axis < 0:
		return
	var variable_axes: Array[int] = []
	for axis in range(3):
		if axis != flat_axis:
			variable_axes.append(axis)
	var corners: Array[Vector3] = []
	for second in range(2):
		for first in range(2):
			var point := bounds.position
			point[variable_axes[0]] += bounds.size[variable_axes[0]] * float(first)
			point[variable_axes[1]] += bounds.size[variable_axes[1]] * float(second)
			corners.append(_display_position(point))
	for pair in [[0, 1], [1, 3], [3, 2], [2, 0]]:
		lines.append(corners[int(pair[0])])
		lines.append(corners[int(pair[1])])
		colors.append(color)
		colors.append(color)


func _chunk_bounds(chunk: Dictionary) -> AABB:
	var extent := float(
		Contracts.CHUNK_PROBE_CELLS_PER_AXIS * (1 << int(chunk.get("lod", 0)))
	)
	return AABB(
		Vector3(
			float(chunk.get("world_origin_x", 0.0)),
			float(chunk.get("world_origin_y", 0.0)),
			float(chunk.get("world_origin_z", 0.0))
		),
		Vector3.ONE * extent
	)


func _display_position(world_position: Vector3) -> Vector3:
	return (world_position - DISPLAY_CENTER) * DISPLAY_SCALE


func _empty_lines() -> Dictionary:
	return {
		"vertices": PackedVector3Array(),
		"colors": PackedColorArray(),
		"line_count": 0,
	}


func _empty_seams() -> Dictionary:
	return {
		"passing_vertices": PackedVector3Array(),
		"passing_colors": PackedColorArray(),
		"failing_vertices": PackedVector3Array(),
		"failing_colors": PackedColorArray(),
		"transition_vertices": PackedVector3Array(),
		"transition_colors": PackedColorArray(),
		"passing_overlay_count": 0,
		"failing_overlay_count": 0,
		"passing_interface_count": 0,
		"failing_interface_count": 0,
		"passing_edge_count": 0,
		"failing_edge_count": 0,
		"transition_overlay_count": 0,
	}


func _empty_slice() -> Dictionary:
	return {
		"available": false,
		"vertices": PackedVector3Array(),
		"colors": PackedColorArray(),
		"indices": PackedInt32Array(),
		"sample_count": 0,
		"triangle_count": 0,
	}


func _unavailable_result(view_mode: int, error: String) -> Dictionary:
	return {
		"schema": Contracts.TERRAIN_OBSERVATORY_SCHEMA,
		"authority": Contracts.NATIVE_AUTHORITY,
		"status": "FAIL",
		"view_mode": view_mode,
		"view_name": VIEW_NAMES[view_mode],
		"error": error,
		"display_buffers": [],
		"display_buffer_count": 0,
	}
