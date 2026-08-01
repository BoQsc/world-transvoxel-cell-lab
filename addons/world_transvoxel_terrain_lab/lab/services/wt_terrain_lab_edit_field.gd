@tool
extends RefCounted
class_name WtTerrainLabEditField

const ISO_VALUE := 0.0
const BASE_MATERIAL := 1
const DEFAULT_CONSTRUCTION_MATERIAL := 5
const BASE_HEIGHT_M := 12.0
const DEFAULT_SAMPLE_SCALE_M := 0.5
const SPATIAL_BUCKET_SIZE_M := 4.0
const MAX_BUCKET_REFERENCES_PER_OPERATION := 4096
const JOURNAL_SCHEMA_V1 := "world_transvoxel.terrain_lab.edit_journal.v1"
const JOURNAL_SCHEMA := "world_transvoxel.terrain_lab.edit_journal.v2"

var operations: Array[Dictionary] = []
var terrain_profile := "flat"
var sample_scale_m := DEFAULT_SAMPLE_SCALE_M
var base_height_m := BASE_HEIGHT_M
var _operation_ids := {}
var _transaction_ids := {}
var _spatial_index := {}
var _global_operation_indices: Array[int] = []
var _spatial_reference_count := 0


func sample(point: Vector3i) -> Dictionary:
	return sample_point(Vector3(point) * sample_scale_m)


func sample_point(point: Vector3) -> Dictionary:
	var density_value := density(point)
	return {
		"density": density_value,
		"material": material_at(point, density_value),
		"material_authored": density_value < ISO_VALUE,
	}


func density(point: Vector3) -> float:
	var value := base_density(point)
	for operation_index in _candidate_indices(point):
		var operation: Dictionary = operations[operation_index]
		if not bool(operation.get("enabled", true)):
			continue
		var shape_density := shape_sdf(operation, point)
		var smoothing := maxf(float(operation.get("smoothing_m", 0.0)), 0.0)
		if str(operation.get("mode", "")) == "dig":
			value = (
				smooth_max(value, -shape_density, smoothing)
				if smoothing > 0.0
				else maxf(value, -shape_density)
			)
		elif str(operation.get("mode", "")) == "construct":
			value = (
				smooth_min(value, shape_density, smoothing)
				if smoothing > 0.0
				else minf(value, shape_density)
			)
	return value


func base_density(point: Vector3) -> float:
	if terrain_profile == "empty":
		return 1000000.0
	if terrain_profile == "solid":
		return -1000000.0
	if terrain_profile == "observatory":
		var height := 8.5 \
			+ 2.8 * sin(point.x * 0.055) \
			+ 2.0 * cos(point.z * 0.072) \
			+ 0.9 * sin((point.x + point.z) * 0.11)
		return point.y - height
	return point.y - base_height_m


func material_at(point: Vector3, density_value: float) -> int:
	if density_value >= ISO_VALUE:
		return 0
	var material := BASE_MATERIAL
	for operation_index in _candidate_indices(point):
		var operation: Dictionary = operations[operation_index]
		if not bool(operation.get("enabled", true)):
			continue
		if str(operation.get("mode", "")) != "construct":
			continue
		if shape_sdf(operation, point) <= 0.0:
			material = int(operation.get("material", DEFAULT_CONSTRUCTION_MATERIAL))
	return material


func gradient(point: Vector3, epsilon: float = 0.001) -> Vector3:
	var dx := density(point + Vector3(epsilon, 0.0, 0.0)) \
		- density(point - Vector3(epsilon, 0.0, 0.0))
	var dy := density(point + Vector3(0.0, epsilon, 0.0)) \
		- density(point - Vector3(0.0, epsilon, 0.0))
	var dz := density(point + Vector3(0.0, 0.0, epsilon)) \
		- density(point - Vector3(0.0, 0.0, epsilon))
	return Vector3(dx, dy, dz).normalized()


func add_operation(operation_value: Dictionary) -> bool:
	var operation := canonical_operation(operation_value)
	var operation_id := str(operation.get("id", ""))
	if not _operation_is_valid(operation) or _operation_ids.has(operation_id):
		return false
	_append_operation(operation)
	return true


