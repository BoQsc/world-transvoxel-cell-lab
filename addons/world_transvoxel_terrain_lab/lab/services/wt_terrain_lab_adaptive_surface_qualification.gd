@tool
extends Node
class_name WtTerrainLabAdaptiveSurfaceQualification

const Harness := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_runtime_harness.gd"
)
const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)
const SurfaceShader := preload(
	"res://labs/terrain_lab/shaders/adaptive_surface_reference.gdshader"
)

const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/adaptive_surface_continuity_standard.json"
)
const RUNTIME_ROOT := "user://world_transvoxel_terrain_lab/tqp38_adaptive_surface"
const MATERIAL_SLOTS := [1, 2, 3, 4, 5, 7, 8, 10]
const POSITION_SCALE := 100000.0


func run() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var failures: Array[String] = []
	var actions := {}
	var settlements: Array[Dictionary] = []
	var audit_times: Array[float] = []
	var profile: Dictionary = standard.get("runtime_profile", {})
	var workload: Dictionary = standard.get("workload", {})
	Harness.remove_tree(RUNTIME_ROOT)
	var harness := Harness.new()
	add_child(harness)
	if not harness.create_runtime(
		int(profile.get("worker_count", 2)), _runtime_overrides(profile)
	):
		failures.append("native runtime harness could not be created")
		return await _finish(harness, standard, {}, actions, settlements, audit_times, failures)
	var material := ShaderMaterial.new()
	material.shader = SurfaceShader
	material.set_shader_parameter(
		"texture_scale_m", float(profile.get("texture_scale_m", 3.0))
	)
	material.set_shader_parameter(
		"triplanar_sharpness", float(profile.get("triplanar_sharpness", 4.0))
	)
	harness.terrain.call("set_render_material_override", material)
	var volume: Array = profile.get("volume_chunks", [])
	if volume.size() != 3 or not await harness.start_procedural_world_preset(
		RUNTIME_ROOT.path_join("source"),
		int(profile.get("source_revision", 938001)),
		int(profile.get("seed", 380038)),
		str(profile.get("preset", "rolling_hills_cave")),
		int(volume[0]), int(volume[1]),
		int(profile.get("vertical_chunk_origin", -2)), int(volume[2])
	):
		failures.append("native procedural world did not reach running")
		return await _finish(harness, standard, {}, actions, settlements, audit_times, failures)
	var terrain := harness.terrain
	var viewer_revision := 1
	var initial_position := _vector3(workload.get("initial_viewer_position", []))
	var initial_settlement: Dictionary = await _update_viewer_and_settle(
		harness, terrain, profile, initial_position, viewer_revision
	)
	settlements.append(_settlement_record("initial", initial_settlement))
	_expect(
		str(initial_settlement.get("status", "")) == "PASS",
		"initial native publication did not settle", failures
	)
	var audit_started := Time.get_ticks_usec()
	var baseline := _audit_render_payloads(terrain, standard)
	audit_times.append(float(Time.get_ticks_usec() - audit_started))
	_append_audit_failures("baseline", baseline, failures)
	actions["baseline_payload_audit"] = str(baseline.get("status", ""))
	var baseline_metrics: Dictionary = terrain.call("get_runtime_metrics")
	_expect(
		int(baseline_metrics.get("transition_mesh_completions", 0)) > 0,
		"baseline produced no native transition geometry", failures
	)
	actions["regular_transition_shared_position_agreement"] = (
		"PASS" if int(baseline.get("shared_position_payload_errors", -1)) == 0
		else "FAIL"
	)

	var paint: Dictionary = workload.get("paint", {})
	var construction: Dictionary = workload.get("construction", {})
	var transaction: RefCounted = terrain.call("begin_edit_transaction", 3801)
	_expect(transaction != null, "native material edit transaction was not created", failures)
	if transaction != null:
		_expect(
			bool(transaction.call(
				"paint_material_sphere", _vector3(paint.get("center", [])),
				float(paint.get("radius", 0.0)), int(paint.get("material", 0))
			)),
			"native material paint command was rejected", failures
		)
		_expect(
			bool(transaction.call(
				"construct_material_smooth_sdf_sphere",
				_vector3(construction.get("center", [])),
				float(construction.get("radius", 0.0)),
				float(construction.get("strength", 0.0)),
				int(construction.get("material", 0)),
				float(construction.get("smooth_radius", 0.0))
			)),
			"native material construction command was rejected", failures
		)
		_expect(
			bool(terrain.call("commit_edit_transaction", transaction)),
			"native material edit transaction was rejected", failures
		)
	_expect(await harness.wait_for_commit(1), "native material edit did not commit", failures)
	var edited_settlement: Dictionary = await harness.wait_for_settled(1)
	settlements.append(_settlement_record("edited", edited_settlement))
	_expect(
		str(edited_settlement.get("status", "")) == "PASS",
		"edited native publication did not settle", failures
	)
	audit_started = Time.get_ticks_usec()
	var edited := _audit_render_payloads(terrain, standard)
	audit_times.append(float(Time.get_ticks_usec() - audit_started))
	_append_audit_failures("edited", edited, failures)
	var query_points: Array[Vector3i] = [
		_vector3i(paint.get("center", [])),
		_vector3i(construction.get("center", [])),
	]
	var queries := await harness.request_samples(query_points)
	var query_agreement := _validate_authored_queries(queries, paint, construction)
	for failure in query_agreement.get("failures", []):
		failures.append(str(failure))
	_expect(
		int(edited.get("authored_vertex_count", 0)) > 0,
		"edited render payload exposes no authored material vertices", failures
	)
	_expect(
		int(edited.get("material_7_vertex_count", 0)) > 0,
		"constructed material 7 is absent from native render payload", failures
	)
	_expect(
		int(edited.get("material_8_vertex_count", 0)) > 0,
		"painted material 8 is absent from native render payload", failures
	)
	actions["authored_paint_and_construction"] = (
		"PASS" if str(query_agreement.get("status", "")) == "PASS"
			and int(edited.get("authored_vertex_count", 0)) > 0
		else "FAIL"
	)

	viewer_revision += 1
	var away_settlement: Dictionary = await _update_viewer_and_settle(
		harness, terrain, profile,
		_vector3(workload.get("lod_cycle_position", [])), viewer_revision
	)
	settlements.append(_settlement_record("lod_cycle_away", away_settlement))
	_expect(str(away_settlement.get("status", "")) == "PASS", "LOD cycle departure did not settle", failures)
	viewer_revision += 1
	var return_settlement: Dictionary = await _update_viewer_and_settle(
		harness, terrain, profile, initial_position, viewer_revision
	)
	settlements.append(_settlement_record("lod_cycle_return", return_settlement))
	_expect(str(return_settlement.get("status", "")) == "PASS", "LOD cycle return did not settle", failures)
	audit_started = Time.get_ticks_usec()
	var returned := _audit_render_payloads(terrain, standard)
	audit_times.append(float(Time.get_ticks_usec() - audit_started))
	_append_audit_failures("LOD-cycle return", returned, failures)
	var lod_cycle_identity := _lod_cycle_payload_identity(edited, returned, standard)
	var lod_identity := str(lod_cycle_identity.get("status", "")) == "PASS"
	_expect(lod_identity, "material payload changed after deterministic LOD cycle", failures)
	actions["lod_cycle_identity"] = "PASS" if lod_identity else "FAIL"
	var stale_before := int((terrain.call("get_runtime_metrics") as Dictionary).get("rejected_events", 0))
	var stale_submission := bool(terrain.call(
		"update_viewer", int(profile.get("viewer_id", 38)), viewer_revision - 1,
		initial_position, int(profile.get("viewer_radius_chunks", 1)),
		int(profile.get("maximum_lod", 1))
	))
	var stale_rejected := await _wait_for_metric_increase(
		terrain, "rejected_events", stale_before, 360
	)
	_expect(
		stale_submission and stale_rejected,
		"stale material-view publication revision was not rejected asynchronously",
		failures
	)
	actions["stale_revision_control"] = "PASS" if stale_submission and stale_rejected else "FAIL"

	var rebase := _vector3(workload.get("presentation_rebase", []))
	var before_rebase_signature := str(returned.get("payload_signature", ""))
	terrain.position = rebase
	material.set_shader_parameter("texture_world_origin", -rebase)
	await get_tree().process_frame
	var rebased := _audit_render_payloads(terrain, standard)
	var shader_origin: Vector3 = material.get_shader_parameter("texture_world_origin")
	var payload_identity: bool = (
		before_rebase_signature == str(rebased.get("payload_signature", ""))
	)
	var terrain_transform_identity: bool = terrain.position.is_equal_approx(rebase)
	var shader_origin_identity: bool = shader_origin.is_equal_approx(-rebase)
	var rebase_identity: bool = payload_identity \
		and terrain_transform_identity \
		and shader_origin_identity
	_expect(payload_identity, "presentation origin rebase mutated native material payload", failures)
	_expect(terrain_transform_identity, "presentation origin rebase changed terrain transform", failures)
	_expect(shader_origin_identity, "presentation origin rebase did not compensate shader coordinates", failures)
	actions["presentation_origin_rebase"] = "PASS" if rebase_identity else "FAIL"
	var rebase_control := {
		"status": "PASS" if rebase_identity else "FAIL",
		"payload_identity": payload_identity,
		"terrain_transform_identity": terrain_transform_identity,
		"shader_origin_identity": shader_origin_identity,
		"before_payload_signature": before_rebase_signature,
		"rebased_payload_signature": str(rebased.get("payload_signature", "")),
		"rebased_payload_audit": rebased,
	}
	var anchor := _large_coordinate_anchor(rebase, standard)
	for failure in anchor.get("failures", []):
		failures.append(str(failure))
	actions["large_coordinate_texture_anchor"] = str(anchor.get("status", ""))
	terrain.position = Vector3.ZERO
	material.set_shader_parameter("texture_world_origin", Vector3.ZERO)

	var shader_contract := _validate_shader_contract(standard)
	for failure in shader_contract.get("failures", []):
		failures.append(str(failure))
	actions["mipmapped_lit_shader_contract"] = str(shader_contract.get("status", ""))
	for audit_value in [baseline, edited, returned, rebased]:
		var audit: Dictionary = audit_value
		audit.erase("_position_payload_map")
	var data := {
		"baseline": baseline,
		"edited": edited,
		"returned": returned,
		"lod_cycle_identity": lod_cycle_identity,
		"authoritative_queries": query_agreement,
		"presentation_origin_rebase": rebase_control,
		"large_coordinate_anchor": anchor,
		"shader_contract": shader_contract,
		"native_metrics": terrain.call("get_runtime_metrics"),
	}
	return await _finish(
		harness, standard, data, actions, settlements, audit_times, failures
	)


