@tool
extends RefCounted
class_name WtTerrainLabIndependentOracle

const POSITION_SCALE := 1000000.0
const POSITION_TOLERANCE := 0.0001
const AREA_EPSILON_SQUARED := 0.0000000001
const RAY_EPSILON := 0.000001

const CHECK_IDS := [
	"index_integrity",
	"finite_value",
	"bounds",
	"degenerate_triangle",
	"edge_multiplicity",
	"non_manifold",
	"duplicate_overlap",
	"orientation",
	"component",
	"euler_characteristic",
	"ray_parity",
	"signed_volume",
	"field_resampling",
]


static func analyze(mesh: Dictionary, contract: Dictionary) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var vertices: PackedVector3Array = mesh.get("vertices", PackedVector3Array())
	var indices: PackedInt32Array = mesh.get("indices", PackedInt32Array())
	var bounds_min: Vector3 = contract.get("bounds_min", Vector3.ZERO)
	var bounds_max: Vector3 = contract.get("bounds_max", Vector3.ZERO)
	var closed := bool(contract.get("closed", false))
	var allowed_open_faces: Array = contract.get("allowed_open_faces", [])
	var nonfinite_vertex_count := 0
	var bounds_violation_count := 0
	for vertex in vertices:
		if not vertex.is_finite():
			nonfinite_vertex_count += 1
			continue
		if vertex.x < bounds_min.x - POSITION_TOLERANCE \
				or vertex.y < bounds_min.y - POSITION_TOLERANCE \
				or vertex.z < bounds_min.z - POSITION_TOLERANCE \
				or vertex.x > bounds_max.x + POSITION_TOLERANCE \
				or vertex.y > bounds_max.y + POSITION_TOLERANCE \
				or vertex.z > bounds_max.z + POSITION_TOLERANCE:
			bounds_violation_count += 1
	var invalid_index_count := 0
	var incomplete_triangle_index_count := indices.size() % 3
	var degenerate_triangle_count := 0
	var duplicate_triangle_count := 0
	var valid_triangles: Array[Dictionary] = []
	var edge_records := {}
	var triangle_keys := {}
	var unique_vertex_keys := {}
	var signed_volume := 0.0
	for triangle_offset in range(0, indices.size(), 3):
		if triangle_offset + 2 >= indices.size():
			break
		var triangle_indices := [
			int(indices[triangle_offset]),
			int(indices[triangle_offset + 1]),
			int(indices[triangle_offset + 2]),
		]
		var valid_indices := true
		for vertex_index in triangle_indices:
			if vertex_index < 0 or vertex_index >= vertices.size():
				invalid_index_count += 1
				valid_indices = false
		if not valid_indices:
			continue
		var a := vertices[triangle_indices[0]]
		var b := vertices[triangle_indices[1]]
		var c := vertices[triangle_indices[2]]
		if not a.is_finite() or not b.is_finite() or not c.is_finite():
			continue
		var area_vector := (b - a).cross(c - a)
		if area_vector.length_squared() <= AREA_EPSILON_SQUARED:
			degenerate_triangle_count += 1
			continue
		var keys := [_point_key(a), _point_key(b), _point_key(c)]
		for key in keys:
			unique_vertex_keys[key] = true
		var sorted_keys := keys.duplicate()
		sorted_keys.sort()
		var triangle_key := "|".join(sorted_keys)
		if triangle_keys.has(triangle_key):
			duplicate_triangle_count += 1
		triangle_keys[triangle_key] = int(triangle_keys.get(triangle_key, 0)) + 1
		var triangle_index := valid_triangles.size()
		valid_triangles.append({
			"a": a,
			"b": b,
			"c": c,
			"source_triangle_index": int(triangle_offset / 3),
		})
		signed_volume += a.dot(b.cross(c)) / 6.0
		for edge in [[0, 1], [1, 2], [2, 0]]:
			var first_key: String = keys[edge[0]]
			var second_key: String = keys[edge[1]]
			var edge_key := (
				first_key + "|" + second_key
				if first_key < second_key
				else second_key + "|" + first_key
			)
			var record: Dictionary = edge_records.get(edge_key, {
				"count": 0,
				"orientation_balance": 0,
				"a": [a, b, c][edge[0]],
				"b": [a, b, c][edge[1]],
				"triangles": [],
			})
			record["count"] = int(record.get("count", 0)) + 1
			record["orientation_balance"] = int(record.get("orientation_balance", 0)) \
				+ (1 if first_key < second_key else -1)
			(record["triangles"] as Array).append(triangle_index)
			edge_records[edge_key] = record
	var boundary_edge_count := 0
	var forbidden_open_edge_count := 0
	var unclassified_open_edge_count := 0
	var nonmanifold_edge_count := 0
	var orientation_conflict_count := 0
	var open_face_counts := _empty_face_counts()
	for edge_key in edge_records:
		var record: Dictionary = edge_records[edge_key]
		var count := int(record.get("count", 0))
		if count == 1:
			boundary_edge_count += 1
			var faces := _edge_faces(
				record.get("a", Vector3.ZERO),
				record.get("b", Vector3.ZERO),
				bounds_min,
				bounds_max
			)
			if faces.is_empty():
				unclassified_open_edge_count += 1
				forbidden_open_edge_count += 1
			for face in faces:
				open_face_counts[face] = int(open_face_counts[face]) + 1
				if closed or face not in allowed_open_faces:
					forbidden_open_edge_count += 1
		elif count > 2:
			nonmanifold_edge_count += 1
		if count == 2 and int(record.get("orientation_balance", 0)) != 0:
			orientation_conflict_count += 1
	var component_count := _component_count(valid_triangles.size(), edge_records)
	var euler_characteristic := unique_vertex_keys.size() - edge_records.size() \
		+ valid_triangles.size()
	var ray_results: Array[Dictionary] = []
	var ray_failures := 0
	for ray_value in contract.get("ray_tests", []):
		var ray: Dictionary = ray_value
		var intersections := ray_intersections(
			mesh,
			ray.get("origin", Vector3.ZERO),
			ray.get("direction", Vector3.RIGHT)
		)
		var count := int(intersections.get("unique_hit_count", 0))
		var expected_parity := int(ray.get("expected_parity", 0))
		var passed := count >= int(ray.get("minimum_hit_count", 0)) \
			and count % 2 == expected_parity
		if not passed:
			ray_failures += 1
		ray_results.append({
			"id": ray.get("id", ""),
			"status": "PASS" if passed else "FAIL",
			"unique_hit_count": count,
			"expected_parity": expected_parity,
			"minimum_hit_count": ray.get("minimum_hit_count", 0),
			"hit_distances": intersections.get("hit_distances", []),
		})
	var field_result := _field_resampling(
		vertices,
		contract.get("field_sampler", Callable()),
		mesh.get("reference_origin", Vector3.ZERO),
		float(contract.get("field_tolerance", 0.0001))
	)
	var checks := {}
	checks["index_integrity"] = _check_result(
		invalid_index_count == 0 and incomplete_triangle_index_count == 0,
		{"invalid_index_count": invalid_index_count, "incomplete_index_count": incomplete_triangle_index_count}
	)
	checks["finite_value"] = _check_result(
		nonfinite_vertex_count == 0,
		{"nonfinite_vertex_count": nonfinite_vertex_count}
	)
	checks["bounds"] = _check_result(
		bounds_violation_count == 0,
		{"bounds_violation_count": bounds_violation_count}
	)
	checks["degenerate_triangle"] = _check_result(
		degenerate_triangle_count == 0,
		{"degenerate_triangle_count": degenerate_triangle_count}
	)
	checks["edge_multiplicity"] = _check_result(
		forbidden_open_edge_count == 0,
		{
			"boundary_edge_count": boundary_edge_count,
			"forbidden_open_edge_count": forbidden_open_edge_count,
			"unclassified_open_edge_count": unclassified_open_edge_count,
			"open_face_counts": open_face_counts,
		}
	)
	checks["non_manifold"] = _check_result(
		nonmanifold_edge_count == 0,
		{"nonmanifold_edge_count": nonmanifold_edge_count}
	)
	checks["duplicate_overlap"] = _check_result(
		duplicate_triangle_count == 0,
		{"exact_duplicate_triangle_count": duplicate_triangle_count}
	)
	checks["orientation"] = _check_result(
		orientation_conflict_count == 0,
		{"orientation_conflict_edge_count": orientation_conflict_count}
	)
	checks["component"] = _check_result(
		component_count == int(contract.get("expected_component_count", component_count)),
		{
			"component_count": component_count,
			"expected_component_count": contract.get("expected_component_count", component_count),
		}
	)
	var expected_euler: Variant = contract.get("expected_euler_characteristic")
	checks["euler_characteristic"] = _applicable_check(
		expected_euler != null,
		expected_euler == null or euler_characteristic == int(expected_euler),
		{
			"euler_characteristic": euler_characteristic,
			"expected_euler_characteristic": expected_euler,
		}
	)
	checks["ray_parity"] = _applicable_check(
		not (contract.get("ray_tests", []) as Array).is_empty(),
		ray_failures == 0,
		{"ray_results": ray_results, "failure_count": ray_failures}
	)
	var expected_volume_sign := int(contract.get("expected_signed_volume_sign", 0))
	var volume_sign := signi(signed_volume)
	checks["signed_volume"] = _applicable_check(
		expected_volume_sign != 0,
		expected_volume_sign == 0 or (
			volume_sign == expected_volume_sign
			and absf(signed_volume) >= float(contract.get("minimum_abs_signed_volume", 0.0))
		),
		{
			"signed_volume": signed_volume,
			"observed_sign": volume_sign,
			"expected_sign": expected_volume_sign,
		}
	)
	checks["field_resampling"] = _applicable_check(
		bool(field_result.get("applicable", false)),
		str(field_result.get("status", "")) == "PASS",
		field_result
	)
	var failures: Array[String] = []
	for check_id in CHECK_IDS:
		var check: Dictionary = checks.get(check_id, {})
		if str(check.get("status", "")) == "FAIL":
			failures.append(check_id)
	return {
		"schema": "world_transvoxel.terrain_lab.independent_mesh_oracle.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"checks": checks,
		"metrics": {
			"input_vertex_count": vertices.size(),
			"input_triangle_count": int(indices.size() / 3),
			"valid_triangle_count": valid_triangles.size(),
			"unique_vertex_count": unique_vertex_keys.size(),
			"unique_edge_count": edge_records.size(),
			"component_count": component_count,
			"euler_characteristic": euler_characteristic,
			"signed_volume": signed_volume,
		},
		"elapsed_usec": Time.get_ticks_usec() - started_usec,
		"failures": failures,
	}


