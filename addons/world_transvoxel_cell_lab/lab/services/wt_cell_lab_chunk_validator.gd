@tool
extends RefCounted
class_name WtCellLabChunkValidator

const Contracts := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_contracts.gd")
const MeshAnalysis := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_mesh_analysis.gd")

var _fixture_extent := 16.0


func validate(probe: RefCounted) -> Dictionary:
	var start_usec := Time.get_ticks_usec()
	var result := {
		"schema": Contracts.CHUNK_LOD_VALIDATION_SCHEMA,
		"available": probe != null and probe.has_method("mesh_chunk_with_callable"),
		"authority": Contracts.NATIVE_AUTHORITY,
		"failure_classification": "chunk_or_lod",
		"same_lod_levels": [0, 1, 2],
		"same_lod_pairs": 9,
		"same_lod_matching_pairs": 0,
		"same_lod_mismatched_pairs": 0,
		"same_lod_left_only_edges": 0,
		"same_lod_right_only_edges": 0,
		"lod_probe_levels": [1, 2, 3],
		"lod_probe_failures": 0,
		"lod_transition_probe_status": "Unavailable",
		"lod_transition_faces_with_geometry": 0,
		"lod_transition_triangles": 0,
		"lod_transition_nonmanifold_edges": 0,
		"lod_transition_orientation_conflict_edges": 0,
		"mixed_lod_pairs": 12,
		"mixed_lod_matching_pairs": 0,
		"mixed_lod_mismatched_pairs": 0,
		"mixed_lod_coarse_only_edges": 0,
		"mixed_lod_fine_only_edges": 0,
		"visible_crack_count": 0,
		"mixed_lod_scope": "coarse_transition_surface_vs_four_fine_neighbor_surface_interface_proof",
		"sample_failures": [],
		"status": "Unavailable",
		"elapsed_ms": 0.0,
	}
	if not bool(result["available"]):
		return result
	result["status"] = "PASS"
	_validate_same_lod(probe, result)
	_validate_lod_probes(probe, result)
	_validate_mixed_lod(probe, result)
	for key in [
		"same_lod_mismatched_pairs",
		"lod_probe_failures",
		"lod_transition_nonmanifold_edges",
		"lod_transition_orientation_conflict_edges",
		"mixed_lod_mismatched_pairs",
		"visible_crack_count",
	]:
		if int(result[key]) > 0:
			result["status"] = "FAIL"
			break
	result["elapsed_ms"] = float(Time.get_ticks_usec() - start_usec) / 1000.0
	return result


func build_mixed_lod_fixture(probe: RefCounted, face: int, coarse_lod: int = 1) -> Dictionary:
	if probe == null or not probe.has_method("mesh_chunk_with_callable"):
		return {"ok": false, "status": "Unavailable", "buffers": []}
	face = clampi(face, 0, Contracts.CHUNK_FACE_NAMES.size() - 1)
	coarse_lod = clampi(coarse_lod, 1, 3)
	_fixture_extent = float(Contracts.CHUNK_PROBE_CELLS_PER_AXIS * (1 << coarse_lod))
	var coarse := mesh_chunk(probe, Vector3i.ZERO, coarse_lod, 1 << face, 1 << face)
	var fine_chunks: Array[Dictionary] = []
	for coordinate in _fine_neighbor_coordinates(face):
		fine_chunks.append(mesh_chunk(probe, coordinate, coarse_lod - 1, 0, 0))
	var buffers := _rendered_chunk_buffers(coarse, face)
	for fine_chunk in fine_chunks:
		buffers.append_array(_rendered_chunk_buffers(fine_chunk, -1))
	var comparison := _mixed_lod_comparison(coarse, fine_chunks, face)
	return {
		"ok": bool(coarse.get("ok", false)) and _all_chunks_ok(fine_chunks),
		"status": "Ok" if bool(comparison.get("matches", false)) else "Mismatch",
		"face": Contracts.CHUNK_FACE_NAMES[face],
		"face_index": face,
		"coarse_lod": coarse_lod,
		"fine_lod": coarse_lod - 1,
		"coarse": coarse,
		"fine_chunks": fine_chunks,
		"buffers": buffers,
		"comparison": comparison,
	}


func mesh_chunk(
	probe: RefCounted,
	chunk_coordinate: Vector3i,
	lod: int,
	transition_mask: int,
	cached_transition_mask: int
) -> Dictionary:
	if probe == null or not probe.has_method("mesh_chunk_with_callable"):
		return {
			"ok": false,
			"status": "Unavailable",
			"error": "mesh_chunk_with_callable unavailable",
		}
	return probe.call(
		"mesh_chunk_with_callable",
		Callable(self, "_sample"),
		chunk_coordinate,
		lod,
		transition_mask,
		cached_transition_mask,
		0.0,
		0.25
	)