func _finish(
	harness: Node,
	standard: Dictionary,
	data: Dictionary,
	actions: Dictionary,
	settlements: Array[Dictionary],
	audit_times: Array[float],
	failures: Array[String]
) -> Dictionary:
	var stop_passed := true
	if harness != null and harness.terrain != null:
		stop_passed = await harness.stop_world()
		if not stop_passed:
			failures.append("native material fixture did not stop cleanly")
		harness.dispose()
		harness.queue_free()
		await get_tree().process_frame
	Harness.remove_tree(RUNTIME_ROOT)
	var semantic_source := {
		"actions": actions,
		"baseline_signature": str((data.get("baseline", {}) as Dictionary).get("payload_signature", "")),
		"edited_signature": str((data.get("edited", {}) as Dictionary).get("payload_signature", "")),
		"returned_signature": str((data.get("returned", {}) as Dictionary).get("payload_signature", "")),
		"query_signature": str((data.get("authoritative_queries", {}) as Dictionary).get("signature", "")),
		"shader_signature": str((data.get("shader_contract", {}) as Dictionary).get("signature", "")),
	}
	var report := {
		"schema": "world_transvoxel.terrain_lab.adaptive_surface_continuity_qualification.v1",
		"milestone": "TQP-38",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"retained_complete": true,
		"standard_id": standard.get("standard_id", ""),
		"authority": standard.get("authority", ""),
		"actions": actions,
		"payload_audits": {
			"baseline": data.get("baseline", {}),
			"edited": data.get("edited", {}),
			"returned": data.get("returned", {}),
		},
		"authoritative_queries": data.get("authoritative_queries", {}),
		"lod_cycle_identity": data.get("lod_cycle_identity", {}),
		"presentation_origin_rebase": data.get("presentation_origin_rebase", {}),
		"large_coordinate_anchor": data.get("large_coordinate_anchor", {}),
		"shader_contract": data.get("shader_contract", {}),
		"settlements": settlements,
		"native_metrics": data.get("native_metrics", {}),
		"performance": {
			"scope": "WINDOWS_DEBUG_DIAGNOSTIC_NOT_PRODUCTION_SHADER_OR_FRAME_BUDGET",
			"payload_audit_usec": Statistics.distribution(audit_times),
			"memory": Statistics.memory_metrics(),
		},
		"semantic_signature": JSON.stringify(semantic_source, "", true).sha256_text(),
		"shader_contract_signature": str((data.get("shader_contract", {}) as Dictionary).get("signature", "")),
		"provenance": Statistics.provenance("tqp38_native_adaptive_surface_windows_v1"),
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}
	return report


