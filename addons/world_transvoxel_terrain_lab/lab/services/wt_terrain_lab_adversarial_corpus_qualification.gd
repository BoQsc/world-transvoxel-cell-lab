@tool
extends RefCounted
class_name WtTerrainLabAdversarialCorpusQualification

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)
const NativeAdapter := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_mesh_adapter.gd"
)
const Oracle := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_independent_oracle.gd"
)
const AdversarialField := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_adversarial_field.gd"
)
const EditField := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_edit_field.gd"
)
const NativeField := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_field.gd"
)
const TransitionField := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_transition_field.gd"
)

const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/adversarial_corpus_standard.json"
)
const REPLAY_ORDERS := [
	"cold_canonical",
	"warm_canonical",
	"worker_reverse",
	"worker_seeded",
]
const ALL_FACES := [
	"negative_x", "positive_x", "negative_y", "positive_y",
	"negative_z", "positive_z",
]


static func run(case_filter: String = "", enforce_stable: bool = true) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var failures: Array[String] = []
	var contract_validation := _validate_contract(standard)
	if str(contract_validation.get("status", "")) != "PASS":
		failures.append_array(contract_validation.get("failures", []))
	var probe := NativeAdapter.create_probe()
	if probe == null:
		failures.append(
			"WorldTransvoxelCellProbe is unavailable; fallback geometry is forbidden"
		)
	var case_results: Array[Dictionary] = []
	var case_times: Array[float] = []
	var replay_times: Array[float] = []
	var oracle_times: Array[float] = []
	var matrix_lines: Array[String] = []
	var coverage := _empty_coverage()
	var minimizer_source_mesh := {}
	var minimizer_source_contract := {}
	if probe != null:
		for case_value in standard.get("cases", []):
			var definition: Dictionary = case_value
			if not case_filter.is_empty() and str(definition.get("id", "")) != case_filter:
				continue
			var case_probe := NativeAdapter.create_probe()
			if case_probe == null:
				failures.append(
					"WorldTransvoxelCellProbe became unavailable during corpus execution"
				)
				break
			var result := _qualify_case(
				case_probe, definition, standard, enforce_stable
			)
			case_results.append(result)
			case_times.append(float(result.get("elapsed_usec", 0.0)))
			for replay_value in result.get("replays", []):
				var replay: Dictionary = replay_value
				replay_times.append(float(replay.get("elapsed_usec", 0.0)))
				oracle_times.append(float(replay.get("oracle_elapsed_usec", 0.0)))
			matrix_lines.append(
				str(result.get("case_id", "")) + ":"
				+ str(result.get("geometry_signature", "")) + ":"
				+ str(result.get("definition_signature", "")) + ":"
				+ str(result.get("case_definition_signature", ""))
			)
			_accumulate_coverage(coverage, definition, result)
			if str(result.get("status", "")) != "PASS":
				failures.append(
					"case %s failed: %s"
					% [str(result.get("case_id", "")), str(result.get("failures", []))]
				)
			if minimizer_source_mesh.is_empty() \
					and str(result.get("status", "")) == "PASS":
				minimizer_source_mesh = result.get("_canonical_mesh", {})
				minimizer_source_contract = result.get("_runtime_contract", {})
	var complete := case_filter.is_empty()
	var minimizer := {
		"status": "NOT_RUN",
		"designated_check": "duplicate_overlap",
		"failures": [],
	}
	if complete and not minimizer_source_mesh.is_empty():
		minimizer = _minimizer_control(
			minimizer_source_mesh,
			minimizer_source_contract
		)
		if str(minimizer.get("status", "")) != "PASS":
			failures.append_array(minimizer.get("failures", []))
	matrix_lines.sort()
	var matrix_signature := "\n".join(matrix_lines).sha256_text()
	var budgets: Dictionary = standard.get("budgets", {})
	if complete:
		_validate_coverage(coverage, case_results, budgets, failures)
		var expected: Dictionary = standard.get("stable_expected", {})
		var expected_matrix := str(expected.get("matrix_signature", ""))
		if enforce_stable and not expected_matrix.is_empty() \
				and matrix_signature != expected_matrix:
			failures.append("adversarial corpus matrix signature changed")
		var expected_minimized := str(expected.get("minimized_fixture_signature", ""))
		if enforce_stable and not expected_minimized.is_empty() and str(
			minimizer.get("fixture_signature", "")
		) != expected_minimized:
			failures.append("retained minimized failure fixture changed")
	var case_distribution := Statistics.distribution(case_times)
	var replay_distribution := Statistics.distribution(replay_times)
	var oracle_distribution := Statistics.distribution(oracle_times)
	if complete and float(case_distribution.get("p95_usec", INF)) > float(
		budgets.get("maximum_case_p95_usec", 0)
	):
		failures.append("adversarial corpus case p95 exceeded")
	if complete and float(oracle_distribution.get("p95_usec", INF)) > float(
		budgets.get("maximum_oracle_p95_usec", 0)
	):
		failures.append("adversarial corpus oracle p95 exceeded")
	var elapsed_usec := Time.get_ticks_usec() - started_usec
	if complete and elapsed_usec > int(budgets.get("maximum_total_usec", 0)):
		failures.append("TQP-34 total duration exceeded")
	for result in case_results:
		result.erase("_canonical_mesh")
		result.erase("_runtime_contract")
	return {
		"schema": "world_transvoxel.terrain_lab.adversarial_corpus_qualification.v1",
		"standard_id": standard.get("standard_id", ""),
		"authority": standard.get("authority", ""),
		"milestone": "TQP-34",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"retained_complete": complete,
		"contract": contract_validation,
		"cases": case_results,
		"coverage": coverage,
		"minimizer_control": minimizer,
		"matrix_signature": matrix_signature,
		"performance": {
			"profile": "debug_regression_reference_not_production_budget",
			"case_distribution": case_distribution,
			"replay_distribution": replay_distribution,
			"oracle_distribution": oracle_distribution,
			"minimizer_elapsed_usec": minimizer.get("elapsed_usec", 0),
			"elapsed_usec": elapsed_usec,
			"memory": Statistics.memory_metrics(),
		},
		"provenance": Statistics.provenance(matrix_signature),
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get(
			"explicitly_unqualified_scope", []
		),
		"failures": failures,
	}