func add_transaction(transaction_id: String, operation_values: Array) -> bool:
	if transaction_id.is_empty() or _transaction_ids.has(transaction_id) \
			or operation_values.is_empty():
		return false
	var pending: Array[Dictionary] = []
	var pending_ids := {}
	for operation_value in operation_values:
		if not operation_value is Dictionary:
			return false
		var source: Dictionary = operation_value
		var operation := canonical_operation(source)
		operation["transaction_id"] = transaction_id
		var operation_id := str(operation.get("id", ""))
		if not _operation_is_valid(operation) \
				or _operation_ids.has(operation_id) \
				or pending_ids.has(operation_id):
			return false
		pending.append(operation)
		pending_ids[operation_id] = true
	_transaction_ids[transaction_id] = []
	for operation in pending:
		_append_operation(operation)
	return true


func set_operation_enabled(operation_id: String, enabled: bool) -> bool:
	if not _operation_ids.has(operation_id):
		return false
	var index := int(_operation_ids[operation_id])
	operations[index]["enabled"] = enabled
	return true


func set_transaction_enabled(transaction_id: String, enabled: bool) -> bool:
	if not _transaction_ids.has(transaction_id):
		return false
	for index_value in _transaction_ids[transaction_id]:
		operations[int(index_value)]["enabled"] = enabled
	return true


func undo_latest() -> String:
	for index in range(operations.size() - 1, -1, -1):
		if bool(operations[index].get("enabled", true)):
			operations[index]["enabled"] = false
			return str(operations[index].get("id", ""))
	return ""


func redo(operation_id: String) -> bool:
	return set_operation_enabled(operation_id, true)


func undo_latest_transaction() -> String:
	for index in range(operations.size() - 1, -1, -1):
		var operation: Dictionary = operations[index]
		if not bool(operation.get("enabled", true)):
			continue
		var transaction_id := str(operation.get("transaction_id", ""))
		if transaction_id.is_empty():
			operation["enabled"] = false
			return str(operation.get("id", ""))
		set_transaction_enabled(transaction_id, false)
		return transaction_id
	return ""


func serialized_journal() -> String:
	return JSON.stringify(_journal_document(false))


func compacted_serialized_journal() -> String:
	return JSON.stringify(_journal_document(true))


func _journal_document(compact: bool) -> Dictionary:
	var serialized: Array[Dictionary] = []
	for operation in operations:
		if compact and not bool(operation.get("enabled", true)):
			continue
		serialized.append(canonical_operation(operation))
	return {
		"schema": JOURNAL_SCHEMA,
		"terrain_profile": terrain_profile,
		"sample_scale_m": sample_scale_m,
		"base_height_m": base_height_m,
		"operations": serialized,
	}


func reconstruct(serialized: String) -> bool:
	var parsed: Variant = JSON.parse_string(serialized)
	if not parsed is Dictionary:
		return false
	var document: Dictionary = parsed
	var schema := str(document.get("schema", ""))
	if schema not in [JOURNAL_SCHEMA_V1, JOURNAL_SCHEMA]:
		return false
	var candidate_profile := str(document.get(
		"terrain_profile",
		"flat" if schema == JOURNAL_SCHEMA_V1 else terrain_profile
	))
	var candidate_scale := float(document.get(
		"sample_scale_m",
		DEFAULT_SAMPLE_SCALE_M if schema == JOURNAL_SCHEMA_V1 else sample_scale_m
	))
	var candidate_height := float(document.get(
		"base_height_m",
		BASE_HEIGHT_M if schema == JOURNAL_SCHEMA_V1 else base_height_m
	))
	if candidate_profile not in ["flat", "observatory", "empty", "solid"] \
			or not _float_is_finite(candidate_scale) \
			or candidate_scale <= 0.0 \
			or not _float_is_finite(candidate_height):
		return false
	var candidate_operations: Array[Dictionary] = []
	var candidate_ids := {}
	for operation_value in document.get("operations", []):
		if not operation_value is Dictionary:
			return false
		var operation := canonical_operation(operation_value)
		var operation_id := str(operation.get("id", ""))
		if not _operation_is_valid(operation) or candidate_ids.has(operation_id):
			return false
		candidate_operations.append(operation)
		candidate_ids[operation_id] = true
	operations.clear()
	_operation_ids.clear()
	_transaction_ids.clear()
	_spatial_index.clear()
	_global_operation_indices.clear()
	_spatial_reference_count = 0
	terrain_profile = candidate_profile
	sample_scale_m = candidate_scale
	base_height_m = candidate_height
	for operation in candidate_operations:
		_append_operation(operation)
	return true