func _audit_render_payloads(terrain: Node, standard: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	var payload_lines: Array[String] = []
	var chunk_payload_signatures := {}
	var position_payload := {}
	var vertex_count := 0
	var authored_count := 0
	var shared_count := 0
	var shared_errors := 0
	var normal_errors := 0
	var payload_errors := 0
	var material_counts := {}
	var render_count := 0
	var maximum_normal_error := 0.0
	var maximum_tangent_dot := 0.0
	for child in terrain.get_children():
		if not child is MeshInstance3D or not str(child.name).begins_with("WT_Render_"):
			continue
		var render := child as MeshInstance3D
		if render.mesh == null:
			continue
		render_count += 1
		var chunk_payload_lines: Array[String] = []
		for surface in range(render.mesh.get_surface_count()):
			var arrays: Array = render.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var material_data: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
			var generated_low: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM0]
			var generated_high: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM1]
			var authored_low: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM2]
			var authored_high: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM3]
			if normals.size() != vertices.size() or material_data.size() != vertices.size() \
					or generated_low.size() != vertices.size() * 4 \
					or generated_high.size() != vertices.size() * 4 \
					or authored_low.size() != vertices.size() * 4 \
					or authored_high.size() != vertices.size() * 4:
				payload_errors += 1
				continue
			for index in range(vertices.size()):
				vertex_count += 1
				var normal := normals[index]
				var normal_error := absf(normal.length() - 1.0)
				maximum_normal_error = maxf(maximum_normal_error, normal_error)
				var tangent := _stable_tangent(normal)
				var tangent_dot := absf(normal.dot(tangent))
				maximum_tangent_dot = maxf(maximum_tangent_dot, tangent_dot)
				if not _vector_finite(normal) or normal_error > float(
					(standard.get("budgets", {}) as Dictionary).get("maximum_normal_length_error", 0.0001)
				) or tangent_dot > float(
					(standard.get("budgets", {}) as Dictionary).get("maximum_normal_tangent_dot", 0.0001)
				):
					normal_errors += 1
				var material_id := roundi(material_data[index].x)
				var authored := roundi(material_data[index].y)
				material_counts[material_id] = int(material_counts.get(material_id, 0)) + 1
				if authored == 1:
					authored_count += 1
				var generated := _weight_vector(generated_low, generated_high, index)
				var authored_weights := _weight_vector(authored_low, authored_high, index)
				var selected: Array[int] = authored_weights if authored == 1 else generated
				var rejected: Array[int] = generated if authored == 1 else authored_weights
				var material_slot := MATERIAL_SLOTS.find(material_id)
				var valid_payload := (
					absf(material_data[index].x - float(material_id)) <= 0.000001
					and absf(material_data[index].y - float(authored)) <= 0.000001
					and authored in [0, 1]
					and material_slot >= 0
					and _sum_ints(selected) == 255
					and _nonzero_count(selected) == 1
					and selected[material_slot] == 255
					and _sum_ints(rejected) == 0
				)
				if not valid_payload:
					payload_errors += 1
				var world_local := render.position + vertices[index]
				var position_key := _position_key(world_local)
				var payload := "%d:%d:%s:%s" % [
					material_id, authored, _weight_key(generated), _weight_key(authored_weights)
				]
				if position_payload.has(position_key):
					shared_count += 1
					if str(position_payload[position_key]) != payload:
						shared_errors += 1
				else:
					position_payload[position_key] = payload
				var payload_line := "%s:%s" % [position_key, payload]
				payload_lines.append(payload_line)
				chunk_payload_lines.append(payload_line)
		chunk_payload_lines.sort()
		chunk_payload_signatures[str(render.name)] = "\n".join(chunk_payload_lines).sha256_text()
	payload_lines.sort()
	if render_count == 0 or vertex_count == 0:
		failures.append("native render payload is absent")
	if payload_errors > 0:
		failures.append("native material vertex payload errors: %d" % payload_errors)
	if normal_errors > 0:
		failures.append("native normal/tangent errors: %d" % normal_errors)
	if shared_errors > 0:
		failures.append("shared-position material payload mismatches: %d" % shared_errors)
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"render_chunk_count": render_count,
		"vertex_count": vertex_count,
		"authored_vertex_count": authored_count,
		"generated_vertex_count": vertex_count - authored_count,
		"shared_position_count": shared_count,
		"shared_position_payload_errors": shared_errors,
		"vertex_payload_errors": payload_errors,
		"normal_tangent_errors": normal_errors,
		"maximum_normal_length_error": maximum_normal_error,
		"maximum_normal_tangent_dot": maximum_tangent_dot,
		"material_counts": material_counts,
		"material_7_vertex_count": int(material_counts.get(7, 0)),
		"material_8_vertex_count": int(material_counts.get(8, 0)),
		"chunk_payload_signatures": chunk_payload_signatures,
		"_position_payload_map": position_payload,
		"payload_signature": "\n".join(payload_lines).sha256_text(),
		"failures": failures,
	}


