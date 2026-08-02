@tool
extends Node
class_name WtTerrainLabPhase03SystemQualification

const Harness := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_runtime_harness.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)

const FIXTURE_ROOT := "user://world_transvoxel_terrain_lab/phase_03_collision"
const SOURCE_REVISION := 82401
const VIEWER_ID := 24
const TARGET_POINT := Vector3i(40, 6, 40)
const QUERY_POINT := Vector3i(45, 6, 40)
const TARGET_CHUNK := Vector3i(2, 0, 2)
const TARGET_RENDER := "WT_Render_2_0_2_L0"
const TARGET_COLLISION := "WT_Collision_2_0_2_L0"


func run() -> Dictionary:
	var failures: Array[String] = []
	var tqp_24 := await _qualify_collision_queries_navigation(failures)
	return {
		"schema": "world_transvoxel.terrain_lab.phase_03_system_qualification.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"authority": "world_transvoxel_native_runtime_plus_godot_servers",
		"provenance": Statistics.provenance("tqp24_native_godot_publication_v1"),
		"memory": Statistics.memory_metrics(),
		"milestones": {"TQP-24": tqp_24},
		"failures": failures,
	}


func _qualify_collision_queries_navigation(failures: Array[String]) -> Dictionary:
	var local_failures: Array[String] = []
	print("WT_TQP24_STAGE create_runtime")
	Harness.remove_tree(FIXTURE_ROOT)
	var harness := Harness.new()
	add_child(harness)
	if not harness.create_runtime(2):
		local_failures.append("native runtime harness could not be created")
		return await _finish_tqp_24(harness, {}, local_failures, failures)
	if not await harness.start_flat_world(FIXTURE_ROOT, SOURCE_REVISION):
		local_failures.append("native flat world did not reach running")
		return await _finish_tqp_24(harness, {}, local_failures, failures)
	var terrain := harness.terrain
	print("WT_TQP24_STAGE initial_publication")
	_expect(
		bool(terrain.call("update_viewer", VIEWER_ID, 1, Vector3(40, 8, 40), 0, 0)),
		"native viewer update was rejected",
		local_failures
	)
	var initial_settlement: Dictionary = await harness.wait_for_settled(1)
	print("WT_TQP24_STAGE initial_settled " + str(initial_settlement.get("status", "")))
	_expect(str(initial_settlement.get("status", "")) == "PASS", "initial native publication did not settle", local_failures)
	var initial_state := _chunk_state(terrain)
	var initial_generation := int(initial_state.get("generation", 0))
	var render := terrain.get_node_or_null(TARGET_RENDER) as MeshInstance3D
	var collision := terrain.get_node_or_null(TARGET_COLLISION) as StaticBody3D
	var collision_shape := _collision_shape(collision)
	_expect(render != null and render.mesh != null, "native render mesh is missing", local_failures)
	_expect(collision_shape != null, "native concave collision shape is missing", local_failures)
	var initial_query: Dictionary = await harness.request_sample(TARGET_POINT)
	_expect(str(initial_query.get("status", "")) == "PASS", "initial authoritative query failed", local_failures)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var first_hit := _ray_hits_terrain(terrain, Vector3(45, 24, 40), Vector3(45, -8, 40))
	_expect(first_hit, "initial direct-space ray missed native collision", local_failures)
	var navigation_control := await _navigation_server_control(render)
	print("WT_TQP24_STAGE navigation_control " + str(navigation_control))
	_expect(navigation_control, "Godot NavigationServer control polygon failed", local_failures)
	var navigation := await _publish_navigation(render)
	print("WT_TQP24_STAGE initial_navigation " + str(navigation))
	_expect(bool(navigation.get("query_passed", false)), "initial navigation publication/query failed", local_failures)

	var edit: RefCounted = terrain.call("begin_edit_transaction", 2401)
	_expect(edit != null, "native edit transaction was not created", local_failures)
	if edit != null:
		_expect(
			bool(edit.call("carve_smooth_sdf_sphere", Vector3(TARGET_POINT), 4.0, 1.0, 0.75)),
			"native carve command was rejected",
			local_failures
		)
		_expect(bool(terrain.call("commit_edit_transaction", edit)), "native carve submission failed", local_failures)
	_expect(await harness.wait_for_commit(1), "native carve did not commit", local_failures)
	print("WT_TQP24_STAGE edit_committed")
	var edited_ready: Dictionary = await harness.wait_for_chunk_ready(TARGET_CHUNK, 0, initial_generation)
	print("WT_TQP24_STAGE edited_ready " + str(edited_ready.get("status", "")))
	_expect(str(edited_ready.get("status", "")) == "PASS", "edited native chunk did not republish", local_failures)
	var edited_settlement: Dictionary = await harness.wait_for_settled(1)
	_expect(str(edited_settlement.get("status", "")) == "PASS", "edited native publication did not settle", local_failures)
	var edited_state := _chunk_state(terrain)
	var edited_render := terrain.get_node_or_null(TARGET_RENDER) as MeshInstance3D
	var edited_collision := terrain.get_node_or_null(TARGET_COLLISION) as StaticBody3D
	var edited_shape := _collision_shape(edited_collision)
	var edited_query: Dictionary = await harness.request_sample(TARGET_POINT)
	_expect(
		str(edited_query.get("status", "")) == "PASS"
			and int(edited_query.get("world_revision", -1)) == 1
			and float(edited_query.get("density", -INF)) > float(initial_query.get("density", INF)),
		"edited authoritative query did not expose the committed carve",
		local_failures
	)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var second_hit := _ray_hits_terrain(terrain, Vector3(45, 24, 40), Vector3(45, -8, 40))
	_expect(second_hit, "edited direct-space ray missed native collision", local_failures)
	var edited_navigation := await _publish_navigation(edited_render)
	print("WT_TQP24_STAGE edited_navigation " + str(edited_navigation))
	_expect(bool(edited_navigation.get("query_passed", false)), "edited navigation publication/query failed", local_failures)
	_expect(edited_shape != null, "edited collision shape is missing", local_failures)
	_expect(_generations_coherent(initial_state, initial_generation), "initial publication generations diverged", local_failures)
	var edited_generation := int(edited_state.get("generation", 0))
	_expect(
		edited_generation > initial_generation and _generations_coherent(edited_state, edited_generation),
		"edited render/collision generation is incoherent",
		local_failures
	)
	_expect(await harness.stop_world(), "native fixture did not stop cleanly", local_failures)
	var record := {
		"milestone": "TQP-24",
		"status": "PASS" if local_failures.is_empty() else "FAIL",
		"fixture": "native_godot_collision_query_navigation_v1",
		"initial_generation": initial_generation,
		"edited_generation": edited_generation,
		"world_revision": int(edited_query.get("world_revision", -1)),
		"generation_coherent_before_edit": _generations_coherent(initial_state, initial_generation),
		"generation_coherent_after_edit": _generations_coherent(edited_state, edited_generation),
		"collision_shape_type": "ConcavePolygonShape3D" if edited_shape is ConcavePolygonShape3D else "MISSING",
		"collision_face_count": edited_shape.get_faces().size() / 3 if edited_shape != null else 0,
		"physics_ray_hits": int(first_hit) + int(second_hit),
		"authoritative_query_count": 2,
		"initial_query": initial_query,
		"edited_query": edited_query,
		"navigation_polygon_count": int(edited_navigation.get("polygon_count", 0)),
		"navigation_query_passed": bool(edited_navigation.get("query_passed", false)),
		"native_metrics": edited_settlement.get("metrics", {}),
		"failures": local_failures,
	}
	return await _finish_tqp_24(harness, record, local_failures, failures)