static func inspect_case(
	case_id: String,
	replay_order: String = "cold_canonical",
	seed_override: int = 0
) -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var definition := {}
	for value in standard.get("cases", []):
		var candidate: Dictionary = value
		if str(candidate.get("id", "")) == case_id:
			definition = candidate.duplicate(true)
			break
	if definition.is_empty():
		return {"status": "FAIL", "failures": ["unknown adversarial case"]}
	if seed_override != 0 and str(definition.get("source", "")).begins_with(
		"adversarial_"
	):
		definition["seed"] = seed_override
	var probe := NativeAdapter.create_probe()
	if probe == null:
		return {"status": "FAIL", "failures": ["native dependency unavailable"]}
	var replay := _run_replay(probe, definition, replay_order)
	return {
		"status": replay.get("status", ""),
		"case_id": case_id,
		"seed": definition.get("seed", 0),
		"traversal_seed": definition.get(
			"traversal_seed", definition.get("seed", 1)
		),
		"replay_order": replay_order,
		"mesh": replay.get("mesh", {}),
		"oracle": replay.get("oracle", {}),
		"geometry_signature": replay.get("geometry_signature", ""),
		"native_chunk_call_count": replay.get("native_chunk_call_count", 0),
		"material_ids": replay.get("material_ids", []),
		"failures": replay.get("failures", []),
	}


static func replay_minimized_fixture(fixture: Dictionary) -> Dictionary:
	var vertices := PackedVector3Array()
	for point_value in fixture.get("vertices", []):
		vertices.append(_vector3(point_value))
	var indices := PackedInt32Array()
	for index_value in fixture.get("indices", []):
		indices.append(int(index_value))
	var mesh := {
		"reference_origin": Vector3.ZERO,
		"vertices": vertices,
		"indices": indices,
	}
	var contract := _runtime_contract(fixture.get("oracle_contract", {}), null)
	var result := Oracle.analyze(mesh, contract)
	var designated: Dictionary = (result.get("checks", {}) as Dictionary).get(
		str(fixture.get("designated_check", "")), {}
	)
	return {
		"status": "PASS" if str(designated.get("status", "")) == "FAIL" else "FAIL",
		"oracle_status": result.get("status", ""),
		"designated_check_result": designated,
		"fixture_signature": NativeAdapter.mesh_signature(vertices, indices),
	}


