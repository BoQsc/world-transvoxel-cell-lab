@tool
extends RefCounted
class_name WtTerrainLabAdaptiveLodSelector

var max_lod := 4
var chunk_world_size_m := 8.0
var maximum_neighbor_delta := 1
var teleport_reset_distance_m := 256.0
var split_distances_m: Array[float] = [0.0, 6.0, 12.0, 24.0, 32.0]
var merge_distances_m: Array[float] = [0.0, 9.0, 18.0, 36.0, 48.0]


func configure(standard: Dictionary) -> bool:
	var contract: Dictionary = standard.get("contract", {})
	var split_values: Array = contract.get("split_distances_m", [])
	var merge_values: Array = contract.get("merge_distances_m", [])
	var candidate_max_lod := int(contract.get("maximum_lod", -1))
	var candidate_root_span := int(contract.get("root_span_lod0_chunks", -1))
	if candidate_max_lod < 1 or split_values.size() != candidate_max_lod + 1 \
			or merge_values.size() != candidate_max_lod + 1 \
			or candidate_root_span != (1 << candidate_max_lod):
		return false
	var candidate_split: Array[float] = []
	var candidate_merge: Array[float] = []
	for lod in range(candidate_max_lod + 1):
		var split_distance := float(split_values[lod])
		var merge_distance := float(merge_values[lod])
		if split_distance < 0.0 or merge_distance < split_distance:
			return false
		candidate_split.append(split_distance)
		candidate_merge.append(merge_distance)
	max_lod = candidate_max_lod
	chunk_world_size_m = float(contract.get("lod0_chunk_world_size_m", 0.0))
	maximum_neighbor_delta = int(contract.get("maximum_neighbor_lod_delta", -1))
	teleport_reset_distance_m = float(contract.get("teleport_reset_distance_m", 0.0))
	if chunk_world_size_m <= 0.0 or maximum_neighbor_delta != 1 \
			or teleport_reset_distance_m <= 0.0:
		return false
	split_distances_m = candidate_split
	merge_distances_m = candidate_merge
	return true


func select(
	root_origin_chunk: Vector3i,
	viewer_local_m: Vector3,
	previous_leaves: Array = [],
	previous_viewer_local_m: Variant = null
) -> Dictionary:
	var teleport_reset := previous_viewer_local_m is Vector3 and (
		viewer_local_m.distance_to(previous_viewer_local_m)
			>= teleport_reset_distance_m
	)
	var retained_previous: Array = [] if teleport_reset else previous_leaves
	var leaves: Array[Dictionary] = []
	var split_records: Array[Dictionary] = []
	_select_node(
		root_origin_chunk,
		max_lod,
		root_origin_chunk,
		viewer_local_m,
		retained_previous,
		leaves,
		split_records,
		"metric"
	)
	var balance_splits := _balance(leaves, root_origin_chunk, split_records)
	var result := {
		"schema": "world_transvoxel.terrain_lab.adaptive_lod_selection.v1",
		"root_origin_chunk": root_origin_chunk,
		"root_lod": max_lod,
		"viewer_local_m": viewer_local_m,
		"teleport_reset": teleport_reset,
		"balance_split_count": balance_splits,
		"leaves": leaves,
		"split_records": split_records,
	}
	result["validation"] = validate_selection(result)
	result["signature"] = selection_signature(result)
	return result


