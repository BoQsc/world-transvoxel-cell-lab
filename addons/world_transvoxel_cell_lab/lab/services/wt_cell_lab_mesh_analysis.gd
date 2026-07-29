@tool
extends RefCounted
class_name WtCellLabMeshAnalysis

const Contracts := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_contracts.gd")
const POSITION_SCALE := 10000.0
const POSITION_TOLERANCE := 0.0001
const NORMAL_WINDING_POLARITY := -1.0
const MINIMUM_TRIANGLE_EDGE_LENGTH_SQUARED := 0.000001
const MINIMUM_TRIANGLE_THIN_RATIO_SQUARED := 0.000000000001


static func validate_cell_mesh_buffers(
	cell_mesh: Dictionary,
	material_limit: int,
	topology_sample_count: int,
	validate_winding: bool = false
) -> Dictionary:
	var vertices: PackedVector3Array = cell_mesh.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = cell_mesh.get("normals", PackedVector3Array())
	var indices: PackedInt32Array = cell_mesh.get("indices", PackedInt32Array())
	var materials: PackedInt32Array = cell_mesh.get("materials", PackedInt32Array())
	var material_authored: PackedInt32Array = cell_mesh.get("material_authored", PackedInt32Array())
	var endpoint_a: PackedInt32Array = cell_mesh.get("endpoint_a", PackedInt32Array())
	var endpoint_b: PackedInt32Array = cell_mesh.get("endpoint_b", PackedInt32Array())
	var failures := 0
	var first_failure_message := ""
	if (indices.size() % 3) != 0:
		failures += 1
		first_failure_message = first_failure(first_failure_message, "index count is not triangular")
	for index in indices:
		if int(index) < 0 or int(index) >= vertices.size():
			failures += 1
			first_failure_message = first_failure(first_failure_message, "index outside active vertices")
			break
	for index in range(vertices.size()):
		var position := vertices[index]
		if not vector_is_finite(position):
			failures += 1
			first_failure_message = first_failure(first_failure_message, "position is not finite")
		if index >= normals.size() or not normal_is_valid(normals[index]):
			failures += 1
			first_failure_message = first_failure(first_failure_message, "normal is not unit length")
		if index >= materials.size() or int(materials[index]) <= 0 or int(materials[index]) > material_limit:
			failures += 1
			first_failure_message = first_failure(first_failure_message, "material is outside sample set")
		if index >= material_authored.size():
			failures += 1
			first_failure_message = first_failure(first_failure_message, "material provenance is missing")
		if index >= endpoint_a.size() or index >= endpoint_b.size():
			failures += 1
			first_failure_message = first_failure(first_failure_message, "endpoint provenance is missing")
			continue
		var a := int(endpoint_a[index])
		var b := int(endpoint_b[index])
		if a < 0 or a >= topology_sample_count or b < 0 or b >= topology_sample_count:
			failures += 1
			first_failure_message = first_failure(first_failure_message, "endpoint provenance is outside topology samples")
		if a == b:
			failures += 1
			first_failure_message = first_failure(first_failure_message, "endpoint provenance names a zero-length topology edge")
	var integrity := validate_triangle_mesh_integrity(vertices, normals, indices)
	var integrity_keys := [
		"nonfinite_vertices",
		"degenerate_triangles",
		"duplicate_triangles",
	]
	if validate_winding:
		integrity_keys.append("winding_normal_conflicts")
	for key in integrity_keys:
		if int(integrity.get(key, 0)) > 0:
			failures += int(integrity.get(key, 0))
			first_failure_message = first_failure(
				first_failure_message,
				"triangle integrity failed: %s=%d" % [
					key,
					int(integrity.get(key, 0)),
				]
			)
	return {
		"failures": failures,
		"first_failure": first_failure_message,
		"integrity": integrity,
	}


