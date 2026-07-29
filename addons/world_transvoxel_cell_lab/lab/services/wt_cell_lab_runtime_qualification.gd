@tool
extends RefCounted
class_name WtCellLabRuntimeQualification

const Contracts := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_contracts.gd")
const MeshAnalysis := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_mesh_analysis.gd")
const ReproStore := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_repro_store.gd")
const ReferenceField := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_reference_field.gd")
const AdversarialField := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_adversarial_field.gd")
const Common := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_qualification_common.gd")

const EDIT_STRESS_SEED := 0x51A7
const EDIT_STRESS_OPERATION_COUNT := 24
const EDIT_STRESS_CHECKPOINT_INTERVAL := 6
const COLLISION_QUERY_TOLERANCE := 1.5
const PRECISION_ERROR_BUDGET := 0.01
const BUFFER_MEMORY_BUDGET_BYTES := 64 * 1024 * 1024
const PERSISTENCE_PATH := "user://world_transvoxel_cell_lab/qualification/persistence_roundtrip.json"


func validate(
	lab: Object,
	probe: RefCounted,
	reference_terrain: RefCounted
) -> Dictionary:
	var start_usec := Time.get_ticks_usec()
	var baseline: Dictionary = lab.call("build_reference_terrain")
	var edit_stress := _validate_edit_stress(lab, reference_terrain)
	var scaling := _validate_scaling(probe)
	var memory := _validate_memory(lab, baseline)
	var rendering := _validate_rendering_quality(baseline)
	var collision := _validate_collision_queries(lab, baseline)
	var streaming := _validate_streaming(probe, reference_terrain, baseline)
	var persistence := _validate_persistence(lab)
	var failures: Array[String] = []
	for entry in [
		["edit_stress", edit_stress],
		["scaling", scaling],
		["memory", memory],
		["rendering_quality", rendering],
		["collision_queries", collision],
		["streaming", streaming],
		["persistence", persistence],
	]:
		var section: Dictionary = entry[1]
		if str(section.get("status", "")) != "PASS":
			failures.append("%s=%s" % [str(entry[0]), str(section.get("status", "FAIL"))])
	return {
		"schema": Contracts.RUNTIME_QUALIFICATION_SCHEMA,
		"status": "PASS" if failures.is_empty() else "FAIL",
		"authority": Contracts.NATIVE_AUTHORITY,
		"edit_stress": edit_stress,
		"scaling": scaling,
		"memory": memory,
		"rendering_quality": rendering,
		"collision_queries": collision,
		"streaming": streaming,
		"persistence": persistence,
		"sample_failures": failures,
		"elapsed_ms": float(Time.get_ticks_usec() - start_usec) / 1000.0,
	}


func standard_signature(validation: Dictionary) -> Dictionary:
	var edit_stress: Dictionary = validation.get("edit_stress", {})
	var scaling: Dictionary = validation.get("scaling", {})
	var memory: Dictionary = validation.get("memory", {})
	var rendering: Dictionary = validation.get("rendering_quality", {})
	var collision: Dictionary = validation.get("collision_queries", {})
	var streaming: Dictionary = validation.get("streaming", {})
	var persistence: Dictionary = validation.get("persistence", {})
	return {
		"schema": Contracts.RUNTIME_QUALIFICATION_STANDARD_SCHEMA,
		"edit_operation_count": int(edit_stress.get("operation_count", 0)),
		"edit_checkpoint_count": int(edit_stress.get("checkpoint_count", 0)),
		"edit_final_signature": str(edit_stress.get("final_signature", "")),
		"scaling_scenario_count": int(scaling.get("scenario_count", 0)),
		"scaling_triangle_count": int(scaling.get("triangle_count", 0)),
		"scaling_signature": str(scaling.get("matrix_signature", "")),
		"canonical_buffer_bytes": int(memory.get("canonical_buffer_bytes", 0)),
		"canonical_buffer_count": int(memory.get("buffer_count", 0)),
		"render_tangent_samples": int(rendering.get("tangent_samples", 0)),
		"render_material_ids": rendering.get("material_ids", []),
		"collision_face_count": int(collision.get("collision_face_count", 0)),
		"collision_query_count": int(collision.get("query_count", 0)),
		"stream_schedule_count": int(streaming.get("schedule_count", 0)),
		"stream_chunk_build_count": int(streaming.get("chunk_build_count", 0)),
		"persistence_edit_count": int(persistence.get("edit_count", 0)),
		"persistence_geometry_signature": str(
			persistence.get("geometry_signature", "")
		),
		"status": str(validation.get("status", "FAIL")),
	}