func journal_signature() -> String:
	return serialized_journal().sha256_text()


func compacted_journal_signature() -> String:
	return compacted_serialized_journal().sha256_text()


func bake_probe_snapshot(points: Array[Vector3]) -> Dictionary:
	var lines: Array[String] = []
	for point in points:
		var density_value := density(point)
		lines.append("%d,%d,%d:%d:%d" % [
			roundi(point.x * 1000000.0),
			roundi(point.y * 1000000.0),
			roundi(point.z * 1000000.0),
			roundi(density_value * 1000000.0),
			material_at(point, density_value),
		])
	return {
		"schema": "world_transvoxel.terrain_lab.edit_probe_bake.v1",
		"sample_count": points.size(),
		"journal_signature": journal_signature(),
		"sample_signature": "\n".join(lines).sha256_text(),
	}


func spatial_metrics() -> Dictionary:
	var largest_bucket := 0
	for bucket_value in _spatial_index.values():
		largest_bucket = maxi(largest_bucket, (bucket_value as Array).size())
	return {
		"bucket_count": _spatial_index.size(),
		"reference_count": _spatial_reference_count,
		"largest_bucket": largest_bucket,
		"global_operation_count": _global_operation_indices.size(),
	}


static func canonical_operation(source: Dictionary) -> Dictionary:
	return {
		"id": str(source.get("id", "")),
		"mode": str(source.get("mode", "")),
		"shape": str(source.get("shape", "sphere")),
		"center": _vector_array(source.get("center", Vector3.ZERO)),
		"radius_m": float(source.get("radius_m", 1.0)),
		"half_extents": _vector_array(source.get("half_extents", Vector3.ONE)),
		"rounding_m": float(source.get("rounding_m", 0.0)),
		"segment_a": _vector_array(source.get("segment_a", Vector3.ZERO)),
		"segment_b": _vector_array(source.get("segment_b", Vector3.ZERO)),
		"normal": _vector_array(source.get("normal", Vector3.UP)),
		"depth_m": float(source.get("depth_m", 1.0)),
		"noise_amplitude_m": float(source.get("noise_amplitude_m", 0.0)),
		"noise_frequency": float(source.get("noise_frequency", 1.0)),
		"smoothing_m": float(source.get("smoothing_m", 0.0)),
		"material": int(source.get("material", DEFAULT_CONSTRUCTION_MATERIAL)),
		"enabled": bool(source.get("enabled", true)),
		"transaction_id": str(source.get("transaction_id", "")),
		"support_role": str(source.get("support_role", "none")),
		"support_anchor": bool(source.get("support_anchor", false)),
	}


static func operation_bounds(operation: Dictionary) -> AABB:
	var center := _as_vector3(operation.get("center", Vector3.ZERO))
	var radius := maxf(float(operation.get("radius_m", 1.0)), 0.000001)
	var smoothing := maxf(float(operation.get("smoothing_m", 0.0)), 0.0)
	var extent := Vector3.ONE * (radius + smoothing)
	match str(operation.get("shape", "sphere")):
		"capsule", "swept_stroke":
			var segment_a := _as_vector3(operation.get("segment_a", center))
			var segment_b := _as_vector3(operation.get("segment_b", center))
			var minimum := Vector3(
				minf(segment_a.x, segment_b.x),
				minf(segment_a.y, segment_b.y),
				minf(segment_a.z, segment_b.z)
			) - extent
			var maximum := Vector3(
				maxf(segment_a.x, segment_b.x),
				maxf(segment_a.y, segment_b.y),
				maxf(segment_a.z, segment_b.z)
			) + extent
			return AABB(minimum, maximum - minimum)
		"rounded_box":
			extent = _as_vector3(operation.get("half_extents", Vector3.ONE)).abs() \
				+ Vector3.ONE * smoothing
		"plane_stamp":
			var depth := maxf(float(operation.get("depth_m", 1.0)), 0.000001)
			extent = Vector3.ONE * (radius + depth * 0.5 + smoothing)
		"ellipsoid_stamp":
			extent = _as_vector3(operation.get("half_extents", Vector3.ONE)).abs() \
				+ Vector3.ONE * smoothing
		"bounded_noise":
			var amplitude := maxf(float(operation.get("noise_amplitude_m", 0.0)), 0.0)
			extent = Vector3.ONE * (radius + amplitude + smoothing)
	return AABB(center - extent, extent * 2.0)


