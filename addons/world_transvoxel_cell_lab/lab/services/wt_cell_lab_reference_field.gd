@tool
extends RefCounted
class_name WtCellLabReferenceField

const MeshAnalysis := preload("res://addons/world_transvoxel_cell_lab/lab/services/wt_cell_lab_mesh_analysis.gd")

const ISO_VALUE := 0.0
const CONSTRUCT_MATERIAL := 5
const PROFILE_CANONICAL := "canonical"
const PROFILE_COARSE_TUNNEL_ROOF_ALIAS := "coarse_tunnel_roof_alias"
const CANONICAL_MAIN_TUNNEL_CENTER_Y := 5.0
const ALIAS_MAIN_TUNNEL_CENTER_Y := 6.6
const MAIN_TUNNEL_CENTER_Z := 14.5
const MAIN_TUNNEL_RADIUS := 2.35

var edits: Array[Dictionary] = []
var fixture_profile := PROFILE_CANONICAL


func sample(point: Vector3i) -> Dictionary:
	return sample_point(Vector3(point))


func sample_point(point: Vector3) -> Dictionary:
	var density_value := density(point)
	var material := material_at(point, density_value)
	return {
		"density": density_value,
		"material": material,
		"material_authored": material > 0,
	}


func density(point: Vector3, include_edits: bool = true) -> float:
	var value := density_without_edits(point)
	if not include_edits:
		return value
	for edit in edits:
		var center: Vector3 = edit.get("center", Vector3.ZERO)
		var radius := float(edit.get("radius", 1.0))
		var influence := radius - point.distance_to(center)
		if influence <= 0.0:
			continue
		if str(edit.get("mode", "")) == "dig":
			value = maxf(value, influence)
		else:
			value = minf(value, -influence)
	return value


func density_without_edits(point: Vector3) -> float:
	var value := point.y - base_height(point.x, point.z)

	# Two crossing tunnels and a chamber form one connected cave system.
	var main_tunnel := MAIN_TUNNEL_RADIUS - Vector2(
		point.y - main_tunnel_center_y(),
		point.z - MAIN_TUNNEL_CENTER_Z
	).length()
	var branch_tunnel := 1.85 - Vector2(point.x - 12.0, point.y - 7.0).length()
	var chamber := 4.25 - point.distance_to(Vector3(12.0, 7.0, 14.5))
	value = maxf(value, maxf(main_tunnel, maxf(branch_tunnel, chamber)))

	# An overhang shelf is unioned above the base and its underside is carved.
	var shelf := _ellipsoid_sdf(
		point,
		Vector3(25.0, 14.4, 6.0),
		Vector3(7.5, 2.6, 5.5)
	)
	value = minf(value, shelf)
	var shelf_undercut := -_ellipsoid_sdf(
		point,
		Vector3(24.0, 11.9, 6.0),
		Vector3(5.8, 1.7, 3.9)
	)
	value = maxf(value, shelf_undercut)

	# Rounded pillars and a crown create an inspectable volumetric arch.
	var arch_left := _rounded_box_sdf(
		point - Vector3(4.0, 13.0, 25.0),
		Vector3(0.8, 3.7, 1.15),
		0.35
	)
	var arch_right := _rounded_box_sdf(
		point - Vector3(10.0, 13.0, 25.0),
		Vector3(0.8, 3.7, 1.15),
		0.35
	)
	var arch_crown := _rounded_box_sdf(
		point - Vector3(7.0, 16.5, 25.0),
		Vector3(3.8, 0.85, 1.15),
		0.45
	)
	value = minf(value, minf(arch_left, minf(arch_right, arch_crown)))

	# A sub-cell-width fin remains a deliberate thin-feature stress case.
	var thin_feature := _rounded_box_sdf(
		point - Vector3(18.0, 13.5, 25.0),
		Vector3(0.42, 3.8, 3.2),
		0.12
	)
	value = minf(value, thin_feature)
	return value


func base_height(x: float, z: float) -> float:
	var rolling := 9.35 \
		+ 1.9 * sin((x + 7.0) * 0.075) \
		+ 1.35 * cos((z - 2.0) * 0.105) \
		+ 0.75 * sin((x + z) * 0.048)
	var cliff_step := 3.2 * tanh((x + 9.0) * 0.55)
	var cliff_window := 0.5 + 0.5 * cos(clampf((z - 8.0) / 22.0, -1.0, 1.0) * PI)
	return rolling + cliff_step * cliff_window