func _finish_tqp_24(
	harness: Node,
	record: Dictionary,
	local_failures: Array[String],
	failures: Array[String]
) -> Dictionary:
	for failure in local_failures:
		failures.append("TQP-24: " + failure)
	if harness != null:
		harness.dispose()
		harness.queue_free()
		await get_tree().process_frame
	Harness.remove_tree(FIXTURE_ROOT)
	if record.is_empty():
		record = {
			"milestone": "TQP-24",
			"status": "FAIL",
			"fixture": "native_godot_collision_query_navigation_v1",
			"failures": local_failures,
		}
	return record


func _chunk_state(terrain: Node) -> Dictionary:
	var state: RefCounted = terrain.call("query_chunk_state", TARGET_CHUNK, 0)
	return Harness.chunk_state(state) if state != null else {}


func _collision_shape(body: StaticBody3D) -> ConcavePolygonShape3D:
	if body == null:
		return null
	var shape_node := body.get_node_or_null("Shape") as CollisionShape3D
	if shape_node == null or not shape_node.shape is ConcavePolygonShape3D:
		return null
	return shape_node.shape as ConcavePolygonShape3D


func _ray_hits_terrain(terrain: Node, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit: Dictionary = terrain.get_world_3d().direct_space_state.intersect_ray(query)
	var collider := hit.get("collider") as Node
	return collider != null and collider.name.begins_with("WT_Collision_")


func _publish_navigation(render: MeshInstance3D) -> Dictionary:
	if render == null or render.mesh == null or render.mesh.get_surface_count() == 0:
		return {"polygon_count": 0, "query_passed": false}
	var source: Array = render.mesh.surface_get_arrays(0)
	var positions: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = source[Mesh.ARRAY_INDEX]
	var vertices := PackedVector3Array()
	var polygons: Array[PackedInt32Array] = []
	var navigation_indices := PackedInt32Array()
	var vertex_lookup := {}
	var query_start := Vector3.ZERO
	var query_end := Vector3.ZERO
	for triangle in range(0, indices.size(), 3):
		var a := render.global_transform * positions[indices[triangle]]
		var b := render.global_transform * positions[indices[triangle + 1]]
		var c := render.global_transform * positions[indices[triangle + 2]]
		var cross := (b - a).cross(c - a)
		# Native ArrayMesh triangles use clockwise front-face winding, so an
		# upward walkable face has a negative geometric cross-product Y.
		if cross.length_squared() <= 0.000001 or cross.normalized().y > -0.55:
			continue
		var nav_a := _navigation_vertex_index(a, vertices, vertex_lookup)
		var nav_b := _navigation_vertex_index(b, vertices, vertex_lookup)
		var nav_c := _navigation_vertex_index(c, vertices, vertex_lookup)
		# NavigationMesh polygons use upward counter-clockwise winding, opposite
		# the clockwise renderer triangles supplied by the native backend.
		polygons.append(PackedInt32Array([nav_a, nav_c, nav_b]))
		navigation_indices.append_array(PackedInt32Array([nav_a, nav_c, nav_b]))
		if polygons.size() == 1:
			query_start = a.lerp(b, 0.25).lerp(c, 0.25)
			query_end = a.lerp(b, 0.55).lerp(c, 0.15)
	var navigation_source := ArrayMesh.new()
	var navigation_arrays := []
	navigation_arrays.resize(Mesh.ARRAY_MAX)
	navigation_arrays[Mesh.ARRAY_VERTEX] = vertices
	navigation_arrays[Mesh.ARRAY_INDEX] = navigation_indices
	if not vertices.is_empty():
		navigation_source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, navigation_arrays)
	var navigation_mesh := NavigationMesh.new()
	if navigation_source.get_surface_count() > 0:
		navigation_mesh.create_from_mesh(navigation_source)
	var region := NavigationRegion3D.new()
	region.navigation_mesh = navigation_mesh
	render.get_parent().add_child(region)
	NavigationServer3D.set_active(true)
	var map_rid := region.get_navigation_map()
	NavigationServer3D.map_set_use_async_iterations(map_rid, false)
	NavigationServer3D.map_set_cell_size(map_rid, navigation_mesh.cell_size)
	NavigationServer3D.map_set_cell_height(map_rid, navigation_mesh.cell_height)
	NavigationServer3D.map_set_up(map_rid, Vector3.UP)
	NavigationServer3D.map_set_active(map_rid, true)
	await get_tree().physics_frame
	NavigationServer3D.map_force_update(map_rid)
	for _frame in range(60):
		if NavigationServer3D.map_get_iteration_id(map_rid) > 0:
			break
		await get_tree().physics_frame
	var closest_start := NavigationServer3D.map_get_closest_point(map_rid, query_start)
	var closest_end := NavigationServer3D.map_get_closest_point(map_rid, query_end)
	var owner := NavigationServer3D.map_get_closest_point_owner(map_rid, query_start)
	var path := NavigationServer3D.map_get_path(map_rid, closest_start, closest_end, true)
	var query_passed := (
		not polygons.is_empty()
		and owner.is_valid()
		and closest_start.distance_to(query_start) <= 0.01
		and closest_end.distance_to(query_end) <= 0.01
		and path.size() >= 1
	)
	var diagnostics := {
		"polygon_count": navigation_mesh.get_polygon_count(),
		"query_passed": query_passed,
		"iteration_id": NavigationServer3D.map_get_iteration_id(map_rid),
		"map_active": NavigationServer3D.map_is_active(map_rid),
		"map_region_count": NavigationServer3D.map_get_regions(map_rid).size(),
		"region_enabled": region.enabled,
		"region_map_valid": region.get_navigation_map().is_valid(),
		"owner_valid": owner.is_valid(),
		"start_error": closest_start.distance_to(query_start),
		"end_error": closest_end.distance_to(query_end),
		"path_point_count": path.size(),
	}
	region.free()
	NavigationServer3D.map_force_update(map_rid)
	await get_tree().physics_frame
	return diagnostics


