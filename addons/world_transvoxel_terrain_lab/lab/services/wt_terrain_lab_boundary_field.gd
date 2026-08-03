@tool
extends RefCounted
class_name WtTerrainLabBoundaryField

const CHUNK_CELLS_PER_AXIS := 16
const SAMPLE_SCALE_M := 0.5
const OUTSIDE_AIR_DENSITY := 1000000.0

const FIELD_KINDS := [
	"closed_volume",
	"closed_terrain",
	"open_terrain",
	"residency_interface",
]

var fixture_id := ""
var kind := ""
var chunk_base := Vector3i.ZERO
var window_chunks := Vector3i(2, 2, 2)
var lod := 0
var enclosure_inset_samples := 1.75
var residency_coupled_sampling := false
var resident_chunks: Array[Vector3i] = []

var _audit_initialized := false
var _sample_min := Vector3i.ZERO
var _sample_max := Vector3i.ZERO
var _sample_call_count := 0
var _outside_sample_count := 0
var _outside_face_counts := {
	"negative_x": 0,
	"positive_x": 0,
	"negative_y": 0,
	"positive_y": 0,
	"negative_z": 0,
	"positive_z": 0,
}


func configure(definition: Dictionary) -> bool:
	var candidate_kind := str(definition.get("kind", ""))
	var candidate_window := _vector3i(definition.get("window_chunks", [2, 2, 2]))
	var candidate_inset := float(definition.get("enclosure_inset_samples", 1.75))
	var candidate_lod := int(definition.get("lod", 0))
	if candidate_kind not in FIELD_KINDS \
			or candidate_window.x <= 0 or candidate_window.y <= 0 \
			or candidate_window.z <= 0 or candidate_lod < 0 or candidate_lod > 7 \
			or candidate_inset <= float(1 << candidate_lod):
		return false
	fixture_id = str(definition.get("id", candidate_kind))
	kind = candidate_kind
	chunk_base = _vector3i(definition.get("chunk_base", [0, 0, 0]))
	window_chunks = candidate_window
	lod = candidate_lod
	enclosure_inset_samples = candidate_inset
	residency_coupled_sampling = bool(
		definition.get("residency_coupled_sampling", false)
	)
	resident_chunks.clear()
	reset_sample_audit()
	return true


func sample(point: Vector3i) -> Dictionary:
	_record_sample(point)
	if residency_coupled_sampling and not _sample_has_resident_owner(point):
		return {
			"density": OUTSIDE_AIR_DENSITY,
			"material": 0,
			"material_authored": false,
		}
	var density_value := density_grid(point)
	return {
		"density": density_value,
		"material": 1 if density_value < 0.0 else 0,
		"material_authored": density_value < 0.0,
	}


func density_grid(point: Vector3i) -> float:
	var chunk_extent := CHUNK_CELLS_PER_AXIS * (1 << lod)
	var domain_min := Vector3(chunk_base * chunk_extent)
	var domain_max := Vector3(
		(chunk_base + window_chunks) * chunk_extent
	)
	var center := (domain_min + domain_max) * 0.5
	var local := Vector3(point) - center
	var box_half_extent := (domain_max - domain_min) * 0.5 \
		- Vector3.ONE * enclosure_inset_samples
	match kind:
		"closed_volume":
			return _box_sdf(local, box_half_extent)
		"closed_terrain":
			var surface_y := center.y + 3.0 \
				+ 1.1 * sin(local.x * 0.19) + 0.8 * cos(local.z * 0.23)
			return maxf(Vector3(point).y - surface_y, _box_sdf(local, box_half_extent))
		"open_terrain":
			var open_surface_y := center.y \
				+ 1.25 * sin(local.x * 0.17) + 0.75 * cos(local.z * 0.21)
			return Vector3(point).y - open_surface_y
		"residency_interface":
			var interface_surface_y := center.y - 2.0 \
				+ 0.35 * local.x - 0.16 * local.z
			return Vector3(point).y - interface_surface_y
	return OUTSIDE_AIR_DENSITY