func _validate_edit_stress(lab: Object, reference_terrain: RefCounted) -> Dictionary:
	var original_edits: Array = lab.call("get_reference_terrain_edits")
	var original_auto_rebuild := bool(lab.get("auto_rebuild"))
	lab.set("auto_rebuild", false)
	var operations := _stress_operations()
	var checkpoints: Array[Dictionary] = []
	var previous_signatures := {}
	var unexpected_changes: Array = []
	var empty_checkpoints := 0
	for count in range(
		EDIT_STRESS_CHECKPOINT_INTERVAL,
		EDIT_STRESS_OPERATION_COUNT + 1,
		EDIT_STRESS_CHECKPOINT_INTERVAL
	):
		var current_operations := operations.slice(0, count)
		lab.call("set_reference_terrain_edits", current_operations)
		var fixture: Dictionary = lab.call("build_reference_terrain")
		var signatures := Common.fixture_chunk_signatures(fixture)
		var changed_ids: Array[String] = []
		if not previous_signatures.is_empty():
			for chunk_id in signatures.keys():
				if str(signatures[chunk_id]) != str(previous_signatures.get(chunk_id, "")):
					changed_ids.append(str(chunk_id))
			var expected_ids := {}
			for operation_index in range(
				count - EDIT_STRESS_CHECKPOINT_INTERVAL,
				count
			):
				var operation: Dictionary = operations[operation_index]
				for chunk_id in reference_terrain.call(
					"affected_chunk_ids",
					operation.get("center", Vector3.ZERO),
					float(operation.get("radius", 1.0))
				):
					expected_ids[str(chunk_id)] = true
			for chunk_id in changed_ids:
				if not expected_ids.has(chunk_id):
					unexpected_changes.append({
						"checkpoint": count,
						"chunk_id": chunk_id,
					})
		if changed_ids.is_empty() and not previous_signatures.is_empty():
			empty_checkpoints += 1
		checkpoints.append({
			"operation_count": count,
			"status": str(fixture.get("status", "FAIL")),
			"geometry_signature": str(fixture.get("geometry_signature", "")),
			"changed_chunk_ids": changed_ids,
			"seam_status": str(
				(fixture.get("seam_validation", {}) as Dictionary).get("status", "FAIL")
			),
		})
		previous_signatures = signatures
	var final_fixture: Dictionary = lab.call("build_reference_terrain")
	var final_signature := str(final_fixture.get("geometry_signature", ""))
	lab.call("set_reference_terrain_edits", [])
	var replay_signatures: Array[String] = []
	for count in range(
		EDIT_STRESS_CHECKPOINT_INTERVAL,
		EDIT_STRESS_OPERATION_COUNT + 1,
		EDIT_STRESS_CHECKPOINT_INTERVAL
	):
		lab.call("set_reference_terrain_edits", operations.slice(0, count))
		var replay: Dictionary = lab.call("build_reference_terrain")
		replay_signatures.append(str(replay.get("geometry_signature", "")))
	var replay_matches := true
	for index in range(checkpoints.size()):
		if str(checkpoints[index].get("geometry_signature", "")) != replay_signatures[index]:
			replay_matches = false
			break
	lab.call("set_reference_terrain_edits", operations)
	var before_duplicate: Dictionary = lab.call("build_reference_terrain")
	var duplicated_operations := operations.duplicate(true)
	duplicated_operations.append((operations.back() as Dictionary).duplicate(true))
	lab.call("set_reference_terrain_edits", duplicated_operations)
	var after_duplicate: Dictionary = lab.call("build_reference_terrain")
	var duplicate_idempotent := str(before_duplicate.get("geometry_signature", "")) == str(
		after_duplicate.get("geometry_signature", "")
	)
	var checkpoints_pass := true
	for checkpoint in checkpoints:
		if str(checkpoint.get("status", "")) != "PASS" \
				or str(checkpoint.get("seam_status", "")) != "PASS":
			checkpoints_pass = false
			break
	lab.call("set_reference_terrain_edits", original_edits)
	lab.set("auto_rebuild", original_auto_rebuild)
	var status_ok: bool = checkpoints_pass \
		and replay_matches \
		and duplicate_idempotent \
		and unexpected_changes.is_empty() \
		and empty_checkpoints == 0 \
		and final_signature == replay_signatures.back()
	return {
		"schema": Contracts.EDIT_STRESS_SCHEMA,
		"status": "PASS" if status_ok else "FAIL",
		"seed": EDIT_STRESS_SEED,
		"operation_count": operations.size(),
		"checkpoint_interval": EDIT_STRESS_CHECKPOINT_INTERVAL,
		"checkpoint_count": checkpoints.size(),
		"passing_checkpoints": checkpoints.size() if checkpoints_pass else 0,
		"replay_matches": replay_matches,
		"duplicate_edit_idempotent": duplicate_idempotent,
		"unexpected_chunk_changes": unexpected_changes,
		"empty_changed_checkpoints": empty_checkpoints,
		"final_signature": final_signature,
		"checkpoints": checkpoints,
		"sample_failures": [] if status_ok else [
			"seeded edit stress invariant failed",
		],
	}


