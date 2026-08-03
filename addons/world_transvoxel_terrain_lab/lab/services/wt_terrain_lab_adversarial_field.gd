@tool
extends RefCounted
class_name WtTerrainLabAdversarialField

const CHUNK_CELLS_PER_AXIS := 16
const AIR_DENSITY := 1000000.0
const DENSITY_SCALE := 0.25
const PROFILES := [
	"closed_wave",
	"closed_blob",
	"exact_isovalue",
	"transition_surface",
]

var fixture_id := ""
var profile := ""
var seed := 0
var chunk_base := Vector3i.ZERO
var window_chunks := Vector3i(2, 2, 2)
var lod := 0
var coarse_coordinate := Vector3i.ZERO
var coarse_lod := 1
var material_palette: Array[int] = [1]

var _domain_min := Vector3i.ZERO
var _domain_max := Vector3i.ONE
var _center := Vector3.ZERO
var _half_extent := Vector3.ONE
var _phase_x := 0.0
var _phase_z := 0.0
var _amplitude_x := 1.0
var _amplitude_z := 1.0
var _frequency_x := 0.1
var _frequency_z := 0.1
var _blob_radii := Vector3.ONE
var _exact_offset := 0
var _sample_call_count := 0
var _exact_isovalue_hit_count := 0
var _observed_materials := {}


func configure(definition: Dictionary) -> bool:
	var candidate_profile := str(definition.get("field_profile", ""))
	var candidate_window := _vector3i(definition.get("window_chunks", [2, 2, 2]))
	var candidate_lod := int(definition.get("lod", 0))
	var candidate_coarse_lod := int(definition.get("coarse_lod", 1))
	if candidate_profile not in PROFILES \
			or candidate_window.x <= 0 or candidate_window.y <= 0 \
			or candidate_window.z <= 0 or candidate_lod < 0 or candidate_lod > 3 \
			or candidate_coarse_lod < 1 or candidate_coarse_lod > 3:
		return false
	fixture_id = str(definition.get("id", candidate_profile))
	profile = candidate_profile
	seed = int(definition.get("seed", 1))
	chunk_base = _vector3i(definition.get("chunk_base", [0, 0, 0]))
	window_chunks = candidate_window
	lod = candidate_lod
	coarse_coordinate = _vector3i(definition.get("coarse_coordinate", [0, 0, 0]))
	coarse_lod = candidate_coarse_lod
	material_palette.clear()
	for value in definition.get("material_palette", [1]):
		var material_id := int(value)
		if material_id > 0 and material_id not in material_palette:
			material_palette.append(material_id)
	if material_palette.is_empty():
		return false
	var extent := CHUNK_CELLS_PER_AXIS * (1 << lod)
	_domain_min = chunk_base * extent
	_domain_max = (chunk_base + window_chunks) * extent
	if profile == "transition_surface":
		var coarse_extent := CHUNK_CELLS_PER_AXIS * (1 << coarse_lod)
		_domain_min = coarse_coordinate * coarse_extent
		_domain_max = _domain_min + Vector3i.ONE * coarse_extent
	_center = (Vector3(_domain_min) + Vector3(_domain_max)) * 0.5
	_half_extent = (Vector3(_domain_max) - Vector3(_domain_min)) * 0.5
	var state := seed & 0x7fffffff
	state = _next_state(state)
	_phase_x = _unit(state) * TAU
	state = _next_state(state)
	_phase_z = _unit(state) * TAU
	state = _next_state(state)
	_amplitude_x = 0.65 + _unit(state) * 1.85
	state = _next_state(state)
	_amplitude_z = 0.55 + _unit(state) * 1.65
	state = _next_state(state)
	_frequency_x = 0.055 + _unit(state) * 0.16
	state = _next_state(state)
	_frequency_z = 0.06 + _unit(state) * 0.15
	state = _next_state(state)
	_blob_radii = _half_extent * Vector3(
		0.48 + _unit(state) * 0.22,
		0.45 + _unit(_next_state(state)) * 0.25,
		0.47 + _unit(_next_state(_next_state(state))) * 0.23
	)
	_exact_offset = int(definition.get("exact_offset", posmod(seed, 5) - 2))
	_sample_call_count = 0
	_exact_isovalue_hit_count = 0
	_observed_materials.clear()
	return true


