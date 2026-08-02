@tool
extends RefCounted
class_name WtTerrainLabMaterialQualification

const EditField := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_edit_field.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)


static func run() -> Dictionary:
	var milestones: Array[Dictionary] = [
		_qualify_material_contract(),
		_implement_material_blending(),
		_implement_texture_contract(),
		_implement_surface_shading(),
		_specify_visual_corpus(),
	]
	var failures: Array[String] = []
	for milestone in milestones:
		for failure_value in milestone.get("failures", []):
			failures.append(
				"%s: %s" % [str(milestone.get("milestone", "UNKNOWN")), str(failure_value)]
			)
	return {
		"schema": "world_transvoxel.terrain_lab.material_surface_qualification.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"scope_status": {
			"TQP-08": "qualified",
			"TQP-18": "implemented_pending_visual_evidence",
			"TQP-21": "implemented_pending_render_validation",
			"TQP-23": "implemented_pending_temporal_inspection",
			"TQP-25": "specified_pending_human_acceptance",
		},
		"qualified_scope": [
			"deterministic material IDs, weights, ties, and construction provenance",
		],
		"explicitly_unqualified_scope": [
			"production texture assets",
			"visual pleasantness",
			"temporal shader stability",
			"renderer and GPU cost",
			"human visual acceptance",
		],
		"provenance": Statistics.provenance("material_surface_reference_v1"),
		"milestones": milestones,
		"failures": failures,
	}


static func _qualify_material_contract() -> Dictionary:
	var failures: Array[String] = []
	var normalized := _normalized_weights({1: 2.0, 3: 1.0, 7: 1.0})
	_expect(is_equal_approx(_weight_sum(normalized), 1.0), "weights do not normalize", failures)
	_expect(
		is_equal_approx(float(normalized.get(1, 0.0)), 0.5),
		"normalized dominant weight changed",
		failures
	)
	var tie := _dominant_material({7: 0.5, 3: 0.5})
	_expect(tie == 3, "equal-weight tie must choose the lower material ID", failures)
	var field := EditField.new()
	var construction := {
		"id": "material-construct-001",
		"mode": "construct",
		"shape": "sphere",
		"center": Vector3(4.0, 16.0, 4.0),
		"radius_m": 3.0,
		"material": 12,
	}
	_expect(field.add_operation(construction), "construction fixture was rejected", failures)
	var point := Vector3(4.0, 16.0, 4.0)
	_expect(field.material_at(point, field.density(point)) == 12, "construction provenance changed", failures)
	_expect(field.material_at(Vector3(0.0, 10.0, 0.0), -2.0) == 1, "base provenance changed", failures)
	return _result("TQP-08", 6, failures)


static func _implement_material_blending() -> Dictionary:
	var failures: Array[String] = []
	var source := {9: 0.10, 4: 0.30, 1: 0.25, 7: 0.20, 3: 0.15}
	var reduced := _top_materials(source, 4)
	_expect(reduced.size() == 4, "top-material reduction count changed", failures)
	_expect(not reduced.has(9), "lowest material weight survived top-four reduction", failures)
	_expect(is_equal_approx(_weight_sum(reduced), 1.0), "reduced weights do not normalize", failures)
	var left := _normalized_weights({1: 1.0})
	var right := _normalized_weights({2: 1.0})
	var midpoint := _blend_weights(left, right, 0.5)
	_expect(is_equal_approx(float(midpoint.get(1, 0.0)), 0.5), "blend left weight changed", failures)
	_expect(is_equal_approx(float(midpoint.get(2, 0.0)), 0.5), "blend right weight changed", failures)
	_expect(_dominant_material(midpoint) == 1, "blend tie policy changed", failures)
	var timings: Array[float] = []
	for iteration in range(100):
		var started := Time.get_ticks_usec()
		for blend_index in range(128):
			_blend_weights(left, right, float(blend_index) / 127.0)
		timings.append(float(Time.get_ticks_usec() - started))
	var result := _result("TQP-18", 6, failures)
	result["performance"] = Statistics.distribution(timings)
	result["qualification_status"] = "IMPLEMENTED_PENDING_VISUAL_EVIDENCE"
	return result


static func _implement_texture_contract() -> Dictionary:
	var failures: Array[String] = []
	var scale_m := 2.0
	for point in [
		Vector3.ZERO,
		Vector3(100000.25, -4000.5, 80000.75),
		Vector3(-100000.25, 4000.5, -80000.75),
	]:
		var coordinates := _world_triplanar_coordinates(point, scale_m)
		_expect(
			(coordinates["xy"] as Vector2).is_equal_approx(Vector2(point.x, point.y) / scale_m),
			"XY triplanar coordinates changed",
			failures
		)
		_expect(
			(coordinates["xz"] as Vector2).is_equal_approx(Vector2(point.x, point.z) / scale_m),
			"XZ triplanar coordinates changed",
			failures
		)
		_expect(
			(coordinates["yz"] as Vector2).is_equal_approx(Vector2(point.y, point.z) / scale_m),
			"YZ triplanar coordinates changed",
			failures
		)
	var policy := {
		"storage": "texture_array",
		"mapping": "world_space_triplanar",
		"mipmaps": "required",
		"anisotropy": "required",
		"normal_maps": "tangent_free_triplanar_reorientation",
		"edited_surface_coordinates": "world_position_not_edit_local",
	}
	_expect(policy.size() == 6, "texture policy is incomplete", failures)
	var result := _result("TQP-21", 10, failures)
	result["policy"] = policy
	result["qualification_status"] = "IMPLEMENTED_PENDING_RENDER_VALIDATION"
	return result