func set_resident_chunks(chunks: Array) -> void:
	resident_chunks.clear()
	for value in chunks:
		var coordinate := _vector3i(value)
		if coordinate not in resident_chunks:
			resident_chunks.append(coordinate)


func reset_sample_audit() -> void:
	_audit_initialized = false
	_sample_min = Vector3i.ZERO
	_sample_max = Vector3i.ZERO
	_sample_call_count = 0
	_outside_sample_count = 0
	for face in _outside_face_counts:
		_outside_face_counts[face] = 0


func sample_audit() -> Dictionary:
	return {
		"sample_call_count": _sample_call_count,
		"sample_min": _sample_min,
		"sample_max": _sample_max,
		"outside_sample_count": _outside_sample_count,
		"outside_face_counts": _outside_face_counts.duplicate(true),
		"declared_domain_min": chunk_base * CHUNK_CELLS_PER_AXIS * (1 << lod),
		"declared_domain_max": (chunk_base + window_chunks) \
			* CHUNK_CELLS_PER_AXIS * (1 << lod),
	}


func definition_signature() -> String:
	return JSON.stringify({
		"fixture_id": fixture_id,
		"kind": kind,
		"chunk_base": chunk_base,
		"window_chunks": window_chunks,
		"lod": lod,
		"enclosure_inset_samples": enclosure_inset_samples,
		"residency_coupled_sampling": residency_coupled_sampling,
		"sample_scale_m": SAMPLE_SCALE_M,
	}).sha256_text()


static func validate_world_catalog(
	entries: Array,
	catalog_min: Vector3i,
	catalog_size: Vector3i,
	capacity: int
) -> Dictionary:
	var failures: Array[String] = []
	var seen := {}
	var expected_count := catalog_size.x * catalog_size.y * catalog_size.z
	if catalog_size.x <= 0 or catalog_size.y <= 0 or catalog_size.z <= 0:
		failures.append("catalog size must be positive")
	if capacity <= 0 or entries.size() > capacity:
		failures.append("catalog capacity exceeded")
	for entry_value in entries:
		if not entry_value is Dictionary:
			failures.append("catalog entry is not an object")
			continue
		var entry: Dictionary = entry_value
		if not _valid_catalog_entry_shape(entry):
			failures.append("catalog entry has an invalid coordinate or LOD type")
			continue
		var coordinate := _vector3i(entry.get("coordinate", []))
		var lod := int(entry.get("lod", -1))
		var key := _coordinate_key(coordinate, lod)
		if lod != 0:
			failures.append("catalog entry has unsupported LOD")
		if not _inside_catalog(coordinate, catalog_min, catalog_size):
			failures.append("catalog entry is outside the finite world")
		if seen.has(key):
			failures.append("catalog contains a duplicate chunk")
		seen[key] = true
	if entries.size() != expected_count:
		failures.append("catalog does not exactly own the finite world")
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"entry_count": entries.size(),
		"expected_entry_count": expected_count,
		"capacity": capacity,
		"failures": failures,
	}


static func validate_residency_set(
	resident: Array,
	world_catalog: Array,
	capacity: int
) -> Dictionary:
	var failures: Array[String] = []
	var catalog_keys := {}
	var resident_keys := {}
	for entry_value in world_catalog:
		if not entry_value is Dictionary:
			failures.append("world catalog entry is not an object")
			continue
		var entry: Dictionary = entry_value
		if not _valid_catalog_entry_shape(entry):
			failures.append("world catalog entry has an invalid coordinate or LOD type")
			continue
		var coordinate := _vector3i(entry.get("coordinate", []))
		catalog_keys[_coordinate_key(coordinate, int(entry.get("lod", -1)))] = true
	if capacity <= 0 or resident.size() > capacity:
		failures.append("resident capacity exceeded")
	for entry_value in resident:
		if not entry_value is Dictionary:
			failures.append("resident entry is not an object")
			continue
		var entry: Dictionary = entry_value
		if not _valid_catalog_entry_shape(entry):
			failures.append("resident entry has an invalid coordinate or LOD type")
			continue
		var coordinate := _vector3i(entry.get("coordinate", []))
		var key := _coordinate_key(coordinate, int(entry.get("lod", -1)))
		if not catalog_keys.has(key):
			failures.append("resident entry is absent from the world catalog")
		if resident_keys.has(key):
			failures.append("resident set contains a duplicate chunk")
		resident_keys[key] = true
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"resident_count": resident.size(),
		"capacity": capacity,
		"failures": failures,
	}