static func shape_sdf(operation: Dictionary, point: Vector3) -> float:
	var center := _as_vector3(operation.get("center", Vector3.ZERO))
	var radius := maxf(float(operation.get("radius_m", 1.0)), 0.000001)
	match str(operation.get("shape", "sphere")):
		"sphere":
			return point.distance_to(center) - radius
		"capsule", "swept_stroke":
			var segment_a := _as_vector3(operation.get("segment_a", center))
			var segment_b := _as_vector3(operation.get("segment_b", center))
			return _capsule_sdf(point, segment_a, segment_b, radius)
		"rounded_box":
			var half_extents := _as_vector3(operation.get("half_extents", Vector3.ONE))
			var rounding := maxf(float(operation.get("rounding_m", 0.0)), 0.0)
			return _rounded_box_sdf(point - center, half_extents, rounding)
		"plane_stamp":
			var normal := _as_vector3(operation.get("normal", Vector3.UP)).normalized()
			var depth := maxf(float(operation.get("depth_m", 1.0)), 0.000001)
			var slab := absf((point - center).dot(normal)) - depth * 0.5
			var radial := (point - center - normal * (point - center).dot(normal)).length() - radius
			return maxf(slab, radial)
		"ellipsoid_stamp":
			var extents := _as_vector3(operation.get("half_extents", Vector3.ONE))
			return _ellipsoid_sdf(point - center, extents)
		"bounded_noise":
			var base := point.distance_to(center) - radius
			var amplitude := maxf(float(operation.get("noise_amplitude_m", 0.0)), 0.0)
			var frequency := maxf(float(operation.get("noise_frequency", 1.0)), 0.000001)
			var local := (point - center) * frequency
			var noise := sin(local.x * 1.17 + 0.31) \
				* sin(local.y * 1.73 - 0.19) \
				* sin(local.z * 1.41 + 0.73)
			return base + noise * amplitude
	return INF


static func smooth_min(a: float, b: float, width: float) -> float:
	if width <= 0.0:
		return minf(a, b)
	var h := clampf(0.5 + 0.5 * (b - a) / width, 0.0, 1.0)
	return lerpf(b, a, h) - width * h * (1.0 - h)


static func smooth_max(a: float, b: float, width: float) -> float:
	return -smooth_min(-a, -b, width)


