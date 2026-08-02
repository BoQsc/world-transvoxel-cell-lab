@tool
extends RefCounted
class_name WtTerrainLabEditNativeEvidence

const NATIVE_DEPENDENCY_CLASS := "WorldTransvoxelCellProbe"
const CHUNK_CELLS_PER_AXIS := 16
const POSITION_SCALE := 1000000.0


static func create_probe() -> RefCounted:
	if not ClassDB.class_exists(NATIVE_DEPENDENCY_CLASS):
		return null
	var instance: Variant = ClassDB.instantiate(NATIVE_DEPENDENCY_CLASS)
	if instance is RefCounted and instance.has_method("mesh_chunk_with_callable"):
		return instance as RefCounted
	return null


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


static func validate_chunk(chunk: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	var vertex_count := 0
	var triangle_count := 0
	var material_ids: Array[int] = []
	var nonfinite_vertices := 0
	var invalid_indices := 0
	var degenerate_triangles := 0
	var bounds_errors := 0
	for buffer in chunk_buffers(chunk):
		var vertices: PackedVector3Array = buffer.get("vertices", PackedVector3Array())
		var normals: PackedVector3Array = buffer.get("normals", PackedVector3Array())
		var indices: PackedInt32Array = buffer.get("indices", PackedInt32Array())
		var materials: PackedInt32Array = buffer.get("materials", PackedInt32Array())
		vertex_count += vertices.size()
		triangle_count += int(indices.size() / 3)
		if indices.size() % 3 != 0:
			failures.append(str(buffer.get("kind", "")) + ": index count is not triangular")
		if not normals.is_empty() and normals.size() != vertices.size():
			failures.append(str(buffer.get("kind", "")) + ": normal count differs from vertices")
		if not materials.is_empty() and materials.size() != vertices.size():
			failures.append(str(buffer.get("kind", "")) + ": material count differs from vertices")
		var extent := float(CHUNK_CELLS_PER_AXIS * (1 << int(buffer.get("lod", 0))))
		for vertex in vertices:
			if not vertex.is_finite():
				nonfinite_vertices += 1
			if vertex.x < -0.0001 or vertex.y < -0.0001 or vertex.z < -0.0001 \
					or vertex.x > extent + 0.0001 \
					or vertex.y > extent + 0.0001 \
					or vertex.z > extent + 0.0001:
				bounds_errors += 1
		for material_id in materials:
			if int(material_id) not in material_ids:
				material_ids.append(int(material_id))
		for triangle_start in range(0, indices.size(), 3):
			if triangle_start + 2 >= indices.size():
				break
			var a := int(indices[triangle_start])
			var b := int(indices[triangle_start + 1])
			var c := int(indices[triangle_start + 2])
			if a < 0 or b < 0 or c < 0 \
					or a >= vertices.size() or b >= vertices.size() or c >= vertices.size():
				invalid_indices += 1
				continue
			if (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).length_squared() \
					<= 0.0000000001:
				degenerate_triangles += 1
	material_ids.sort()
	if not bool(chunk.get("ok", false)):
		failures.append("native chunk status=" + str(chunk.get("status", "Unknown")))
	if nonfinite_vertices > 0:
		failures.append("nonfinite_vertices=%d" % nonfinite_vertices)
	if invalid_indices > 0:
		failures.append("invalid_indices=%d" % invalid_indices)
	if degenerate_triangles > 0:
		failures.append("degenerate_triangles=%d" % degenerate_triangles)
	if bounds_errors > 0:
		failures.append("bounds_errors=%d" % bounds_errors)
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"vertex_count": vertex_count,
		"triangle_count": triangle_count,
		"material_ids": material_ids,
		"nonfinite_vertices": nonfinite_vertices,
		"invalid_indices": invalid_indices,
		"degenerate_triangles": degenerate_triangles,
		"bounds_errors": bounds_errors,
		"failures": failures,
	}