static func cell_meshes_equivalent(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("status", "Unknown")) != str(b.get("status", "Unknown")):
		return false
	var packed_keys := [
		"vertices",
		"normals",
		"indices",
		"backend_indices",
		"materials",
		"material_authored",
		"endpoint_a",
		"endpoint_b",
		"reuse_data",
	]
	for key in packed_keys:
		var left: Variant = a.get(key)
		var right: Variant = b.get(key)
		if left == null or right == null or left.size() != right.size():
			return false
	var a_vertices: PackedVector3Array = a.get("vertices", PackedVector3Array())
	var b_vertices: PackedVector3Array = b.get("vertices", PackedVector3Array())
	var a_normals: PackedVector3Array = a.get("normals", PackedVector3Array())
	var b_normals: PackedVector3Array = b.get("normals", PackedVector3Array())
	for index in range(a_vertices.size()):
		if not vectors_nearly_equal(a_vertices[index], b_vertices[index]):
			return false
		if not vectors_nearly_equal(a_normals[index], b_normals[index]):
			return false
	for key in [
		"indices",
		"backend_indices",
		"materials",
		"material_authored",
		"endpoint_a",
		"endpoint_b",
		"reuse_data",
	]:
		var left: Variant = a.get(key)
		var right: Variant = b.get(key)
		for index in range(left.size()):
			if int(left[index]) != int(right[index]):
				return false
	return true


static func transition_bounds_failure_count(vertices: PackedVector3Array, orientation: int) -> int:
	var basis := transition_basis(orientation)
	var u: Vector3 = basis.get("u", Vector3.RIGHT)
	var v: Vector3 = basis.get("v", Vector3.UP)
	var w: Vector3 = basis.get("w", Vector3.FORWARD)
	var failures := 0
	for vertex in vertices:
		var local := Vector3(vertex.dot(u), vertex.dot(v), vertex.dot(w))
		if local.x < -POSITION_TOLERANCE or local.x > 2.0 + POSITION_TOLERANCE:
			failures += 1
		elif local.y < -POSITION_TOLERANCE or local.y > 2.0 + POSITION_TOLERANCE:
			failures += 1
		elif local.z < -POSITION_TOLERANCE or local.z > 0.25 + POSITION_TOLERANCE:
			failures += 1
	return failures


static func transition_basis(orientation: int) -> Dictionary:
	match orientation:
		0:
			return {
				"u": Vector3(0.0, 1.0, 0.0),
				"v": Vector3(0.0, 0.0, 1.0),
				"w": Vector3(1.0, 0.0, 0.0),
			}
		1:
			return {
				"u": Vector3(0.0, 1.0, 0.0),
				"v": Vector3(0.0, 0.0, -1.0),
				"w": Vector3(-1.0, 0.0, 0.0),
			}
		2:
			return {
				"u": Vector3(0.0, 0.0, 1.0),
				"v": Vector3(1.0, 0.0, 0.0),
				"w": Vector3(0.0, 1.0, 0.0),
			}
		3:
			return {
				"u": Vector3(0.0, 0.0, 1.0),
				"v": Vector3(-1.0, 0.0, 0.0),
				"w": Vector3(0.0, -1.0, 0.0),
			}
		4:
			return {
				"u": Vector3(1.0, 0.0, 0.0),
				"v": Vector3(0.0, 1.0, 0.0),
				"w": Vector3(0.0, 0.0, 1.0),
			}
		5:
			return {
				"u": Vector3(1.0, 0.0, 0.0),
				"v": Vector3(0.0, -1.0, 0.0),
				"w": Vector3(0.0, 0.0, -1.0),
			}
	return {
		"u": Vector3(1.0, 0.0, 0.0),
		"v": Vector3(0.0, 1.0, 0.0),
		"w": Vector3(0.0, 0.0, 1.0),
	}


