@tool
extends RefCounted
class_name WtTerrainLabMaterialQualification

const EditField := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_edit_field.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)
const MaterialBlendingQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_material_blending_qualification.gd"
)
const TextureSystemQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_texture_system_qualification.gd"
)
const SurfaceShadingQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_surface_shading_qualification.gd"
)


static func run() -> Dictionary:
	var milestones: Array[Dictionary] = [
		_qualify_material_contract(),
		MaterialBlendingQualification.run(),
		TextureSystemQualification.run(),
		SurfaceShadingQualification.run(),
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
			"TQP-18": "qualified",
			"TQP-21": "qualified",
			"TQP-23": "qualified_reference_surface_shading",
			"TQP-25": "specified_pending_human_acceptance",
		},
		"qualified_scope": [
			"deterministic material IDs, weights, ties, and construction provenance",
			"TQP-18 accepted exact blending corpus and retained diagnostic visual",
			"TQP-21 accepted reference triplanar texture-array presentation",
			"TQP-23 accepted bounded reference surface-shading contract",
		],
		"explicitly_unqualified_scope": [
			"production texture assets",
			"visual pleasantness",
			"temporal shader stability",
			"renderer and GPU cost",
			"TQP-25 multi-scene human visual acceptance",
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
