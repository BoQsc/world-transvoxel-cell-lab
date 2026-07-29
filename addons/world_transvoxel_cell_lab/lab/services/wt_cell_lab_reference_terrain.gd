@tool
extends RefCounted
class_name WtCellLabReferenceTerrain

const Contracts := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_contracts.gd")
const MeshAnalysis := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_mesh_analysis.gd")
const ReferenceField := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_reference_field.gd")

const FIXTURE_ID := "canonical_lod_ring_v2"
const TOPOLOGY_ALIAS_FIXTURE_ID := "coarse_tunnel_roof_alias_v1"
const FINE_LOD := 0
const COARSE_LOD := 1
const ISO_VALUE := 0.0
const TRANSITION_WIDTH_RATIO := 0.25
const CONSTRUCT_MATERIAL := 5
const TERRAIN_BOUNDS := AABB(Vector3(-32.0, 0.0, -32.0), Vector3(96.0, 32.0, 96.0))
const TOPOLOGY_SECTION_AXIS := 0
const TOPOLOGY_SECTION_PLANE := 46.14122
const EXPECTED_SECTION_COMPONENTS := 2

var _field := ReferenceField.new()
var edits: Array[Dictionary]:
	get:
		return _field.edits
	set(value):
		_field.set_edits(value)


func build(probe: RefCounted) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	if probe == null or not probe.has_method("mesh_chunk_with_callable"):
		return _unavailable_result("mesh_chunk_with_callable unavailable")
	var chunks: Array[Dictionary] = []
	var failed_chunks := 0
	var sample_count := 0
	var triangle_count := 0
	var regular_triangles := 0
	var transition_triangles := 0
	for spec in fixture_specs():
		var chunk := _mesh_spec(probe, spec)
		chunks.append(chunk)
		if not bool(chunk.get("ok", false)):
			failed_chunks += 1
		sample_count += int(chunk.get("sample_count", 0))
		triangle_count += int(chunk.get("triangle_count", 0))
		var regular: Dictionary = chunk.get("regular", {})
		regular_triangles += int(regular.get("triangle_count", 0))
		for transition_value in chunk.get("transitions", []):
			var transition: Dictionary = transition_value
			transition_triangles += int(transition.get("triangle_count", 0))
	var buffers := _all_rendered_buffers(chunks)
	var material_ids := _material_ids(buffers)
	var seam_validation := _validate_seams(chunks)
	return {
		"schema": Contracts.REFERENCE_TERRAIN_FIXTURE_SCHEMA,
		"authority": Contracts.NATIVE_AUTHORITY,
		"implementation": Contracts.REFERENCE_TERRAIN_IMPLEMENTATION,
		"fixture_id": FIXTURE_ID,
		"available": true,
		"ok": failed_chunks == 0,
		"status": "PASS" if failed_chunks == 0 else "FAIL",
		"bounds": TERRAIN_BOUNDS,
		"chunk_count": chunks.size(),
		"coarse_chunk_count": 8,
		"fine_chunk_count": 4,
		"transition_chunk_count": 4,
		"failed_chunks": failed_chunks,
		"sample_count": sample_count,
		"triangle_count": triangle_count,
		"regular_triangles": regular_triangles,
		"transition_triangles": transition_triangles,
		"material_ids": material_ids,
		"feature_count": _field.feature_catalog().size(),
		"feature_ids": _field.feature_ids(),
		"feature_catalog": _field.feature_catalog(),
		"seam_validation": seam_validation,
		"edit_count": edits.size(),
		"chunks": chunks,
		"buffers": buffers,
		"geometry_signature": _geometry_signature(chunks),
		"elapsed_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
	}


func validate(probe: RefCounted) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var original_edits := edits.duplicate(true)
	edits.clear()
	var baseline := build(probe)
	var repeated := build(probe)
	var buffer_validation := _validate_buffers(baseline.get("buffers", []))
	var seam_validation: Dictionary = baseline.get("seam_validation", {})
	var feature_validation := _field.validate_feature_probes()
	var topology_separation := _validate_canonical_topology_separation(baseline)
	var negative_fixture := _validate_topology_alias_fixture(probe)
	var deterministic := str(baseline.get("geometry_signature", "")) == str(
		repeated.get("geometry_signature", "")
	)
	var edit_validation := _validate_edit_workflow(probe, baseline)
	edits = original_edits
	var failures: Array = []
	if not bool(baseline.get("ok", false)):
		failures.append("one or more canonical chunks failed to mesh")
	if not deterministic:
		failures.append("canonical terrain geometry changed across identical rebuilds")
	if str(buffer_validation.get("status", "")) != "PASS":
		failures.append("one or more terrain buffers violated native mesh contracts")
	if str(seam_validation.get("status", "")) != "PASS":
		failures.append("one or more canonical terrain seams did not match")
	if str(feature_validation.get("status", "")) != "PASS":
		failures.append("one or more canonical field feature probes changed")
	if str(topology_separation.get("status", "")) != "PASS":
		failures.append("canonical terrain and tunnel sections are not separated")
	if str(negative_fixture.get("status", "")) != "PASS":
		failures.append("coarse topology-alias negative fixture was not detected")
	if str(edit_validation.get("status", "")) != "PASS":
		failures.append("incremental terrain edit rebuild did not match a full rebuild")
	return {
		"schema": Contracts.REFERENCE_TERRAIN_VALIDATION_SCHEMA,
		"authority": Contracts.NATIVE_AUTHORITY,
		"implementation": Contracts.REFERENCE_TERRAIN_IMPLEMENTATION,
		"fixture_id": FIXTURE_ID,
		"status": "PASS" if failures.is_empty() else "FAIL",
		"chunk_count": int(baseline.get("chunk_count", 0)),
		"coarse_chunk_count": int(baseline.get("coarse_chunk_count", 0)),
		"fine_chunk_count": int(baseline.get("fine_chunk_count", 0)),
		"transition_chunk_count": int(baseline.get("transition_chunk_count", 0)),
		"failed_chunks": int(baseline.get("failed_chunks", 0)),
		"sample_count": int(baseline.get("sample_count", 0)),
		"triangle_count": int(baseline.get("triangle_count", 0)),
		"regular_triangles": int(baseline.get("regular_triangles", 0)),
		"transition_triangles": int(baseline.get("transition_triangles", 0)),
		"material_ids": baseline.get("material_ids", []),
		"feature_count": int(baseline.get("feature_count", 0)),
		"feature_ids": baseline.get("feature_ids", []),
		"geometry_signature": str(baseline.get("geometry_signature", "")),
		"determinism_failures": 0 if deterministic else 1,
		"buffer_validation": buffer_validation,
		"seam_validation": seam_validation,
		"feature_validation": feature_validation,
		"topology_separation": topology_separation,
		"negative_fixture": negative_fixture,
		"edit_validation": edit_validation,
		"visible_crack_count": int(seam_validation.get("visible_crack_count", 0)),
		"sample_failures": failures,
		"elapsed_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
	}