static func _validate_contract(standard: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	var checks: Array[Dictionary] = []
	var contract: Dictionary = standard.get("contract", {})
	_check(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.adversarial_corpus_standard.v1",
		"standard_schema",
		"adversarial corpus standard schema changed",
		checks,
		failures
	)
	_check(
		str(contract.get("native_dependency", "")) == "WorldTransvoxelCellProbe",
		"native_authority",
		"adversarial corpus native authority changed",
		checks,
		failures
	)
	_check(
		str(contract.get("fallback_geometry", "")) == "forbidden",
		"no_fallback",
		"fallback geometry is not forbidden",
		checks,
		failures
	)
	_check(
		contract.get("replay_orders", []) == REPLAY_ORDERS,
		"replay_inventory",
		"cold/warm or worker completion replay inventory changed",
		checks,
		failures
	)
	_check(
		str(contract.get("cold_warm_scope", ""))
			== "first and immediate repeated canonical replay on a fresh per-case probe; correctness lanes rather than hardware-cache isolation",
		"cold_warm_scope",
		"TQP-34 cold/warm replay scope is ambiguous",
		checks,
		failures
	)
	_check(
		str(contract.get("oracle", ""))
			== "TQP-33 independent triangle-soup oracle",
		"independent_oracle",
		"TQP-34 does not require the TQP-33 independent oracle",
		checks,
		failures
	)
	_check(
		str(contract.get("worker_order_scope", ""))
			== "serialized_completion_publication_permutations_not_concurrent_execution",
		"worker_order_scope",
		"TQP-34 worker-order claim is ambiguous",
		checks,
		failures
	)
	var regression_ids := {}
	var all_regressions_have_decisions := true
	for regression_value in standard.get("regression_registry", []):
		var regression: Dictionary = regression_value
		var decision_id := str(regression.get("decision_id", ""))
		regression_ids[decision_id] = true
		all_regressions_have_decisions = all_regressions_have_decisions and FileAccess.file_exists(
			str(regression.get("decision", ""))
		)
	_check(
		regression_ids.keys().size() == 3
			and regression_ids.has("TQP-D011")
			and regression_ids.has("TQP-D018")
			and regression_ids.has("TQP-D019")
			and all_regressions_have_decisions,
		"regression_registry",
		"corrected terrain regression registry is incomplete",
		checks,
		failures
	)
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"checks": checks,
		"failures": failures,
	}


static func _qualify_case(
	probe: RefCounted,
	definition: Dictionary,
	standard: Dictionary,
	enforce_stable: bool
) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var failures: Array[String] = []
	var replay_results: Array[Dictionary] = []
	var replay_signatures := {}
	var canonical_mesh := {}
	var runtime_contract := {}
	var definition_signature := ""
	var material_ids := {}
	var exact_hits := 0
	var native_chunk_calls := 0
	for replay_order in REPLAY_ORDERS:
		var replay := _run_replay(probe, definition, replay_order)
		replay_results.append(replay)
		replay_signatures[replay_order] = replay.get("geometry_signature", "")
		native_chunk_calls += int(replay.get("native_chunk_call_count", 0))
		definition_signature = str(replay.get("definition_signature", ""))
		exact_hits += int((replay.get("field_audit", {}) as Dictionary).get(
			"exact_isovalue_hit_count", 0
		))
		for material_value in replay.get("material_ids", []):
			material_ids[int(material_value)] = true
		if str(replay.get("status", "")) != "PASS":
			failures.append(
				"%s replay failed: %s"
				% [replay_order, str(replay.get("failures", []))]
			)
		if replay_order == "cold_canonical":
			canonical_mesh = replay.get("mesh", {})
			runtime_contract = replay.get("runtime_contract", {})
	var canonical_signature := str(replay_signatures.get("cold_canonical", ""))
	for replay_order in REPLAY_ORDERS:
		if str(replay_signatures.get(replay_order, "")) != canonical_signature:
			failures.append("native geometry differs under " + replay_order)
	var expected_cases: Dictionary = (
		standard.get("stable_expected", {}) as Dictionary
	).get("cases", {})
	var expected_signature := str(expected_cases.get(str(definition.get("id", "")), ""))
	if enforce_stable and not expected_signature.is_empty() \
			and canonical_signature != expected_signature:
		failures.append("retained adversarial case geometry changed")
	var sorted_materials: Array = material_ids.keys()
	sorted_materials.sort()
	for replay in replay_results:
		replay.erase("mesh")
		replay.erase("runtime_contract")
	return {
		"case_id": definition.get("id", ""),
		"source": definition.get("source", ""),
		"seed": definition.get("seed", 0),
		"traversal_seed": definition.get(
			"traversal_seed", definition.get("seed", 1)
		),
		"field_profile": definition.get("field_profile", ""),
		"regression_decision": definition.get("regression_decision", ""),
		"status": "PASS" if failures.is_empty() else "FAIL",
		"geometry_signature": canonical_signature,
		"definition_signature": definition_signature,
		"case_definition_signature": JSON.stringify(definition).sha256_text(),
		"replay_signatures": replay_signatures,
		"replays": replay_results,
		"native_chunk_call_count": native_chunk_calls,
		"exact_isovalue_hit_count": exact_hits,
		"material_ids": sorted_materials,
		"minimized_repro": {
			"runner": "res://labs/terrain_lab/tools/run_adversarial_corpus_validation.gd",
			"arguments": ["--case", definition.get("id", "")],
			"seed": definition.get("seed", 0),
			"traversal_seed": definition.get(
				"traversal_seed", definition.get("seed", 1)
			),
		},
		"elapsed_usec": Time.get_ticks_usec() - started_usec,
		"_canonical_mesh": canonical_mesh,
		"_runtime_contract": runtime_contract,
		"failures": failures,
	}