func _record_sample(point: Vector3i) -> void:
	_sample_call_count += 1
	if not _audit_initialized:
		_sample_min = point
		_sample_max = point
		_audit_initialized = true
	else:
		_sample_min = _sample_min.min(point)
		_sample_max = _sample_max.max(point)
	var chunk_extent := CHUNK_CELLS_PER_AXIS * (1 << lod)
	var domain_min := chunk_base * chunk_extent
	var domain_max := (chunk_base + window_chunks) * chunk_extent
	var outside := false
	if point.x < domain_min.x:
		_outside_face_counts["negative_x"] += 1
		outside = true
	if point.x > domain_max.x:
		_outside_face_counts["positive_x"] += 1
		outside = true
	if point.y < domain_min.y:
		_outside_face_counts["negative_y"] += 1
		outside = true
	if point.y > domain_max.y:
		_outside_face_counts["positive_y"] += 1
		outside = true
	if point.z < domain_min.z:
		_outside_face_counts["negative_z"] += 1
		outside = true
	if point.z > domain_max.z:
		_outside_face_counts["positive_z"] += 1
		outside = true
	if outside:
		_outside_sample_count += 1


func _sample_has_resident_owner(point: Vector3i) -> bool:
	for coordinate in resident_chunks:
		var chunk_extent := CHUNK_CELLS_PER_AXIS * (1 << lod)
		var minimum := coordinate * chunk_extent
		var maximum := minimum + Vector3i.ONE * chunk_extent
		# This ownership rule exists only for the injected bad source. It models
		# page-local half-open samples that lose a shared boundary when a neighbor
		# is absent; qualified fields never consult residency while sampling.
		if point.x >= minimum.x and point.x < maximum.x \
				and point.y >= minimum.y and point.y < maximum.y \
				and point.z >= minimum.z and point.z < maximum.z:
			return true
	return false


static func _inside_catalog(
	coordinate: Vector3i,
	catalog_min: Vector3i,
	catalog_size: Vector3i
) -> bool:
	var catalog_max := catalog_min + catalog_size
	return coordinate.x >= catalog_min.x and coordinate.x < catalog_max.x \
		and coordinate.y >= catalog_min.y and coordinate.y < catalog_max.y \
		and coordinate.z >= catalog_min.z and coordinate.z < catalog_max.z


static func _coordinate_key(coordinate: Vector3i, lod: int) -> String:
	return "%d,%d,%d@%d" % [coordinate.x, coordinate.y, coordinate.z, lod]


static func _valid_catalog_entry_shape(entry: Dictionary) -> bool:
	if not entry.has("coordinate") or typeof(entry.get("lod")) != TYPE_INT:
		return false
	var coordinate: Variant = entry.get("coordinate")
	if coordinate is Vector3i:
		return true
	if not coordinate is Array or coordinate.size() != 3:
		return false
	for component in coordinate:
		if typeof(component) != TYPE_INT:
			return false
	return true


static func _box_sdf(point: Vector3, half_extents: Vector3) -> float:
	var q := point.abs() - half_extents
	return q.max(Vector3.ZERO).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)


static func _vector3i(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Vector3 and (value as Vector3).round() == value:
		return Vector3i(value)
	if value is Array and value.size() == 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i(2147483647, 2147483647, 2147483647)