func benchmark(probe: RefCounted, iterations: int = 2) -> Dictionary:
	iterations = clampi(iterations, 1, 12)
	var original_edits := edits.duplicate(true)
	edits.clear()
	var timings: Array[float] = []
	var total_samples := 0
	var total_triangles := 0
	var status := "PASS"
	for iteration in range(iterations):
		var started_usec := Time.get_ticks_usec()
		var fixture := build(probe)
		timings.append(float(Time.get_ticks_usec() - started_usec) / 1000.0)
		total_samples += int(fixture.get("sample_count", 0))
		total_triangles += int(fixture.get("triangle_count", 0))
		if not bool(fixture.get("ok", false)):
			status = "FAIL"
	edits = original_edits
	var total_ms := 0.0
	for timing in timings:
		total_ms += timing
	var average_ms := total_ms / float(timings.size()) if not timings.is_empty() else 0.0
	return {
		"status": status,
		"iterations": iterations,
		"average_ms": average_ms,
		"maximum_ms": timings.max() if not timings.is_empty() else 0.0,
		"samples_per_ms": float(total_samples) / maxf(total_ms, 0.000001),
		"triangles_per_ms": float(total_triangles) / maxf(total_ms, 0.000001),
	}


func standard_signature(probe: RefCounted) -> Dictionary:
	var original_edits := edits.duplicate(true)
	edits.clear()
	var fixture := build(probe)
	var integrity := _validate_buffers(fixture.get("buffers", []))
	var topology_separation := _validate_canonical_topology_separation(fixture)
	var negative_fixture := _validate_topology_alias_fixture(probe)
	var standard_ok := str(fixture.get("status", "")) == "PASS" \
		and str(integrity.get("status", "")) == "PASS" \
		and str(topology_separation.get("status", "")) == "PASS" \
		and str(negative_fixture.get("status", "")) == "PASS"
	edits = original_edits
	return {
		"fixture_id": FIXTURE_ID,
		"chunk_count": int(fixture.get("chunk_count", 0)),
		"coarse_chunk_count": int(fixture.get("coarse_chunk_count", 0)),
		"fine_chunk_count": int(fixture.get("fine_chunk_count", 0)),
		"transition_chunk_count": int(fixture.get("transition_chunk_count", 0)),
		"sample_count": int(fixture.get("sample_count", 0)),
		"triangle_count": int(fixture.get("triangle_count", 0)),
		"regular_triangles": int(fixture.get("regular_triangles", 0)),
		"transition_triangles": int(fixture.get("transition_triangles", 0)),
		"material_ids": fixture.get("material_ids", []),
		"feature_count": int(fixture.get("feature_count", 0)),
		"feature_ids": fixture.get("feature_ids", []),
		"feature_probe_count": int(
			_field.validate_feature_probes().get("probe_count", 0)
		),
		"same_lod_matching_pairs": int(
			fixture.get("seam_validation", {}).get("same_lod_matching_pairs", 0)
		),
		"mixed_lod_matching_interfaces": int(
			fixture.get("seam_validation", {}).get("mixed_lod_matching_interfaces", 0)
		),
		"mesh_integrity": {
			"nonfinite_vertices": int(integrity.get("nonfinite_vertices", 0)),
			"degenerate_triangles": int(integrity.get("degenerate_triangles", 0)),
			"duplicate_triangles": int(integrity.get("duplicate_triangles", 0)),
			"winding_normal_conflicts": int(
				integrity.get("winding_normal_conflicts", 0)
			),
			"local_winding_normal_disagreements": int(
				integrity.get("local_winding_normal_disagreements", 0)
			),
			"local_winding_normal_ambiguous": int(
				integrity.get("local_winding_normal_ambiguous", 0)
			),
			"nonmanifold_edges": int(integrity.get("nonmanifold_edges", 0)),
			"orientation_conflict_edges": int(
				integrity.get("orientation_conflict_edges", 0)
			),
			"expected_normal_winding_polarity": MeshAnalysis.NORMAL_WINDING_POLARITY,
		},
		"topology_separation": topology_separation,
		"negative_fixture": negative_fixture,
		"geometry_signature": str(fixture.get("geometry_signature", "")),
		"status": "PASS" if standard_ok else "FAIL",
	}


func apply_edit(mode: String, center: Vector3, radius: float, material: int = CONSTRUCT_MATERIAL) -> void:
	_field.apply_edit(mode, center, radius, material)


func clear_edits() -> void:
	_field.clear_edits()


func set_edits(values: Array) -> void:
	_field.set_edits(values)


func dirty_region() -> AABB:
	return _field.dirty_region()


func sample_point(point: Vector3) -> Dictionary:
	return _field.sample_point(point)


func feature_catalog() -> Array[Dictionary]:
	return _field.feature_catalog()


func affected_chunk_ids(center: Vector3, radius: float) -> Array[String]:
	var result: Array[String] = []
	for spec in fixture_specs():
		var dependency_halo := float(1 << int(spec.get("lod", 0)))
		if _sphere_intersects_aabb(
			center,
			radius,
			_spec_bounds(spec).grow(dependency_halo)
		):
			result.append(str(spec.get("id", "")))
	return result


