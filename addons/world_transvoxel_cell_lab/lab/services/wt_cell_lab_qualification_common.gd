@tool
extends RefCounted
class_name WtCellLabQualificationCommon

const MeshAnalysis := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_mesh_analysis.gd")
const ReproStore := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_repro_store.gd")


static func mesh_chunk(
	probe: RefCounted,
	field: RefCounted,
	coordinate: Vector3i,
	lod: int,
	transition_mask: int = 0
) -> Dictionary:
	if probe == null or not probe.has_method("mesh_chunk_with_callable"):
		return {
			"ok": false,
			"status": "Unavailable",
			"error": "native_chunk_probe_unavailable",
		}
	return probe.call(
		"mesh_chunk_with_callable",
		Callable(field, "sample"),
		coordinate,
		lod,
		transition_mask,
		transition_mask,
		0.0,
		0.25
	)


static func chunk_origin(chunk: Dictionary) -> Vector3:
	return MeshAnalysis.vector3_from_variant(
		chunk.get(
			"chunk_origin",
			Vector3(chunk.get("chunk_coordinate", Vector3i.ZERO))
				* float(16 * (1 << int(chunk.get("lod", 0))))
		)
	)


static func chunk_buffers(chunk: Dictionary, include_transitions: bool = true) -> Array[Dictionary]:
	var buffers: Array[Dictionary] = []
	var origin := chunk_origin(chunk)
	var regular: Dictionary = chunk.get("regular", {})
	if not regular.is_empty():
		buffers.append(buffer_from_mesh(chunk, regular, origin, "regular", -1))
	if not include_transitions:
		return buffers
	var transitions: Array = chunk.get("transitions", [])
	for face in range(transitions.size()):
		var transition: Dictionary = transitions[face]
		if transition.is_empty():
			continue
		var vertices: PackedVector3Array = transition.get(
			"vertices",
			PackedVector3Array()
		)
		var indices: PackedInt32Array = transition.get("indices", PackedInt32Array())
		if vertices.is_empty() and indices.is_empty():
			continue
		buffers.append(buffer_from_mesh(
			chunk,
			transition,
			origin,
			"transition",
			face
		))
	return buffers


static func buffer_from_mesh(
	chunk: Dictionary,
	mesh: Dictionary,
	origin: Vector3,
	kind: String,
	face: int
) -> Dictionary:
	return {
		"chunk_id": str(chunk.get(
			"fixture_chunk_id",
			chunk.get("chunk_coordinate", Vector3i.ZERO)
		)),
		"coordinate": chunk.get("chunk_coordinate", Vector3i.ZERO),
		"lod": int(chunk.get("lod", 0)),
		"kind": kind,
		"face": face,
		"origin": origin,
		"vertices": mesh.get("vertices", PackedVector3Array()),
		"normals": mesh.get("normals", PackedVector3Array()),
		"indices": mesh.get("indices", PackedInt32Array()),
		"materials": mesh.get("materials", PackedInt32Array()),
	}


static func validate_chunk(chunk: Dictionary, require_local_alignment: bool = false) -> Dictionary:
	var failures: Array[String] = []
	var triangle_count := 0
	var vertex_count := 0
	var local_disagreements := 0
	var local_ambiguous := 0
	var component_conflicts := 0
	var nonmanifold_edges := 0
	var orientation_conflicts := 0
	var interior_open_edges := 0
	for buffer in chunk_buffers(chunk):
		var vertices: PackedVector3Array = buffer.get("vertices", PackedVector3Array())
		var normals: PackedVector3Array = buffer.get("normals", PackedVector3Array())
		var indices: PackedInt32Array = buffer.get("indices", PackedInt32Array())
		vertex_count += vertices.size()
		triangle_count += int(indices.size() / 3)
		var integrity := MeshAnalysis.validate_triangle_mesh_integrity(
			vertices,
			normals,
			indices
		)
		for key in [
			"nonfinite_vertices",
			"degenerate_triangles",
			"duplicate_triangles",
			"winding_normal_conflicts",
		]:
			if int(integrity.get(key, 0)) > 0:
				failures.append("%s:%s=%d" % [
					str(buffer.get("kind", "")),
					key,
					int(integrity.get(key, 0)),
				])
		local_disagreements += int(
			integrity.get("local_winding_normal_disagreements", 0)
		)
		local_ambiguous += int(integrity.get("local_winding_normal_ambiguous", 0))
		component_conflicts += int(integrity.get("winding_normal_conflicts", 0))
		if require_local_alignment and (
			int(integrity.get("local_winding_normal_disagreements", 0)) > 0
			or int(integrity.get("local_winding_normal_ambiguous", 0)) > 0
		):
			failures.append("%s:local_normal_alignment" % str(buffer.get("kind", "")))
		var bounds_size := float(16 * (1 << int(buffer.get("lod", 0))))
		var edge_metrics := MeshAnalysis.bounded_edge_metrics(
			vertices,
			indices,
			AABB(Vector3.ZERO, Vector3.ONE * bounds_size)
		)
		nonmanifold_edges += int(edge_metrics.get("nonmanifold_edges", 0))
		interior_open_edges += int(edge_metrics.get("interior_open_edges", 0))
		var orientation := MeshAnalysis.orientation_metrics(vertices, indices)
		orientation_conflicts += int(
			orientation.get("orientation_conflict_edges", 0)
		)
	if nonmanifold_edges > 0:
		failures.append("nonmanifold_edges=%d" % nonmanifold_edges)
	if orientation_conflicts > 0:
		failures.append("orientation_conflicts=%d" % orientation_conflicts)
	if interior_open_edges > 0:
		failures.append("interior_open_edges=%d" % interior_open_edges)
	if not bool(chunk.get("ok", false)):
		failures.append("chunk_status=%s" % str(chunk.get("status", "Unknown")))
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"failure_count": failures.size(),
		"sample_failures": failures,
		"vertex_count": vertex_count,
		"triangle_count": triangle_count,
		"local_winding_normal_disagreements": local_disagreements,
		"local_winding_normal_ambiguous": local_ambiguous,
		"winding_normal_conflicts": component_conflicts,
		"nonmanifold_edges": nonmanifold_edges,
		"orientation_conflict_edges": orientation_conflicts,
		"interior_open_edges": interior_open_edges,
	}


