@tool
extends RefCounted
class_name WtTerrainLabNativeField

const ISO_VALUE := 0.0
const SAMPLE_SCALE_M := 0.5
const CHUNK_CELLS_PER_AXIS := 16

const FIXTURE_KINDS := [
	"slope",
	"ridge_valley",
	"cliff",
	"cave",
	"tunnel",
	"arch",
	"overhang",
	"pillar",
	"saddle",
	"thin_layer",
	"high_curvature",
	"mixed_material",
	"exact_isovalue",
	"large_coordinate",
]

var fixture_id := ""
var kind := ""
var seed := 0
var chunk_base := Vector3i.ZERO
var window_chunks := Vector3i(2, 2, 2)
var origin_grid := Vector3i(16, 16, 16)


func configure(definition: Dictionary) -> bool:
	var candidate_kind := str(definition.get("kind", ""))
	var candidate_window := _vector3i(definition.get("window_chunks", [2, 2, 2]))
	if candidate_kind not in FIXTURE_KINDS or candidate_window.x <= 0 \
			or candidate_window.y <= 0 or candidate_window.z <= 0:
		return false
	fixture_id = str(definition.get("id", candidate_kind))
	kind = candidate_kind
	seed = int(definition.get("seed", 0))
	chunk_base = _vector3i(definition.get("chunk_base", [0, 0, 0]))
	window_chunks = candidate_window
	origin_grid = chunk_base * CHUNK_CELLS_PER_AXIS + Vector3i(
		window_chunks.x * CHUNK_CELLS_PER_AXIS / 2,
		window_chunks.y * CHUNK_CELLS_PER_AXIS / 2,
		window_chunks.z * CHUNK_CELLS_PER_AXIS / 2
	)
	return true


func sample(point: Vector3i) -> Dictionary:
	var local_point := Vector3(point - origin_grid) * SAMPLE_SCALE_M
	var density_value := density_local(local_point)
	return {
		"density": density_value,
		"material": material_local(local_point, density_value),
		"material_authored": density_value < ISO_VALUE,
	}


func density_grid(point: Vector3i) -> float:
	return density_local(Vector3(point - origin_grid) * SAMPLE_SCALE_M)


func material_grid(point: Vector3i) -> int:
	var local_point := Vector3(point - origin_grid) * SAMPLE_SCALE_M
	var density_value := density_local(local_point)
	return material_local(local_point, density_value)


func gradient_grid(point: Vector3i) -> Vector3:
	return gradient_local(Vector3(point - origin_grid) * SAMPLE_SCALE_M)


func density_local(point: Vector3) -> float:
	match kind:
		"slope", "large_coordinate":
			return point.y - (0.25 * point.x - 0.125 * point.z)
		"ridge_valley":
			var phase := float(posmod(seed, 4096)) * 0.001953125
			var height := 1.8 * sin(point.x * 0.55 + phase) \
				+ 1.25 * cos(point.z * 0.42 - phase * 0.5) \
				+ 0.55 * sin((point.x + point.z) * 0.31 + phase * 0.25)
			return point.y - height
		"cliff":
			var cliff_face := point.x - 0.35 * sin(point.z * 0.65)
			return maxf(point.y - 3.5, cliff_face)
		"cave":
			return maxf(point.y - 5.0, -(point.length() - 4.25))
		"tunnel":
			var tunnel := Vector2(point.x, point.y).length() - 2.5
			return maxf(point.y - 5.0, -tunnel)
		"arch":
			var left_pillar := _box_sdf(point - Vector3(-4.0, -1.0, 0.0), Vector3(1.4, 4.5, 1.8))
			var right_pillar := _box_sdf(point - Vector3(4.0, -1.0, 0.0), Vector3(1.4, 4.5, 1.8))
			var beam := _box_sdf(point - Vector3(0.0, 3.7, 0.0), Vector3(5.4, 1.0, 1.8))
			return minf(minf(left_pillar, right_pillar), beam)
		"overhang":
			var ground := point.y + 4.5
			var shelf := _ellipsoid_sdf(point - Vector3(1.5, 1.0, 0.0), Vector3(6.0, 1.5, 4.0))
			var support := _box_sdf(point - Vector3(-3.5, -1.5, 0.0), Vector3(1.2, 3.2, 2.2))
			return minf(ground, minf(shelf, support))
		"pillar":
			return maxf(Vector2(point.x, point.z).length() - 2.5, absf(point.y) - 6.0)
		"saddle":
			return point.y - 0.08 * (point.x * point.x - point.z * point.z)
		"thin_layer":
			return absf(point.length() - 5.0) - 0.5
		"high_curvature":
			var torus_plane := Vector2(Vector2(point.x, point.z).length() - 4.25, point.y)
			return torus_plane.length() - 1.35
		"mixed_material", "exact_isovalue":
			return point.length() - (5.25 if kind == "mixed_material" else 4.0)
	return 1000000.0


func material_local(point: Vector3, density_value: float) -> int:
	if density_value >= ISO_VALUE:
		return 0
	if kind != "mixed_material":
		return 1
	if point.y > 1.0:
		return 3
	return 2 if point.x >= 0.0 else 1


func gradient_local(point: Vector3, epsilon_m: float = 0.001) -> Vector3:
	var epsilon := maxf(epsilon_m, 0.000001)
	var dx := density_local(point + Vector3(epsilon, 0.0, 0.0)) \
		- density_local(point - Vector3(epsilon, 0.0, 0.0))
	var dy := density_local(point + Vector3(0.0, epsilon, 0.0)) \
		- density_local(point - Vector3(0.0, epsilon, 0.0))
	var dz := density_local(point + Vector3(0.0, 0.0, epsilon)) \
		- density_local(point - Vector3(0.0, 0.0, epsilon))
	return Vector3(dx, dy, dz).normalized()


static func interpolation_fraction(a: float, b: float, isovalue: float = ISO_VALUE) -> float:
	if is_equal_approx(a, b):
		return 0.5
	return clampf((isovalue - a) / (b - a), 0.0, 1.0)


func definition_signature() -> String:
	return JSON.stringify({
		"fixture_id": fixture_id,
		"kind": kind,
		"seed": seed,
		"chunk_base": chunk_base,
		"window_chunks": window_chunks,
		"origin_grid": origin_grid,
		"sample_scale_m": SAMPLE_SCALE_M,
		"isovalue": ISO_VALUE,
	}).sha256_text()


static func _box_sdf(point: Vector3, half_extents: Vector3) -> float:
	var q := point.abs() - half_extents
	return q.max(Vector3.ZERO).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)


static func _ellipsoid_sdf(point: Vector3, radii: Vector3) -> float:
	var normalized := Vector3(point.x / radii.x, point.y / radii.y, point.z / radii.z)
	return (normalized.length() - 1.0) * minf(radii.x, minf(radii.y, radii.z))


static func _vector3i(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() == 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i.ZERO