func fixture_specs() -> Array[Dictionary]:
	return [
		_spec("coarse_north_west", Vector3i(-1, 0, -1), COARSE_LOD, 0),
		_spec("coarse_north", Vector3i(0, 0, -1), COARSE_LOD, 1 << 5),
		_spec("coarse_north_east", Vector3i(1, 0, -1), COARSE_LOD, 0),
		_spec("coarse_west", Vector3i(-1, 0, 0), COARSE_LOD, 1 << 1),
		_spec("coarse_east", Vector3i(1, 0, 0), COARSE_LOD, 1 << 0),
		_spec("coarse_south_west", Vector3i(-1, 0, 1), COARSE_LOD, 0),
		_spec("coarse_south", Vector3i(0, 0, 1), COARSE_LOD, 1 << 4),
		_spec("coarse_south_east", Vector3i(1, 0, 1), COARSE_LOD, 0),
		_spec("fine_00", Vector3i(0, 0, 0), FINE_LOD, 0),
		_spec("fine_10", Vector3i(1, 0, 0), FINE_LOD, 0),
		_spec("fine_01", Vector3i(0, 0, 1), FINE_LOD, 0),
		_spec("fine_11", Vector3i(1, 0, 1), FINE_LOD, 0),
	]


func _spec(id_value: String, coordinate: Vector3i, lod: int, transition_mask: int) -> Dictionary:
	return {
		"id": id_value,
		"coordinate": coordinate,
		"lod": lod,
		"transition_mask": transition_mask,
	}


func _mesh_spec(probe: RefCounted, spec: Dictionary) -> Dictionary:
	return _mesh_spec_with_field(probe, spec, _field)


func _mesh_spec_with_field(
	probe: RefCounted,
	spec: Dictionary,
	field: RefCounted
) -> Dictionary:
	var chunk: Dictionary = probe.call(
		"mesh_chunk_with_callable",
		Callable(field, "sample"),
		spec.get("coordinate", Vector3i.ZERO),
		int(spec.get("lod", 0)),
		int(spec.get("transition_mask", 0)),
		int(spec.get("transition_mask", 0)),
		ISO_VALUE,
		TRANSITION_WIDTH_RATIO
	)
	chunk["fixture_chunk_id"] = str(spec.get("id", ""))
	chunk["requested_transition_mask"] = int(spec.get("transition_mask", 0))
	return chunk


func _sample(point: Vector3i) -> Dictionary:
	return _field.sample(point)


func _validate_canonical_topology_separation(fixture: Dictionary) -> Dictionary:
	var buffer := _regular_buffer_by_id(fixture.get("buffers", []), "coarse_east")
	var section := _plane_section_topology(
		[buffer] if not buffer.is_empty() else [],
		TOPOLOGY_SECTION_AXIS,
		TOPOLOGY_SECTION_PLANE
	)
	var roof := _field.main_tunnel_roof_clearance(TOPOLOGY_SECTION_PLANE)
	var coarse_cell_size := float(1 << COARSE_LOD)
	var status_ok := not buffer.is_empty() \
		and int(section.get("component_count", 0)) == EXPECTED_SECTION_COMPONENTS \
		and int(section.get("open_endpoint_count", -1)) == 2 \
		and int(section.get("branch_point_count", -1)) == 0 \
		and float(roof.get("minimum_clearance", 0.0)) > coarse_cell_size
	return {
		"schema": "world_transvoxel.cell_lab.topology_separation.v1",
		"id": "canonical_main_tunnel_roof",
		"status": "PASS" if status_ok else "FAIL",
		"section_axis": TOPOLOGY_SECTION_AXIS,
		"section_plane": TOPOLOGY_SECTION_PLANE,
		"expected_analytic_components": EXPECTED_SECTION_COMPONENTS,
		"extracted_component_count": int(section.get("component_count", 0)),
		"section_segment_count": int(section.get("segment_count", 0)),
		"open_endpoint_count": int(section.get("open_endpoint_count", 0)),
		"branch_point_count": int(section.get("branch_point_count", 0)),
		"minimum_roof_clearance": float(roof.get("minimum_clearance", 0.0)),
		"minimum_roof_clearance_z": float(roof.get("minimum_clearance_z", 0.0)),
		"coarse_cell_size": coarse_cell_size,
	}


func build_topology_alias_fixture(probe: RefCounted) -> Dictionary:
	var alias_field := ReferenceField.new()
	alias_field.set_fixture_profile(ReferenceField.PROFILE_COARSE_TUNNEL_ROOF_ALIAS)
	var coarse_chunk := _mesh_spec_with_field(
		probe,
		_spec("alias_coarse_east", Vector3i(1, 0, 0), COARSE_LOD, 0),
		alias_field
	)
	var coarse_buffer := _buffer_from_mesh(
		coarse_chunk,
		coarse_chunk.get("regular", {}),
		_chunk_origin(coarse_chunk),
		"regular",
		-1
	)
	var fine_chunks: Array[Dictionary] = []
	for coordinate in [
		Vector3i(2, 0, 0),
		Vector3i(3, 0, 0),
		Vector3i(2, 0, 1),
		Vector3i(3, 0, 1),
	]:
		fine_chunks.append(_mesh_spec_with_field(
			probe,
			_spec("alias_fine_%d_%d" % [coordinate.x, coordinate.z], coordinate, FINE_LOD, 0),
			alias_field
		))
	var fine_buffers: Array = []
	var fine_ok := true
	for chunk in fine_chunks:
		fine_ok = fine_ok and bool(chunk.get("ok", false))
		fine_buffers.append(_buffer_from_mesh(
			chunk,
			chunk.get("regular", {}),
			_chunk_origin(chunk),
			"regular",
			-1
		))
	return {
		"field": alias_field,
		"coarse_chunk": coarse_chunk,
		"coarse_buffer": coarse_buffer,
		"fine_chunks": fine_chunks,
		"fine_buffers": fine_buffers,
		"fine_ok": fine_ok,
		"roof": alias_field.main_tunnel_roof_clearance(TOPOLOGY_SECTION_PLANE),
	}