static func isolated_edge_metrics(vertices: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	var counts := edge_counts_for_buffers([{"vertices": vertices, "indices": indices}], false)
	var open_edges := 0
	var nonmanifold_edges := 0
	for count_value in counts.values():
		var count := int(count_value)
		if count == 1:
			open_edges += 1
		elif count > 2:
			nonmanifold_edges += 1
	return {
		"open_edges": open_edges,
		"nonmanifold_edges": nonmanifold_edges,
	}


static func bounded_edge_metrics(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	bounds: AABB
) -> Dictionary:
	var counts := {}
	var edge_points := {}
	accumulate_edges(vertices, indices, Vector3.ZERO, counts, edge_points)
	var open_edges := 0
	var boundary_open_edges := 0
	var interior_open_edges := 0
	var nonmanifold_edges := 0
	for key in counts.keys():
		var count := int(counts[key])
		if count == 1:
			open_edges += 1
			var edge: Array = edge_points[key]
			if edge_on_bounds(edge[0], edge[1], bounds):
				boundary_open_edges += 1
			else:
				interior_open_edges += 1
		elif count > 2:
			nonmanifold_edges += 1
	return {
		"open_edges": open_edges,
		"boundary_open_edges": boundary_open_edges,
		"interior_open_edges": interior_open_edges,
		"nonmanifold_edges": nonmanifold_edges,
	}


static func orientation_metrics(vertices: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	var directed_counts := {}
	var undirected_counts := {}
	for i in range(0, indices.size(), 3):
		var triangle_indices := [int(indices[i]), int(indices[i + 1]), int(indices[i + 2])]
		for pair in [
			[triangle_indices[0], triangle_indices[1]],
			[triangle_indices[1], triangle_indices[2]],
			[triangle_indices[2], triangle_indices[0]],
		]:
			if pair[0] < 0 or pair[1] < 0 or pair[0] >= vertices.size() or pair[1] >= vertices.size():
				continue
			var a := vertices[int(pair[0])]
			var b := vertices[int(pair[1])]
			var directed_key := point_key(a) + ">" + point_key(b)
			var undirected_key := edge_key(a, b)
			directed_counts[directed_key] = int(directed_counts.get(directed_key, 0)) + 1
			undirected_counts[undirected_key] = int(undirected_counts.get(undirected_key, 0)) + 1
	var conflicts := 0
	for raw_key in undirected_counts.keys():
		var key := str(raw_key)
		if int(undirected_counts[key]) != 2:
			continue
		var parts := key.split("|")
		if parts.size() != 2:
			continue
		var forward := int(directed_counts.get(parts[0] + ">" + parts[1], 0))
		var reverse := int(directed_counts.get(parts[1] + ">" + parts[0], 0))
		if forward != 1 or reverse != 1:
			conflicts += 1
	return {"orientation_conflict_edges": conflicts}


static func validate_triangle_mesh_integrity(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array
) -> Dictionary:
	var nonfinite_vertices := 0
	for vertex in vertices:
		if not vector_is_finite(vertex):
			nonfinite_vertices += 1
	var degenerate_triangles := 0
	var duplicate_triangles := 0
	var winding_normal_conflicts := 0
	var compared_winding_triangles := 0
	var minimum_signed_alignment := INF
	var maximum_signed_alignment := -INF
	var local_winding_normal_disagreements := 0
	var local_winding_normal_ambiguous := 0
	var local_winding_normal_samples: Array = []
	var winding_normal_conflict_samples: Array = []
	var winding_scores: Array[float] = []
	var winding_edges := {}
	var seen_triangles := {}
	for offset in range(0, indices.size(), 3):
		if offset + 2 >= indices.size():
			break
		var ia := int(indices[offset])
		var ib := int(indices[offset + 1])
		var ic := int(indices[offset + 2])
		if ia < 0 or ib < 0 or ic < 0 \
				or ia >= vertices.size() or ib >= vertices.size() or ic >= vertices.size():
			continue
		var a := vertices[ia]
		var b := vertices[ib]
		var c := vertices[ic]
		var edge_ab := b - a
		var edge_ac := c - a
		var edge_bc := c - b
		var geometric := edge_ab.cross(edge_ac)
		var maximum_edge_squared := maxf(
			edge_ab.length_squared(),
			maxf(edge_ac.length_squared(), edge_bc.length_squared())
		)
		var minimum_edge_squared := minf(
			edge_ab.length_squared(),
			minf(edge_ac.length_squared(), edge_bc.length_squared())
		)
		if not vector_is_finite(geometric) \
				or minimum_edge_squared <= MINIMUM_TRIANGLE_EDGE_LENGTH_SQUARED \
				or geometric.length_squared() <= (
					maximum_edge_squared
					* maximum_edge_squared
					* MINIMUM_TRIANGLE_THIN_RATIO_SQUARED
				):
			degenerate_triangles += 1
			continue
		var triangle_points := [
			_precise_point_key(a),
			_precise_point_key(b),
			_precise_point_key(c),
		]
		triangle_points.sort()
		var triangle_key := "|".join(triangle_points)
		if seen_triangles.has(triangle_key):
			duplicate_triangles += 1
		else:
			seen_triangles[triangle_key] = true
		if normals.size() != vertices.size():
			continue
		var authored_normal := normals[ia] + normals[ib] + normals[ic]
		if authored_normal.length_squared() <= 0.000000000001:
			continue
		var alignment := geometric.normalized().dot(authored_normal.normalized())
		var signed_alignment := alignment * NORMAL_WINDING_POLARITY
		var winding_triangle_index := winding_scores.size()
		winding_scores.append(
			geometric.dot(authored_normal) * NORMAL_WINDING_POLARITY
		)
		for edge_points in [[a, b], [b, c], [c, a]]:
			var winding_edge := _winding_edge_key(edge_points[0], edge_points[1])
			if not winding_edges.has(winding_edge):
				winding_edges[winding_edge] = []
			winding_edges[winding_edge].append(winding_triangle_index)
		compared_winding_triangles += 1
		minimum_signed_alignment = minf(minimum_signed_alignment, signed_alignment)
		maximum_signed_alignment = maxf(maximum_signed_alignment, signed_alignment)
		if signed_alignment < -0.0001:
			local_winding_normal_disagreements += 1
			if local_winding_normal_samples.size() < 16:
				local_winding_normal_samples.append({
					"triangle_index": int(offset / 3),
					"alignment": alignment,
					"signed_alignment": signed_alignment,
				})
		elif signed_alignment <= 0.001:
			local_winding_normal_ambiguous += 1
	var winding_adjacency: Array = []
	winding_adjacency.resize(winding_scores.size())
	for index in winding_adjacency.size():
		winding_adjacency[index] = []
	for incidents_value in winding_edges.values():
		var incidents: Array = incidents_value
		if incidents.size() != 2:
			continue
		var first := int(incidents[0])
		var second := int(incidents[1])
		winding_adjacency[first].append(second)
		winding_adjacency[second].append(first)
	var visited := PackedByteArray()
	visited.resize(winding_scores.size())
	var winding_component_count := 0
	for start in winding_scores.size():
		if visited[start] != 0:
			continue
		winding_component_count += 1
		var pending: Array[int] = [start]
		visited[start] = 1
		var component_score := 0.0
		var component_magnitude := 0.0
		var component_triangles := 0
		while not pending.is_empty():
			var current := pending.pop_back()
			var triangle_score := winding_scores[current]
			component_score += triangle_score
			component_magnitude += absf(triangle_score)
			component_triangles += 1
			for neighbor_value in winding_adjacency[current]:
				var neighbor := int(neighbor_value)
				if visited[neighbor] != 0:
					continue
				visited[neighbor] = 1
				pending.append(neighbor)
		if component_magnitude <= 0.000000001:
			continue
		if component_score < -0.000000001:
			winding_normal_conflicts += 1
			if winding_normal_conflict_samples.size() < 16:
				winding_normal_conflict_samples.append({
					"component_index": winding_component_count - 1,
					"triangle_count": component_triangles,
					"signed_score": component_score,
					"magnitude": component_magnitude,
				})
	return {
		"nonfinite_vertices": nonfinite_vertices,
		"degenerate_triangles": degenerate_triangles,
		"duplicate_triangles": duplicate_triangles,
		"winding_normal_conflicts": winding_normal_conflicts,
		"winding_normal_conflict_samples": winding_normal_conflict_samples,
		"winding_component_count": winding_component_count,
		"local_winding_normal_disagreements": local_winding_normal_disagreements,
		"local_winding_normal_ambiguous": local_winding_normal_ambiguous,
		"local_winding_normal_samples": local_winding_normal_samples,
		"expected_normal_winding_polarity": NORMAL_WINDING_POLARITY,
		"compared_winding_triangles": compared_winding_triangles,
		"minimum_signed_alignment": (
			minimum_signed_alignment if compared_winding_triangles > 0 else 0.0
		),
		"maximum_signed_alignment": (
			maximum_signed_alignment if compared_winding_triangles > 0 else 0.0
		),
		"triangle_count": int(indices.size() / 3),
	}


static func _winding_edge_key(a: Vector3, b: Vector3) -> String:
	var first := _quantized_point_key(a, 1024.0)
	var second := _quantized_point_key(b, 1024.0)
	if second < first:
		var temporary := first
		first = second
		second = temporary
	return first + "|" + second


static func edge_counts_for_buffers(buffers: Array, world_space: bool = true) -> Dictionary:
	var counts := {}
	var edge_points := {}
	for raw_buffer in buffers:
		var buffer: Dictionary = raw_buffer
		var origin := vector3_from_variant(buffer.get("origin", Vector3.ZERO))
		if not world_space:
			origin = Vector3.ZERO
		accumulate_edges(
			buffer.get("vertices", PackedVector3Array()),
			buffer.get("indices", PackedInt32Array()),
			origin,
			counts,
			edge_points
		)
	return counts


static func plane_open_edge_signatures(buffers: Array, axis: int, plane: float) -> Dictionary:
	var counts := {}
	var edge_points := {}
	for raw_buffer in buffers:
		var buffer: Dictionary = raw_buffer
		accumulate_edges(
			buffer.get("vertices", PackedVector3Array()),
			buffer.get("indices", PackedInt32Array()),
			vector3_from_variant(buffer.get("origin", Vector3.ZERO)),
			counts,
			edge_points
		)
	var signatures := {}
	for key in counts.keys():
		if int(counts[key]) != 1:
			continue
		var edge: Array = edge_points[key]
		var a: Vector3 = edge[0]
		var b: Vector3 = edge[1]
		if absf(a[axis] - plane) <= POSITION_TOLERANCE and absf(b[axis] - plane) <= POSITION_TOLERANCE:
			signatures[face_edge_signature(a, b, axis)] = true
	return signatures


static func accumulate_edges(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	origin: Vector3,
	counts: Dictionary,
	edge_points: Dictionary
) -> void:
	for i in range(0, indices.size(), 3):
		if i + 2 >= indices.size():
			break
		var vertex_indices := [int(indices[i]), int(indices[i + 1]), int(indices[i + 2])]
		if vertex_indices.min() < 0 or vertex_indices.max() >= vertices.size():
			continue
		var a := vertices[vertex_indices[0]] + origin
		var b := vertices[vertex_indices[1]] + origin
		var c := vertices[vertex_indices[2]] + origin
		for edge in [[a, b], [b, c], [c, a]]:
			var key := edge_key(edge[0], edge[1])
			counts[key] = int(counts.get(key, 0)) + 1
			edge_points[key] = edge


static func set_difference_counts(left: Dictionary, right: Dictionary) -> Dictionary:
	var left_only := 0
	var right_only := 0
	for key in left.keys():
		if not right.has(key):
			left_only += 1
	for key in right.keys():
		if not left.has(key):
			right_only += 1
	return {"left_only": left_only, "right_only": right_only}


static func face_edge_signature(a: Vector3, b: Vector3, axis: int) -> String:
	var components: Array[int] = []
	for component in range(3):
		if component != axis:
			components.append(component)
	var first := "%d,%d" % [
		roundi(a[components[0]] * POSITION_SCALE),
		roundi(a[components[1]] * POSITION_SCALE),
	]
	var second := "%d,%d" % [
		roundi(b[components[0]] * POSITION_SCALE),
		roundi(b[components[1]] * POSITION_SCALE),
	]
	return first + "|" + second if first < second else second + "|" + first


static func edge_on_bounds(a: Vector3, b: Vector3, bounds: AABB) -> bool:
	var maximum := bounds.position + bounds.size
	for axis in range(3):
		if same_plane(a[axis], b[axis], bounds.position[axis]):
			return true
		if same_plane(a[axis], b[axis], maximum[axis]):
			return true
	return false


static func same_plane(a: float, b: float, plane: float) -> bool:
	return absf(a - plane) <= POSITION_TOLERANCE and absf(b - plane) <= POSITION_TOLERANCE


static func edge_key(a: Vector3, b: Vector3) -> String:
	var ka := point_key(a)
	var kb := point_key(b)
	return ka + "|" + kb if ka < kb else kb + "|" + ka


static func point_key(point: Vector3) -> String:
	return "%d,%d,%d" % [
		roundi(point.x * POSITION_SCALE),
		roundi(point.y * POSITION_SCALE),
		roundi(point.z * POSITION_SCALE),
	]


static func _precise_point_key(point: Vector3) -> String:
	return "%d,%d,%d" % [
		roundi(point.x * 1000000.0),
		roundi(point.y * 1000000.0),
		roundi(point.z * 1000000.0),
	]


static func _quantized_point_key(point: Vector3, scale: float) -> String:
	return "%d,%d,%d" % [
		roundi(point.x * scale),
		roundi(point.y * scale),
		roundi(point.z * scale),
	]


static func append_sample_failure(
	result: Dictionary,
	case_code: int,
	orientation: int,
	message: String,
	layer: String = "world_transvoxel"
) -> void:
	var failures: Array = result.get("sample_failures", [])
	if failures.size() >= 32:
		return
	var entry := {
		"case": case_code,
		"message": message,
		"source_layer": layer,
	}
	if orientation >= 0:
		entry["orientation"] = Contracts.TRANSITION_ORIENTATION_NAMES[orientation] \
			if orientation < Contracts.TRANSITION_ORIENTATION_NAMES.size() else str(orientation)
	failures.append(entry)
	result["sample_failures"] = failures


static func first_failure(existing: String, candidate: String) -> String:
	return candidate if existing.is_empty() else existing


static func vector_is_finite(value: Vector3) -> bool:
	return float_is_finite(value.x) and float_is_finite(value.y) and float_is_finite(value.z)


static func float_is_finite(value: float) -> bool:
	return value == value and absf(value) < 100000000000000000000.0


static func normal_is_valid(value: Vector3) -> bool:
	if not vector_is_finite(value):
		return false
	var length_squared := value.length_squared()
	return length_squared >= 0.999 and length_squared <= 1.001


static func vectors_nearly_equal(a: Vector3, b: Vector3, tolerance: float = 0.00001) -> bool:
	return absf(a.x - b.x) <= tolerance \
		and absf(a.y - b.y) <= tolerance \
		and absf(a.z - b.z) <= tolerance


static func vector3_from_variant(value: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	match typeof(value):
		TYPE_VECTOR3:
			return value
		TYPE_VECTOR3I:
			return Vector3(value)
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value
			return Vector3(
				float(dictionary.get("x", fallback.x)),
				float(dictionary.get("y", fallback.y)),
				float(dictionary.get("z", fallback.z))
			)
	return fallback