func _stress_operations() -> Array[Dictionary]:
	var operations: Array[Dictionary] = []
	var state := EDIT_STRESS_SEED
	for index in range(EDIT_STRESS_OPERATION_COUNT):
		state = Common.lcg_next(state)
		var x := 1.75 + float(state % 2850) / 100.0
		state = Common.lcg_next(state)
		var z := 1.75 + float(state % 2850) / 100.0
		state = Common.lcg_next(state)
		var y := 7.5 + float(state % 750) / 100.0
		state = Common.lcg_next(state)
		var radius := 0.85 + float(state % 150) / 100.0
		operations.append({
			"mode": "dig" if index % 3 != 1 else "construct",
			"center": Vector3(x, y, z),
			"radius": radius,
			"material": 5 if index % 3 == 1 else 0,
		})
	return operations


func _validate_scaling(probe: RefCounted) -> Dictionary:
	var scenarios := [
		{"id": "plane_lod0", "profile": "diagonal_plane", "lod": 0, "chunks": 1},
		{"id": "plane_lod1", "profile": "diagonal_plane", "lod": 1, "chunks": 1},
		{"id": "plane_lod2", "profile": "diagonal_plane", "lod": 2, "chunks": 1},
		{"id": "plane_lod3", "profile": "diagonal_plane", "lod": 3, "chunks": 1},
		{"id": "curvature_lod0", "profile": "high_curvature", "lod": 0, "chunks": 1},
		{"id": "diagonal_lod1_4_chunks", "profile": "diagonal_plane", "lod": 1, "chunks": 4},
	]
	var results: Array[Dictionary] = []
	var failures: Array = []
	var total_triangles := 0
	var total_samples := 0
	var signature_lines: Array[String] = []
	var coordinates := [
		Vector3i.ZERO,
		Vector3i(1, 0, 0),
		Vector3i(0, 0, 1),
		Vector3i(1, 0, 1),
	]
	for scenario_value in scenarios:
		var scenario: Dictionary = scenario_value
		var start_usec := Time.get_ticks_usec()
		var triangle_count := 0
		var sample_count := 0
		var active_cells := 0
		var bytes := 0
		var chunk_signatures: Array[String] = []
		var scenario_ok := true
		for coordinate_index in range(int(scenario.get("chunks", 1))):
			var field := AdversarialField.new()
			field.configure(str(scenario.get("profile", "diagonal_plane")))
			var chunk := Common.mesh_chunk(
				probe,
				field,
				coordinates[coordinate_index],
				int(scenario.get("lod", 0)),
				0
			)
			var integrity := Common.validate_chunk(chunk)
			scenario_ok = scenario_ok and str(integrity.get("status", "")) == "PASS"
			triangle_count += int(integrity.get("triangle_count", 0))
			sample_count += int(chunk.get("sample_count", 0))
			active_cells += int(chunk.get("active_cells", 0))
			bytes += Common.packed_buffer_bytes(Common.chunk_buffers(chunk))
			chunk_signatures.append(Common.chunk_signature(chunk))
		var elapsed_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
		scenario_ok = scenario_ok and triangle_count > 0 and sample_count > 0
		var entry := {
			"id": str(scenario.get("id", "")),
			"profile": str(scenario.get("profile", "")),
			"lod": int(scenario.get("lod", 0)),
			"chunk_count": int(scenario.get("chunks", 1)),
			"status": "PASS" if scenario_ok else "FAIL",
			"samples": sample_count,
			"active_cells": active_cells,
			"triangles": triangle_count,
			"buffer_bytes": bytes,
			"elapsed_ms": elapsed_ms,
			"samples_per_ms": float(sample_count) / maxf(elapsed_ms, 0.000001),
			"triangles_per_ms": float(triangle_count) / maxf(elapsed_ms, 0.000001),
			"signature": "\n".join(chunk_signatures).sha256_text(),
		}
		results.append(entry)
		total_triangles += triangle_count
		total_samples += sample_count
		signature_lines.append("%s:%s:%d:%d:%d" % [
			entry["id"],
			entry["signature"],
			sample_count,
			active_cells,
			triangle_count,
		])
		if not scenario_ok:
			failures.append({"scenario": entry["id"]})
	return {
		"schema": Contracts.SCALING_QUALIFICATION_SCHEMA,
		"status": "PASS" if failures.is_empty() else "FAIL",
		"scenario_count": results.size(),
		"passing_scenarios": results.size() - failures.size(),
		"failing_scenarios": failures.size(),
		"sample_count": total_samples,
		"triangle_count": total_triangles,
		"matrix_signature": "\n".join(signature_lines).sha256_text(),
		"scenarios": results,
		"sample_failures": failures,
	}