func _navigation_server_control(context: Node3D) -> bool:
	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.vertices = PackedVector3Array([
		Vector3(-1.0, 0.0, 1.0),
		Vector3(1.0, 0.0, 1.0),
		Vector3(1.0, 0.0, -1.0),
		Vector3(-1.0, 0.0, -1.0),
	])
	navigation_mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	var region := NavigationRegion3D.new()
	region.navigation_mesh = navigation_mesh
	context.get_parent().add_child(region)
	NavigationServer3D.set_active(true)
	var map_rid := region.get_navigation_map()
	NavigationServer3D.map_set_use_async_iterations(map_rid, false)
	NavigationServer3D.map_set_cell_size(map_rid, navigation_mesh.cell_size)
	NavigationServer3D.map_set_cell_height(map_rid, navigation_mesh.cell_height)
	NavigationServer3D.map_set_up(map_rid, Vector3.UP)
	NavigationServer3D.map_set_active(map_rid, true)
	await get_tree().physics_frame
	NavigationServer3D.map_force_update(map_rid)
	await get_tree().physics_frame
	var owner := NavigationServer3D.map_get_closest_point_owner(map_rid, Vector3.ZERO)
	var closest := NavigationServer3D.map_get_closest_point(map_rid, Vector3.ZERO)
	var passed := owner.is_valid() and closest.distance_to(Vector3.ZERO) <= 0.001
	region.free()
	NavigationServer3D.map_force_update(map_rid)
	await get_tree().physics_frame
	return passed


static func _navigation_vertex_index(
	point: Vector3,
	vertices: PackedVector3Array,
	lookup: Dictionary
) -> int:
	var key := "%d:%d:%d" % [
		roundi(point.x * 100000.0),
		roundi(point.y * 100000.0),
		roundi(point.z * 100000.0),
	]
	if lookup.has(key):
		return int(lookup[key])
	var index := vertices.size()
	vertices.append(point)
	lookup[key] = index
	return index


static func _generations_coherent(state: Dictionary, generation: int) -> bool:
	return (
		generation > 0
		and bool(state.get("fully_ready", false))
		and int(state.get("render_generation", -1)) == generation
		and int(state.get("collision_generation", -1)) == generation
	)


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