func material_at(point: Vector3, density_value: float) -> int:
	if density_value >= ISO_VALUE:
		return 0
	for edit in edits:
		if str(edit.get("mode", "")) != "construct":
			continue
		var center: Vector3 = edit.get("center", Vector3.ZERO)
		if point.distance_to(center) <= float(edit.get("radius", 1.0)):
			return int(edit.get("material", CONSTRUCT_MATERIAL))
	if _inside_authored_feature_region(point):
		return 4
	var cavity_distance := minf(
		absf(MAIN_TUNNEL_RADIUS - Vector2(
			point.y - main_tunnel_center_y(),
			point.z - MAIN_TUNNEL_CENTER_Z
		).length()),
		minf(
			absf(1.85 - Vector2(point.x - 12.0, point.y - 7.0).length()),
			absf(4.25 - point.distance_to(Vector3(12.0, 7.0, 14.5)))
		)
	)
	if cavity_distance <= 1.25 and point.y <= 11.5:
		return 6
	if point.y < 4.5:
		return 3
	var surface := base_height(point.x, point.z)
	if point.y >= surface - 2.25:
		return 2
	return 1


func feature_catalog() -> Array[Dictionary]:
	return [
		{"id": "rolling_hills", "label": "Rolling hills", "position": Vector3(-18.0, 11.0, -10.0)},
		{"id": "cliff", "label": "Escarpment", "position": Vector3(-9.0, 12.0, 8.0)},
		{
			"id": "main_tunnel",
			"label": "Main tunnel",
			"position": Vector3(0.0, main_tunnel_center_y(), MAIN_TUNNEL_CENTER_Z),
		},
		{"id": "branch_tunnel", "label": "Branch tunnel", "position": Vector3(12.0, 7.0, 4.0)},
		{"id": "cave_chamber", "label": "Cave chamber", "position": Vector3(12.0, 7.0, 14.5)},
		{"id": "overhang", "label": "Overhang shelf", "position": Vector3(25.0, 14.4, 6.0)},
		{"id": "arch", "label": "Volumetric arch", "position": Vector3(7.0, 16.5, 25.0)},
		{"id": "thin_feature", "label": "Thin fin", "position": Vector3(18.0, 13.5, 25.0)},
		{"id": "material_strata", "label": "Material strata", "position": Vector3(-18.0, 5.0, 22.0)},
	]


func validate_feature_probes() -> Dictionary:
	var probes := [
		{"name": "bedrock", "point": Vector3(-24.0, 1.5, -18.0), "solid": true},
		{"name": "open_air", "point": Vector3(16.0, 28.0, 16.0), "solid": false},
		{"name": "cliff_low_side_air", "point": Vector3(-11.0, 11.5, 8.0), "solid": false},
		{"name": "cliff_high_side_solid", "point": Vector3(-7.0, 11.5, 8.0), "solid": true},
		{
			"name": "main_tunnel_core",
			"point": Vector3(0.0, main_tunnel_center_y(), MAIN_TUNNEL_CENTER_Z),
			"solid": false,
		},
		{"name": "branch_tunnel_core", "point": Vector3(12.0, 7.0, 3.0), "solid": false},
		{"name": "cave_chamber_core", "point": Vector3(12.0, 7.0, 14.5), "solid": false},
		{"name": "cave_chamber_shell", "point": Vector3(15.5, 9.5, 17.5), "solid": true},
		{"name": "overhang_shelf", "point": Vector3(25.0, 14.4, 6.0), "solid": true},
		{"name": "overhang_undercut", "point": Vector3(24.0, 11.9, 6.0), "solid": false},
		{"name": "arch_left_pillar", "point": Vector3(4.0, 13.0, 25.0), "solid": true},
		{"name": "arch_opening", "point": Vector3(7.0, 13.0, 25.0), "solid": false},
		{"name": "arch_crown", "point": Vector3(7.0, 16.5, 25.0), "solid": true},
		{"name": "thin_feature", "point": Vector3(18.0, 13.5, 25.0), "solid": true},
		{"name": "thin_feature_clearance", "point": Vector3(19.0, 13.5, 25.0), "solid": false},
	]
	var passing := 0
	var results: Array = []
	for probe in probes:
		var density_value := density_without_edits(probe.get("point", Vector3.ZERO))
		var actual_solid := density_value < ISO_VALUE
		var matches := actual_solid == bool(probe.get("solid", false))
		passing += 1 if matches else 0
		results.append({
			"name": probe.get("name", ""),
			"point": probe.get("point", Vector3.ZERO),
			"expected_solid": probe.get("solid", false),
			"actual_solid": actual_solid,
			"density": density_value,
			"matches": matches,
		})
	return {
		"status": "PASS" if passing == probes.size() else "FAIL",
		"feature_count": feature_catalog().size(),
		"feature_ids": feature_ids(),
		"probe_count": probes.size(),
		"passing_probes": passing,
		"failing_probes": probes.size() - passing,
		"probes": results,
	}