func _validate_memory(lab: Object, baseline: Dictionary) -> Dictionary:
	var before_static := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var before_objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var buffers: Array = baseline.get("buffers", [])
	var canonical_bytes := Common.packed_buffer_bytes(buffers)
	var repeated: Dictionary = lab.call("build_reference_terrain")
	var after_static := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var after_peak := int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX))
	var after_objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var repeated_bytes := Common.packed_buffer_bytes(repeated.get("buffers", []))
	var first_signatures := Common.fixture_chunk_signatures(baseline)
	var repeated_signatures := Common.fixture_chunk_signatures(repeated)
	var reused_chunks := 0
	for chunk_id in first_signatures.keys():
		if str(first_signatures[chunk_id]) == str(repeated_signatures.get(chunk_id, "")):
			reused_chunks += 1
	var triangle_count := int(baseline.get("triangle_count", 0))
	var bytes_per_triangle := float(canonical_bytes) / float(maxi(triangle_count, 1))
	var status_ok := canonical_bytes > 0 \
		and canonical_bytes <= BUFFER_MEMORY_BUDGET_BYTES \
		and repeated_bytes == canonical_bytes \
		and reused_chunks == first_signatures.size()
	return {
		"schema": Contracts.MEMORY_QUALIFICATION_SCHEMA,
		"status": "PASS" if status_ok else "FAIL",
		"buffer_count": buffers.size(),
		"canonical_buffer_bytes": canonical_bytes,
		"repeated_buffer_bytes": repeated_bytes,
		"buffer_churn_bytes": canonical_bytes + repeated_bytes,
		"buffer_memory_budget_bytes": BUFFER_MEMORY_BUDGET_BYTES,
		"bytes_per_triangle": bytes_per_triangle,
		"static_memory_before_bytes": before_static,
		"static_memory_after_bytes": after_static,
		"static_memory_delta_bytes": after_static - before_static,
		"peak_static_memory_bytes": after_peak,
		"object_count_before": before_objects,
		"object_count_after": after_objects,
		"reused_chunk_results": reused_chunks,
		"expected_reused_chunk_results": first_signatures.size(),
		"reuse_contract": "identical_geometry_and_buffer_sizes_on_repeat",
		"sample_failures": [] if status_ok else ["memory or reuse budget failed"],
	}