func _validate_topology_alias_fixture(probe: RefCounted) -> Dictionary:
	var fixture := build_topology_alias_fixture(probe)
	var coarse_chunk: Dictionary = fixture.get("coarse_chunk", {})
	var coarse_buffer: Dictionary = fixture.get("coarse_buffer", {})
	var fine_buffers: Array = fixture.get("fine_buffers", [])
	var fine_ok := bool(fixture.get("fine_ok", false))
	var coarse_integrity := _winding_diagnostics([coarse_buffer])
	var fine_integrity := _winding_diagnostics(fine_buffers)
	var coarse_section := _plane_section_topology(
		[coarse_buffer],
		TOPOLOGY_SECTION_AXIS,
		TOPOLOGY_SECTION_PLANE
	)
	var fine_section := _plane_section_topology(
		fine_buffers,
		TOPOLOGY_SECTION_AXIS,
		TOPOLOGY_SECTION_PLANE
	)
	var roof: Dictionary = fixture.get("roof", {})
	var coarse_cell_size := float(1 << COARSE_LOD)
	var detected := bool(coarse_chunk.get("ok", false)) \
		and fine_ok \
		and float(roof.get("minimum_clearance", 0.0)) > 0.0 \
		and float(roof.get("minimum_clearance", INF)) < coarse_cell_size \
		and int(coarse_section.get("component_count", 0)) == 1 \
		and int(fine_section.get("component_count", 0)) == EXPECTED_SECTION_COMPONENTS \
		and int(coarse_integrity.get("local_winding_normal_disagreements", 0)) == 8 \
		and int(coarse_integrity.get("winding_normal_conflicts", -1)) == 0 \
		and int(fine_integrity.get("local_winding_normal_disagreements", -1)) == 0 \
		and int(fine_integrity.get("winding_normal_conflicts", -1)) == 0
	return {
		"schema": "world_transvoxel.cell_lab.negative_terrain_fixture.v1",
		"id": TOPOLOGY_ALIAS_FIXTURE_ID,
		"status": "PASS" if detected else "FAIL",
		"expected_result": "coarse_alias_detected_and_fine_control_separated",
		"detected": detected,
		"section_axis": TOPOLOGY_SECTION_AXIS,
		"section_plane": TOPOLOGY_SECTION_PLANE,
		"expected_analytic_components": EXPECTED_SECTION_COMPONENTS,
		"coarse_extracted_components": int(coarse_section.get("component_count", 0)),
		"fine_extracted_components": int(fine_section.get("component_count", 0)),
		"coarse_section_segments": int(coarse_section.get("segment_count", 0)),
		"fine_section_segments": int(fine_section.get("segment_count", 0)),
		"coarse_local_winding_normal_disagreements": int(
			coarse_integrity.get("local_winding_normal_disagreements", 0)
		),
		"fine_local_winding_normal_disagreements": int(
			fine_integrity.get("local_winding_normal_disagreements", 0)
		),
		"coarse_winding_normal_conflicts": int(
			coarse_integrity.get("winding_normal_conflicts", 0)
		),
		"fine_winding_normal_conflicts": int(
			fine_integrity.get("winding_normal_conflicts", 0)
		),
		"minimum_roof_clearance": float(roof.get("minimum_clearance", 0.0)),
		"minimum_roof_clearance_z": float(roof.get("minimum_clearance_z", 0.0)),
		"coarse_cell_size": coarse_cell_size,
	}


func _regular_buffer_by_id(buffers: Array, chunk_id: String) -> Dictionary:
	for buffer_value in buffers:
		var buffer: Dictionary = buffer_value
		if str(buffer.get("chunk_id", "")) == chunk_id \
				and str(buffer.get("kind", "")) == "regular":
			return buffer
	return {}


func _winding_diagnostics(buffers: Array) -> Dictionary:
	var local_disagreements := 0
	var local_ambiguous := 0
	var component_conflicts := 0
	for buffer_value in buffers:
		var buffer: Dictionary = buffer_value
		var integrity := MeshAnalysis.validate_triangle_mesh_integrity(
			buffer.get("vertices", PackedVector3Array()),
			buffer.get("normals", PackedVector3Array()),
			buffer.get("indices", PackedInt32Array())
		)
		local_disagreements += int(
			integrity.get("local_winding_normal_disagreements", 0)
		)
		local_ambiguous += int(integrity.get("local_winding_normal_ambiguous", 0))
		component_conflicts += int(integrity.get("winding_normal_conflicts", 0))
	return {
		"local_winding_normal_disagreements": local_disagreements,
		"local_winding_normal_ambiguous": local_ambiguous,
		"winding_normal_conflicts": component_conflicts,
	}


func _plane_section_topology(buffers: Array, axis: int, plane: float) -> Dictionary:
	var segments := {}
	for buffer_value in buffers:
		var buffer: Dictionary = buffer_value
		var origin: Vector3 = buffer.get("origin", Vector3.ZERO)
		var vertices: PackedVector3Array = buffer.get("vertices", PackedVector3Array())
		var indices: PackedInt32Array = buffer.get("indices", PackedInt32Array())
		for offset in range(0, indices.size(), 3):
			if offset + 2 >= indices.size():
				break
			var points := [
				vertices[indices[offset]] + origin,
				vertices[indices[offset + 1]] + origin,
				vertices[indices[offset + 2]] + origin,
			]
			var hits: Array[Vector3] = []
			for pair in [[0, 1], [1, 2], [2, 0]]:
				var a: Vector3 = points[pair[0]]
				var b: Vector3 = points[pair[1]]
				var da := a[axis] - plane
				var db := b[axis] - plane
				if absf(da) <= 0.000001:
					_append_unique_section_hit(hits, a)
				if absf(db) <= 0.000001:
					_append_unique_section_hit(hits, b)
				if da * db < 0.0:
					_append_unique_section_hit(hits, a.lerp(b, da / (da - db)))
			if hits.size() < 2:
				continue
			var first := _section_point_key(hits[0])
			var second := _section_point_key(hits[1])
			if first == second:
				continue
			var segment_key := "%s|%s" % [first, second] \
				if first < second else "%s|%s" % [second, first]
			segments[segment_key] = [first, second]
	var adjacency := {}
	for endpoints_value in segments.values():
		var endpoints: Array = endpoints_value
		_connect_section_points(adjacency, str(endpoints[0]), str(endpoints[1]))
	var visited := {}
	var component_count := 0
	for start_value in adjacency.keys():
		var start := str(start_value)
		if visited.has(start):
			continue
		component_count += 1
		var pending: Array[String] = [start]
		visited[start] = true
		while not pending.is_empty():
			var current := pending.pop_back()
			for neighbor_value in adjacency.get(current, []):
				var neighbor := str(neighbor_value)
				if visited.has(neighbor):
					continue
				visited[neighbor] = true
				pending.append(neighbor)
	var open_endpoints := 0
	var branch_points := 0
	for neighbors_value in adjacency.values():
		var degree := (neighbors_value as Array).size()
		open_endpoints += 1 if degree == 1 else 0
		branch_points += 1 if degree > 2 else 0
	return {
		"component_count": component_count,
		"segment_count": segments.size(),
		"point_count": adjacency.size(),
		"open_endpoint_count": open_endpoints,
		"branch_point_count": branch_points,
	}