static func collision_evidence(chunk: Dictionary, sample_scale_m: float) -> Dictionary:
	var source_faces := PackedVector3Array()
	var origin := chunk_origin(chunk)
	for buffer in chunk_buffers(chunk):
		var vertices: PackedVector3Array = buffer.get("vertices", PackedVector3Array())
		var indices: PackedInt32Array = buffer.get("indices", PackedInt32Array())
		for index_value in indices:
			var vertex_index := int(index_value)
			if vertex_index < 0 or vertex_index >= vertices.size():
				continue
			source_faces.append((origin + vertices[vertex_index]) * sample_scale_m)
	var shape := ConcavePolygonShape3D.new()
	if not source_faces.is_empty():
		shape.set_faces(source_faces)
	var published_faces := shape.get_faces()
	var source_signature := _vector_signature(source_faces)
	var published_signature := _vector_signature(published_faces)
	return {
		"status": "PASS" \
			if source_faces.size() == published_faces.size() \
				and source_signature == published_signature \
			else "FAIL",
		"face_vertex_count": source_faces.size(),
		"triangle_count": int(source_faces.size() / 3),
		"source_signature": source_signature,
		"published_signature": published_signature,
	}


static func same_lod_seam(
	left: Dictionary,
	right: Dictionary,
	axis: int
) -> Dictionary:
	var left_coordinate: Vector3i = left.get("chunk_coordinate", Vector3i.ZERO)
	var right_coordinate: Vector3i = right.get("chunk_coordinate", Vector3i.ZERO)
	var lod := int(left.get("lod", -1))
	var expected_delta := Vector3i.ZERO
	expected_delta[clampi(axis, 0, 2)] = 1
	var failures: Array[String] = []
	if lod != int(right.get("lod", -2)):
		failures.append("LOD mismatch")
	if right_coordinate - left_coordinate != expected_delta:
		failures.append("chunk coordinates are not adjacent on requested axis")
	var extent := float(CHUNK_CELLS_PER_AXIS * (1 << maxi(lod, 0)))
	var left_edges := _boundary_edges(left, axis, extent)
	var right_edges := _boundary_edges(right, axis, 0.0)
	var left_only: Array[String] = []
	var right_only: Array[String] = []
	var multiplicity_mismatches: Array[String] = []
	for key in left_edges:
		if not right_edges.has(key):
			left_only.append("%s:%d" % [str(key), int(left_edges[key])])
		elif int(left_edges[key]) != int(right_edges[key]):
			multiplicity_mismatches.append(
				"%s:%d!=%d" % [str(key), int(left_edges[key]), int(right_edges[key])]
			)
	for key in right_edges:
		if not left_edges.has(key):
			right_only.append("%s:%d" % [str(key), int(right_edges[key])])
	if left_only.size() > 0 or right_only.size() > 0:
		failures.append("shared boundary edge sets differ")
	if not multiplicity_mismatches.is_empty():
		failures.append("shared boundary edge multiplicities differ")
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"axis": axis,
		"left_edge_count": left_edges.size(),
		"right_edge_count": right_edges.size(),
		"left_only_count": left_only.size(),
		"right_only_count": right_only.size(),
		"multiplicity_mismatch_count": multiplicity_mismatches.size(),
		"sample_left_only": left_only.slice(0, mini(left_only.size(), 4)),
		"sample_right_only": right_only.slice(0, mini(right_only.size(), 4)),
		"sample_multiplicity_mismatches": multiplicity_mismatches.slice(
			0,
			mini(multiplicity_mismatches.size(), 4)
		),
		"failures": failures,
	}


static func chunk_signature(chunk: Dictionary) -> String:
	var lines: Array[String] = [
		str(chunk.get("chunk_coordinate", Vector3i.ZERO)),
		str(int(chunk.get("lod", 0))),
		str(chunk.get("status", "")),
	]
	for buffer in chunk_buffers(chunk):
		lines.append("%s:%d" % [str(buffer.get("kind", "")), int(buffer.get("face", -1))])
		var vertices: PackedVector3Array = buffer.get("vertices", PackedVector3Array())
		for vertex in vertices:
			lines.append(_vector_key(vertex))
		var normals: PackedVector3Array = buffer.get("normals", PackedVector3Array())
		for normal in normals:
			lines.append("n:" + _vector_key(normal))
		var indices: PackedInt32Array = buffer.get("indices", PackedInt32Array())
		for index_value in indices:
			lines.append("i:%d" % int(index_value))
		var materials: PackedInt32Array = buffer.get("materials", PackedInt32Array())
		for material_id in materials:
			lines.append("m:%d" % int(material_id))
	return "\n".join(lines).sha256_text()