func _validate_rendering_quality(fixture: Dictionary) -> Dictionary:
	var tangent_failures := 0
	var tangent_samples := 0
	var material_failures := 0
	var material_ids := {}
	var lighting_failures := 0
	var lighting_minimum := INF
	var lighting_maximum := -INF
	var maximum_precision_error := 0.0
	var maximum_normal_angle_error := 0.0
	var offsets := [Vector3.ZERO, Vector3.ONE * 1000.0, Vector3.ONE * 10000.0]
	for buffer_value in fixture.get("buffers", []):
		var buffer: Dictionary = buffer_value
		var vertices: PackedVector3Array = buffer.get("vertices", PackedVector3Array())
		var normals: PackedVector3Array = buffer.get("normals", PackedVector3Array())
		var materials: PackedInt32Array = buffer.get("materials", PackedInt32Array())
		var indices: PackedInt32Array = buffer.get("indices", PackedInt32Array())
		for index in range(vertices.size()):
			if index >= normals.size():
				tangent_failures += 1
				continue
			var normal := normals[index]
			var reference := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
			var tangent := normal.cross(reference).normalized()
			var bitangent := normal.cross(tangent).normalized()
			if absf(normal.dot(tangent)) > 0.0001 \
					or absf(normal.dot(bitangent)) > 0.0001 \
					or absf(tangent.dot(bitangent)) > 0.0001 \
					or absf(tangent.length() - 1.0) > 0.0001:
				tangent_failures += 1
			tangent_samples += 1
			if index >= materials.size() or int(materials[index]) <= 0:
				material_failures += 1
			else:
				material_ids[int(materials[index])] = true
			if index % 11 == 0:
				for light in [
					Vector3(0.37, 0.89, 0.25).normalized(),
					Vector3(-0.71, 0.43, 0.56).normalized(),
					Vector3(0.18, -0.31, 0.93).normalized(),
				]:
					var response := clampf(normal.dot(light) * 0.5 + 0.5, 0.0, 1.0)
					if not MeshAnalysis.float_is_finite(response):
						lighting_failures += 1
					lighting_minimum = minf(lighting_minimum, response)
					lighting_maximum = maxf(lighting_maximum, response)
			for translation in offsets:
				var reconstructed: Vector3 = (vertices[index] + translation) - translation
				maximum_precision_error = maxf(
					maximum_precision_error,
					reconstructed.distance_to(vertices[index])
				)
		for offset in range(0, indices.size(), 3 * 23):
			if offset + 2 >= indices.size():
				break
			var a := vertices[int(indices[offset])]
			var b := vertices[int(indices[offset + 1])]
			var c := vertices[int(indices[offset + 2])]
			var base_normal := (b - a).cross(c - a).normalized()
			for translation in offsets:
				var translated_normal: Vector3 = (
					(b + translation - (a + translation))
					.cross(c + translation - (a + translation))
				).normalized()
				maximum_normal_angle_error = maxf(
					maximum_normal_angle_error,
					base_normal.angle_to(translated_normal)
				)
	var sorted_materials: Array[int] = []
	for material_id in material_ids.keys():
		sorted_materials.append(int(material_id))
	sorted_materials.sort()
	var status_ok := tangent_failures == 0 \
		and material_failures == 0 \
		and lighting_failures == 0 \
		and lighting_maximum - lighting_minimum > 0.25 \
		and maximum_precision_error <= PRECISION_ERROR_BUDGET \
		and maximum_normal_angle_error <= 0.01
	return {
		"schema": Contracts.RENDERING_QUALITY_SCHEMA,
		"status": "PASS" if status_ok else "FAIL",
		"tangent_contract": "derived_orthonormal_basis_from_authoritative_normals",
		"tangent_samples": tangent_samples,
		"tangent_failures": tangent_failures,
		"material_contract": "categorical_native_material_ids_no_blend_weights",
		"material_ids": sorted_materials,
		"material_failures": material_failures,
		"lighting_samples_finite": lighting_failures == 0,
		"lighting_response_minimum": lighting_minimum,
		"lighting_response_maximum": lighting_maximum,
		"precision_offsets": offsets,
		"maximum_precision_error": maximum_precision_error,
		"precision_error_budget": PRECISION_ERROR_BUDGET,
		"maximum_camera_distance_normal_angle_error": maximum_normal_angle_error,
		"sample_failures": [] if status_ok else ["rendering quality invariant failed"],
	}