func sample(point: Vector3i) -> Dictionary:
	_sample_call_count += 1
	var density_value := density_grid(point)
	if is_zero_approx(density_value):
		_exact_isovalue_hit_count += 1
	var material_id := 0
	if density_value < 0.0:
		var region := floori(float(point.x) / 8.0) \
			+ 3 * floori(float(point.y) / 8.0) \
			+ 5 * floori(float(point.z) / 8.0) + seed
		material_id = material_palette[posmod(region, material_palette.size())]
		_observed_materials[material_id] = true
	return {
		"density": density_value,
		"material": material_id,
		"material_authored": density_value < 0.0,
	}


func density_grid(point: Vector3i) -> float:
	var local := Vector3(point) - _center
	match profile:
		"closed_wave":
			var surface_y := (
				_amplitude_x * sin(local.x * _frequency_x + _phase_x)
				+ _amplitude_z * cos(local.z * _frequency_z + _phase_z)
			)
			var terrain := local.y - surface_y
			var inset := 1.75 * float(1 << lod)
			return maxf(
				terrain,
				_box_sdf(local, _half_extent - Vector3.ONE * inset)
			) * DENSITY_SCALE
		"closed_blob":
			var normalized := Vector3(
				local.x / maxf(_blob_radii.x, 0.001),
				local.y / maxf(_blob_radii.y, 0.001),
				local.z / maxf(_blob_radii.z, 0.001)
			)
			var perturbation := 0.18 * sin(local.x * _frequency_x + _phase_x) \
				* cos(local.z * _frequency_z + _phase_z)
			return (normalized.length() - 1.0 + perturbation) \
				* minf(_blob_radii.x, minf(_blob_radii.y, _blob_radii.z)) \
				* DENSITY_SCALE
		"exact_isovalue":
			return float(point.x + 2 * point.y - point.z - _exact_offset) \
				* DENSITY_SCALE
		"transition_surface":
			return (local.x + 0.73 * local.y - 0.41 * local.z \
				+ _amplitude_x * sin((local.x + local.z) * _frequency_x + _phase_x) \
				+ _amplitude_z * cos((local.y - local.z) * _frequency_z + _phase_z)) \
				* DENSITY_SCALE
	return AIR_DENSITY


func audit() -> Dictionary:
	var materials: Array = _observed_materials.keys()
	materials.sort()
	return {
		"sample_call_count": _sample_call_count,
		"exact_isovalue_hit_count": _exact_isovalue_hit_count,
		"observed_material_ids": materials,
		"derived_parameters": {
			"phase_x": _phase_x,
			"phase_z": _phase_z,
			"amplitude_x": _amplitude_x,
			"amplitude_z": _amplitude_z,
			"frequency_x": _frequency_x,
			"frequency_z": _frequency_z,
			"blob_radii": [_blob_radii.x, _blob_radii.y, _blob_radii.z],
			"exact_offset": _exact_offset,
		},
	}


func definition_signature() -> String:
	return JSON.stringify({
		"fixture_id": fixture_id,
		"profile": profile,
		"seed": seed,
		"chunk_base": chunk_base,
		"window_chunks": window_chunks,
		"lod": lod,
		"coarse_coordinate": coarse_coordinate,
		"coarse_lod": coarse_lod,
		"material_palette": material_palette,
		"derived": audit().get("derived_parameters", {}),
		"density_scale": DENSITY_SCALE,
	}).sha256_text()


static func _next_state(state: int) -> int:
	return (1103515245 * state + 12345) & 0x7fffffff


static func _unit(state: int) -> float:
	return float(state & 0x7fffffff) / 2147483647.0


static func _box_sdf(point: Vector3, half_extents: Vector3) -> float:
	var q := point.abs() - half_extents
	return q.max(Vector3.ZERO).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)


static func _vector3i(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() == 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i.ZERO