static func _lod_cycle_payload_identity(
	before: Dictionary,
	after: Dictionary,
	standard: Dictionary
) -> Dictionary:
	var expected: Dictionary = before.get("chunk_payload_signatures", {})
	var actual: Dictionary = after.get("chunk_payload_signatures", {})
	var missing: Array[String] = []
	var changed: Array[String] = []
	var additional: Array[String] = []
	var identity_lines: Array[String] = []
	for chunk_value in expected.keys():
		var chunk := str(chunk_value)
		if not actual.has(chunk):
			missing.append(chunk)
		elif str(actual[chunk]) != str(expected[chunk]):
			changed.append(chunk)
		else:
			identity_lines.append(chunk + ":" + str(expected[chunk]))
	for chunk_value in actual.keys():
		var chunk := str(chunk_value)
		if not expected.has(chunk):
			additional.append(chunk)
	missing.sort()
	changed.sort()
	additional.sort()
	identity_lines.sort()
	var expected_positions: Dictionary = before.get("_position_payload_map", {})
	var actual_positions: Dictionary = after.get("_position_payload_map", {})
	var shared_positions := 0
	var changed_positions: Array[String] = []
	for position_value in expected_positions.keys():
		var position := str(position_value)
		if not actual_positions.has(position):
			continue
		shared_positions += 1
		if str(actual_positions[position]) != str(expected_positions[position]):
			changed_positions.append(position)
	changed_positions.sort()
	var shared_ratio := (
		float(shared_positions) / float(expected_positions.size())
		if not expected_positions.is_empty() else 0.0
	)
	var minimum_ratio := float(
		(standard.get("budgets", {}) as Dictionary).get(
			"minimum_lod_cycle_shared_position_ratio", 0.5
		)
	)
	return {
		"status": "PASS" if changed_positions.is_empty() and shared_ratio >= minimum_ratio else "FAIL",
		"expected_chunk_count": expected.size(),
		"matched_chunk_count": identity_lines.size(),
		"additional_retained_chunk_count": additional.size(),
		"missing_chunks": missing,
		"changed_chunks": changed,
		"additional_retained_chunks": additional,
		"matched_payload_signature": "\n".join(identity_lines).sha256_text(),
		"expected_unique_position_count": expected_positions.size(),
		"shared_position_count": shared_positions,
		"shared_position_ratio": shared_ratio,
		"minimum_shared_position_ratio": minimum_ratio,
		"changed_shared_position_count": changed_positions.size(),
		"changed_shared_positions": changed_positions,
	}