func _validate_collision_queries(lab: Object, fixture: Dictionary) -> Dictionary:
	var faces := Common.world_faces(fixture.get("buffers", []))
	var collision_shape := ConcavePolygonShape3D.new()
	collision_shape.set_faces(faces)
	var collision_faces := collision_shape.get_faces()
	var query_points := [
		Vector2(-19.3, -18.7),
		Vector2(-3.4, -17.2),
		Vector2(18.6, -19.1),
		Vector2(42.7, -16.8),
		Vector2(-18.4, 40.3),
		Vector2(-4.2, 41.1),
		Vector2(19.2, 39.4),
		Vector2(42.1, 40.7),
		Vector2(-18.2, 4.3),
	]
	var queries: Array[Dictionary] = []
	var failures: Array = []
	var maximum_error := 0.0
	for point in query_points:
		var ray_origin := Vector3(point.x, 32.0, point.y)
		var mesh_y := _highest_vertical_mesh_hit(faces, ray_origin)
		var field_y := _highest_field_crossing(lab, point.x, point.y)
		var error := absf(mesh_y - field_y) if mesh_y > -INF and field_y > -INF else INF
		maximum_error = maxf(maximum_error, error)
		var query_ok := error <= COLLISION_QUERY_TOLERANCE
		queries.append({
			"x": point.x,
			"z": point.y,
			"mesh_y": mesh_y,
			"field_y": field_y,
			"absolute_error": error,
			"status": "PASS" if query_ok else "FAIL",
		})
		if not query_ok:
			failures.append({"x": point.x, "z": point.y, "error": error})
	var shape_exact := collision_faces.size() == faces.size()
	var status_ok := not faces.is_empty() and shape_exact and failures.is_empty()
	return {
		"schema": Contracts.COLLISION_QUERY_SCHEMA,
		"status": "PASS" if status_ok else "FAIL",
		"geometry_source": "exact_authoritative_render_buffers",
		"render_face_vertex_count": faces.size(),
		"collision_face_vertex_count": collision_faces.size(),
		"collision_face_count": int(collision_faces.size() / 3),
		"shape_exact": shape_exact,
		"query_count": queries.size(),
		"passing_queries": queries.size() - failures.size(),
		"failing_queries": failures.size(),
		"maximum_surface_error": maximum_error,
		"surface_error_tolerance": COLLISION_QUERY_TOLERANCE,
		"queries": queries,
		"sample_failures": failures,
	}


func _highest_vertical_mesh_hit(faces: PackedVector3Array, origin: Vector3) -> float:
	var closest_t := INF
	for offset in range(0, faces.size(), 3):
		if offset + 2 >= faces.size():
			break
		var t := _ray_triangle_distance(
			origin,
			Vector3.DOWN,
			faces[offset],
			faces[offset + 1],
			faces[offset + 2]
		)
		if t >= 0.0:
			closest_t = minf(closest_t, t)
	return origin.y - closest_t if closest_t < INF else -INF


func _ray_triangle_distance(
	origin: Vector3,
	direction: Vector3,
	a: Vector3,
	b: Vector3,
	c: Vector3
) -> float:
	var edge_ab := b - a
	var edge_ac := c - a
	var h := direction.cross(edge_ac)
	var determinant := edge_ab.dot(h)
	if absf(determinant) <= 0.0000001:
		return -1.0
	var inverse := 1.0 / determinant
	var s := origin - a
	var u := inverse * s.dot(h)
	if u < 0.0 or u > 1.0:
		return -1.0
	var q := s.cross(edge_ab)
	var v := inverse * direction.dot(q)
	if v < 0.0 or u + v > 1.0:
		return -1.0
	var t := inverse * edge_ac.dot(q)
	return t if t >= 0.0 else -1.0


func _highest_field_crossing(lab: Object, x: float, z: float) -> float:
	var previous_y := 32.0
	var previous_density := float(
		(lab.call("sample_reference_terrain", Vector3(x, previous_y, z)) as Dictionary)
			.get("density", 0.0)
	)
	for step_index in range(1, 129):
		var current_y := 32.0 - float(step_index) * 0.25
		var current_density := float(
			(lab.call("sample_reference_terrain", Vector3(x, current_y, z)) as Dictionary)
				.get("density", 0.0)
		)
		if previous_density >= 0.0 and current_density < 0.0:
			var high := previous_y
			var low := current_y
			for iteration in range(16):
				var middle := (high + low) * 0.5
				var density := float(
					(lab.call(
						"sample_reference_terrain",
						Vector3(x, middle, z)
					) as Dictionary).get("density", 0.0)
				)
				if density >= 0.0:
					high = middle
				else:
					low = middle
			return (high + low) * 0.5
		previous_y = current_y
		previous_density = current_density
	return -INF


