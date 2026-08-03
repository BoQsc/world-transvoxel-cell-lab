@tool
extends RefCounted
class_name WtTerrainLabNativeMeshAdapter

const NATIVE_DEPENDENCY_CLASS := "WorldTransvoxelCellProbe"
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


static func assemble(chunks: Array, include_transitions: bool = true) -> Dictionary:
	var failures: Array[String] = []
	var keyed_chunks := {}
	var reference_origin := Vector3(INF, INF, INF)
	for chunk_value in chunks:
		if not chunk_value is Dictionary:
			failures.append("assembly contains a non-dictionary chunk")
			continue
		var chunk: Dictionary = chunk_value
		if not bool(chunk.get("ok", false)):
			failures.append("assembly contains an unsuccessful native chunk")
			continue
		var origin := chunk_origin(chunk)
		reference_origin = reference_origin.min(origin)
		var key := "%s@%d" % [
			_vector_key(origin),
			int(chunk.get("lod", -1)),
		]
		if keyed_chunks.has(key):
			failures.append("assembly contains a duplicate native chunk")
			continue
		keyed_chunks[key] = chunk
	if keyed_chunks.is_empty():
		failures.append("assembly contains no successful native chunks")
		reference_origin = Vector3.ZERO
	var chunk_keys: Array = keyed_chunks.keys()
	chunk_keys.sort()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var materials := PackedInt32Array()
	var source_triangles: Array[Dictionary] = []
	var source_buffers := 0
	for chunk_key in chunk_keys:
		var chunk: Dictionary = keyed_chunks[chunk_key]
		var relative_origin := chunk_origin(chunk) - reference_origin
		for buffer in _buffers(chunk, include_transitions):
			source_buffers += 1
			var source_vertices: PackedVector3Array = buffer.get(
				"vertices", PackedVector3Array()
			)
			var source_normals: PackedVector3Array = buffer.get(
				"normals", PackedVector3Array()
			)
			var source_indices: PackedInt32Array = buffer.get(
				"indices", PackedInt32Array()
			)
			var source_materials: PackedInt32Array = buffer.get(
				"materials", PackedInt32Array()
			)
			var vertex_offset := vertices.size()
			for vertex_index in range(source_vertices.size()):
				vertices.append(relative_origin + source_vertices[vertex_index])
				normals.append(
					source_normals[vertex_index]
					if vertex_index < source_normals.size()
					else Vector3.ZERO
				)
				materials.append(
					int(source_materials[vertex_index])
					if vertex_index < source_materials.size()
					else 0
				)
			for triangle_offset in range(0, source_indices.size(), 3):
				if triangle_offset + 2 >= source_indices.size():
					failures.append("native buffer index count is not triangular")
					break
				var output_offset := indices.size()
				for corner in range(3):
					indices.append(
						vertex_offset + int(source_indices[triangle_offset + corner])
					)
				source_triangles.append({
					"triangle_index": int(output_offset / 3),
					"chunk_key": chunk_key,
					"buffer_kind": buffer.get("kind", ""),
					"transition_face": buffer.get("face", -1),
				})
	return {
		"schema": "world_transvoxel.terrain_lab.normalized_native_mesh.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"reference_origin": reference_origin,
		"vertices": vertices,
		"normals": normals,
		"indices": indices,
		"materials": materials,
		"source_triangles": source_triangles,
		"source_chunk_count": keyed_chunks.size(),
		"source_buffer_count": source_buffers,
		"geometry_signature": mesh_signature(vertices, indices, materials),
		"failures": failures,
	}


static func clone_mesh(mesh: Dictionary) -> Dictionary:
	return {
		"schema": mesh.get("schema", ""),
		"status": mesh.get("status", ""),
		"reference_origin": mesh.get("reference_origin", Vector3.ZERO),
		"vertices": (mesh.get("vertices", PackedVector3Array()) as PackedVector3Array).duplicate(),
		"normals": (mesh.get("normals", PackedVector3Array()) as PackedVector3Array).duplicate(),
		"indices": (mesh.get("indices", PackedInt32Array()) as PackedInt32Array).duplicate(),
		"materials": (mesh.get("materials", PackedInt32Array()) as PackedInt32Array).duplicate(),
		"source_triangles": (mesh.get("source_triangles", []) as Array).duplicate(true),
		"source_chunk_count": mesh.get("source_chunk_count", 0),
		"source_buffer_count": mesh.get("source_buffer_count", 0),
		"failures": (mesh.get("failures", []) as Array).duplicate(),
	}


static func mesh_signature(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	materials: PackedInt32Array = PackedInt32Array()
) -> String:
	var lines: Array[String] = []
	for vertex in vertices:
		lines.append("v:" + _vector_key(vertex))
	for index_value in indices:
		lines.append("i:%d" % int(index_value))
	for material_id in materials:
		lines.append("m:%d" % int(material_id))
	return "\n".join(lines).sha256_text()


static func chunk_origin(chunk: Dictionary) -> Vector3:
	return Vector3(
		float(chunk.get("world_origin_x", 0.0)),
		float(chunk.get("world_origin_y", 0.0)),
		float(chunk.get("world_origin_z", 0.0))
	)


static func _buffers(chunk: Dictionary, include_transitions: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var regular: Dictionary = chunk.get("regular", {})
	if not regular.is_empty():
		var regular_buffer := regular.duplicate(false)
		regular_buffer["kind"] = "regular"
		regular_buffer["face"] = -1
		result.append(regular_buffer)
	if not include_transitions:
		return result
	var transitions: Array = chunk.get("transitions", [])
	for face in range(transitions.size()):
		if not transitions[face] is Dictionary:
			continue
		var transition: Dictionary = transitions[face]
		var transition_indices: PackedInt32Array = transition.get(
			"indices", PackedInt32Array()
		)
		if transition_indices.is_empty():
			continue
		var transition_buffer := transition.duplicate(false)
		transition_buffer["kind"] = "transition"
		transition_buffer["face"] = face
		result.append(transition_buffer)
	return result


static func _vector_key(value: Vector3) -> String:
	return "%d,%d,%d" % [
		roundi(value.x * POSITION_SCALE),
		roundi(value.y * POSITION_SCALE),
		roundi(value.z * POSITION_SCALE),
	]