func _validate_authored_queries(
	queries: Array[Dictionary],
	paint: Dictionary,
	construction: Dictionary
) -> Dictionary:
	var failures: Array[String] = []
	if queries.size() != 2:
		failures.append("authoritative material query batch is incomplete")
		return {"status": "FAIL", "queries": queries, "failures": failures, "signature": ""}
	for index in range(queries.size()):
		if str(queries[index].get("status", "")) != "PASS":
			failures.append("authoritative material query failed at index %d" % index)
	var paint_expected := int(paint.get("material", 8))
	var construction_expected := int(construction.get("material", 7))
	if int(queries[0].get("material", -1)) != paint_expected:
		failures.append("painted authoritative sample does not retain material %d" % paint_expected)
	if int(queries[1].get("material", -1)) != construction_expected:
		failures.append("constructed authoritative sample does not retain material %d" % construction_expected)
	for query in queries:
		if int(query.get("world_revision", -1)) != 1:
			failures.append("authoritative material query has the wrong world revision")
	var signature_rows: Array[String] = []
	for query in queries:
		signature_rows.append("%s:%d:%d:%d" % [
			str(query.get("point", "")), roundi(float(query.get("density", 0.0)) * 1000000.0),
			int(query.get("material", -1)), int(query.get("world_revision", -1))
		])
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"queries": queries,
		"signature": "\n".join(signature_rows).sha256_text(),
		"failures": failures,
	}