func _append_unique_section_hit(hits: Array[Vector3], point: Vector3) -> void:
	for existing in hits:
		if existing.distance_squared_to(point) <= 0.0000000001:
			return
	hits.append(point)


func _section_point_key(point: Vector3) -> String:
	return "%d:%d:%d" % [
		roundi(point.x * 10000.0),
		roundi(point.y * 10000.0),
		roundi(point.z * 10000.0),
	]


func _connect_section_points(adjacency: Dictionary, first: String, second: String) -> void:
	if not adjacency.has(first):
		adjacency[first] = []
	if not adjacency.has(second):
		adjacency[second] = []
	if second not in adjacency[first]:
		adjacency[first].append(second)
	if first not in adjacency[second]:
		adjacency[second].append(first)


func _validate_buffers(
	buffers: Array,
	reject_local_winding_diagnostics: bool = true
) -> Dictionary:
	var failures := 0
	var invalid_indices := 0
	var invalid_normals := 0
	var invalid_materials := 0
	var nonfinite_vertices := 0
	var degenerate_triangles := 0
	var duplicate_triangles := 0
	var winding_normal_conflicts := 0
	var local_winding_normal_disagreements := 0
	var local_winding_normal_ambiguous := 0
	var integrity_failures: Array = []
	var nonmanifold_edges := 0
	var orientation_conflicts := 0
	for buffer_value in buffers:
		var buffer: Dictionary = buffer_value
		var vertices: PackedVector3Array = buffer.get("vertices", PackedVector3Array())
		var normals: PackedVector3Array = buffer.get("normals", PackedVector3Array())
		var indices: PackedInt32Array = buffer.get("indices", PackedInt32Array())
		var materials: PackedInt32Array = buffer.get("materials", PackedInt32Array())
		if indices.size() % 3 != 0:
			invalid_indices += 1
		for index in indices:
			if int(index) < 0 or int(index) >= vertices.size():
				invalid_indices += 1
				break
		if not vertices.is_empty() and normals.size() != vertices.size():
			invalid_normals += 1
		else:
			for normal in normals:
				if not MeshAnalysis.normal_is_valid(normal):
					invalid_normals += 1
					break
		if not vertices.is_empty() and materials.size() != vertices.size():
			invalid_materials += 1
		else:
			for material in materials:
				if int(material) <= 0 or int(material) > 65535:
					invalid_materials += 1
					break
		var topology := MeshAnalysis.isolated_edge_metrics(vertices, indices)
		var integrity := MeshAnalysis.validate_triangle_mesh_integrity(
			vertices,
			normals,
			indices
		)
		nonfinite_vertices += int(integrity.get("nonfinite_vertices", 0))
		degenerate_triangles += int(integrity.get("degenerate_triangles", 0))
		duplicate_triangles += int(integrity.get("duplicate_triangles", 0))
		winding_normal_conflicts += int(
			integrity.get("winding_normal_conflicts", 0)
		)
		local_winding_normal_disagreements += int(
			integrity.get("local_winding_normal_disagreements", 0)
		)
		local_winding_normal_ambiguous += int(
			integrity.get("local_winding_normal_ambiguous", 0)
		)
		if int(integrity.get("nonfinite_vertices", 0)) > 0 \
				or int(integrity.get("degenerate_triangles", 0)) > 0 \
				or int(integrity.get("duplicate_triangles", 0)) > 0 \
				or int(integrity.get("winding_normal_conflicts", 0)) > 0 \
				or (
					reject_local_winding_diagnostics
					and (
						int(integrity.get("local_winding_normal_disagreements", 0)) > 0
						or int(integrity.get("local_winding_normal_ambiguous", 0)) > 0
					)
				):
			integrity_failures.append({
				"chunk_id": buffer.get("chunk_id", ""),
				"kind": buffer.get("kind", ""),
				"face": buffer.get("face", -1),
				"integrity": integrity,
			})
		nonmanifold_edges += int(topology.get("nonmanifold_edges", 0))
		var orientation := MeshAnalysis.orientation_metrics(vertices, indices)
		orientation_conflicts += int(orientation.get("orientation_conflict_edges", 0))
	failures = invalid_indices + invalid_normals + invalid_materials \
		+ nonfinite_vertices + degenerate_triangles + duplicate_triangles \
		+ winding_normal_conflicts + nonmanifold_edges + orientation_conflicts
	if reject_local_winding_diagnostics:
		failures += local_winding_normal_disagreements + local_winding_normal_ambiguous
	return {
		"status": "PASS" if failures == 0 else "FAIL",
		"buffer_count": buffers.size(),
		"invalid_indices": invalid_indices,
		"invalid_normals": invalid_normals,
		"invalid_materials": invalid_materials,
		"nonfinite_vertices": nonfinite_vertices,
		"degenerate_triangles": degenerate_triangles,
		"duplicate_triangles": duplicate_triangles,
		"winding_normal_conflicts": winding_normal_conflicts,
		"local_winding_normal_disagreements": local_winding_normal_disagreements,
		"local_winding_normal_ambiguous": local_winding_normal_ambiguous,
		"integrity_failures": integrity_failures,
		"nonmanifold_edges": nonmanifold_edges,
		"orientation_conflict_edges": orientation_conflicts,
		"reject_local_winding_diagnostics": reject_local_winding_diagnostics,
		"failure_count": failures,
	}