static func _run_replay(
	probe: RefCounted,
	definition: Dictionary,
	replay_order: String
) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var failures: Array[String] = []
	var field := _create_field(definition)
	if field == null:
		return {
			"status": "FAIL",
			"replay_order": replay_order,
			"failures": ["field configuration failed"],
		}
	var requests := _requests(definition)
	if replay_order == "worker_reverse":
		requests.reverse()
	elif replay_order == "worker_seeded":
		requests = _seeded_permutation(
			requests,
			int(definition.get(
				"traversal_seed", definition.get("seed", 1)
			)) ^ 0x5f3759df
		)
	var chunks: Array[Dictionary] = []
	for request_value in requests:
		var request: Dictionary = request_value
		chunks.append(NativeAdapter.mesh_chunk(
			probe,
			field,
			request.get("coordinate", Vector3i.ZERO),
			int(request.get("lod", 0)),
			int(request.get("mask", 0))
		))
	var mesh := NativeAdapter.assemble(chunks, true)
	if str(mesh.get("status", "")) != "PASS":
		failures.append_array(mesh.get("failures", []))
	var runtime_contract := _runtime_contract(definition.get("oracle", {}), field)
	var oracle_started := Time.get_ticks_usec()
	var oracle_result := Oracle.analyze(mesh, runtime_contract)
	var oracle_elapsed := Time.get_ticks_usec() - oracle_started
	if str(oracle_result.get("status", "")) != "PASS":
		failures.append("independent oracle failed: " + str(oracle_result.get("failures", [])))
	var material_ids := {}
	for material_value in mesh.get("materials", PackedInt32Array()):
		var material_id := int(material_value)
		if material_id > 0:
			material_ids[material_id] = true
	var sorted_materials: Array = material_ids.keys()
	sorted_materials.sort()
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"replay_order": replay_order,
		"geometry_signature": mesh.get("geometry_signature", ""),
		"definition_signature": _field_definition_signature(field, definition),
		"native_chunk_call_count": chunks.size(),
		"oracle": oracle_result,
		"oracle_elapsed_usec": oracle_elapsed,
		"material_ids": sorted_materials,
		"field_audit": field.call("audit") if field.has_method("audit") else {},
		"mesh": mesh,
		"runtime_contract": runtime_contract,
		"elapsed_usec": Time.get_ticks_usec() - started_usec,
		"failures": failures,
	}


static func _create_field(definition: Dictionary) -> RefCounted:
	var source := str(definition.get("source", ""))
	if source in ["adversarial_uniform", "adversarial_transition"]:
		var field := AdversarialField.new()
		return field if field.configure(definition) else null
	if source == "canonical_tangent_edit":
		var edit := EditField.new()
		edit.terrain_profile = "observatory"
		edit.sample_scale_m = float(definition.get("sample_scale_m", 0.5))
		for operation_value in definition.get("operations", []):
			if not operation_value is Dictionary or not edit.add_operation(operation_value):
				return null
		return edit
	if source == "native_field":
		var native_field := NativeField.new()
		return native_field if native_field.configure(definition) else null
	if source == "transition_field":
		var transition := TransitionField.new()
		return transition if transition.configure(
			_vector3i(definition.get("coarse_coordinate", [])),
			int(definition.get("coarse_lod", 1)),
			str(definition.get("mode", "surface"))
		) else null
	return null