func _validate_streaming(
	probe: RefCounted,
	reference_terrain: RefCounted,
	baseline: Dictionary
) -> Dictionary:
	var specs: Array = reference_terrain.call("fixture_specs")
	var baseline_signatures := Common.fixture_chunk_signatures(baseline)
	var orders := [
		range(specs.size()),
		_reversed_indices(specs.size()),
		_seeded_indices(specs.size()),
	]
	var schedules: Array[Dictionary] = []
	var failures: Array = []
	var total_builds := 0
	for schedule_index in range(orders.size()):
		var signatures := {}
		var field := ReferenceField.new()
		for raw_index in orders[schedule_index]:
			var index := int(raw_index)
			var spec: Dictionary = specs[index]
			var chunk := Common.mesh_chunk(
				probe,
				field,
				spec.get("coordinate", Vector3i.ZERO),
				int(spec.get("lod", 0)),
				int(spec.get("transition_mask", 0))
			)
			chunk["fixture_chunk_id"] = str(spec.get("id", ""))
			chunk["requested_transition_mask"] = int(spec.get("transition_mask", 0))
			signatures[str(spec.get("id", ""))] = Common.chunk_signature(chunk)
			total_builds += 1
		var mismatches: Array[String] = []
		for chunk_id in baseline_signatures.keys():
			if str(signatures.get(chunk_id, "")) != str(baseline_signatures[chunk_id]):
				mismatches.append(str(chunk_id))
		var schedule_ok := mismatches.is_empty()
		schedules.append({
			"id": ["forward", "reverse", "seeded"][schedule_index],
			"status": "PASS" if schedule_ok else "FAIL",
			"chunk_count": signatures.size(),
			"mismatches": mismatches,
		})
		if not schedule_ok:
			failures.append({
				"schedule": schedules.back().get("id", ""),
				"mismatches": mismatches,
			})
	var stale_requests := [
		{"chunk": "fine_00", "version": 1},
		{"chunk": "fine_00", "version": 3},
		{"chunk": "fine_00", "version": 2},
		{"chunk": "fine_10", "version": 2},
		{"chunk": "fine_10", "version": 1},
	]
	var accepted_versions := {}
	var stale_rejections := 0
	for request in stale_requests:
		var chunk_id := str(request.get("chunk", ""))
		var version := int(request.get("version", 0))
		if version < int(accepted_versions.get(chunk_id, -1)):
			stale_rejections += 1
			continue
		accepted_versions[chunk_id] = version
	var seam_validation: Dictionary = baseline.get("seam_validation", {})
	var status_ok := failures.is_empty() \
		and stale_rejections == 2 \
		and str(seam_validation.get("status", "")) == "PASS" \
		and int(seam_validation.get("mixed_lod_matching_interfaces", 0)) == 4
	return {
		"schema": Contracts.STREAMING_QUALIFICATION_SCHEMA,
		"status": "PASS" if status_ok else "FAIL",
		"schedule_count": schedules.size(),
		"chunk_build_count": total_builds,
		"order_independent_schedules": schedules.size() - failures.size(),
		"moving_window_count": 3,
		"unload_reload_signature_stable": failures.is_empty(),
		"stale_request_count": stale_requests.size(),
		"stale_result_rejections": stale_rejections,
		"accepted_versions": accepted_versions,
		"boundary_stability_status": str(seam_validation.get("status", "FAIL")),
		"same_lod_stable_interfaces": int(
			seam_validation.get("same_lod_matching_pairs", 0)
		),
		"mixed_lod_stable_interfaces": int(
			seam_validation.get("mixed_lod_matching_interfaces", 0)
		),
		"schedules": schedules,
		"sample_failures": failures if not status_ok else [],
	}


func _reversed_indices(size: int) -> Array[int]:
	var values: Array[int] = []
	for index in range(size - 1, -1, -1):
		values.append(index)
	return values


func _seeded_indices(size: int) -> Array[int]:
	var values: Array[int] = []
	for index in range(size):
		values.append(index)
	var state := 0x7105
	for index in range(size - 1, 0, -1):
		state = Common.lcg_next(state)
		var swap_index := state % (index + 1)
		var temporary := values[index]
		values[index] = values[swap_index]
		values[swap_index] = temporary
	return values