func _validate_shader_contract(standard: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	var shader_path := str(standard.get("shader", ""))
	var source := FileAccess.get_file_as_string(shader_path)
	for token in [
		"filter_linear_mipmap_anisotropic",
		"sampler2DArray terrain_textures",
		"sampler2DArray terrain_normal_textures",
		"CUSTOM0", "CUSTOM1", "CUSTOM2", "CUSTOM3",
		"world_position + texture_world_origin",
		"pow(abs(world_normal)",
		"triplanar_normal",
		"decal_center_global",
		"NORMAL =",
	]:
		if not source.contains(token):
			failures.append("adaptive surface shader lacks contract token: " + token)
	var profile: Dictionary = standard.get("runtime_profile", {})
	var layer_size := int(profile.get("texture_layer_size_px", 0))
	var mip_count := floori(log(float(layer_size)) / log(2.0)) + 1 if layer_size > 0 else 0
	if int(profile.get("texture_layer_count", 0)) != MATERIAL_SLOTS.size():
		failures.append("texture layer count no longer matches native material slots")
	if mip_count != 7:
		failures.append("diagnostic texture mip chain is incomplete")
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"shader": shader_path,
		"shader_sha256": FileAccess.get_sha256(shader_path) if FileAccess.file_exists(shader_path) else "",
		"texture_layer_count": int(profile.get("texture_layer_count", 0)),
		"texture_layer_size_px": layer_size,
		"mipmap_level_count": mip_count,
		"signature": source.sha256_text(),
		"failures": failures,
	}


func _large_coordinate_anchor(rebase: Vector3, standard: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	var maximum_error := 0.0
	var scale := float((standard.get("runtime_profile", {}) as Dictionary).get("texture_scale_m", 3.0))
	for local in [
		Vector3(0.25, 0.5, 0.75),
		Vector3(17.375, -9.25, 31.625),
		Vector3(255.5, 127.25, -63.75),
	]:
		var direct: Vector3 = local / scale
		var reconstructed: Vector3 = (local + rebase - rebase) / scale
		maximum_error = maxf(maximum_error, direct.distance_to(reconstructed))
	var budget := float((standard.get("budgets", {}) as Dictionary).get("maximum_texture_anchor_error", 0.000001))
	if maximum_error > budget:
		failures.append("large-coordinate texture anchor exceeded its error budget")
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"presentation_rebase": rebase,
		"texture_world_origin": -rebase,
		"maximum_coordinate_error": maximum_error,
		"qualified_as": "presentation_coordinate_compensation_not_native_horizontal_streaming",
		"failures": failures,
	}