static func _requests(definition: Dictionary) -> Array[Dictionary]:
	var source := str(definition.get("source", ""))
	if source in [
		"adversarial_uniform", "canonical_tangent_edit", "native_field",
	]:
		var base := _vector3i(definition.get("chunk_base", [0, 0, 0]))
		var window := _vector3i(definition.get("window_chunks", [2, 2, 2]))
		var lod := int(definition.get("lod", 0))
		var result: Array[Dictionary] = []
		for z in range(window.z):
			for y in range(window.y):
				for x in range(window.x):
					result.append({
						"coordinate": base + Vector3i(x, y, z),
						"lod": lod,
						"mask": 0,
					})
		return result
	if source in ["adversarial_transition", "transition_field"]:
		var coarse := _vector3i(definition.get("coarse_coordinate", [0, 0, 0]))
		var coarse_lod := int(definition.get("coarse_lod", 1))
		var face := int(definition.get("face", 1))
		var transition_requests: Array[Dictionary] = [{
			"coordinate": coarse,
			"lod": coarse_lod,
			"mask": 1 << face,
		}]
		for coordinate in _fine_neighbor_coordinates(coarse, face):
			transition_requests.append({
				"coordinate": coordinate,
				"lod": coarse_lod - 1,
				"mask": 0,
			})
		return transition_requests
	return []


static func _runtime_contract(definition: Dictionary, field: RefCounted) -> Dictionary:
	var rays: Array[Dictionary] = []
	for ray_value in definition.get("ray_tests", []):
		var ray: Dictionary = ray_value
		rays.append({
			"id": ray.get("id", ""),
			"origin": _vector3(ray.get("origin", [])),
			"direction": _vector3(ray.get("direction", [])),
			"expected_parity": int(ray.get("expected_parity", 0)),
			"minimum_hit_count": int(ray.get("minimum_hit_count", 0)),
		})
	var contract := {
		"bounds_min": _vector3(definition.get("bounds_min", [])),
		"bounds_max": _vector3(definition.get("bounds_max", [])),
		"closed": bool(definition.get("closed", false)),
		"allowed_open_faces": definition.get("allowed_open_faces", []),
		"expected_euler_characteristic": definition.get(
			"expected_euler_characteristic"
		),
		"expected_signed_volume_sign": int(definition.get(
			"expected_signed_volume_sign", 0
		)),
		"minimum_abs_signed_volume": float(definition.get(
			"minimum_abs_signed_volume", 0.0
		)),
		"field_tolerance": float(definition.get("field_tolerance", 0.0313)),
		"field_sampler": Callable(field, "sample") if field != null else Callable(),
		"ray_tests": rays,
	}
	if definition.has("expected_component_count"):
		contract["expected_component_count"] = int(definition.get(
			"expected_component_count", 1
		))
	return contract