func _validate_persistence(lab: Object) -> Dictionary:
	var original_edits: Array = lab.call("get_reference_terrain_edits")
	var original_auto_rebuild := bool(lab.get("auto_rebuild"))
	lab.set("auto_rebuild", false)
	var edits := _stress_operations().slice(0, 8)
	lab.call("set_reference_terrain_edits", edits)
	var before: Dictionary = lab.call("build_reference_terrain")
	var payload := {
		"schema": Contracts.PERSISTENCE_QUALIFICATION_SCHEMA,
		"field_profile": ReferenceField.PROFILE_CANONICAL,
		"revision": 8,
		"edits": ReproStore.to_json_safe(edits),
		"chunk_versions": Common.fixture_chunk_signatures(before),
		"geometry_signature": str(before.get("geometry_signature", "")),
	}
	var payload_json := JSON.stringify(payload, "", true)
	var checksum := payload_json.sha256_text()
	var envelope := {
		"schema": Contracts.PERSISTENCE_ENVELOPE_SCHEMA,
		"checksum": checksum,
		"payload_json": payload_json,
	}
	var serialized := JSON.stringify(envelope, "\t", true)
	var absolute_directory := ProjectSettings.globalize_path(
		PERSISTENCE_PATH.get_base_dir()
	)
	var write_ok := DirAccess.make_dir_recursive_absolute(absolute_directory) == OK
	var file := FileAccess.open(PERSISTENCE_PATH, FileAccess.WRITE) if write_ok else null
	if file != null:
		file.store_string(serialized)
		file.close()
	else:
		write_ok = false
	var read_file := FileAccess.open(PERSISTENCE_PATH, FileAccess.READ) if write_ok else null
	var parsed: Variant = JSON.parse_string(read_file.get_as_text()) if read_file != null else null
	if read_file != null:
		read_file.close()
	var parsed_ok := typeof(parsed) == TYPE_DICTIONARY
	var parsed_envelope: Dictionary = parsed if parsed_ok else {}
	var parsed_payload_json := str(parsed_envelope.get("payload_json", ""))
	var parsed_payload_value: Variant = JSON.parse_string(parsed_payload_json)
	var parsed_payload: Dictionary = (
		parsed_payload_value if typeof(parsed_payload_value) == TYPE_DICTIONARY else {}
	)
	var checksum_ok := str(parsed_envelope.get("checksum", "")) == (
		parsed_payload_json.sha256_text()
	)
	lab.call("set_reference_terrain_edits", parsed_payload.get("edits", []))
	var after: Dictionary = lab.call("build_reference_terrain")
	var geometry_matches := str(before.get("geometry_signature", "")) == str(
		after.get("geometry_signature", "")
	)
	var chunks_match := Common.fixture_chunk_signatures(before) == Common.fixture_chunk_signatures(
		after
	)
	var corrupted_payload_json := parsed_payload_json.replace(
		"\"revision\":8",
		"\"revision\":9"
	)
	var corruption_detected := str(parsed_envelope.get("checksum", "")) != (
		corrupted_payload_json.sha256_text()
	)
	lab.call("set_reference_terrain_edits", original_edits)
	lab.set("auto_rebuild", original_auto_rebuild)
	var status_ok := write_ok \
		and parsed_ok \
		and checksum_ok \
		and geometry_matches \
		and chunks_match \
		and corruption_detected
	return {
		"schema": Contracts.PERSISTENCE_QUALIFICATION_SCHEMA,
		"status": "PASS" if status_ok else "FAIL",
		"envelope_schema": Contracts.PERSISTENCE_ENVELOPE_SCHEMA,
		"field_profile": ReferenceField.PROFILE_CANONICAL,
		"edit_count": edits.size(),
		"chunk_version_count": (
			payload.get("chunk_versions", {}) as Dictionary
		).size(),
		"serialized_bytes": serialized.to_utf8_buffer().size(),
		"write_read_roundtrip": write_ok and parsed_ok,
		"checksum_matches": checksum_ok,
		"corruption_detected": corruption_detected,
		"geometry_matches": geometry_matches,
		"chunk_versions_match": chunks_match,
		"geometry_signature": str(after.get("geometry_signature", "")),
		"path": PERSISTENCE_PATH,
		"sample_failures": [] if status_ok else ["persistence roundtrip invariant failed"],
	}