func _validate_seams(chunks: Array) -> Dictionary:
	var by_id := {}
	for chunk_value in chunks:
		var chunk: Dictionary = chunk_value
		by_id[str(chunk.get("fixture_chunk_id", ""))] = chunk
	var same_lod_specs := [
		["coarse_north_west", "coarse_north", 1, 0],
		["coarse_north", "coarse_north_east", 1, 0],
		["coarse_north_west", "coarse_west", 5, 4],
		["coarse_north_east", "coarse_east", 5, 4],
		["coarse_west", "coarse_south_west", 5, 4],
		["coarse_east", "coarse_south_east", 5, 4],
		["coarse_south_west", "coarse_south", 1, 0],
		["coarse_south", "coarse_south_east", 1, 0],
		["fine_00", "fine_10", 1, 0],
		["fine_01", "fine_11", 1, 0],
		["fine_00", "fine_01", 5, 4],
		["fine_10", "fine_11", 5, 4],
	]
	var same_matching := 0
	var same_mismatched := 0
	var same_left_only := 0
	var same_right_only := 0
	var same_interfaces: Array = []
	for pair in same_lod_specs:
		var left: Dictionary = by_id.get(str(pair[0]), {})
		var right: Dictionary = by_id.get(str(pair[1]), {})
		var left_signatures := _chunk_face_signatures(left, int(pair[2]), false)
		var right_signatures := _chunk_face_signatures(right, int(pair[3]), false)
		var difference := MeshAnalysis.set_difference_counts(left_signatures, right_signatures)
		var axis := _face_axis(int(pair[2]))
		var plane := _face_plane(left, int(pair[2]))
		var matching_signatures := _intersection_keys(
			left_signatures,
			right_signatures
		)
		same_left_only += int(difference.get("left_only", 0))
		same_right_only += int(difference.get("right_only", 0))
		var matches := int(difference.get("left_only", 0)) == 0 \
			and int(difference.get("right_only", 0)) == 0
		if matches:
			same_matching += 1
		else:
			same_mismatched += 1
		same_interfaces.append({
			"left_chunk": pair[0],
			"right_chunk": pair[1],
			"left_face_index": int(pair[2]),
			"right_face_index": int(pair[3]),
			"left_face": Contracts.CHUNK_FACE_NAMES[int(pair[2])],
			"right_face": Contracts.CHUNK_FACE_NAMES[int(pair[3])],
			"axis": axis,
			"plane": plane,
			"matches": matches,
			"matching_signature_count": matching_signatures.size(),
			"matching_signatures": matching_signatures,
			"left_only": int(difference.get("left_only", 0)),
			"right_only": int(difference.get("right_only", 0)),
			"left_only_signatures": _set_only_keys(left_signatures, right_signatures),
			"right_only_signatures": _set_only_keys(right_signatures, left_signatures),
		})
	var mixed_specs := [
		["coarse_west", 1, ["fine_00", "fine_01"], 0],
		["coarse_east", 0, ["fine_10", "fine_11"], 1],
		["coarse_north", 5, ["fine_00", "fine_10"], 4],
		["coarse_south", 4, ["fine_01", "fine_11"], 5],
	]
	var mixed_matching := 0
	var mixed_mismatched := 0
	var coarse_only := 0
	var fine_only := 0
	var mixed_interfaces: Array = []
	for interface_spec in mixed_specs:
		var coarse: Dictionary = by_id.get(str(interface_spec[0]), {})
		var coarse_face := int(interface_spec[1])
		var axis := _face_axis(coarse_face)
		var plane := _face_plane(coarse, coarse_face)
		var coarse_signatures := MeshAnalysis.plane_open_edge_signatures(
			_chunk_buffers(coarse, coarse_face),
			axis,
			plane
		)
		var fine_buffers: Array = []
		for fine_id in interface_spec[2]:
			var fine: Dictionary = by_id.get(str(fine_id), {})
			fine_buffers.append_array(_chunk_buffers(fine, -1))
		var fine_signatures := MeshAnalysis.plane_open_edge_signatures(fine_buffers, axis, plane)
		var difference := MeshAnalysis.set_difference_counts(coarse_signatures, fine_signatures)
		var matching_signatures := _intersection_keys(
			coarse_signatures,
			fine_signatures
		)
		var matches := int(difference.get("left_only", 0)) == 0 \
			and int(difference.get("right_only", 0)) == 0
		coarse_only += int(difference.get("left_only", 0))
		fine_only += int(difference.get("right_only", 0))
		mixed_matching += 1 if matches else 0
		mixed_mismatched += 0 if matches else 1
		mixed_interfaces.append({
			"coarse_chunk": interface_spec[0],
			"coarse_face_index": coarse_face,
			"coarse_face": Contracts.CHUNK_FACE_NAMES[coarse_face],
			"fine_chunks": interface_spec[2],
			"fine_face_index": int(interface_spec[3]),
			"fine_face": Contracts.CHUNK_FACE_NAMES[int(interface_spec[3])],
			"axis": axis,
			"plane": plane,
			"matches": matches,
			"matching_signature_count": matching_signatures.size(),
			"matching_signatures": matching_signatures,
			"coarse_only": int(difference.get("left_only", 0)),
			"fine_only": int(difference.get("right_only", 0)),
			"coarse_only_signatures": _set_only_keys(
				coarse_signatures,
				fine_signatures
			),
			"fine_only_signatures": _set_only_keys(
				fine_signatures,
				coarse_signatures
			),
		})
	var visible_cracks := same_left_only + same_right_only + coarse_only + fine_only
	return {
		"status": "PASS" if same_mismatched == 0 and mixed_mismatched == 0 else "FAIL",
		"same_lod_pairs": same_lod_specs.size(),
		"same_lod_matching_pairs": same_matching,
		"same_lod_mismatched_pairs": same_mismatched,
		"same_lod_left_only_edges": same_left_only,
		"same_lod_right_only_edges": same_right_only,
		"mixed_lod_interfaces": mixed_specs.size(),
		"mixed_lod_matching_interfaces": mixed_matching,
		"mixed_lod_mismatched_interfaces": mixed_mismatched,
		"mixed_lod_coarse_only_edges": coarse_only,
		"mixed_lod_fine_only_edges": fine_only,
		"visible_crack_count": visible_cracks,
		"same_interfaces": same_interfaces,
		"interfaces": mixed_interfaces,
	}