static func chunk_signature(chunk: Dictionary) -> String:
	var lines: Array[String] = [
		str(chunk.get("chunk_coordinate", Vector3i.ZERO)),
		str(int(chunk.get("lod", 0))),
		str(int(chunk.get("requested_transition_mask", 0))),
		str(chunk.get("status", "")),
	]
	for buffer in chunk_buffers(chunk):
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
		var normals: PackedVector3Array = buffer.get("normals", PackedVector3Array())
		for normal in normals:
			lines.append("n:%d,%d,%d" % [
				roundi(normal.x * MeshAnalysis.POSITION_SCALE),
				roundi(normal.y * MeshAnalysis.POSITION_SCALE),
				roundi(normal.z * MeshAnalysis.POSITION_SCALE),
			])
		var indices: PackedInt32Array = buffer.get("indices", PackedInt32Array())
		for index in indices:
			lines.append("i:%d" % int(index))
		var materials: PackedInt32Array = buffer.get("materials", PackedInt32Array())
		for material in materials:
			lines.append("m:%d" % int(material))
	return "\n".join(lines).sha256_text()


static func fixture_chunk_signatures(fixture: Dictionary) -> Dictionary:
	var signatures := {}
	for chunk_value in fixture.get("chunks", []):
		var chunk: Dictionary = chunk_value
		signatures[str(chunk.get("fixture_chunk_id", ""))] = chunk_signature(chunk)
	return signatures


static func packed_buffer_bytes(buffers: Array) -> int:
	var total := 0
	for buffer_value in buffers:
		var buffer: Dictionary = buffer_value
		total += (
			buffer.get("vertices", PackedVector3Array()) as PackedVector3Array
		).size() * 12
		total += (
			buffer.get("normals", PackedVector3Array()) as PackedVector3Array
		).size() * 12
		total += (
			buffer.get("indices", PackedInt32Array()) as PackedInt32Array
		).size() * 4
		total += (
			buffer.get("materials", PackedInt32Array()) as PackedInt32Array
		).size() * 4
	return total


static func world_faces(buffers: Array) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for buffer_value in buffers:
		var buffer: Dictionary = buffer_value
		var origin: Vector3 = buffer.get("origin", Vector3.ZERO)
		var vertices: PackedVector3Array = buffer.get("vertices", PackedVector3Array())
		var indices: PackedInt32Array = buffer.get("indices", PackedInt32Array())
		for offset in range(0, indices.size(), 3):
			if offset + 2 >= indices.size():
				break
			var ia := int(indices[offset])
			var ib := int(indices[offset + 1])
			var ic := int(indices[offset + 2])
			if min(ia, min(ib, ic)) < 0 or max(ia, max(ib, ic)) >= vertices.size():
				continue
			faces.append(vertices[ia] + origin)
			faces.append(vertices[ib] + origin)
			faces.append(vertices[ic] + origin)
	return faces


static func json_hash(value: Variant) -> String:
	return JSON.stringify(ReproStore.to_json_safe(value), "", true).sha256_text()


static func vector_dictionary(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}


static func lcg_next(state: int) -> int:
	return int((state * 1664525 + 1013904223) & 0x7fffffff)