static func ray_intersections(mesh: Dictionary, origin: Vector3, direction: Vector3) -> Dictionary:
	var vertices: PackedVector3Array = mesh.get("vertices", PackedVector3Array())
	var indices: PackedInt32Array = mesh.get("indices", PackedInt32Array())
	var normalized_direction := direction.normalized()
	var hits: Array[Dictionary] = []
	if normalized_direction.length_squared() <= 0.0:
		return {"unique_hit_count": 0, "hits": [], "hit_distances": []}
	for triangle_offset in range(0, indices.size(), 3):
		if triangle_offset + 2 >= indices.size():
			break
		var ia := int(indices[triangle_offset])
		var ib := int(indices[triangle_offset + 1])
		var ic := int(indices[triangle_offset + 2])
		if ia < 0 or ib < 0 or ic < 0 or ia >= vertices.size() \
				or ib >= vertices.size() or ic >= vertices.size():
			continue
		var distance := _ray_triangle_distance(
			origin, normalized_direction, vertices[ia], vertices[ib], vertices[ic]
		)
		if distance < 0.0:
			continue
		hits.append({
			"triangle_index": int(triangle_offset / 3),
			"distance": distance,
		})
	hits.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return float(left.get("distance", 0.0)) < float(right.get("distance", 0.0))
	)
	var unique_hits: Array[Dictionary] = []
	for hit in hits:
		if unique_hits.is_empty() or absf(
			float(hit.get("distance", 0.0))
				- float(unique_hits[-1].get("distance", 0.0))
		) > POSITION_TOLERANCE:
			unique_hits.append(hit)
	var distances: Array[float] = []
	for hit in unique_hits:
		distances.append(float(hit.get("distance", 0.0)))
	return {
		"unique_hit_count": unique_hits.size(),
		"hits": unique_hits,
		"hit_distances": distances,
	}


