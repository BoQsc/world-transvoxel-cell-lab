@tool
extends RefCounted
class_name WtTerrainLabStructuralQualification

const EditField := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_edit_field.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)

const NEIGHBORS: Array[Vector3i] = [
	Vector3i.LEFT,
	Vector3i.RIGHT,
	Vector3i.UP,
	Vector3i.DOWN,
	Vector3i.FORWARD,
	Vector3i.BACK,
]


static func run() -> Dictionary:
	var milestones: Array[Dictionary] = [
		_qualify_connectivity(),
		_qualify_fluid_ownership(),
		_qualify_placement_invalidation(),
		_qualify_authored_composition(),
		_qualify_collapse_policy(),
	]
	var failures: Array[String] = []
	for milestone in milestones:
		for failure_value in milestone.get("failures", []):
			failures.append(
				"%s: %s" % [str(milestone.get("milestone", "UNKNOWN")), str(failure_value)]
			)
	return {
		"schema": "world_transvoxel.terrain_lab.structural_world_qualification.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"scope_status": {
			"TQP-47": "implemented_pending_strength_and_under_resolution_matrix",
			"TQP-48": "implemented_ownership_only_pending_fluid_system_evidence",
			"TQP-49": "implemented_pending_collision_destruction_and_persistence",
			"TQP-50": "implemented_pending_bridge_authoring_and_lod_matrix",
			"TQP-51": "implemented_pending_rigid_body_remesh_collision_and_persistence",
		},
		"implemented_scope": [
			"fluid ownership boundary",
		],
		"explicitly_unqualified_scope": [
			"production rigid-body debris",
			"fluid simulation and rendering",
			"production vegetation rendering",
			"road and bridge authoring tools",
			"gameplay suitability",
			"complete TQP-47 through TQP-51 qualification",
		],
		"provenance": Statistics.provenance("structural_world_reference_v1"),
		"milestones": milestones,
		"failures": failures,
	}


static func _qualify_connectivity() -> Dictionary:
	var failures: Array[String] = []
	var solid := {}
	for y in range(4):
		solid[Vector3i(0, y, 0)] = true
	solid[Vector3i(1, 3, 0)] = true
	solid[Vector3i(8, 8, 8)] = true
	solid[Vector3i(8, 9, 8)] = true
	var supported := _flood_from_anchors(solid, [Vector3i(0, 0, 0)])
	_expect(supported.size() == 5, "supported component size changed", failures)
	_expect(supported.has(Vector3i(1, 3, 0)), "connected overhang lost support", failures)
	_expect(not supported.has(Vector3i(8, 8, 8)), "floating component became supported", failures)
	var unsupported := _difference(solid, supported)
	_expect(unsupported.size() == 2, "unsupported component size changed", failures)
	var result := _result("TQP-47", solid.size() + 4, failures)
	result["supported_count"] = supported.size()
	result["unsupported_count"] = unsupported.size()
	return result


static func _qualify_collapse_policy() -> Dictionary:
	var failures: Array[String] = []
	var components := [
		{"voxel_count": 1, "material_strength": 0.2, "expected": "discard_fragment"},
		{"voxel_count": 12, "material_strength": 0.7, "expected": "rigid_debris"},
		{"voxel_count": 300, "material_strength": 0.9, "expected": "remesh_dynamic_component"},
	]
	for component in components:
		var decision := _collapse_decision(
			int(component["voxel_count"]),
			float(component["material_strength"])
		)
		_expect(decision == str(component["expected"]), "collapse policy changed", failures)
	var replay_signature := JSON.stringify(components).sha256_text()
	_expect(not replay_signature.is_empty(), "collapse replay signature missing", failures)
	var result := _result("TQP-51", components.size() + 1, failures)
	result["replay_signature"] = replay_signature
	result["qualification_scope"] = "REFERENCE_POLICY_NO_RIGID_BODY_IMPLEMENTATION"
	return result


static func _qualify_fluid_ownership() -> Dictionary:
	var failures: Array[String] = []
	var ownership := {
		"terrain_solid_boundary": "authoritative_density_field",
		"water_volume": "separate_fluid_system",
		"intersection_query": "terrain_field_query_at_fluid_resolution",
		"coastline_rendering": "fluid_renderer",
		"cave_water": "fluid_regions_clipped_by_authoritative_terrain_queries",
		"drainage": "fluid_system_policy_not_terrain_meshing_policy",
		"flooding": "fluid_system_state_reacts_to_terrain_edit_invalidation",
		"terrain_edit_invalidation": "fluid_regions_overlapping_edit_bounds",
		"lod_behavior": "fluid_surface_lod_is_independent_and_queries_continuous_terrain",
		"persistence": "fluid_system_state_plus_terrain_version_reference",
	}
	for key in ownership:
		_expect(not str(ownership[key]).is_empty(), "fluid ownership entry is empty", failures)
	_expect(
		str(ownership["water_volume"]) != str(ownership["terrain_solid_boundary"]),
		"fluid volume must not become terrain density authority",
		failures
	)
	var result := _result("TQP-48", ownership.size() + 1, failures)
	result["ownership"] = ownership
	result["qualification_scope"] = "OWNERSHIP_CONTRACT_ONLY"
	return result