func _validate_same_lod(probe: RefCounted, result: Dictionary) -> void:
	for lod in result["same_lod_levels"]:
		_fixture_extent = float(Contracts.CHUNK_PROBE_CELLS_PER_AXIS * (1 << int(lod)))
		for spec in [
			{"axis": 0, "face_a": 1, "face_b": 0, "neighbor": Vector3i(1, 0, 0)},
			{"axis": 1, "face_a": 3, "face_b": 2, "neighbor": Vector3i(0, 1, 0)},
			{"axis": 2, "face_a": 5, "face_b": 4, "neighbor": Vector3i(0, 0, 1)},
		]:
			var chunk_a := mesh_chunk(probe, Vector3i.ZERO, lod, 0, 0)
			var chunk_b := mesh_chunk(probe, spec["neighbor"], lod, 0, 0)
			if not bool(chunk_a.get("ok", false)) or not bool(chunk_b.get("ok", false)):
				result["same_lod_mismatched_pairs"] = int(result["same_lod_mismatched_pairs"]) + 1
				MeshAnalysis.append_sample_failure(
					result,
					lod,
					-1,
					"same LOD chunk probe failed on axis %d" % int(spec["axis"])
				)
				continue
			var signatures_a := _chunk_face_edge_signatures(chunk_a, spec["face_a"])
			var signatures_b := _chunk_face_edge_signatures(chunk_b, spec["face_b"])
			var difference := MeshAnalysis.set_difference_counts(signatures_a, signatures_b)
			result["same_lod_left_only_edges"] = int(result["same_lod_left_only_edges"]) + int(difference["left_only"])
			result["same_lod_right_only_edges"] = int(result["same_lod_right_only_edges"]) + int(difference["right_only"])
			if int(difference["left_only"]) == 0 and int(difference["right_only"]) == 0:
				result["same_lod_matching_pairs"] = int(result["same_lod_matching_pairs"]) + 1
			else:
				result["same_lod_mismatched_pairs"] = int(result["same_lod_mismatched_pairs"]) + 1
				MeshAnalysis.append_sample_failure(
					result,
					lod,
					-1,
					"same LOD face signatures differed on axis %d" % int(spec["axis"])
				)


func _validate_lod_probes(probe: RefCounted, result: Dictionary) -> void:
	var statuses: Array[String] = []
	for lod in result["lod_probe_levels"]:
		_fixture_extent = float(Contracts.CHUNK_PROBE_CELLS_PER_AXIS * (1 << int(lod)))
		var chunk := mesh_chunk(probe, Vector3i.ZERO, lod, 0x3F, 0x3F)
		statuses.append(str(chunk.get("status", "Unavailable")))
		if not bool(chunk.get("ok", false)):
			result["lod_probe_failures"] = int(result["lod_probe_failures"]) + 1
			MeshAnalysis.append_sample_failure(
				result,
				lod,
				-1,
				"LOD %d all-face transition probe failed: %s" % [lod, str(chunk.get("sample_error", chunk.get("error", "")))]
			)
			continue
		var transitions: Array = chunk.get("transitions", [])
		for transition_value in transitions:
			var transition: Dictionary = transition_value
			var vertices: PackedVector3Array = transition.get("vertices", PackedVector3Array())
			var indices: PackedInt32Array = transition.get("indices", PackedInt32Array())
			if not indices.is_empty():
				result["lod_transition_faces_with_geometry"] = int(result["lod_transition_faces_with_geometry"]) + 1
			result["lod_transition_triangles"] = int(result["lod_transition_triangles"]) + int(indices.size() / 3)
			var edge_metrics := MeshAnalysis.isolated_edge_metrics(vertices, indices)
			var orientation_metrics := MeshAnalysis.orientation_metrics(vertices, indices)
			result["lod_transition_nonmanifold_edges"] = int(result["lod_transition_nonmanifold_edges"]) + int(edge_metrics["nonmanifold_edges"])
			result["lod_transition_orientation_conflict_edges"] = int(result["lod_transition_orientation_conflict_edges"]) + int(orientation_metrics["orientation_conflict_edges"])
	result["lod_transition_probe_status"] = "Ok" if result["lod_probe_failures"] == 0 else ",".join(statuses)


func _validate_mixed_lod(probe: RefCounted, result: Dictionary) -> void:
	for coarse_lod in [1, 2]:
		for face in range(Contracts.CHUNK_FACE_NAMES.size()):
			var fixture := build_mixed_lod_fixture(probe, face, coarse_lod)
			if not bool(fixture.get("ok", false)):
				result["mixed_lod_mismatched_pairs"] = int(result["mixed_lod_mismatched_pairs"]) + 1
				result["visible_crack_count"] = int(result["visible_crack_count"]) + 1
				MeshAnalysis.append_sample_failure(
					result,
					coarse_lod,
					face,
					"mixed LOD fixture could not be meshed"
				)
				continue
			var comparison: Dictionary = fixture.get("comparison", {})
			var coarse_only := int(comparison.get("coarse_only", 0))
			var fine_only := int(comparison.get("fine_only", 0))
			result["mixed_lod_coarse_only_edges"] = int(result["mixed_lod_coarse_only_edges"]) + coarse_only
			result["mixed_lod_fine_only_edges"] = int(result["mixed_lod_fine_only_edges"]) + fine_only
			if bool(comparison.get("matches", false)):
				result["mixed_lod_matching_pairs"] = int(result["mixed_lod_matching_pairs"]) + 1
			else:
				result["mixed_lod_mismatched_pairs"] = int(result["mixed_lod_mismatched_pairs"]) + 1
				result["visible_crack_count"] = int(result["visible_crack_count"]) + coarse_only + fine_only
				MeshAnalysis.append_sample_failure(
					result,
					coarse_lod,
					face,
					"mixed LOD interface signatures differed (%d coarse-only, %d fine-only)" % [
						coarse_only,
						fine_only,
					]
				)