static func _minimizer_control(
	base_mesh: Dictionary,
	base_contract: Dictionary
) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var failures: Array[String] = []
	var source_indices: PackedInt32Array = base_mesh.get("indices", PackedInt32Array())
	var source_triangle_count := mini(24, int(source_indices.size() / 3))
	if source_triangle_count <= 0:
		return {
			"status": "FAIL",
			"failures": ["minimizer source mesh is empty"],
		}
	var control_indices := PackedInt32Array()
	for offset in range(source_triangle_count * 3):
		control_indices.append(source_indices[offset])
	for corner in range(3):
		control_indices.append(source_indices[corner])
	var control_mesh := NativeAdapter.clone_mesh(base_mesh)
	control_mesh["indices"] = control_indices
	var control_contract := {
		"bounds_min": base_contract.get("bounds_min", Vector3.ZERO),
		"bounds_max": base_contract.get("bounds_max", Vector3.ONE),
		"closed": false,
		"allowed_open_faces": ALL_FACES,
		"field_tolerance": 0.0313,
		"ray_tests": [],
	}
	var original_result := Oracle.analyze(control_mesh, control_contract)
	var original_detected := str((
		original_result.get("checks", {}) as Dictionary
	).get("duplicate_overlap", {}).get("status", "")) == "FAIL"
	if not original_detected:
		failures.append("injected duplicate was not detected before minimization")
	var minimized := _ddmin_triangles(
		control_mesh,
		control_contract,
		"duplicate_overlap"
	)
	var compact := _compact_mesh(minimized)
	var minimized_result := Oracle.analyze(compact, control_contract)
	var minimized_detected := str((
		minimized_result.get("checks", {}) as Dictionary
	).get("duplicate_overlap", {}).get("status", "")) == "FAIL"
	var replay_result := Oracle.analyze(compact, control_contract)
	var replay_detected := str((
		replay_result.get("checks", {}) as Dictionary
	).get("duplicate_overlap", {}).get("status", "")) == "FAIL"
	var vertices: PackedVector3Array = compact.get("vertices", PackedVector3Array())
	var indices: PackedInt32Array = compact.get("indices", PackedInt32Array())
	var fixture_signature := NativeAdapter.mesh_signature(vertices, indices)
	if int(indices.size() / 3) != 2:
		failures.append("delta debugger did not shrink duplicate failure to two triangles")
	if not minimized_detected or not replay_detected:
		failures.append("minimized duplicate failure is not stable under replay")
	var serialized_vertices: Array = []
	for vertex in vertices:
		serialized_vertices.append([vertex.x, vertex.y, vertex.z])
	var serialized_indices: Array[int] = []
	for index_value in indices:
		serialized_indices.append(index_value)
	var fixture := {
		"schema": "world_transvoxel.terrain_lab.minimized_mesh_failure.v1",
		"designated_check": "duplicate_overlap",
		"vertices": serialized_vertices,
		"indices": serialized_indices,
		"oracle_contract": {
			"bounds_min": _vector_array(control_contract.get("bounds_min", Vector3.ZERO)),
			"bounds_max": _vector_array(control_contract.get("bounds_max", Vector3.ONE)),
			"closed": false,
			"allowed_open_faces": ALL_FACES,
			"expected_euler_characteristic": null,
			"expected_signed_volume_sign": 0,
			"field_tolerance": 0.0313,
			"ray_tests": [],
		},
	}
	var replay_fixture := replay_minimized_fixture(fixture)
	if str(replay_fixture.get("status", "")) != "PASS" \
			or str(replay_fixture.get("fixture_signature", "")) != fixture_signature:
		failures.append("serialized minimized fixture does not replay identically")
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"designated_check": "duplicate_overlap",
		"injected_failure_detected": original_detected,
		"original_triangle_count": int(control_indices.size() / 3),
		"minimized_triangle_count": int(indices.size() / 3),
		"minimized_vertex_count": vertices.size(),
		"fixture_signature": fixture_signature,
		"replay_signature": replay_fixture.get("fixture_signature", ""),
		"fixture": fixture,
		"minimized_repro": {
			"runner": "res://labs/terrain_lab/tools/run_adversarial_corpus_validation.gd",
			"arguments": ["--replay-minimized"],
		},
		"elapsed_usec": Time.get_ticks_usec() - started_usec,
		"failures": failures,
	}


static func _ddmin_triangles(
	mesh: Dictionary,
	contract: Dictionary,
	check_id: String
) -> Dictionary:
	var indices: PackedInt32Array = mesh.get("indices", PackedInt32Array())
	var active: Array[int] = []
	for triangle_index in range(int(indices.size() / 3)):
		active.append(triangle_index)
	var granularity := 2
	while active.size() >= 2:
		var subset_size := ceili(float(active.size()) / float(granularity))
		var reduced := false
		for start in range(0, active.size(), subset_size):
			var removed := {}
			for index in range(start, mini(start + subset_size, active.size())):
				removed[active[index]] = true
			var complement: Array[int] = []
			for triangle_index in active:
				if not removed.has(triangle_index):
					complement.append(triangle_index)
			if complement.is_empty():
				continue
			var candidate := _triangle_subset_mesh(mesh, complement)
			var result := Oracle.analyze(candidate, contract)
			var check: Dictionary = (result.get("checks", {}) as Dictionary).get(
				check_id, {}
			)
			if str(check.get("status", "")) == "FAIL":
				active = complement
				granularity = maxi(2, granularity - 1)
				reduced = true
				break
		if reduced:
			continue
		if granularity >= active.size():
			break
		granularity = mini(active.size(), granularity * 2)
	return _triangle_subset_mesh(mesh, active)


