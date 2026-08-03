@tool
extends RefCounted
class_name WtTerrainLabNativeFieldQualification

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const NativeField := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_native_field.gd"
)
const NativeEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_edit_native_evidence.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)

const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/native_field_standard.json"
)
const DENSITY_SCALE := 1000000.0


static func run(fixture_filter: String = "") -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var failures: Array[String] = []
	var contract := _qualify_contract(standard)
	if str(contract.get("status", "")) != "PASS":
		failures.append_array(contract.get("failures", []))
	var probe := NativeEvidence.create_probe()
	if probe == null:
		failures.append("WorldTransvoxelCellProbe is unavailable")
	var fixture_results: Array[Dictionary] = []
	var corpus_field_lines: Array[String] = []
	var corpus_geometry_lines: Array[String] = []
	var observed_features: Array[String] = []
	var fixture_samples_usec: Array[float] = []
	var native_chunk_count := 0
	var same_lod_seam_count := 0
	for fixture_value in standard.get("fixtures", []):
		if not fixture_value is Dictionary:
			failures.append("standard contains a non-dictionary fixture")
			continue
		var fixture: Dictionary = fixture_value
		if not fixture_filter.is_empty() and str(fixture.get("id", "")) != fixture_filter:
			continue
		var result := _qualify_fixture(probe, fixture)
		fixture_results.append(result)
		fixture_samples_usec.append(float(result.get("elapsed_usec", 0.0)))
		native_chunk_count += int(result.get("native_chunk_count", 0))
		same_lod_seam_count += int(result.get("seam_count", 0))
		corpus_field_lines.append(
			str(result.get("fixture_id", "")) + ":" + str(result.get("field_signature", ""))
		)
		corpus_geometry_lines.append(
			str(result.get("fixture_id", "")) + ":" + str(result.get("geometry_signature", ""))
		)
		for feature in result.get("features", []):
			if str(feature) not in observed_features:
				observed_features.append(str(feature))
		if str(result.get("status", "")) != "PASS":
			for failure in result.get("failures", []):
				failures.append(str(result.get("fixture_id", "")) + ": " + str(failure))
	if fixture_results.is_empty():
		failures.append("no fixtures matched the requested corpus")
	if fixture_filter.is_empty():
		for feature in standard.get("required_feature_inventory", []):
			if str(feature) not in observed_features:
				failures.append("missing required feature " + str(feature))
		var budgets: Dictionary = standard.get("budgets", {})
		if fixture_results.size() < int(budgets.get("minimum_fixture_count", 0)):
			failures.append("fixture count is below the standard minimum")
		if native_chunk_count < int(budgets.get("minimum_native_chunk_count", 0)):
			failures.append("native chunk count is below the standard minimum")
		if same_lod_seam_count < int(budgets.get("minimum_same_lod_seam_count", 0)):
			failures.append("same-LOD seam count is below the standard minimum")
	corpus_field_lines.sort()
	corpus_geometry_lines.sort()
	observed_features.sort()
	var corpus_field_signature := "\n".join(corpus_field_lines).sha256_text()
	var corpus_geometry_signature := "\n".join(corpus_geometry_lines).sha256_text()
	var elapsed_usec := Time.get_ticks_usec() - started_usec
	var maximum_total_usec := int(
		(standard.get("budgets", {}) as Dictionary).get("maximum_total_usec", 0)
	)
	if maximum_total_usec > 0 and elapsed_usec > maximum_total_usec:
		failures.append("qualification duration exceeded the debug reference ceiling")
	var fixture_distribution := Statistics.distribution(fixture_samples_usec)
	var maximum_fixture_p95_usec := float(
		(standard.get("budgets", {}) as Dictionary).get("maximum_fixture_p95_usec", 0.0)
	)
	if fixture_filter.is_empty() and float(fixture_distribution.get("p95_usec", INF)) \
			> maximum_fixture_p95_usec:
		failures.append("fixture p95 exceeded the debug reference ceiling")
	return {
		"schema": "world_transvoxel.terrain_lab.native_field_qualification.v1",
		"standard_id": standard.get("standard_id", ""),
		"authority": standard.get("authority", ""),
		"milestones": ["TQP-28", "TQP-29"],
		"status": "PASS" if failures.is_empty() else "FAIL",
		"retained_complete": fixture_filter.is_empty(),
		"fixture_filter": fixture_filter,
		"contract": contract,
		"corpus": {
			"fixture_count": fixture_results.size(),
			"native_chunk_count": native_chunk_count,
			"same_lod_seam_count": same_lod_seam_count,
			"observed_features": observed_features,
			"field_signature": corpus_field_signature,
			"geometry_signature": corpus_geometry_signature,
			"fixtures": fixture_results,
		},
		"performance": {
			"profile": "debug_regression_reference_not_production_budget",
			"elapsed_usec": elapsed_usec,
			"maximum_total_usec": maximum_total_usec,
			"fixture_distribution": fixture_distribution,
			"maximum_fixture_p95_usec": maximum_fixture_p95_usec,
		},
		"provenance": _provenance(
			corpus_field_signature + ":" + corpus_geometry_signature
		),
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


static func _qualify_contract(standard: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	var checks: Array[Dictionary] = []
	var contract: Dictionary = standard.get("contract", {})
	_check(
		str(contract.get("density_sign", "")) == "solid_negative_air_positive",
		"density_sign",
		"density sign contract changed",
		checks,
		failures
	)
	var slope := NativeField.new()
	_check(
		slope.configure({"id": "analytical_slope", "kind": "slope"}),
		"valid_configuration",
		"analytical slope configuration failed",
		checks,
		failures
	)
	_check(
		slope.density_local(Vector3(0.0, -2.0, 0.0)) < 0.0
			and is_zero_approx(slope.density_local(Vector3.ZERO))
			and slope.density_local(Vector3(0.0, 2.0, 0.0)) > 0.0,
		"analytical_sign_boundary",
		"analytical solid/boundary/air fixture failed",
		checks,
		failures
	)
	var origin_sample: Dictionary = slope.sample(slope.origin_grid)
	_check(
		int(origin_sample.get("material", -1)) == 0
			and not bool(origin_sample.get("material_authored", true)),
		"isovalue_ownership",
		"exact-isovalue ownership changed",
		checks,
		failures
	)
	_check(
		is_equal_approx(
			slope.density_grid(slope.origin_grid + Vector3i.UP)
				- slope.density_grid(slope.origin_grid),
			float(contract.get("sample_scale_m", -1.0))
		),
		"world_units",
		"integer grid to world metre scale changed",
		checks,
		failures
	)
	var expected_gradient := Vector3(-0.25, 1.0, 0.125).normalized()
	_check(
		slope.gradient_local(Vector3(1.5, 0.25, -2.0)).dot(expected_gradient) > 0.99999,
		"gradient",
		"finite-difference gradient disagrees with analytical slope",
		checks,
		failures
	)
	var mixed := NativeField.new()
	mixed.configure({"id": "mixed", "kind": "mixed_material"})
	_check(
		mixed.material_local(Vector3(-1.0, 0.0, 0.0), -1.0) == 1
			and mixed.material_local(Vector3(1.0, 0.0, 0.0), -1.0) == 2
			and mixed.material_local(Vector3(0.0, 2.0, 0.0), -1.0) == 3
			and mixed.material_local(Vector3.ZERO, 1.0) == 0,
		"material_sampling",
		"solid/air material sampling changed",
		checks,
		failures
	)
	_check(
		is_equal_approx(NativeField.interpolation_fraction(-1.0, 1.0), 0.5)
			and is_equal_approx(NativeField.interpolation_fraction(0.0, 1.0), 0.0)
			and is_equal_approx(NativeField.interpolation_fraction(-1.0, 0.0), 1.0)
			and is_equal_approx(NativeField.interpolation_fraction(2.0, 2.0), 0.5),
		"interpolation",
		"edge interpolation rules changed",
		checks,
		failures
	)
	var cave := NativeField.new()
	cave.configure({"id": "composition", "kind": "cave"})
	_check(
		cave.density_local(Vector3.ZERO) > 0.0
			and cave.density_local(Vector3(7.0, -2.0, 7.0)) < 0.0,
		"composition_order",
		"subtractive cave composition order changed",
		checks,
		failures
	)
	var ridge_a := NativeField.new()
	var ridge_b := NativeField.new()
	var ridge_c := NativeField.new()
	ridge_a.configure({"id": "seed_a", "kind": "ridge_valley", "seed": 211})
	ridge_b.configure({"id": "seed_b", "kind": "ridge_valley", "seed": 211})
	ridge_c.configure({"id": "seed_c", "kind": "ridge_valley", "seed": 212})
	var seed_a_signature := _field_signature(ridge_a, Vector3i(-8, -8, -8), Vector3i(8, 8, 8)).get("signature", "")
	var seed_b_signature := _field_signature(ridge_b, Vector3i(-8, -8, -8), Vector3i(8, 8, 8)).get("signature", "")
	var seed_c_signature := _field_signature(ridge_c, Vector3i(-8, -8, -8), Vector3i(8, 8, 8)).get("signature", "")
	_check(
		seed_a_signature == seed_b_signature and seed_a_signature != seed_c_signature,
		"deterministic_seed",
		"explicit seed determinism or distinction failed",
		checks,
		failures
	)
	var identity_point := slope.origin_grid + Vector3i(11, 7, 19)
	var identity_density := slope.density_grid(identity_point)
	var identity_ok := true
	for lod in range(4):
		var extent := NativeField.CHUNK_CELLS_PER_AXIS * (1 << lod)
		var chunk := Vector3i(
			floori(float(identity_point.x) / float(extent)),
			floori(float(identity_point.y) / float(extent)),
			floori(float(identity_point.z) / float(extent))
		)
		var local := identity_point - chunk * extent
		identity_ok = identity_ok and is_equal_approx(
			slope.density_grid(chunk * extent + local),
			identity_density
		)
	_check(
		identity_ok,
		"chunk_lod_sample_identity",
		"same integer world sample differs by chunk/LOD representation",
		checks,
		failures
	)
	var large := NativeField.new()
	large.configure({
		"id": "large",
		"kind": "large_coordinate",
		"chunk_base": [62500, 0, -62500],
		"window_chunks": [2, 2, 2],
	})
	var local_offset := Vector3i(13, -7, 21)
	_check(
		is_equal_approx(
			large.density_grid(large.origin_grid + local_offset),
			slope.density_grid(slope.origin_grid + local_offset)
		),
		"large_coordinate",
		"integer-local large-coordinate sampling lost identity",
		checks,
		failures
	)
	var frequency_ok := true
	for fixture_value in standard.get("fixtures", []):
		var fixture: Dictionary = fixture_value
		frequency_ok = frequency_ok and float(
			fixture.get("maximum_authored_periodic_frequency_cycles_per_m", INF)
		) <= float(contract.get("maximum_authored_periodic_frequency_cycles_per_m", -INF))
	_check(
		frequency_ok,
		"frequency_limits",
		"a fixture exceeds the declared authored periodic frequency limit",
		checks,
		failures
	)
	var feature_thickness_ok := true
	for fixture_value in standard.get("fixtures", []):
		var fixture: Dictionary = fixture_value
		if fixture.has("minimum_feature_thickness_m"):
			feature_thickness_ok = feature_thickness_ok and float(
				fixture.get("minimum_feature_thickness_m", 0.0)
			) >= float(contract.get("minimum_resolvable_feature_thickness_m", INF))
	_check(
		feature_thickness_ok,
		"feature_resolution_limits",
		"a retained thin feature is below the declared resolvable thickness",
		checks,
		failures
	)
	var invalid := NativeField.new()
	_check(
		not invalid.configure({"id": "negative_unknown", "kind": "unknown"})
			and not invalid.configure({"id": "negative_window", "kind": "slope", "window_chunks": [0, 2, 2]}),
		"negative_configuration",
		"invalid field configurations were accepted",
		checks,
		failures
	)
	return {
		"schema": "world_transvoxel.terrain_lab.native_field_contract_qualification.v1",
		"milestone": "TQP-28",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"checks": checks,
		"failures": failures,
	}


static func _qualify_fixture(probe: RefCounted, fixture: Dictionary) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var failures: Array[String] = []
	var field := NativeField.new()
	if not field.configure(fixture):
		return {
			"fixture_id": fixture.get("id", ""),
			"status": "FAIL",
			"elapsed_usec": Time.get_ticks_usec() - started_usec,
			"failures": ["field configuration failed"],
		}
	var window_min := field.chunk_base * NativeField.CHUNK_CELLS_PER_AXIS
	var window_max := window_min + field.window_chunks * NativeField.CHUNK_CELLS_PER_AXIS
	var field_evidence := _field_signature(field, window_min, window_max)
	var first_pass := _mesh_window(probe, field)
	var second_pass := _mesh_window(probe, field)
	if str(first_pass.get("status", "")) != "PASS":
		failures.append_array(first_pass.get("failures", []))
	if str(second_pass.get("status", "")) != "PASS":
		failures.append_array(second_pass.get("failures", []))
	if str(first_pass.get("geometry_signature", "")) != str(second_pass.get("geometry_signature", "")):
		failures.append("cold/warm native geometry signatures differ")
	var topology: Dictionary = first_pass.get("topology", {})
	if str(topology.get("status", "")) != "PASS":
		failures.append("assembled same-LOD window topology failed")
	var observed_materials: Array = first_pass.get("material_ids", [])
	for expected_material in fixture.get("expected_materials", []):
		if int(expected_material) not in observed_materials:
			failures.append("missing expected native material %d" % int(expected_material))
	if int(first_pass.get("triangle_count", 0)) <= 0:
		failures.append("fixture generated no native triangles")
	var resolvability := str(fixture.get("resolvability", ""))
	if resolvability not in ["pass", "degraded_but_present", "intentional_disappearance"]:
		failures.append("fixture lacks an explicit resolvability classification")
	return {
		"fixture_id": fixture.get("id", ""),
		"kind": fixture.get("kind", ""),
		"status": "PASS" if failures.is_empty() else "FAIL",
		"features": fixture.get("features", []),
		"resolvability": resolvability,
		"definition_signature": field.definition_signature(),
		"field_signature": field_evidence.get("signature", ""),
		"geometry_signature": first_pass.get("geometry_signature", ""),
		"warm_geometry_signature": second_pass.get("geometry_signature", ""),
		"sample_inventory": field_evidence.get("inventory", {}),
		"native_chunk_count": first_pass.get("chunk_count", 0),
		"triangle_count": first_pass.get("triangle_count", 0),
		"vertex_count": first_pass.get("vertex_count", 0),
		"material_ids": observed_materials,
		"seam_count": first_pass.get("seam_count", 0),
		"topology": topology,
		"elapsed_usec": Time.get_ticks_usec() - started_usec,
		"minimized_repro": {
			"runner": "res://labs/terrain_lab/tools/run_native_field_validation.gd",
			"arguments": ["--fixture", fixture.get("id", "")],
			"fixture": fixture,
			"lod": 0,
			"transition_mask": 0,
			"sample_scale_m": NativeField.SAMPLE_SCALE_M,
			"field_signature": field_evidence.get("signature", ""),
			"geometry_signature": first_pass.get("geometry_signature", ""),
		},
		"failures": failures,
	}


static func _mesh_window(probe: RefCounted, field: RefCounted) -> Dictionary:
	var failures: Array[String] = []
	var chunks: Array[Dictionary] = []
	var chunks_by_key := {}
	var geometry_lines: Array[String] = []
	var material_ids: Array[int] = []
	var triangle_count := 0
	var vertex_count := 0
	for z in range(field.window_chunks.z):
		for y in range(field.window_chunks.y):
			for x in range(field.window_chunks.x):
				var offset := Vector3i(x, y, z)
				var coordinate: Vector3i = field.chunk_base + offset
				var chunk := NativeEvidence.mesh_chunk(probe, field, coordinate, 0, 0)
				chunks.append(chunk)
				chunks_by_key[_coordinate_key(offset)] = chunk
				var validation := NativeEvidence.validate_chunk(chunk)
				if str(validation.get("status", "")) != "PASS":
					failures.append(
						"chunk %s failed: %s" % [coordinate, str(validation.get("failures", []))]
					)
				triangle_count += int(validation.get("triangle_count", 0))
				vertex_count += int(validation.get("vertex_count", 0))
				for material_id in validation.get("material_ids", []):
					if int(material_id) not in material_ids:
						material_ids.append(int(material_id))
				geometry_lines.append(
					_coordinate_key(offset) + ":" + NativeEvidence.chunk_signature(chunk)
				)
	var seam_count := 0
	for z in range(field.window_chunks.z):
		for y in range(field.window_chunks.y):
			for x in range(field.window_chunks.x):
				var offset := Vector3i(x, y, z)
				for axis in range(3):
					var neighbor := offset
					neighbor[axis] += 1
					if neighbor[axis] >= field.window_chunks[axis]:
						continue
					seam_count += 1
					var seam := NativeEvidence.same_lod_seam(
						chunks_by_key[_coordinate_key(offset)],
						chunks_by_key[_coordinate_key(neighbor)],
						axis
					)
					if str(seam.get("status", "")) != "PASS":
						failures.append(
							"seam %s axis %d failed: %s"
							% [offset, axis, str(seam.get("failures", []))]
						)
	var topology := NativeEvidence.same_lod_window_topology(chunks)
	if str(topology.get("status", "")) != "PASS":
		failures.append("window topology failed: " + str(topology.get("failures", [])))
	geometry_lines.sort()
	material_ids.sort()
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"chunk_count": chunks.size(),
		"seam_count": seam_count,
		"triangle_count": triangle_count,
		"vertex_count": vertex_count,
		"material_ids": material_ids,
		"geometry_signature": "\n".join(geometry_lines).sha256_text(),
		"topology": topology,
		"failures": failures,
	}


static func _field_signature(field: RefCounted, minimum: Vector3i, maximum: Vector3i) -> Dictionary:
	var lines: Array[String] = []
	var solid_samples := 0
	var air_samples := 0
	var boundary_samples := 0
	var material_ids: Array[int] = []
	var minimum_density := INF
	var maximum_density := -INF
	for z in range(minimum.z, maximum.z + 1):
		for y in range(minimum.y, maximum.y + 1):
			for x in range(minimum.x, maximum.x + 1):
				var point := Vector3i(x, y, z)
				var sample: Dictionary = field.sample(point)
				var density_value := float(sample.get("density", INF))
				var material_id := int(sample.get("material", -1))
				minimum_density = minf(minimum_density, density_value)
				maximum_density = maxf(maximum_density, density_value)
				if is_zero_approx(density_value):
					boundary_samples += 1
				elif density_value < 0.0:
					solid_samples += 1
				else:
					air_samples += 1
				if material_id not in material_ids:
					material_ids.append(material_id)
				lines.append(
					"%d,%d,%d:%d:%d" % [
						x,
						y,
						z,
						roundi(density_value * DENSITY_SCALE),
						material_id,
					]
				)
	material_ids.sort()
	return {
		"signature": "\n".join(lines).sha256_text(),
		"inventory": {
			"sample_count": lines.size(),
			"solid_samples": solid_samples,
			"air_samples": air_samples,
			"boundary_samples": boundary_samples,
			"material_ids": material_ids,
			"minimum_density": minimum_density,
			"maximum_density": maximum_density,
		},
	}


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


static func _coordinate_key(coordinate: Vector3i) -> String:
	return "%d,%d,%d" % [coordinate.x, coordinate.y, coordinate.z]


static func _provenance(workload_signature: String) -> Dictionary:
	var result := Statistics.provenance(workload_signature)
	result["processor_count"] = OS.get_processor_count()
	result["native_dependency"] = "WorldTransvoxelCellProbe"
	return result