static func _field_resampling(
	vertices: PackedVector3Array,
	field_sampler: Callable,
	reference_origin: Vector3,
	tolerance: float
) -> Dictionary:
	if not field_sampler.is_valid():
		return {"applicable": false, "status": "NOT_APPLICABLE"}
	var cache := {}
	var maximum_residual := 0.0
	var failure_count := 0
	for vertex in vertices:
		if not vertex.is_finite():
			continue
		var density := _trilinear_density(reference_origin + vertex, field_sampler, cache)
		maximum_residual = maxf(maximum_residual, absf(density))
		if absf(density) > tolerance:
			failure_count += 1
	return {
		"applicable": true,
		"status": "PASS" if failure_count == 0 else "FAIL",
		"sampled_vertex_count": vertices.size(),
		"unique_grid_sample_count": cache.size(),
		"maximum_abs_density_residual": maximum_residual,
		"tolerance": tolerance,
		"failure_count": failure_count,
	}


static func _trilinear_density(
	point: Vector3,
	field_sampler: Callable,
	cache: Dictionary
) -> float:
	var minimum := Vector3i(floori(point.x), floori(point.y), floori(point.z))
	var fraction := point - Vector3(minimum)
	var result := 0.0
	for z in range(2):
		for y in range(2):
			for x in range(2):
				var coordinate := minimum + Vector3i(x, y, z)
				var key := "%d,%d,%d" % [coordinate.x, coordinate.y, coordinate.z]
				if not cache.has(key):
					var sample: Variant = field_sampler.call(coordinate)
					cache[key] = (
						float((sample as Dictionary).get("density", INF))
						if sample is Dictionary
						else float(sample)
					)
				var weight := (
					(fraction.x if x == 1 else 1.0 - fraction.x)
					* (fraction.y if y == 1 else 1.0 - fraction.y)
					* (fraction.z if z == 1 else 1.0 - fraction.z)
				)
				result += float(cache[key]) * weight
	return result