func _mixed_lod_comparison(
	coarse: Dictionary,
	fine_chunks: Array[Dictionary],
	face: int
) -> Dictionary:
	if not bool(coarse.get("ok", false)) or not _all_chunks_ok(fine_chunks):
		return {"matches": false, "coarse_only": 0, "fine_only": 0}
	var axis := _face_axis(face)
	var coarse_origin := _chunk_origin(coarse)
	var extent := float(Contracts.CHUNK_PROBE_CELLS_PER_AXIS * (1 << int(coarse.get("lod", 1))))
	var plane := coarse_origin[axis] + (extent if _face_is_positive(face) else 0.0)
	var coarse_buffers := _rendered_chunk_buffers(coarse, face)
	var fine_buffers: Array = []
	for fine_chunk in fine_chunks:
		fine_buffers.append_array(_rendered_chunk_buffers(fine_chunk, -1))
	var coarse_signatures := MeshAnalysis.plane_open_edge_signatures(coarse_buffers, axis, plane)
	var fine_signatures := MeshAnalysis.plane_open_edge_signatures(fine_buffers, axis, plane)
	var difference := MeshAnalysis.set_difference_counts(coarse_signatures, fine_signatures)
	return {
		"matches": int(difference["left_only"]) == 0 and int(difference["right_only"]) == 0,
		"coarse_only": int(difference["left_only"]),
		"fine_only": int(difference["right_only"]),
		"coarse_signature_count": coarse_signatures.size(),
		"fine_signature_count": fine_signatures.size(),
		"axis": axis,
		"plane": plane,
	}


func _chunk_face_edge_signatures(chunk: Dictionary, face: int) -> Dictionary:
	var axis := _face_axis(face)
	var origin := _chunk_origin(chunk)
	var extent := float(Contracts.CHUNK_PROBE_CELLS_PER_AXIS * (1 << int(chunk.get("lod", 0))))
	var plane := origin[axis] + (extent if _face_is_positive(face) else 0.0)
	return MeshAnalysis.plane_open_edge_signatures(_rendered_chunk_buffers(chunk, -1), axis, plane)


func _rendered_chunk_buffers(chunk: Dictionary, transition_face: int) -> Array:
	var origin := _chunk_origin(chunk)
	var buffers: Array = []
	var regular: Dictionary = chunk.get("regular", {})
	buffers.append({
		"vertices": regular.get("vertices", PackedVector3Array()),
		"indices": regular.get("indices", PackedInt32Array()),
		"origin": origin,
		"kind": "regular",
	})
	if transition_face >= 0:
		var transitions: Array = chunk.get("transitions", [])
		if transition_face < transitions.size():
			var transition: Dictionary = transitions[transition_face]
			buffers.append({
				"vertices": transition.get("vertices", PackedVector3Array()),
				"indices": transition.get("indices", PackedInt32Array()),
				"origin": origin,
				"kind": "transition",
				"face": transition_face,
			})
	return buffers


func _fine_neighbor_coordinates(face: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var axis := _face_axis(face)
	var fixed := 2 if _face_is_positive(face) else -1
	for first in range(2):
		for second in range(2):
			var coordinate := Vector3i.ZERO
			coordinate[axis] = fixed
			var variable_axes: Array[int] = []
			for candidate in range(3):
				if candidate != axis:
					variable_axes.append(candidate)
			coordinate[variable_axes[0]] = first
			coordinate[variable_axes[1]] = second
			result.append(coordinate)
	return result


func _all_chunks_ok(chunks: Array[Dictionary]) -> bool:
	for chunk in chunks:
		if not bool(chunk.get("ok", false)):
			return false
	return true


func _chunk_origin(chunk: Dictionary) -> Vector3:
	return Vector3(
		float(chunk.get("world_origin_x", 0)),
		float(chunk.get("world_origin_y", 0)),
		float(chunk.get("world_origin_z", 0))
	)


func _face_axis(face: int) -> int:
	if face == 0 or face == 1:
		return 0
	if face == 2 or face == 3:
		return 1
	return 2


func _face_is_positive(face: int) -> bool:
	return face == 1 or face == 3 or face == 5


func _sample(point: Vector3i) -> Dictionary:
	var p := Vector3(point)
	var threshold := _fixture_extent * 1.5
	var perturbation := 0.21 * sin((p.x + p.z) * 0.17) + 0.13 * cos((p.y - p.z) * 0.11)
	var density := p.x + p.y + p.z - threshold + perturbation
	var material: int = 1 + (absi(point.x + point.y * 3 + point.z * 5) % 4)
	return {
		"density": density,
		"material": material if density < 0.0 else 0,
		"material_authored": density < 0.0,
	}
