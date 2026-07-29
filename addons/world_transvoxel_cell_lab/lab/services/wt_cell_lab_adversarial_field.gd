@tool
extends RefCounted
class_name WtCellLabAdversarialField

const PROFILE_IDS := [
	"diagonal_plane",
	"offset_sphere",
	"saddle",
	"gyroid",
	"high_curvature",
	"resolved_thin_layer",
	"resolved_tunnel",
	"near_cancellation",
	"seeded_warp_17",
	"seeded_warp_29",
]

var profile_id := PROFILE_IDS[0]


func configure(value: String) -> void:
	if value in PROFILE_IDS:
		profile_id = value


func sample(point: Vector3i) -> Dictionary:
	var density_value := density_at(Vector3(point))
	var profile_index := maxi(PROFILE_IDS.find(profile_id), 0)
	return {
		"density": density_value,
		"material": 0 if density_value >= 0.0 else 1 + profile_index % 6,
		"material_authored": density_value < 0.0,
	}


func density_at(point: Vector3) -> float:
	match profile_id:
		"diagonal_plane":
			return point.y - 8.371 + point.x * 0.173 - point.z * 0.119
		"offset_sphere":
			return point.distance_to(Vector3(8.37, 8.61, 7.83)) - 5.17
		"saddle":
			return point.y - (
				8.421
				+ 0.052 * (point.x - 8.0) * (point.z - 8.0)
				+ 0.17 * sin(point.x * 0.61)
			)
		"gyroid":
			var q := (point - Vector3(8.13, 7.91, 8.27)) * 0.43
			return (
				sin(q.x) * cos(q.y)
				+ sin(q.y) * cos(q.z)
				+ sin(q.z) * cos(q.x)
				- 0.17
			)
		"high_curvature":
			var first := point.distance_to(Vector3(5.73, 8.19, 8.41)) - 3.11
			var second := point.distance_to(Vector3(10.67, 8.53, 7.79)) - 3.07
			return minf(first, second)
		"resolved_thin_layer":
			return absf(
				point.y - 8.37 - 0.13 * sin(point.x * 0.47 + point.z * 0.31)
			) - 1.21
		"resolved_tunnel":
			var ground := point.y - (
				11.31 + 0.31 * sin(point.x * 0.33) + 0.27 * cos(point.z * 0.29)
			)
			var tunnel := 2.43 - Vector2(
				point.y - 6.17,
				point.z - 8.29
			).length()
			return maxf(ground, tunnel)
		"near_cancellation":
			return (
				(point.y - 8.371 + point.x * 0.071 - point.z * 0.053)
				* 0.000013
				+ sin(point.x * 0.73 + point.z * 0.41) * 0.0000021
			)
		"seeded_warp_17":
			return _seeded_warp(point, 17)
		"seeded_warp_29":
			return _seeded_warp(point, 29)
	return point.y - 8.371


func gradient_at(point: Vector3, step: float = 0.25) -> Vector3:
	var gradient := Vector3(
		density_at(point + Vector3(step, 0.0, 0.0))
			- density_at(point - Vector3(step, 0.0, 0.0)),
		density_at(point + Vector3(0.0, step, 0.0))
			- density_at(point - Vector3(0.0, step, 0.0)),
		density_at(point + Vector3(0.0, 0.0, step))
			- density_at(point - Vector3(0.0, 0.0, step))
	)
	return gradient.normalized() if gradient.length_squared() > 0.000000000001 else Vector3.UP


func _seeded_warp(point: Vector3, seed: int) -> float:
	var seed_value := float(seed)
	var height := (
		8.17
		+ 1.31 * sin(point.x * (0.17 + seed_value * 0.001))
		+ 1.07 * cos(point.z * (0.21 + seed_value * 0.0007))
		+ 0.43 * sin((point.x + point.z) * 0.37 + seed_value)
	)
	return point.y - height
