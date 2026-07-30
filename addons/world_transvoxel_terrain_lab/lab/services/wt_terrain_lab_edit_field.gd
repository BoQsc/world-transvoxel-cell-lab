@tool
extends RefCounted
class_name WtTerrainLabEditField

const ISO_VALUE := 0.0
const BASE_MATERIAL := 1
const DEFAULT_CONSTRUCTION_MATERIAL := 5
const BASE_HEIGHT_M := 12.0

var operations: Array[Dictionary] = []
var terrain_profile := "flat"
var _operation_ids := {}


func sample(point: Vector3i) -> Dictionary:
	return sample_point(Vector3(point))


func sample_point(point: Vector3) -> Dictionary:
	var density_value := density(point)
	return {
		"density": density_value,
		"material": material_at(point, density_value),
		"material_authored": density_value < ISO_VALUE,
	}


func density(point: Vector3) -> float:
	var value := base_density(point)
	for operation in operations:
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
	if terrain_profile == "observatory":
		var height := 8.5 \
			+ 2.8 * sin(point.x * 0.055) \
			+ 2.0 * cos(point.z * 0.072) \
			+ 0.9 * sin((point.x + point.z) * 0.11)
		return point.y - height
	return point.y - BASE_HEIGHT_M


func material_at(point: Vector3, density_value: float) -> int:
	if density_value >= ISO_VALUE:
		return 0
	var material := BASE_MATERIAL
	for operation in operations:
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
	if operation_id.is_empty() or _operation_ids.has(operation_id):
		return false
	if str(operation.get("mode", "")) not in ["dig", "construct"]:
		return false
	if str(operation.get("shape", "")) not in [
		"sphere",
		"capsule",
		"swept_stroke",
		"rounded_box",
		"plane_stamp",
		"ellipsoid_stamp",
		"bounded_noise",
	]:
		return false
	operations.append(operation)
	_operation_ids[operation_id] = operations.size() - 1
	return true


func set_operation_enabled(operation_id: String, enabled: bool) -> bool:
	if not _operation_ids.has(operation_id):
		return false
	var index := int(_operation_ids[operation_id])
	operations[index]["enabled"] = enabled
	return true


func undo_latest() -> String:
	for index in range(operations.size() - 1, -1, -1):
		if bool(operations[index].get("enabled", true)):
			operations[index]["enabled"] = false
			return str(operations[index].get("id", ""))
	return ""


func redo(operation_id: String) -> bool:
	return set_operation_enabled(operation_id, true)


func serialized_journal() -> String:
	var serialized: Array[Dictionary] = []
	for operation in operations:
		serialized.append(canonical_operation(operation))
	return JSON.stringify({
		"schema": "world_transvoxel.terrain_lab.edit_journal.v1",
		"operations": serialized,
	})


func reconstruct(serialized: String) -> bool:
	var parsed: Variant = JSON.parse_string(serialized)
	if not parsed is Dictionary:
		return false
	var document: Dictionary = parsed
	if str(document.get("schema", "")) != "world_transvoxel.terrain_lab.edit_journal.v1":
		return false
	operations.clear()
	_operation_ids.clear()
	for operation_value in document.get("operations", []):
		if not operation_value is Dictionary or not add_operation(operation_value):
			operations.clear()
			_operation_ids.clear()
			return false
	return true


func journal_signature() -> String:
	return serialized_journal().sha256_text()


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
	}


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