func _validate_edit_workflow(probe: RefCounted, baseline: Dictionary) -> Dictionary:
	var steps := [
		{
			"name": "dig_cross_chunk_surface",
			"mode": "dig",
			"center": Vector3(16.0, 12.5, 16.0),
			"radius": 3.25,
			"material": 0,
		},
		{
			"name": "construct_cross_chunk_surface",
			"mode": "construct",
			"center": Vector3(16.0, 14.0, 16.0),
			"radius": 2.75,
			"material": CONSTRUCT_MATERIAL,
		},
		{
			"name": "dig_fine_00_surface",
			"mode": "dig",
			"center": Vector3(8.0, 15.8, 8.0),
			"radius": 2.1,
			"material": 0,
		},
		{
			"name": "construct_fine_10_overhang",
			"mode": "construct",
			"center": Vector3(24.0, 16.3, 8.0),
			"radius": 2.0,
			"material": CONSTRUCT_MATERIAL,
		},
		{
			"name": "dig_fine_01_arch",
			"mode": "dig",
			"center": Vector3(8.0, 13.0, 24.0),
			"radius": 2.0,
			"material": 0,
		},
		{
			"name": "construct_fine_11_surface",
			"mode": "construct",
			"center": Vector3(24.0, 11.5, 24.0),
			"radius": 2.0,
			"material": CONSTRUCT_MATERIAL,
		},
		{
			"name": "dig_east_west_boundary",
			"mode": "dig",
			"center": Vector3(16.0, 14.0, 8.0),
			"radius": 1.75,
			"material": 0,
		},
		{
			"name": "construct_north_south_boundary",
			"mode": "construct",
			"center": Vector3(8.0, 13.0, 16.0),
			"radius": 1.75,
			"material": CONSTRUCT_MATERIAL,
		},
	]
	var before := baseline
	var step_results: Array = []
	var passing_steps := 0
	for edit_step in steps:
		var center: Vector3 = edit_step.get("center", Vector3.ZERO)
		var radius := float(edit_step.get("radius", 1.0))
		apply_edit(
			str(edit_step.get("mode", "")),
			center,
			radius,
			int(edit_step.get("material", CONSTRUCT_MATERIAL))
		)
		var affected_ids := affected_chunk_ids(center, radius)
		var affected_specs: Array[Dictionary] = []
		for spec in fixture_specs():
			if str(spec.get("id", "")) in affected_ids:
				affected_specs.append(spec)
		var partial_chunks: Array[Dictionary] = []
		for affected_spec in affected_specs:
			partial_chunks.append(_mesh_spec(probe, affected_spec))
		var after := build(probe)
		var before_by_id := _chunks_by_id(before.get("chunks", []))
		var after_by_id := _chunks_by_id(after.get("chunks", []))
		var partial_by_id := _chunks_by_id(partial_chunks)
		var changed_ids: Array[String] = []
		var unexpected_changes: Array[String] = []
		var partial_mismatches: Array[String] = []
		for chunk_id in after_by_id.keys():
			var changed := not _chunks_equivalent(
				before_by_id.get(chunk_id, {}),
				after_by_id.get(chunk_id, {})
			)
			if changed:
				changed_ids.append(str(chunk_id))
				if str(chunk_id) not in affected_ids:
					unexpected_changes.append(str(chunk_id))
			if str(chunk_id) in affected_ids and not _chunks_equivalent(
				partial_by_id.get(chunk_id, {}),
				after_by_id.get(chunk_id, {})
			):
				partial_mismatches.append(str(chunk_id))
		var seams := _validate_seams(after.get("chunks", []))
		var buffers := _validate_buffers(after.get("buffers", []), false)
		var step_ok := bool(after.get("ok", false)) \
			and not changed_ids.is_empty() \
			and unexpected_changes.is_empty() \
			and partial_mismatches.is_empty() \
			and str(seams.get("status", "")) == "PASS" \
			and str(buffers.get("status", "")) == "PASS"
		passing_steps += 1 if step_ok else 0
		step_results.append({
			"name": edit_step.get("name", ""),
			"status": "PASS" if step_ok else "FAIL",
			"affected_chunk_ids": affected_ids,
			"affected_chunk_count": affected_ids.size(),
			"changed_chunk_ids": changed_ids,
			"changed_chunk_count": changed_ids.size(),
			"unexpected_changed_chunks": unexpected_changes,
			"partial_rebuild_mismatches": partial_mismatches,
			"triangle_delta": int(after.get("triangle_count", 0)) \
				- int(before.get("triangle_count", 0)),
			"visible_crack_count": int(seams.get("visible_crack_count", 0)),
			"buffer_failure_count": int(buffers.get("failure_count", 0)),
		})
		before = after
	var final_signature := str(before.get("geometry_signature", ""))
	edits.clear()
	for edit_step in steps:
		apply_edit(
			str(edit_step.get("mode", "")),
			edit_step.get("center", Vector3.ZERO),
			float(edit_step.get("radius", 1.0)),
			int(edit_step.get("material", CONSTRUCT_MATERIAL))
		)
	var replay := build(probe)
	var replay_seams: Dictionary = replay.get("seam_validation", {})
	var replay_buffers := _validate_buffers(replay.get("buffers", []), false)
	var replay_matches := bool(replay.get("ok", false)) \
		and final_signature == str(replay.get("geometry_signature", "")) \
		and str(replay_seams.get("status", "")) == "PASS" \
		and str(replay_buffers.get("status", "")) == "PASS"
	var deterministic_failures := 0 if replay_matches else 1
	return {
		"status": (
			"PASS"
			if passing_steps == steps.size() and deterministic_failures == 0
			else "FAIL"
		),
		"step_count": steps.size(),
		"passing_steps": passing_steps,
		"failing_steps": steps.size() - passing_steps,
		"steps": step_results,
		"final_edit_count": edits.size(),
		"final_geometry_signature": final_signature,
		"replay_geometry_signature": str(replay.get("geometry_signature", "")),
		"replay_matches": replay_matches,
		"deterministic_failures": deterministic_failures,
		"replay_visible_crack_count": int(
			replay_seams.get("visible_crack_count", 0)
		),
		"replay_buffer_failure_count": int(
			replay_buffers.get("failure_count", 0)
		),
	}


func _all_rendered_buffers(chunks: Array) -> Array:
	var buffers: Array = []
	for chunk_value in chunks:
		var chunk: Dictionary = chunk_value
		buffers.append_array(
			_chunk_buffers(chunk, -2)
		)
	return buffers


func _chunk_buffers(chunk: Dictionary, transition_face: int) -> Array:
	var buffers: Array = []
	if chunk.is_empty():
		return buffers
	var origin := _chunk_origin(chunk)
	var regular: Dictionary = chunk.get("regular", {})
	buffers.append(_buffer_from_mesh(chunk, regular, origin, "regular", -1))
	if transition_face == -1:
		return buffers
	var transitions: Array = chunk.get("transitions", [])
	for face in range(transitions.size()):
		if transition_face >= 0 and face != transition_face:
			continue
		if transition_face == -2 and (int(chunk.get("requested_transition_mask", 0)) & (1 << face)) == 0:
			continue
		var transition: Dictionary = transitions[face]
		if (transition.get("indices", PackedInt32Array()) as PackedInt32Array).is_empty():
			continue
		buffers.append(_buffer_from_mesh(chunk, transition, origin, "transition", face))
	return buffers