static func _implement_surface_shading() -> Dictionary:
	var failures: Array[String] = []
	var normals: Array[Vector3] = [
		Vector3.UP,
		Vector3.RIGHT,
		Vector3(0.25, 0.93, -0.27).normalized(),
		Vector3(-0.71, 0.1, 0.69).normalized(),
	]
	var records: Array[Dictionary] = []
	for normal in normals:
		var weights := _triplanar_weights(normal, 4.0)
		var tangent := _stable_tangent(normal)
		_expect(is_equal_approx(weights.x + weights.y + weights.z, 1.0), "axis weights do not normalize", failures)
		_expect(absf(tangent.dot(normal)) <= 0.00001, "tangent is not orthogonal", failures)
		_expect(is_equal_approx(tangent.length(), 1.0), "tangent is not normalized", failures)
		records.append({
			"normal": normal,
			"axis_weights": weights,
			"tangent": tangent,
			"slope": 1.0 - absf(normal.y),
		})
	var result := _result("TQP-23", normals.size() * 3, failures)
	result["records"] = records
	result["qualification_status"] = "IMPLEMENTED_PENDING_TEMPORAL_INSPECTION"
	return result


static func _specify_visual_corpus() -> Dictionary:
	var failures: Array[String] = []
	var scenes := [
		{"id": "natural", "fixed_camera": true, "human_review": "PENDING"},
		{"id": "constructed", "fixed_camera": true, "human_review": "PENDING"},
		{"id": "destroyed", "fixed_camera": true, "human_review": "PENDING"},
		{"id": "adversarial", "fixed_camera": true, "human_review": "PENDING"},
	]
	for scene in scenes:
		_expect(bool(scene.get("fixed_camera", false)), "visual fixture lacks a fixed camera", failures)
		_expect(str(scene.get("human_review", "")) == "PENDING", "unreviewed scene was accepted", failures)
	var result := _result("TQP-25", scenes.size(), failures)
	result["scenes"] = scenes
	result["qualification_status"] = "SPECIFIED_PENDING_HUMAN_ACCEPTANCE"
	return result


static func _normalized_weights(source: Dictionary) -> Dictionary:
	var total := 0.0
	for material_id in source:
		total += maxf(float(source[material_id]), 0.0)
	var result := {}
	if total <= 0.0:
		return result
	for material_id in source:
		var weight := maxf(float(source[material_id]), 0.0)
		if weight > 0.0:
			result[int(material_id)] = weight / total
	return result


static func _top_materials(source: Dictionary, maximum_count: int) -> Dictionary:
	var entries: Array[Dictionary] = []
	for material_id in source:
		entries.append({"id": int(material_id), "weight": float(source[material_id])})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["weight"]), float(b["weight"])):
			return float(a["weight"]) > float(b["weight"])
		return int(a["id"]) < int(b["id"])
	)
	var selected := {}
	for index in range(mini(maximum_count, entries.size())):
		selected[int(entries[index]["id"])] = float(entries[index]["weight"])
	return _normalized_weights(selected)


static func _blend_weights(left: Dictionary, right: Dictionary, amount: float) -> Dictionary:
	var result := {}
	var material_ids := {}
	for material_id in left:
		material_ids[int(material_id)] = true
	for material_id in right:
		material_ids[int(material_id)] = true
	for material_id in material_ids:
		result[material_id] = lerpf(
			float(left.get(material_id, 0.0)),
			float(right.get(material_id, 0.0)),
			clampf(amount, 0.0, 1.0)
		)
	return _normalized_weights(result)


static func _dominant_material(weights: Dictionary) -> int:
	var best_id := -1
	var best_weight := -1.0
	for material_id_value in weights:
		var material_id := int(material_id_value)
		var weight := float(weights[material_id_value])
		if weight > best_weight or (is_equal_approx(weight, best_weight) and material_id < best_id):
			best_id = material_id
			best_weight = weight
	return best_id


static func _weight_sum(weights: Dictionary) -> float:
	var result := 0.0
	for material_id in weights:
		result += float(weights[material_id])
	return result


static func _world_triplanar_coordinates(point: Vector3, scale_m: float) -> Dictionary:
	return {
		"xy": Vector2(point.x, point.y) / scale_m,
		"xz": Vector2(point.x, point.z) / scale_m,
		"yz": Vector2(point.y, point.z) / scale_m,
	}


static func _triplanar_weights(normal: Vector3, sharpness: float) -> Vector3:
	var absolute := normal.abs()
	var weights := Vector3(
		pow(absolute.x, sharpness),
		pow(absolute.y, sharpness),
		pow(absolute.z, sharpness)
	)
	var total := weights.x + weights.y + weights.z
	return weights / maxf(total, 0.000001)


static func _stable_tangent(normal: Vector3) -> Vector3:
	var reference := Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT
	return reference.cross(normal).normalized()


static func _result(
	milestone: String,
	fixture_count: int,
	failures: Array[String]
) -> Dictionary:
	return {
		"milestone": milestone,
		"status": "PASS" if failures.is_empty() else "FAIL",
		"fixture_count": fixture_count,
		"failures": failures,
	}


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