static func _capsule_sdf(
	point: Vector3,
	segment_a: Vector3,
	segment_b: Vector3,
	radius: float
) -> float:
	var segment := segment_b - segment_a
	var length_squared := segment.length_squared()
	if length_squared <= 0.0000001:
		return point.distance_to(segment_a) - radius
	var t := clampf((point - segment_a).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(segment_a + segment * t) - radius


static func _rounded_box_sdf(
	point: Vector3,
	half_extents: Vector3,
	rounding: float
) -> float:
	var q := point.abs() - (half_extents - Vector3.ONE * rounding)
	return Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length() \
		+ minf(maxf(q.x, maxf(q.y, q.z)), 0.0) - rounding


static func _ellipsoid_sdf(point: Vector3, radii: Vector3) -> float:
	var safe := Vector3(
		maxf(absf(radii.x), 0.000001),
		maxf(absf(radii.y), 0.000001),
		maxf(absf(radii.z), 0.000001)
	)
	var normalized := Vector3(point.x / safe.x, point.y / safe.y, point.z / safe.z)
	return (normalized.length() - 1.0) * minf(safe.x, minf(safe.y, safe.z))


static func _vector_array(value: Variant) -> Array[float]:
	var vector := _as_vector3(value)
	return [vector.x, vector.y, vector.z]


static func _as_vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Vector3i:
		return Vector3(value)
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


func _append_operation(operation: Dictionary) -> void:
	var index := operations.size()
	operations.append(operation)
	_operation_ids[str(operation.get("id", ""))] = index
	var transaction_id := str(operation.get("transaction_id", ""))
	if not transaction_id.is_empty():
		if not _transaction_ids.has(transaction_id):
			_transaction_ids[transaction_id] = []
		(_transaction_ids[transaction_id] as Array).append(index)
	_index_operation(index, operation_bounds(operation))


func _index_operation(operation_index: int, bounds: AABB) -> void:
	var minimum := Vector3i(
		floori(bounds.position.x / SPATIAL_BUCKET_SIZE_M),
		floori(bounds.position.y / SPATIAL_BUCKET_SIZE_M),
		floori(bounds.position.z / SPATIAL_BUCKET_SIZE_M)
	)
	var end := bounds.position + bounds.size
	var maximum := Vector3i(
		floori(end.x / SPATIAL_BUCKET_SIZE_M),
		floori(end.y / SPATIAL_BUCKET_SIZE_M),
		floori(end.z / SPATIAL_BUCKET_SIZE_M)
	)
	var reference_count := (maximum.x - minimum.x + 1) \
		* (maximum.y - minimum.y + 1) \
		* (maximum.z - minimum.z + 1)
	if reference_count > MAX_BUCKET_REFERENCES_PER_OPERATION:
		_global_operation_indices.append(operation_index)
		return
	for x in range(minimum.x, maximum.x + 1):
		for y in range(minimum.y, maximum.y + 1):
			for z in range(minimum.z, maximum.z + 1):
				var key := Vector3i(x, y, z)
				if not _spatial_index.has(key):
					_spatial_index[key] = []
				(_spatial_index[key] as Array).append(operation_index)
				_spatial_reference_count += 1


func _candidate_indices(point: Vector3) -> Array:
	var key := Vector3i(
		floori(point.x / SPATIAL_BUCKET_SIZE_M),
		floori(point.y / SPATIAL_BUCKET_SIZE_M),
		floori(point.z / SPATIAL_BUCKET_SIZE_M)
	)
	var result: Array = (_spatial_index.get(key, []) as Array).duplicate()
	result.append_array(_global_operation_indices)
	return result


static func _operation_is_valid(operation: Dictionary) -> bool:
	if str(operation.get("id", "")).is_empty():
		return false
	if str(operation.get("mode", "")) not in ["dig", "construct"]:
		return false
	var shape := str(operation.get("shape", ""))
	if shape not in [
		"sphere",
		"capsule",
		"swept_stroke",
		"rounded_box",
		"plane_stamp",
		"ellipsoid_stamp",
		"bounded_noise",
	]:
		return false
	for numeric_key in [
		"radius_m",
		"rounding_m",
		"depth_m",
		"noise_amplitude_m",
		"noise_frequency",
		"smoothing_m",
	]:
		if not _float_is_finite(float(operation.get(numeric_key, 0.0))):
			return false
	for vector_key in ["center", "half_extents", "segment_a", "segment_b", "normal"]:
		if not _as_vector3(operation.get(vector_key, Vector3.ZERO)).is_finite():
			return false
	if float(operation.get("radius_m", 0.0)) <= 0.0:
		return false
	if float(operation.get("smoothing_m", 0.0)) < 0.0:
		return false
	if shape in ["rounded_box", "ellipsoid_stamp"]:
		var extents := _as_vector3(operation.get("half_extents", Vector3.ZERO)).abs()
		if minf(extents.x, minf(extents.y, extents.z)) <= 0.0:
			return false
		if shape == "rounded_box" and float(operation.get("rounding_m", 0.0)) \
				> minf(extents.x, minf(extents.y, extents.z)):
			return false
	if shape == "plane_stamp" \
			and _as_vector3(operation.get("normal", Vector3.ZERO)).length_squared() \
				<= 0.0000001:
		return false
	if shape == "bounded_noise":
		var amplitude := float(operation.get("noise_amplitude_m", 0.0))
		if amplitude < 0.0 or amplitude > float(operation.get("radius_m", 0.0)):
			return false
		if float(operation.get("noise_frequency", 0.0)) <= 0.0:
			return false
	return true


static func _float_is_finite(value: float) -> bool:
	return value == value and absf(value) < INF