static func chunk_origin(chunk: Dictionary) -> Vector3:
	return Vector3(
		float(chunk.get("world_origin_x", 0.0)),
		float(chunk.get("world_origin_y", 0.0)),
		float(chunk.get("world_origin_z", 0.0))
	)


static func chunk_buffers(chunk: Dictionary) -> Array[Dictionary]:
	var buffers: Array[Dictionary] = []
	var regular: Dictionary = chunk.get("regular", {})
	if not regular.is_empty():
		buffers.append(_buffer(chunk, regular, "regular", -1))
	var transitions: Array = chunk.get("transitions", [])
	for face in range(transitions.size()):
		var transition_value: Variant = transitions[face]
		if not transition_value is Dictionary:
			continue
		var transition: Dictionary = transition_value
		var vertices: PackedVector3Array = transition.get("vertices", PackedVector3Array())
		var indices: PackedInt32Array = transition.get("indices", PackedInt32Array())
		if vertices.is_empty() and indices.is_empty():
			continue
		buffers.append(_buffer(chunk, transition, "transition", face))
	return buffers


static func _buffer(
	chunk: Dictionary,
	mesh: Dictionary,
	kind: String,
	face: int
) -> Dictionary:
	return {
		"kind": kind,
		"face": face,
		"lod": int(chunk.get("lod", 0)),
		"vertices": mesh.get("vertices", PackedVector3Array()),
		"normals": mesh.get("normals", PackedVector3Array()),
		"indices": mesh.get("indices", PackedInt32Array()),
		"materials": mesh.get("materials", PackedInt32Array()),
	}


static func _boundary_edges(chunk: Dictionary, axis: int, local_plane: float) -> Dictionary:
	var result := {}
	var origin := chunk_origin(chunk)
	var regular: Dictionary = chunk.get("regular", {})
	var vertices: PackedVector3Array = regular.get("vertices", PackedVector3Array())
	var indices: PackedInt32Array = regular.get("indices", PackedInt32Array())
	for triangle_start in range(0, indices.size(), 3):
		if triangle_start + 2 >= indices.size():
			break
		var triangle := [
			int(indices[triangle_start]),
			int(indices[triangle_start + 1]),
			int(indices[triangle_start + 2]),
		]
		for edge in [[0, 1], [1, 2], [2, 0]]:
			var a_index := int(triangle[edge[0]])
			var b_index := int(triangle[edge[1]])
			if a_index < 0 or b_index < 0 \
					or a_index >= vertices.size() or b_index >= vertices.size():
				continue
			var local_a := vertices[a_index]
			var local_b := vertices[b_index]
			if absf(local_a[axis] - local_plane) > 0.0001 \
					or absf(local_b[axis] - local_plane) > 0.0001:
				continue
			var key := _segment_key(origin + local_a, origin + local_b)
			result[key] = int(result.get(key, 0)) + 1
	return result


static func _segment_key(a: Vector3, b: Vector3) -> String:
	var a_key := _vector_key(a)
	var b_key := _vector_key(b)
	return a_key + "|" + b_key if a_key < b_key else b_key + "|" + a_key


static func _vector_key(value: Vector3) -> String:
	return "%d,%d,%d" % [
		roundi(value.x * POSITION_SCALE),
		roundi(value.y * POSITION_SCALE),
		roundi(value.z * POSITION_SCALE),
	]


static func _vector_signature(values: PackedVector3Array) -> String:
	var lines: Array[String] = []
	for value in values:
		lines.append(_vector_key(value))
	return "\n".join(lines).sha256_text()