static func _triangle_subset_mesh(mesh: Dictionary, triangle_ids: Array[int]) -> Dictionary:
	var source: PackedInt32Array = mesh.get("indices", PackedInt32Array())
	var result := NativeAdapter.clone_mesh(mesh)
	var subset := PackedInt32Array()
	for triangle_index in triangle_ids:
		var offset := triangle_index * 3
		if offset + 2 >= source.size():
			continue
		subset.append(source[offset])
		subset.append(source[offset + 1])
		subset.append(source[offset + 2])
	result["indices"] = subset
	return result


static func _compact_mesh(mesh: Dictionary) -> Dictionary:
	var source_vertices: PackedVector3Array = mesh.get("vertices", PackedVector3Array())
	var source_indices: PackedInt32Array = mesh.get("indices", PackedInt32Array())
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var remap := {}
	for source_index in source_indices:
		if not remap.has(source_index):
			remap[source_index] = vertices.size()
			vertices.append(source_vertices[source_index])
		indices.append(int(remap[source_index]))
	return {
		"reference_origin": Vector3.ZERO,
		"vertices": vertices,
		"indices": indices,
	}


static func _empty_coverage() -> Dictionary:
	return {
		"case_count": 0,
		"seeded_case_count": 0,
		"unique_seeds": [],
		"generated_field_profiles": [],
		"case_profiles": [],
		"lod_levels": [],
		"transition_faces": [],
		"coordinate_classes": [],
		"material_ids": [],
		"replay_orders": REPLAY_ORDERS.duplicate(),
		"replay_count": 0,
		"native_chunk_call_count": 0,
		"oracle_run_count": 0,
		"exact_isovalue_hit_count": 0,
		"regression_decisions": [],
	}


static func _accumulate_coverage(
	coverage: Dictionary,
	definition: Dictionary,
	result: Dictionary
) -> void:
	coverage["case_count"] = int(coverage.get("case_count", 0)) + 1
	var source := str(definition.get("source", ""))
	var seed := int(definition.get("seed", 0))
	if source.begins_with("adversarial_") and seed != 0:
		coverage["seeded_case_count"] = int(coverage.get("seeded_case_count", 0)) + 1
		_append_unique(coverage["unique_seeds"], seed)
	var profile := str(definition.get("field_profile", ""))
	if not profile.is_empty():
		_append_unique(coverage["case_profiles"], profile)
		if source.begins_with("adversarial_"):
			_append_unique(coverage["generated_field_profiles"], profile)
	if source in [
		"adversarial_transition", "transition_field",
	]:
		_append_unique(coverage["lod_levels"], int(definition.get("coarse_lod", 1)))
		_append_unique(coverage["lod_levels"], int(definition.get("coarse_lod", 1)) - 1)
		_append_unique(coverage["transition_faces"], int(definition.get("face", -1)))
	else:
		_append_unique(coverage["lod_levels"], int(definition.get("lod", 0)))
	var coordinate := _vector3i(definition.get(
		"coarse_coordinate",
		definition.get("chunk_base", [0, 0, 0])
	))
	_append_unique(
		coverage["coordinate_classes"],
		"million_grid" if maxi(abs(coordinate.x), maxi(abs(coordinate.y), abs(coordinate.z))) \
			>= 60000 else ("signed" if coordinate.x < 0 or coordinate.y < 0 \
			or coordinate.z < 0 else "nonnegative")
	)
	for material_id in result.get("material_ids", []):
		_append_unique(coverage["material_ids"], int(material_id))
	coverage["replay_count"] = int(coverage.get("replay_count", 0)) \
		+ (result.get("replays", []) as Array).size()
	coverage["oracle_run_count"] = int(coverage.get("oracle_run_count", 0)) \
		+ (result.get("replays", []) as Array).size()
	coverage["native_chunk_call_count"] = int(
		coverage.get("native_chunk_call_count", 0)
	) + int(result.get("native_chunk_call_count", 0))
	coverage["exact_isovalue_hit_count"] = int(
		coverage.get("exact_isovalue_hit_count", 0)
	) + int(result.get("exact_isovalue_hit_count", 0))
	var decision_id := str(definition.get("regression_decision", ""))
	if not decision_id.is_empty():
		_append_unique(coverage["regression_decisions"], decision_id)
	for key in [
		"unique_seeds", "generated_field_profiles", "case_profiles",
		"lod_levels", "transition_faces",
		"coordinate_classes", "material_ids", "regression_decisions",
	]:
		(coverage[key] as Array).sort()