func feature_ids() -> Array[String]:
	var ids: Array[String] = []
	for feature in feature_catalog():
		ids.append(str(feature.get("id", "")))
	return ids


func set_fixture_profile(value: String) -> void:
	if value in [PROFILE_CANONICAL, PROFILE_COARSE_TUNNEL_ROOF_ALIAS]:
		fixture_profile = value


func main_tunnel_center_y() -> float:
	return (
		ALIAS_MAIN_TUNNEL_CENTER_Y
		if fixture_profile == PROFILE_COARSE_TUNNEL_ROOF_ALIAS
		else CANONICAL_MAIN_TUNNEL_CENTER_Y
	)


func main_tunnel_roof_clearance(x: float, sample_intervals: int = 128) -> Dictionary:
	sample_intervals = maxi(sample_intervals, 8)
	var minimum_clearance := INF
	var minimum_z := MAIN_TUNNEL_CENTER_Z
	for index in range(sample_intervals + 1):
		var z := MAIN_TUNNEL_CENTER_Z - MAIN_TUNNEL_RADIUS \
			+ 2.0 * MAIN_TUNNEL_RADIUS * float(index) / float(sample_intervals)
		var offset_z := z - MAIN_TUNNEL_CENTER_Z
		var tunnel_roof := main_tunnel_center_y() + sqrt(
			maxf(MAIN_TUNNEL_RADIUS * MAIN_TUNNEL_RADIUS - offset_z * offset_z, 0.0)
		)
		var clearance := base_height(x, z) - tunnel_roof
		if clearance < minimum_clearance:
			minimum_clearance = clearance
			minimum_z = z
	return {
		"minimum_clearance": minimum_clearance,
		"minimum_clearance_z": minimum_z,
		"sample_count": sample_intervals + 1,
	}


func apply_edit(
	mode: String,
	center: Vector3,
	radius: float,
	material: int = CONSTRUCT_MATERIAL
) -> void:
	if mode not in ["dig", "construct"]:
		return
	edits.append({
		"mode": mode,
		"center": center,
		"radius": maxf(radius, 0.05),
		"material": clampi(material, 1, 65535) if mode == "construct" else 0,
	})


func clear_edits() -> void:
	edits.clear()


func set_edits(values: Array) -> void:
	edits.clear()
	for value in values:
		var edit: Dictionary = value
		var mode := str(edit.get("mode", ""))
		if mode not in ["dig", "construct"]:
			continue
		edits.append({
			"mode": mode,
			"center": MeshAnalysis.vector3_from_variant(edit.get("center", Vector3.ZERO)),
			"radius": maxf(float(edit.get("radius", 1.0)), 0.05),
			"material": int(edit.get("material", CONSTRUCT_MATERIAL)),
		})


func dirty_region() -> AABB:
	if edits.is_empty():
		return AABB()
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	for edit in edits:
		var center: Vector3 = edit.get("center", Vector3.ZERO)
		var radius := float(edit.get("radius", 1.0))
		minimum = minimum.min(center - Vector3.ONE * radius)
		maximum = maximum.max(center + Vector3.ONE * radius)
	return AABB(minimum, maximum - minimum)


func _inside_authored_feature_region(point: Vector3) -> bool:
	if absf(point.x - 18.0) <= 0.7 and absf(point.z - 25.0) <= 3.5 and point.y >= 9.0:
		return true
	if point.z >= 23.5 and point.z <= 26.5 and point.x >= 2.5 and point.x <= 11.5:
		return true
	if point.x >= 18.0 and point.x <= 32.0 and point.z >= 0.0 and point.z <= 12.0:
		return true
	if absf(point.x + 9.0) <= 2.5 and point.z >= -8.0 and point.z <= 24.0:
		return true
	return false


func _ellipsoid_sdf(point: Vector3, center: Vector3, radii: Vector3) -> float:
	var local := Vector3(
		(point.x - center.x) / radii.x,
		(point.y - center.y) / radii.y,
		(point.z - center.z) / radii.z
	)
	return (local.length() - 1.0) * minf(radii.x, minf(radii.y, radii.z))


func _rounded_box_sdf(local: Vector3, half_size: Vector3, radius: float) -> float:
	var q := local.abs() - half_size
	var outside := Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0))
	return outside.length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0) - radius