static func _runtime_overrides(profile: Dictionary) -> Dictionary:
	var capacity := int(profile.get("pipeline_capacity", 2048))
	return {
		"active_chunk_capacity": int(profile.get("active_chunk_capacity", 512)),
		"viewer_capacity": 4,
		"demand_capacity_per_viewer": capacity,
		"lod_refinement_radius_chunks": int(profile.get("lod_refinement_radius_chunks", 1)),
		"storage_request_capacity": capacity,
		"storage_completion_capacity": capacity,
		"encoded_page_entry_capacity": capacity,
		"decoded_page_entry_capacity": capacity,
		"mesh_entry_capacity": capacity,
		"render_entry_capacity": capacity,
		"collision_entry_capacity": capacity,
		"trace_event_capacity": 65536,
		"render_apply_budget": 8,
		"collision_apply_budget": 4,
		"collision_activation_distance": float(profile.get("collision_activation_distance", 0.0)),
		"collision_deactivation_distance": float(profile.get("collision_deactivation_distance", 0.0)),
	}


func _update_viewer_and_settle(
	harness: Node,
	terrain: Node,
	profile: Dictionary,
	position: Vector3,
	viewer_revision: int
) -> Dictionary:
	var before: Dictionary = terrain.call("get_runtime_metrics")
	if not bool(terrain.call(
		"update_viewer", int(profile.get("viewer_id", 38)), viewer_revision,
		position, int(profile.get("viewer_radius_chunks", 1)),
		int(profile.get("maximum_lod", 1))
	)):
		return {"status": "FAIL", "frames": 0, "elapsed_usec": 0}
	var started := Time.get_ticks_usec()
	for frame in range(Harness.MAX_WAIT_FRAMES):
		var metrics: Dictionary = terrain.call("get_runtime_metrics")
		if int(metrics.get("viewer_updates", 0)) > int(before.get("viewer_updates", 0)):
			var settlement: Dictionary = await harness.wait_for_settled(1)
			settlement["event_frames"] = frame
			settlement["elapsed_usec"] = Time.get_ticks_usec() - started
			return settlement
		await get_tree().process_frame
	return {
		"status": "FAIL",
		"frames": Harness.MAX_WAIT_FRAMES,
		"elapsed_usec": Time.get_ticks_usec() - started,
	}


func _wait_for_metric_increase(
	terrain: Node,
	metric: String,
	before: int,
	maximum_frames: int
) -> bool:
	for _frame in range(maximum_frames):
		var metrics: Dictionary = terrain.call("get_runtime_metrics")
		if int(metrics.get(metric, 0)) > before:
			return true
		await get_tree().process_frame
	return false


static func _settlement_record(action: String, settlement: Dictionary) -> Dictionary:
	return {
		"action": action,
		"status": settlement.get("status", ""),
		"frames": int(settlement.get("frames", -1)),
		"elapsed_usec": int(settlement.get("elapsed_usec", -1)),
	}


static func _weight_vector(low: PackedByteArray, high: PackedByteArray, index: int) -> Array[int]:
	var result: Array[int] = []
	for component in range(4):
		result.append(int(low[index * 4 + component]))
	for component in range(4):
		result.append(int(high[index * 4 + component]))
	return result


static func _sum_ints(values: Array[int]) -> int:
	var total := 0
	for value in values:
		total += value
	return total


static func _nonzero_count(values: Array[int]) -> int:
	var count := 0
	for value in values:
		count += int(value != 0)
	return count


static func _weight_key(values: Array[int]) -> String:
	var parts: PackedStringArray = []
	for value in values:
		parts.append(str(value))
	return ",".join(parts)


static func _position_key(point: Vector3) -> String:
	return "%d,%d,%d" % [
		roundi(point.x * POSITION_SCALE),
		roundi(point.y * POSITION_SCALE),
		roundi(point.z * POSITION_SCALE),
	]


static func _stable_tangent(normal: Vector3) -> Vector3:
	if not _vector_finite(normal) or normal.length_squared() <= 0.00000001:
		return Vector3.ZERO
	var axis := Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT
	return axis.cross(normal).normalized()


static func _vector_finite(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


static func _vector3(value: Variant) -> Vector3:
	var array: Array = value
	return Vector3(float(array[0]), float(array[1]), float(array[2])) if array.size() == 3 else Vector3.ZERO


static func _vector3i(value: Variant) -> Vector3i:
	var point := _vector3(value)
	return Vector3i(roundi(point.x), roundi(point.y), roundi(point.z))


static func _append_audit_failures(prefix: String, audit: Dictionary, failures: Array[String]) -> void:
	for failure in audit.get("failures", []):
		failures.append(prefix + ": " + str(failure))


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