static func _component_count(triangle_count: int, edge_records: Dictionary) -> int:
	if triangle_count <= 0:
		return 0
	var adjacency: Array[Array] = []
	for triangle_index in range(triangle_count):
		adjacency.append([])
	for record_value in edge_records.values():
		var incidents: Array = (record_value as Dictionary).get("triangles", [])
		for first_index in range(incidents.size()):
			for second_index in range(first_index + 1, incidents.size()):
				var first := int(incidents[first_index])
				var second := int(incidents[second_index])
				if second not in adjacency[first]:
					adjacency[first].append(second)
				if first not in adjacency[second]:
					adjacency[second].append(first)
	var visited := PackedByteArray()
	visited.resize(triangle_count)
	var components := 0
	for start in range(triangle_count):
		if visited[start] != 0:
			continue
		components += 1
		var pending: Array[int] = [start]
		visited[start] = 1
		while not pending.is_empty():
			var current := pending.pop_back()
			for neighbor_value in adjacency[current]:
				var neighbor := int(neighbor_value)
				if visited[neighbor] == 0:
					visited[neighbor] = 1
					pending.append(neighbor)
	return components


static func _edge_faces(
	a: Vector3,
	b: Vector3,
	bounds_min: Vector3,
	bounds_max: Vector3
) -> Array[String]:
	var faces: Array[String] = []
	if absf(a.x - bounds_min.x) <= POSITION_TOLERANCE \
			and absf(b.x - bounds_min.x) <= POSITION_TOLERANCE:
		faces.append("negative_x")
	if absf(a.x - bounds_max.x) <= POSITION_TOLERANCE \
			and absf(b.x - bounds_max.x) <= POSITION_TOLERANCE:
		faces.append("positive_x")
	if absf(a.y - bounds_min.y) <= POSITION_TOLERANCE \
			and absf(b.y - bounds_min.y) <= POSITION_TOLERANCE:
		faces.append("negative_y")
	if absf(a.y - bounds_max.y) <= POSITION_TOLERANCE \
			and absf(b.y - bounds_max.y) <= POSITION_TOLERANCE:
		faces.append("positive_y")
	if absf(a.z - bounds_min.z) <= POSITION_TOLERANCE \
			and absf(b.z - bounds_min.z) <= POSITION_TOLERANCE:
		faces.append("negative_z")
	if absf(a.z - bounds_max.z) <= POSITION_TOLERANCE \
			and absf(b.z - bounds_max.z) <= POSITION_TOLERANCE:
		faces.append("positive_z")
	return faces


static func _ray_triangle_distance(
	origin: Vector3,
	direction: Vector3,
	a: Vector3,
	b: Vector3,
	c: Vector3
) -> float:
	var edge_one := b - a
	var edge_two := c - a
	var p := direction.cross(edge_two)
	var determinant := edge_one.dot(p)
	if absf(determinant) <= RAY_EPSILON:
		return -1.0
	var inverse := 1.0 / determinant
	var translated := origin - a
	var u := translated.dot(p) * inverse
	if u < -RAY_EPSILON or u > 1.0 + RAY_EPSILON:
		return -1.0
	var q := translated.cross(edge_one)
	var v := direction.dot(q) * inverse
	if v < -RAY_EPSILON or u + v > 1.0 + RAY_EPSILON:
		return -1.0
	var distance := edge_two.dot(q) * inverse
	return distance if distance > RAY_EPSILON else -1.0


static func _check_result(passed: bool, metrics: Dictionary) -> Dictionary:
	var result := metrics.duplicate(true)
	result["status"] = "PASS" if passed else "FAIL"
	return result


static func _applicable_check(
	applicable: bool,
	passed: bool,
	metrics: Dictionary
) -> Dictionary:
	var result := metrics.duplicate(true)
	result["status"] = "PASS" if applicable and passed else (
		"FAIL" if applicable else "NOT_APPLICABLE"
	)
	return result


static func _empty_face_counts() -> Dictionary:
	return {
		"negative_x": 0,
		"positive_x": 0,
		"negative_y": 0,
		"positive_y": 0,
		"negative_z": 0,
		"positive_z": 0,
	}


static func _point_key(point: Vector3) -> String:
	return "%d,%d,%d" % [
		roundi(point.x * POSITION_SCALE),
		roundi(point.y * POSITION_SCALE),
		roundi(point.z * POSITION_SCALE),
	]