static func _validate_coverage(
	coverage: Dictionary,
	case_results: Array[Dictionary],
	budgets: Dictionary,
	failures: Array[String]
) -> void:
	if int(coverage.get("case_count", 0)) < int(budgets.get("minimum_case_count", 0)):
		failures.append("adversarial corpus case coverage is incomplete")
	if (coverage.get("unique_seeds", []) as Array).size() < int(
		budgets.get("minimum_unique_seed_count", 0)
	):
		failures.append("adversarial corpus seed coverage is incomplete")
	if int(coverage.get("seeded_case_count", 0)) < int(
		budgets.get("minimum_seeded_case_count", 0)
	):
		failures.append("adversarial seeded-case coverage is incomplete")
	if (coverage.get("generated_field_profiles", []) as Array).size() < int(
		budgets.get("minimum_generated_field_profile_count", 0)
	):
		failures.append("adversarial field-parameter coverage is incomplete")
	if (coverage.get("case_profiles", []) as Array).size() < int(
		budgets.get("minimum_case_profile_count", 0)
	):
		failures.append("adversarial case-profile coverage is incomplete")
	if (coverage.get("lod_levels", []) as Array).size() < int(
		budgets.get("minimum_lod_level_count", 0)
	):
		failures.append("adversarial LOD coverage is incomplete")
	if (coverage.get("transition_faces", []) as Array).size() < int(
		budgets.get("minimum_transition_face_count", 0)
	):
		failures.append("adversarial transition-face coverage is incomplete")
	if (coverage.get("material_ids", []) as Array).size() < int(
		budgets.get("minimum_material_id_count", 0)
	):
		failures.append("adversarial material coverage is incomplete")
	if int(coverage.get("exact_isovalue_hit_count", 0)) <= 0:
		failures.append("adversarial corpus exercised no exact-isovalue samples")
	if "million_grid" not in coverage.get("coordinate_classes", []):
		failures.append("adversarial corpus lacks million-grid coordinates")
	if int(coverage.get("native_chunk_call_count", 0)) < int(
		budgets.get("minimum_native_chunk_call_count", 0)
	):
		failures.append("adversarial native-call coverage is incomplete")
	if int(coverage.get("replay_count", 0)) != case_results.size() * REPLAY_ORDERS.size():
		failures.append("adversarial replay matrix is incomplete")
	var regressions: Array = coverage.get("regression_decisions", [])
	for decision_id in ["TQP-D011", "TQP-D018", "TQP-D019"]:
		if decision_id not in regressions:
			failures.append("retained corrected regression is missing: " + decision_id)


static func _seeded_permutation(values: Array[Dictionary], seed: int) -> Array[Dictionary]:
	var result := values.duplicate(true)
	var state := seed & 0x7fffffff
	for index in range(result.size() - 1, 0, -1):
		state = (1103515245 * state + 12345) & 0x7fffffff
		var other := posmod(state, index + 1)
		var temporary: Dictionary = result[index]
		result[index] = result[other]
		result[other] = temporary
	return result


static func _field_definition_signature(
	field: RefCounted,
	definition: Dictionary
) -> String:
	if field.has_method("definition_signature"):
		return str(field.call("definition_signature"))
	if field.has_method("journal_signature"):
		return str(field.call("journal_signature"))
	return JSON.stringify(definition).sha256_text()


static func _fine_neighbor_coordinates(coarse: Vector3i, face: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var axis := 0 if face <= 1 else (1 if face <= 3 else 2)
	var positive := face in [1, 3, 5]
	var fixed := coarse[axis] * 2 + (2 if positive else -1)
	var variable_axes: Array[int] = []
	for candidate in range(3):
		if candidate != axis:
			variable_axes.append(candidate)
	for first in range(2):
		for second in range(2):
			var coordinate := coarse * 2
			coordinate[axis] = fixed
			coordinate[variable_axes[0]] += first
			coordinate[variable_axes[1]] += second
			result.append(coordinate)
	return result


static func _append_unique(values: Array, value: Variant) -> void:
	if value not in values:
		values.append(value)


static func _check(
	condition: bool,
	check_id: String,
	failure: String,
	checks: Array[Dictionary],
	failures: Array[String]
) -> void:
	checks.append({"id": check_id, "status": "PASS" if condition else "FAIL"})
	if not condition:
		failures.append(failure)


static func _vector_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


static func _vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


static func _vector3i(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() == 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i.ZERO