func validate_selection(selection: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	var leaves: Array = selection.get("leaves", [])
	var root_origin: Vector3i = selection.get("root_origin_chunk", Vector3i.ZERO)
	var root_lod := int(selection.get("root_lod", max_lod))
	var root_span := 1 << root_lod
	var occupancy := PackedInt32Array()
	occupancy.resize(root_span * root_span * root_span)
	occupancy.fill(-1)
	var overlap_cells := 0
	var misaligned_nodes := 0
	var out_of_bounds_nodes := 0
	var invalid_lod_nodes := 0
	var covered_volume := 0
	for leaf_index in range(leaves.size()):
		var leaf_value: Variant = leaves[leaf_index]
		if not leaf_value is Dictionary:
			failures.append("selection contains a non-dictionary leaf")
			continue
		var leaf: Dictionary = leaf_value
		var origin: Vector3i = leaf.get("origin", Vector3i.ZERO)
		var lod := int(leaf.get("lod", -1))
		if lod < 0 or lod > root_lod:
			invalid_lod_nodes += 1
			continue
		var span := 1 << lod
		var relative := origin - root_origin
		if posmod(relative.x, span) != 0 or posmod(relative.y, span) != 0 \
				or posmod(relative.z, span) != 0:
			misaligned_nodes += 1
		if relative.x < 0 or relative.y < 0 or relative.z < 0 \
				or relative.x + span > root_span \
				or relative.y + span > root_span \
				or relative.z + span > root_span:
			out_of_bounds_nodes += 1
			continue
		covered_volume += span * span * span
		for z in range(origin.z, origin.z + span):
			for y in range(origin.y, origin.y + span):
				for x in range(origin.x, origin.x + span):
					var cell_index := _cell_index(
						Vector3i(x, y, z),
						root_origin,
						root_span
					)
					if occupancy[cell_index] >= 0:
						overlap_cells += 1
					else:
						occupancy[cell_index] = leaf_index
	var missing_cells := 0
	var vertical_incomplete_columns := 0
	for z in range(root_origin.z, root_origin.z + root_span):
		for x in range(root_origin.x, root_origin.x + root_span):
			var column_count := 0
			for y in range(root_origin.y, root_origin.y + root_span):
				if occupancy[_cell_index(Vector3i(x, y, z), root_origin, root_span)] >= 0:
					column_count += 1
				else:
					missing_cells += 1
			if column_count != root_span:
				vertical_incomplete_columns += 1
	var neighbor_delta_violations := 0
	var neighbor_pairs := {}
	for z in range(root_origin.z, root_origin.z + root_span):
		for y in range(root_origin.y, root_origin.y + root_span):
			for x in range(root_origin.x, root_origin.x + root_span):
				var coordinate := Vector3i(x, y, z)
				var left_index := occupancy[_cell_index(coordinate, root_origin, root_span)]
				if left_index < 0:
					continue
				var left: Dictionary = leaves[left_index]
				for axis in range(3):
					var neighbor_coordinate := coordinate
					neighbor_coordinate[axis] += 1
					if neighbor_coordinate[axis] >= root_origin[axis] + root_span:
						continue
					var right_index := occupancy[
						_cell_index(neighbor_coordinate, root_origin, root_span)
					]
					if right_index < 0 or left_index == right_index:
						continue
					var right: Dictionary = leaves[right_index]
					var first_index := mini(left_index, right_index)
					var second_index := maxi(left_index, right_index)
					var pair_key := "%d:%d:%d" % [first_index, second_index, axis]
					if neighbor_pairs.has(pair_key):
						continue
					neighbor_pairs[pair_key] = true
					if absi(int(left.get("lod", 0)) - int(right.get("lod", 0))) \
							> maximum_neighbor_delta:
						neighbor_delta_violations += 1
	var invalid_split_records := 0
	for record_value in selection.get("split_records", []):
		if not record_value is Dictionary:
			invalid_split_records += 1
			continue
		var record: Dictionary = record_value
		var parent_origin: Vector3i = record.get("origin", Vector3i.ZERO)
		var parent_lod := int(record.get("lod", 0))
		var children: Array = record.get("children", [])
		if parent_lod <= 0 or children.size() != 8:
			invalid_split_records += 1
			continue
		var expected_children := _child_keys(parent_origin, parent_lod)
		var observed_children: Array[String] = []
		for child_value in children:
			if child_value is Dictionary:
				observed_children.append(_node_key(child_value))
		observed_children.sort()
		if observed_children != expected_children:
			invalid_split_records += 1
	if leaves.is_empty():
		failures.append("selection contains no leaves")
	if invalid_lod_nodes > 0:
		failures.append("invalid_lod_nodes=%d" % invalid_lod_nodes)
	if misaligned_nodes > 0:
		failures.append("misaligned_nodes=%d" % misaligned_nodes)
	if out_of_bounds_nodes > 0:
		failures.append("out_of_bounds_nodes=%d" % out_of_bounds_nodes)
	if overlap_cells > 0:
		failures.append("overlap_cells=%d" % overlap_cells)
	if missing_cells > 0:
		failures.append("missing_cells=%d" % missing_cells)
	if vertical_incomplete_columns > 0:
		failures.append("vertical_incomplete_columns=%d" % vertical_incomplete_columns)
	if neighbor_delta_violations > 0:
		failures.append("neighbor_delta_violations=%d" % neighbor_delta_violations)
	if invalid_split_records > 0:
		failures.append("invalid_split_records=%d" % invalid_split_records)
	return {
		"schema": "world_transvoxel.terrain_lab.adaptive_lod_structure_validation.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"leaf_count": leaves.size(),
		"covered_volume_lod0_chunks": covered_volume,
		"expected_volume_lod0_chunks": root_span * root_span * root_span,
		"occupancy_cell_count": root_span * root_span * root_span - missing_cells,
		"overlap_cells": overlap_cells,
		"missing_cells": missing_cells,
		"misaligned_nodes": misaligned_nodes,
		"out_of_bounds_nodes": out_of_bounds_nodes,
		"invalid_lod_nodes": invalid_lod_nodes,
		"vertical_incomplete_columns": vertical_incomplete_columns,
		"neighbor_pair_count": neighbor_pairs.size(),
		"neighbor_delta_violations": neighbor_delta_violations,
		"invalid_split_records": invalid_split_records,
		"failures": failures,
	}


func selection_signature(selection: Dictionary, normalize_origin: bool = true) -> String:
	var root_origin: Vector3i = selection.get("root_origin_chunk", Vector3i.ZERO)
	var lines: Array[String] = []
	for leaf_value in selection.get("leaves", []):
		var leaf: Dictionary = leaf_value
		var origin: Vector3i = leaf.get("origin", Vector3i.ZERO)
		if normalize_origin:
			origin -= root_origin
		lines.append("%d,%d,%d:%d" % [
			origin.x,
			origin.y,
			origin.z,
			int(leaf.get("lod", -1)),
		])
	lines.sort()
	return "\n".join(lines).sha256_text()


func distance_to_node_m(
	node_origin_chunk: Vector3i,
	lod: int,
	root_origin_chunk: Vector3i,
	viewer_local_m: Vector3
) -> float:
	var relative := node_origin_chunk - root_origin_chunk
	var minimum := Vector3(relative) * chunk_world_size_m
	var maximum := minimum + Vector3.ONE * float(1 << lod) * chunk_world_size_m
	var nearest := Vector3(
		clampf(viewer_local_m.x, minimum.x, maximum.x),
		clampf(viewer_local_m.y, minimum.y, maximum.y),
		clampf(viewer_local_m.z, minimum.z, maximum.z)
	)
	return viewer_local_m.distance_to(nearest)


func _select_node(
	origin: Vector3i,
	lod: int,
	root_origin: Vector3i,
	viewer_local_m: Vector3,
	previous_leaves: Array,
	leaves: Array[Dictionary],
	split_records: Array[Dictionary],
	reason: String
) -> void:
	if lod <= 0:
		leaves.append(_node(origin, lod))
		return
	var distance := distance_to_node_m(origin, lod, root_origin, viewer_local_m)
	var was_refined := _previously_refined(previous_leaves, origin, lod)
	var threshold := merge_distances_m[lod] if was_refined else split_distances_m[lod]
	if distance > threshold:
		leaves.append(_node(origin, lod))
		return
	var children := _children(origin, lod)
	split_records.append({
		"origin": origin,
		"lod": lod,
		"reason": reason,
		"distance_m": distance,
		"threshold_m": threshold,
		"children": children,
	})
	for child in children:
		_select_node(
			child.get("origin", Vector3i.ZERO),
			lod - 1,
			root_origin,
			viewer_local_m,
			previous_leaves,
			leaves,
			split_records,
			reason
		)


func _balance(
	leaves: Array[Dictionary],
	root_origin: Vector3i,
	split_records: Array[Dictionary]
) -> int:
	var split_count := 0
	for iteration in range(max_lod + 2):
		var occupancy := _valid_occupancy(leaves, root_origin)
		var marked := {}
		var root_span := 1 << max_lod
		for z in range(root_origin.z, root_origin.z + root_span):
			for y in range(root_origin.y, root_origin.y + root_span):
				for x in range(root_origin.x, root_origin.x + root_span):
					var coordinate := Vector3i(x, y, z)
					var left_index := occupancy[_cell_index(coordinate, root_origin, root_span)]
					if left_index < 0:
						continue
					var left: Dictionary = leaves[left_index]
					for axis in range(3):
						var neighbor_coordinate := coordinate
						neighbor_coordinate[axis] += 1
						if neighbor_coordinate[axis] >= root_origin[axis] + root_span:
							continue
						var right_index := occupancy[
							_cell_index(neighbor_coordinate, root_origin, root_span)
						]
						if right_index < 0:
							continue
						var right: Dictionary = leaves[right_index]
						var left_lod := int(left.get("lod", 0))
						var right_lod := int(right.get("lod", 0))
						if absi(left_lod - right_lod) <= maximum_neighbor_delta:
							continue
						var coarse := left if left_lod > right_lod else right
						marked[_node_key(coarse)] = coarse
		if marked.is_empty():
			break
		var next_leaves: Array[Dictionary] = []
		for leaf in leaves:
			if not marked.has(_node_key(leaf)):
				next_leaves.append(leaf)
				continue
			var children := _children(
				leaf.get("origin", Vector3i.ZERO),
				int(leaf.get("lod", 0))
			)
			next_leaves.append_array(children)
			split_records.append({
				"origin": leaf.get("origin", Vector3i.ZERO),
				"lod": int(leaf.get("lod", 0)),
				"reason": "balance",
				"children": children,
			})
			split_count += 1
		leaves.assign(next_leaves)
	return split_count


func _valid_occupancy(leaves: Array[Dictionary], root_origin: Vector3i) -> PackedInt32Array:
	var root_span := 1 << max_lod
	var result := PackedInt32Array()
	result.resize(root_span * root_span * root_span)
	result.fill(-1)
	for leaf_index in range(leaves.size()):
		var leaf: Dictionary = leaves[leaf_index]
		var lod := int(leaf.get("lod", -1))
		if lod < 0 or lod > max_lod:
			continue
		var origin: Vector3i = leaf.get("origin", Vector3i.ZERO)
		var span := 1 << lod
		var relative := origin - root_origin
		if relative.x < 0 or relative.y < 0 or relative.z < 0 \
				or relative.x + span > root_span \
				or relative.y + span > root_span \
				or relative.z + span > root_span:
			continue
		for z in range(origin.z, origin.z + span):
			for y in range(origin.y, origin.y + span):
				for x in range(origin.x, origin.x + span):
					result[_cell_index(Vector3i(x, y, z), root_origin, root_span)] = leaf_index
	return result


func _previously_refined(previous_leaves: Array, origin: Vector3i, lod: int) -> bool:
	var span := 1 << lod
	for leaf_value in previous_leaves:
		if not leaf_value is Dictionary:
			continue
		var leaf: Dictionary = leaf_value
		if int(leaf.get("lod", lod)) >= lod:
			continue
		var candidate: Vector3i = leaf.get("origin", Vector3i.ZERO)
		if candidate.x >= origin.x and candidate.x < origin.x + span \
				and candidate.y >= origin.y and candidate.y < origin.y + span \
				and candidate.z >= origin.z and candidate.z < origin.z + span:
			return true
	return false


func _children(origin: Vector3i, lod: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if lod <= 0:
		return result
	var child_lod := lod - 1
	var child_span := 1 << child_lod
	for z in range(2):
		for y in range(2):
			for x in range(2):
				result.append(_node(
					origin + Vector3i(x, y, z) * child_span,
					child_lod
				))
	return result


func _child_keys(origin: Vector3i, lod: int) -> Array[String]:
	var result: Array[String] = []
	for child in _children(origin, lod):
		result.append(_node_key(child))
	result.sort()
	return result


static func _node(origin: Vector3i, lod: int) -> Dictionary:
	return {"origin": origin, "lod": lod}


static func _node_key(node: Dictionary) -> String:
	var origin: Vector3i = node.get("origin", Vector3i.ZERO)
	return "%d,%d,%d:%d" % [origin.x, origin.y, origin.z, int(node.get("lod", -1))]


static func _cell_index(
	coordinate: Vector3i,
	root_origin: Vector3i,
	root_span: int
) -> int:
	var local := coordinate - root_origin
	return local.x + root_span * (local.y + root_span * local.z)