func _buffer_from_mesh(
	chunk: Dictionary,
	mesh_data: Dictionary,
	origin: Vector3,
	kind: String,
	face: int
) -> Dictionary:
	return {
		"chunk_id": str(chunk.get("fixture_chunk_id", "")),
		"coordinate": chunk.get("chunk_coordinate", Vector3i.ZERO),
		"lod": int(chunk.get("lod", 0)),
		"kind": kind,
		"face": face,
		"origin": origin,
		"vertices": mesh_data.get("vertices", PackedVector3Array()),
		"normals": mesh_data.get("normals", PackedVector3Array()),
		"indices": mesh_data.get("indices", PackedInt32Array()),
		"materials": mesh_data.get("materials", PackedInt32Array()),
	}


func _chunk_face_signatures(chunk: Dictionary, face: int, include_transition: bool) -> Dictionary:
	var axis := _face_axis(face)
	var plane := _face_plane(chunk, face)
	return MeshAnalysis.plane_open_edge_signatures(
		_chunk_buffers(chunk, face if include_transition else -1),
		axis,
		plane
	)


func _set_only_keys(left: Dictionary, right: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in left.keys():
		if not right.has(key):
			result.append(str(key))
	result.sort()
	return result


func _intersection_keys(left: Dictionary, right: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in left.keys():
		if right.has(key):
			result.append(str(key))
	result.sort()
	return result


func _face_plane(chunk: Dictionary, face: int) -> float:
	var origin := _chunk_origin(chunk)
	var extent := float(Contracts.CHUNK_PROBE_CELLS_PER_AXIS * (1 << int(chunk.get("lod", 0))))
	var axis := _face_axis(face)
	return origin[axis] + (extent if _face_is_positive(face) else 0.0)


func _face_axis(face: int) -> int:
	if face == 0 or face == 1:
		return 0
	if face == 2 or face == 3:
		return 1
	return 2


func _face_is_positive(face: int) -> bool:
	return face == 1 or face == 3 or face == 5


func _chunk_origin(chunk: Dictionary) -> Vector3:
	return Vector3(
		float(chunk.get("world_origin_x", 0.0)),
		float(chunk.get("world_origin_y", 0.0)),
		float(chunk.get("world_origin_z", 0.0))
	)


func _material_ids(buffers: Array) -> Array[int]:
	var result: Array[int] = []
	for buffer_value in buffers:
		var buffer: Dictionary = buffer_value
		var materials: PackedInt32Array = buffer.get("materials", PackedInt32Array())
		for material in materials:
			var id := int(material)
			if id > 0 and id not in result:
				result.append(id)
	result.sort()
	return result


func _geometry_signature(chunks: Array) -> String:
	var lines: Array[String] = []
	for chunk_value in chunks:
		var chunk: Dictionary = chunk_value
		lines.append("%s:%s:%d:%d" % [
			str(chunk.get("fixture_chunk_id", "")),
			str(chunk.get("chunk_coordinate", Vector3i.ZERO)),
			int(chunk.get("lod", 0)),
			int(chunk.get("requested_transition_mask", 0)),
		])
		for buffer_value in _chunk_buffers(chunk, -2):
			var buffer: Dictionary = buffer_value
			lines.append("%s:%d" % [
				str(buffer.get("kind", "")),
				int(buffer.get("face", -1)),
			])
			var vertices: PackedVector3Array = buffer.get("vertices", PackedVector3Array())
			for vertex in vertices:
				lines.append("v:%d,%d,%d" % [
					roundi(vertex.x * MeshAnalysis.POSITION_SCALE),
					roundi(vertex.y * MeshAnalysis.POSITION_SCALE),
					roundi(vertex.z * MeshAnalysis.POSITION_SCALE),
				])
			var indices: PackedInt32Array = buffer.get("indices", PackedInt32Array())
			for index in indices:
				lines.append("i:%d" % int(index))
			var materials: PackedInt32Array = buffer.get("materials", PackedInt32Array())
			for material in materials:
				lines.append("m:%d" % int(material))
	return "\n".join(lines).sha256_text()


func _chunks_by_id(chunks: Array) -> Dictionary:
	var result := {}
	for chunk_value in chunks:
		var chunk: Dictionary = chunk_value
		result[str(chunk.get("fixture_chunk_id", ""))] = chunk
	return result


func _chunks_equivalent(left: Dictionary, right: Dictionary) -> bool:
	if left.is_empty() or right.is_empty():
		return false
	if str(left.get("status", "")) != str(right.get("status", "")):
		return false
	if int(left.get("lod", -1)) != int(right.get("lod", -1)):
		return false
	var left_buffers := _chunk_buffers(left, -2)
	var right_buffers := _chunk_buffers(right, -2)
	if left_buffers.size() != right_buffers.size():
		return false
	for index in range(left_buffers.size()):
		var a: Dictionary = left_buffers[index]
		var b: Dictionary = right_buffers[index]
		for key in ["vertices", "normals", "indices", "materials"]:
			if a.get(key) != b.get(key):
				return false
	return true


func _spec_bounds(spec: Dictionary) -> AABB:
	var lod := int(spec.get("lod", 0))
	var extent := float(Contracts.CHUNK_PROBE_CELLS_PER_AXIS * (1 << lod))
	var coordinate: Vector3i = spec.get("coordinate", Vector3i.ZERO)
	return AABB(Vector3(coordinate) * extent, Vector3.ONE * extent)


func _sphere_intersects_aabb(center: Vector3, radius: float, bounds: AABB) -> bool:
	var maximum := bounds.position + bounds.size
	var closest := Vector3(
		clampf(center.x, bounds.position.x, maximum.x),
		clampf(center.y, bounds.position.y, maximum.y),
		clampf(center.z, bounds.position.z, maximum.z)
	)
	return center.distance_squared_to(closest) <= radius * radius


func _unavailable_result(error: String) -> Dictionary:
	return {
		"schema": Contracts.REFERENCE_TERRAIN_FIXTURE_SCHEMA,
		"authority": Contracts.NATIVE_AUTHORITY,
		"implementation": Contracts.REFERENCE_TERRAIN_IMPLEMENTATION,
		"fixture_id": FIXTURE_ID,
		"available": false,
		"ok": false,
		"status": "FAIL",
		"error": error,
		"chunks": [],
		"buffers": [],
	}