static func _qualify_placement_invalidation() -> Dictionary:
	var failures: Array[String] = []
	var first := _placement_set(Vector3i(4, 0, -2), 42, 7)
	var replay := _placement_set(Vector3i(4, 0, -2), 42, 7)
	var changed_surface := _placement_set(Vector3i(4, 0, -2), 42, 8)
	_expect(first == replay, "placement replay is not deterministic", failures)
	_expect(first != changed_surface, "surface version did not invalidate placement", failures)
	_expect(first.size() == 16, "placement count changed", failures)
	var result := _result("TQP-49", first.size() + 2, failures)
	result["placement_signature"] = JSON.stringify(first).sha256_text()
	return result


static func _qualify_authored_composition() -> Dictionary:
	var failures: Array[String] = []
	var field := EditField.new()
	var road_stamp := {
		"id": "road-stamp-001",
		"mode": "construct",
		"shape": "rounded_box",
		"center": Vector3(16.0, 13.0, 16.0),
		"half_extents": Vector3(10.0, 0.5, 2.0),
		"rounding_m": 0.2,
		"material": 9,
	}
	var tunnel_stamp := {
		"id": "tunnel-stamp-002",
		"mode": "dig",
		"shape": "capsule",
		"segment_a": Vector3(16.0, 10.0, 4.0),
		"segment_b": Vector3(16.0, 10.0, 28.0),
		"radius_m": 2.0,
	}
	_expect(field.add_operation(road_stamp), "road stamp rejected", failures)
	_expect(field.add_operation(tunnel_stamp), "tunnel stamp rejected", failures)
	_expect(field.density(Vector3(10.0, 13.0, 16.0)) < 0.0, "road did not compose as solid", failures)
	_expect(field.material_at(Vector3(10.0, 13.0, 16.0), -0.1) == 9, "road material changed", failures)
	_expect(field.density(Vector3(16.0, 10.0, 16.0)) > 0.0, "tunnel did not subtract", failures)
	var replay := EditField.new()
	_expect(replay.reconstruct(field.serialized_journal()), "authored replay failed", failures)
	_expect(replay.journal_signature() == field.journal_signature(), "authored replay diverged", failures)
	var result := _result("TQP-50", 7, failures)
	result["composition_order"] = [
		"procedural_and_authored_base",
		"ordered_construction_and_subtraction_journal",
		"derived_material_and_mesh_publication",
	]
	result["journal_signature"] = field.journal_signature()
	return result


static func _flood_from_anchors(solid: Dictionary, anchors: Array[Vector3i]) -> Dictionary:
	var visited := {}
	var queue: Array[Vector3i] = []
	for anchor in anchors:
		if solid.has(anchor) and not visited.has(anchor):
			visited[anchor] = true
			queue.append(anchor)
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for offset in NEIGHBORS:
			var neighbor := current + offset
			if solid.has(neighbor) and not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	return visited


static func _difference(left: Dictionary, right: Dictionary) -> Dictionary:
	var result := {}
	for key in left:
		if not right.has(key):
			result[key] = true
	return result


static func _collapse_decision(voxel_count: int, material_strength: float) -> String:
	if voxel_count <= 2 or material_strength < 0.25:
		return "discard_fragment"
	if voxel_count < 128:
		return "rigid_debris"
	return "remesh_dynamic_component"


static func _placement_set(
	chunk: Vector3i,
	world_seed: int,
	surface_generation: int
) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([
		chunk.x,
		chunk.y,
		chunk.z,
		world_seed,
		surface_generation,
	])
	var result: Array[Dictionary] = []
	for index in range(16):
		result.append({
			"id": "%d:%d:%d:%d" % [chunk.x, chunk.y, chunk.z, index],
			"local_x": rng.randf_range(0.0, 16.0),
			"local_z": rng.randf_range(0.0, 16.0),
			"yaw": rng.randf_range(0.0, TAU),
			"surface_generation": surface_generation,
		})
	return result


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
