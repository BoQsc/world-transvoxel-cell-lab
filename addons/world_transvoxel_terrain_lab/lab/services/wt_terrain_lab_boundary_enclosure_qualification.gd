@tool
extends RefCounted
class_name WtTerrainLabBoundaryEnclosureQualification

const BoundaryField := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_boundary_field.gd"
)
const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const NativeEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_edit_native_evidence.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)

const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/boundary_enclosure_standard.json"
)


static func run(fixture_filter: String = "") -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var failures: Array[String] = []
	var contract := _qualify_contract(standard)
	if str(contract.get("status", "")) != "PASS":
		failures.append_array(contract.get("failures", []))
	var probe := NativeEvidence.create_probe()
	if probe == null:
		failures.append("WorldTransvoxelCellProbe is unavailable; fallback geometry is forbidden")
	var fixture_results: Array[Dictionary] = []
	var fixture_times: Array[float] = []
	var native_chunk_calls := 0
	var corpus_lines: Array[String] = []
	if probe != null:
		for fixture_value in standard.get("fixtures", []):
			var fixture: Dictionary = fixture_value
			if not fixture_filter.is_empty() and str(fixture.get("id", "")) != fixture_filter:
				continue
			var result := _qualify_fixture(probe, fixture)
			fixture_results.append(result)
			fixture_times.append(float(result.get("elapsed_usec", 0)))
			native_chunk_calls += int(result.get("native_chunk_call_count", 0))
			corpus_lines.append(
				str(result.get("fixture_id", "")) + ":" + str(result.get("geometry_signature", ""))
			)
			if str(result.get("status", "")) != "PASS":
				failures.append(
					"fixture %s failed: %s"
					% [str(result.get("fixture_id", "")), str(result.get("failures", []))]
				)
	var catalog := _qualify_catalog_policy(standard)
	if str(catalog.get("status", "")) != "PASS":
		failures.append_array(catalog.get("failures", []))
	var unloaded := {}
	if probe != null and fixture_filter.is_empty():
		unloaded = _qualify_unloaded_neighbor(probe)
		native_chunk_calls += int(unloaded.get("native_chunk_call_count", 0))
		corpus_lines.append("unloaded:" + str(unloaded.get("signature", "")))
		if str(unloaded.get("status", "")) != "PASS":
			failures.append_array(unloaded.get("failures", []))
	elif fixture_filter.is_empty():
		unloaded = {"status": "FAIL", "failures": ["native probe unavailable"]}
	var negative_controls := {
		"status": "NOT_RUN",
		"reason": "full retained run required",
		"control_count": 0,
		"controls": [],
		"failures": [],
	}
	if fixture_filter.is_empty():
		negative_controls = _negative_controls(standard, unloaded)
		if str(negative_controls.get("status", "")) != "PASS":
			failures.append_array(negative_controls.get("failures", []))
	corpus_lines.sort()
	var corpus_signature := "\n".join(corpus_lines).sha256_text()
	var complete := fixture_filter.is_empty()
	var budgets: Dictionary = standard.get("budgets", {})
	if complete:
		if fixture_results.size() < int(budgets.get("minimum_fixture_count", 0)):
			failures.append("boundary fixture coverage is incomplete")
		if native_chunk_calls < int(budgets.get("minimum_native_chunk_call_count", 0)):
			failures.append("native chunk call coverage is incomplete")
		if int(negative_controls.get("control_count", 0)) < int(
			budgets.get("minimum_negative_control_count", 0)
		):
			failures.append("boundary negative-control coverage is incomplete")
	var elapsed_usec := Time.get_ticks_usec() - started_usec
	if complete and elapsed_usec > int(budgets.get("maximum_total_usec", 0)):
		failures.append("TQP-32 total duration exceeded")
	var provenance := Statistics.provenance(corpus_signature)
	provenance["native_dependency"] = "WorldTransvoxelCellProbe"
	provenance["processor_count"] = OS.get_processor_count()
	return {
		"schema": "world_transvoxel.terrain_lab.boundary_enclosure_qualification.v1",
		"standard_id": standard.get("standard_id", ""),
		"authority": standard.get("authority", ""),
		"milestone": "TQP-32",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"retained_complete": complete,
		"contract": contract,
		"fixtures": fixture_results,
		"catalog_policy": catalog,
		"unloaded_neighbor": unloaded,
		"negative_controls": negative_controls,
		"matrix": {
			"fixture_count": fixture_results.size(),
			"native_chunk_call_count": native_chunk_calls,
			"geometry_signature": corpus_signature,
		},
		"performance": {
			"fixture_distribution": Statistics.distribution(fixture_times),
			"elapsed_usec": elapsed_usec,
		},
		"provenance": provenance,
		"failures": failures,
	}


static func _qualify_contract(standard: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	var checks: Array[Dictionary] = []
	var contract: Dictionary = standard.get("contract", {})
	_check(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.boundary_enclosure_standard.v1",
		"standard_schema",
		"TQP-32 standard schema changed",
		checks,
		failures
	)
	_check(
		str(contract.get("native_dependency", "")) == "WorldTransvoxelCellProbe",
		"native_authority",
		"TQP-32 native authority changed",
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
		str(contract.get("outside_field_sampling", ""))
			== "total_authoritative_density_and_material_function_with_gradient_halo",
		"outside_field_sampling",
		"outside-field sampling policy changed",
		checks,
		failures
	)
	_check(
		str(contract.get("unloaded_neighbor_policy", ""))
			== "residency_never_changes_authoritative_samples_or_resident_chunk_geometry",
		"unloaded_neighbor",
		"unloaded-neighbor sampling policy changed",
		checks,
		failures
	)
	_check(
		str(contract.get("closed_contour_policy", ""))
			== "density_field_enclosure_inside_declared_finite_domain",
		"closed_contours",
		"closed-contour ownership changed",
		checks,
		failures
	)
	_check(
		str(contract.get("open_contour_policy", ""))
			== "open_edges_allowed_only_on_declared_exterior_planes",
		"open_contours",
		"open-contour ownership changed",
		checks,
		failures
	)
	_check(
		str(contract.get("cap_source", "")) == "authoritative_density_field_only",
		"cap_ownership",
		"cap ownership changed",
		checks,
		failures
	)
	_check(
		contract.get("forbidden_topology_corrections", [])
			== ["artificial_skirts", "hidden_overlap", "resident_fallback_density"],
		"forbidden_corrections",
		"forbidden topology corrections changed",
		checks,
		failures
	)
	var catalog: Dictionary = standard.get("catalog", {})
	_check(
		str(catalog.get("rejection_policy", ""))
			== "duplicate_out_of_bounds_missing_malformed_unknown_unsupported_lod_or_over_capacity_entries_fail_closed",
		"catalog_rejection",
		"catalog rejection policy changed",
		checks,
		failures
	)
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"checks": checks,
		"failures": failures,
	}


static func _qualify_fixture(probe: RefCounted, definition: Dictionary) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var failures: Array[String] = []
	var field := BoundaryField.new()
	if not field.configure(definition):
		return {
			"fixture_id": definition.get("id", ""),
			"status": "FAIL",
			"elapsed_usec": Time.get_ticks_usec() - started_usec,
			"failures": ["boundary field configuration failed"],
		}
	field.reset_sample_audit()
	var first := _mesh_window(probe, field)
	var first_audit := field.sample_audit()
	field.reset_sample_audit()
	var second := _mesh_window(probe, field)
	var second_audit := field.sample_audit()
	for pass_result in [first, second]:
		if str(pass_result.get("status", "")) != "PASS":
			failures.append_array(pass_result.get("failures", []))
	if str(first.get("geometry_signature", "")) != str(second.get("geometry_signature", "")):
		failures.append("cold/warm native geometry signatures differ")
	if first_audit != second_audit:
		failures.append("cold/warm sample audits differ")
	var topology: Dictionary = first.get("topology", {})
	var open_faces: Dictionary = first.get("open_edge_faces", {})
	var contour := str(definition.get("contour", ""))
	var declared_open_faces: Array = definition.get("declared_open_faces", [])
	var valid_face_names := [
		"negative_x", "positive_x", "negative_y", "positive_y", "negative_z", "positive_z"
	]
	var unique_declared_faces := {}
	for face_value in declared_open_faces:
		var face_name := str(face_value)
		if face_name not in valid_face_names:
			failures.append("fixture declares an unknown open face: " + face_name)
		if unique_declared_faces.has(face_name):
			failures.append("fixture declares an open face more than once: " + face_name)
		unique_declared_faces[face_name] = true
	if contour == "closed":
		if not declared_open_faces.is_empty():
			failures.append("declared closed contour lists open faces")
		if int(topology.get("exterior_open_edge_count", -1)) != 0:
			failures.append("declared closed contour has exterior open edges")
	elif contour == "open":
		if declared_open_faces.is_empty():
			failures.append("declared open contour lists no open faces")
		if int(topology.get("exterior_open_edge_count", 0)) <= 0:
			failures.append("declared open contour lacks exterior open edges")
	else:
		failures.append("fixture lacks a valid contour declaration")
	if int(topology.get("interior_open_edge_count", -1)) != 0:
		failures.append("fixture has interior open edges")
	if int(topology.get("nonmanifold_edge_count", -1)) != 0:
		failures.append("fixture has nonmanifold edges")
	if int(open_faces.get("unclassified_open_edge_count", -1)) != 0:
		failures.append("fixture has open edges outside declared exterior planes")
	if int(open_faces.get("exterior_open_edge_count", -1)) \
			!= int(topology.get("exterior_open_edge_count", -2)):
		failures.append("open-edge face inventory differs from topology inventory")
	for face in valid_face_names:
		var face_count := int((open_faces.get("face_counts", {}) as Dictionary).get(face, 0))
		if face in declared_open_faces and face_count <= 0:
			failures.append("declared open face has no open contour: " + face)
		if face not in declared_open_faces and face_count > 0:
			failures.append("open contour reached undeclared face: " + face)
	if int(first_audit.get("outside_sample_count", 0)) <= 0:
		failures.append("native mesher did not consume authoritative outside-field halo samples")
	for face in ["negative_x", "positive_x", "negative_y", "positive_y", "negative_z", "positive_z"]:
		if int((first_audit.get("outside_face_counts", {}) as Dictionary).get(face, 0)) <= 0:
			failures.append("native halo did not sample " + face)
	if bool(definition.get("requires_all_enclosure_faces", false)):
		for face in ["negative_x", "positive_x", "negative_y", "positive_y", "negative_z", "positive_z"]:
			if not bool((first.get("enclosure_face_presence", {}) as Dictionary).get(face, false)):
				failures.append("closed volume lacks enclosure surface near " + face)
	return {
		"fixture_id": definition.get("id", ""),
		"kind": definition.get("kind", ""),
		"lod": field.lod,
		"contour": contour,
		"status": "PASS" if failures.is_empty() else "FAIL",
		"definition_signature": field.definition_signature(),
		"geometry_signature": first.get("geometry_signature", ""),
		"warm_geometry_signature": second.get("geometry_signature", ""),
		"native_chunk_call_count": int(first.get("chunk_count", 0))
			+ int(second.get("chunk_count", 0)),
		"triangle_count": first.get("triangle_count", 0),
		"vertex_count": first.get("vertex_count", 0),
		"seam_count": first.get("seam_count", 0),
		"topology": topology,
		"declared_open_faces": declared_open_faces,
		"open_edge_faces": open_faces,
		"enclosure_face_presence": first.get("enclosure_face_presence", {}),
		"sample_audit": first_audit,
		"elapsed_usec": Time.get_ticks_usec() - started_usec,
		"minimized_repro": {
			"runner": "res://labs/terrain_lab/tools/run_boundary_enclosure_validation.gd",
			"arguments": ["--fixture", definition.get("id", "")],
		},
		"failures": failures,
	}


static func _mesh_window(probe: RefCounted, field: RefCounted) -> Dictionary:
	var failures: Array[String] = []
	var chunks: Array[Dictionary] = []
	var chunks_by_key := {}
	var geometry_lines: Array[String] = []
	var triangle_count := 0
	var vertex_count := 0
	var surface_min := Vector3(INF, INF, INF)
	var surface_max := Vector3(-INF, -INF, -INF)
	for z in range(field.window_chunks.z):
		for y in range(field.window_chunks.y):
			for x in range(field.window_chunks.x):
				var offset := Vector3i(x, y, z)
				var coordinate: Vector3i = field.chunk_base + offset
				var chunk := NativeEvidence.mesh_chunk(
					probe, field, coordinate, field.lod, 0
				)
				chunks.append(chunk)
				chunks_by_key[_coordinate_key(offset)] = chunk
				var validation := NativeEvidence.validate_chunk(chunk)
				if str(validation.get("status", "")) != "PASS":
					failures.append(
						"chunk %s failed: %s" % [coordinate, str(validation.get("failures", []))]
					)
				triangle_count += int(validation.get("triangle_count", 0))
				vertex_count += int(validation.get("vertex_count", 0))
				geometry_lines.append(
					_coordinate_key(offset) + ":" + NativeEvidence.chunk_signature(chunk)
				)
				var origin := NativeEvidence.chunk_origin(chunk)
				for buffer in NativeEvidence.chunk_buffers(chunk):
					for vertex in buffer.get("vertices", PackedVector3Array()):
						var world_vertex: Vector3 = origin + vertex
						surface_min = surface_min.min(world_vertex)
						surface_max = surface_max.max(world_vertex)
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
						failures.append("internal seam failed: " + str(seam.get("failures", [])))
	var topology := NativeEvidence.same_lod_window_topology(chunks)
	if str(topology.get("status", "")) != "PASS":
		failures.append("assembled topology failed: " + str(topology.get("failures", [])))
	if triangle_count <= 0:
		failures.append("fixture generated no native triangles")
	geometry_lines.sort()
	var chunk_extent: int = BoundaryField.CHUNK_CELLS_PER_AXIS * (1 << int(field.lod))
	var domain_min := Vector3(field.chunk_base * chunk_extent)
	var domain_max := Vector3(
		(field.chunk_base + field.window_chunks) * chunk_extent
	)
	var tolerance: float = float(field.enclosure_inset_samples) + 1.0
	var face_presence := {
		"negative_x": surface_min.x <= domain_min.x + tolerance,
		"positive_x": surface_max.x >= domain_max.x - tolerance,
		"negative_y": surface_min.y <= domain_min.y + tolerance,
		"positive_y": surface_max.y >= domain_max.y - tolerance,
		"negative_z": surface_min.z <= domain_min.z + tolerance,
		"positive_z": surface_max.z >= domain_max.z - tolerance,
	}
	var open_edge_faces := _open_edge_face_inventory(chunks, domain_min, domain_max)
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"chunk_count": chunks.size(),
		"seam_count": seam_count,
		"triangle_count": triangle_count,
		"vertex_count": vertex_count,
		"geometry_signature": "\n".join(geometry_lines).sha256_text(),
		"topology": topology,
		"open_edge_faces": open_edge_faces,
		"surface_min": surface_min,
		"surface_max": surface_max,
		"enclosure_face_presence": face_presence,
		"failures": failures,
	}


static func _qualify_catalog_policy(standard: Dictionary) -> Dictionary:
	var contract: Dictionary = standard.get("catalog", {})
	var catalog_min := _vector3i(contract.get("minimum_chunk", [0, 0, 0]))
	var catalog_size := _vector3i(contract.get("size_chunks", [2, 2, 2]))
	var catalog := _full_catalog(catalog_min, catalog_size)
	var world_validation := BoundaryField.validate_world_catalog(
		catalog,
		catalog_min,
		catalog_size,
		int(contract.get("world_capacity", 0))
	)
	var resident := catalog.slice(0, mini(3, catalog.size()))
	var residency_validation := BoundaryField.validate_residency_set(
		resident,
		catalog,
		int(contract.get("resident_capacity", 0))
	)
	var failures: Array[String] = []
	if str(world_validation.get("status", "")) != "PASS":
		failures.append_array(world_validation.get("failures", []))
	if str(residency_validation.get("status", "")) != "PASS":
		failures.append_array(residency_validation.get("failures", []))
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"world_catalog": world_validation,
		"partial_residency": residency_validation,
		"catalog_signature": JSON.stringify(catalog).sha256_text(),
		"failures": failures,
	}


static func _open_edge_face_inventory(
	chunks: Array,
	domain_min: Vector3,
	domain_max: Vector3
) -> Dictionary:
	var edge_records := {}
	for chunk_value in chunks:
		if not chunk_value is Dictionary:
			continue
		var chunk: Dictionary = chunk_value
		var origin := NativeEvidence.chunk_origin(chunk)
		var regular: Dictionary = chunk.get("regular", {})
		var vertices: PackedVector3Array = regular.get("vertices", PackedVector3Array())
		var indices: PackedInt32Array = regular.get("indices", PackedInt32Array())
		for triangle_start in range(0, indices.size(), 3):
			if triangle_start + 2 >= indices.size():
				continue
			var triangle := [
				int(indices[triangle_start]),
				int(indices[triangle_start + 1]),
				int(indices[triangle_start + 2]),
			]
			var valid := true
			for vertex_index in triangle:
				if vertex_index < 0 or vertex_index >= vertices.size():
					valid = false
					break
			if not valid:
				continue
			for edge in [[0, 1], [1, 2], [2, 0]]:
				var a := origin + vertices[triangle[edge[0]]]
				var b := origin + vertices[triangle[edge[1]]]
				var key := _segment_key(a, b)
				var record: Dictionary = edge_records.get(key, {"count": 0, "a": a, "b": b})
				record["count"] = int(record.get("count", 0)) + 1
				edge_records[key] = record
	var face_counts := {
		"negative_x": 0,
		"positive_x": 0,
		"negative_y": 0,
		"positive_y": 0,
		"negative_z": 0,
		"positive_z": 0,
	}
	var exterior_open_edge_count := 0
	var unclassified_open_edge_count := 0
	var multiplane_open_edge_count := 0
	for key in edge_records:
		var record: Dictionary = edge_records[key]
		if int(record.get("count", 0)) != 1:
			continue
		exterior_open_edge_count += 1
		var a: Vector3 = record.get("a", Vector3.ZERO)
		var b: Vector3 = record.get("b", Vector3.ZERO)
		var faces: Array[String] = []
		if is_equal_approx(a.x, domain_min.x) and is_equal_approx(b.x, domain_min.x):
			faces.append("negative_x")
		if is_equal_approx(a.x, domain_max.x) and is_equal_approx(b.x, domain_max.x):
			faces.append("positive_x")
		if is_equal_approx(a.y, domain_min.y) and is_equal_approx(b.y, domain_min.y):
			faces.append("negative_y")
		if is_equal_approx(a.y, domain_max.y) and is_equal_approx(b.y, domain_max.y):
			faces.append("positive_y")
		if is_equal_approx(a.z, domain_min.z) and is_equal_approx(b.z, domain_min.z):
			faces.append("negative_z")
		if is_equal_approx(a.z, domain_max.z) and is_equal_approx(b.z, domain_max.z):
			faces.append("positive_z")
		if faces.is_empty():
			unclassified_open_edge_count += 1
		if faces.size() > 1:
			multiplane_open_edge_count += 1
		for face in faces:
			face_counts[face] = int(face_counts[face]) + 1
	return {
		"exterior_open_edge_count": exterior_open_edge_count,
		"face_counts": face_counts,
		"unclassified_open_edge_count": unclassified_open_edge_count,
		"multiplane_open_edge_count": multiplane_open_edge_count,
	}


static func _qualify_unloaded_neighbor(probe: RefCounted) -> Dictionary:
	var failures: Array[String] = []
	var definition := {
		"id": "unloaded_neighbor_invariance",
		"kind": "residency_interface",
		"chunk_base": [0, 0, 0],
		"window_chunks": [2, 1, 1],
		"lod": 2,
		"enclosure_inset_samples": 7.0,
	}
	var target := Vector3i.ZERO
	var neighbor := Vector3i(1, 0, 0)
	var field := BoundaryField.new()
	field.configure(definition)
	field.set_resident_chunks([target])
	var target_neighbor_unloaded := NativeEvidence.mesh_chunk(
		probe, field, target, field.lod, 0
	)
	field.set_resident_chunks([target, neighbor])
	var target_neighbor_loaded := NativeEvidence.mesh_chunk(
		probe, field, target, field.lod, 0
	)
	var loaded_neighbor := NativeEvidence.mesh_chunk(
		probe, field, neighbor, field.lod, 0
	)
	var unloaded_signature := NativeEvidence.chunk_signature(target_neighbor_unloaded)
	var loaded_signature := NativeEvidence.chunk_signature(target_neighbor_loaded)
	if unloaded_signature != loaded_signature:
		failures.append("resident target geometry changed when its neighbor loaded")
	for chunk in [target_neighbor_unloaded, target_neighbor_loaded, loaded_neighbor]:
		var validation := NativeEvidence.validate_chunk(chunk)
		if str(validation.get("status", "")) != "PASS":
			failures.append("unloaded-neighbor native chunk failed")
	var seam := NativeEvidence.same_lod_seam(target_neighbor_loaded, loaded_neighbor, 0)
	if str(seam.get("status", "")) != "PASS":
		failures.append("loaded neighbor does not match the resident target interface")
	var injected := BoundaryField.new()
	var injected_definition := definition.duplicate(true)
	injected_definition["residency_coupled_sampling"] = true
	injected.configure(injected_definition)
	injected.set_resident_chunks([target])
	var injected_unloaded := NativeEvidence.mesh_chunk(
		probe, injected, target, injected.lod, 0
	)
	injected.set_resident_chunks([target, neighbor])
	var injected_loaded := NativeEvidence.mesh_chunk(
		probe, injected, target, injected.lod, 0
	)
	var injected_changed := NativeEvidence.chunk_signature(injected_unloaded) \
		!= NativeEvidence.chunk_signature(injected_loaded)
	if not injected_changed:
		failures.append("resident-coupled sample-source negative control was not detected")
	var signature := JSON.stringify({
		"target": loaded_signature,
		"neighbor": NativeEvidence.chunk_signature(loaded_neighbor),
		"seam": seam,
		"injected_changed": injected_changed,
	}).sha256_text()
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"resident_target_signature": loaded_signature,
		"unloaded_target_signature": unloaded_signature,
		"geometry_invariant": unloaded_signature == loaded_signature,
		"loaded_interface": seam,
		"resident_coupled_negative_detected": injected_changed,
		"native_chunk_call_count": 5,
		"signature": signature,
		"failures": failures,
	}


static func _negative_controls(standard: Dictionary, unloaded: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	var controls: Array[Dictionary] = []
	var catalog_contract: Dictionary = standard.get("catalog", {})
	var catalog_min := _vector3i(catalog_contract.get("minimum_chunk", [0, 0, 0]))
	var catalog_size := _vector3i(catalog_contract.get("size_chunks", [2, 2, 2]))
	var capacity := int(catalog_contract.get("world_capacity", 0))
	var catalog := _full_catalog(catalog_min, catalog_size)
	var duplicate := catalog.duplicate(true)
	duplicate.append(catalog[0].duplicate(true))
	_record_negative(
		"duplicate_catalog_chunk",
		BoundaryField.validate_world_catalog(duplicate, catalog_min, catalog_size, capacity),
		controls,
		failures
	)
	var missing := catalog.duplicate(true)
	missing.pop_back()
	_record_negative(
		"missing_catalog_chunk",
		BoundaryField.validate_world_catalog(missing, catalog_min, catalog_size, capacity),
		controls,
		failures
	)
	var outside := catalog.duplicate(true)
	outside[0] = {"coordinate": [catalog_min.x - 1, catalog_min.y, catalog_min.z], "lod": 0}
	_record_negative(
		"out_of_bounds_catalog_chunk",
		BoundaryField.validate_world_catalog(outside, catalog_min, catalog_size, capacity),
		controls,
		failures
	)
	_record_negative(
		"catalog_capacity_overflow",
		BoundaryField.validate_world_catalog(catalog, catalog_min, catalog_size, capacity - 1),
		controls,
		failures
	)
	var malformed := catalog.duplicate(true)
	var malformed_entry: Dictionary = malformed[0]
	malformed_entry["coordinate"] = [0.5, 0, 0]
	malformed[0] = malformed_entry
	_record_negative(
		"malformed_catalog_coordinate",
		BoundaryField.validate_world_catalog(malformed, catalog_min, catalog_size, capacity),
		controls,
		failures
	)
	var unsupported_lod := catalog.duplicate(true)
	var unsupported_lod_entry: Dictionary = unsupported_lod[0]
	unsupported_lod_entry["lod"] = 1
	unsupported_lod[0] = unsupported_lod_entry
	_record_negative(
		"unsupported_catalog_lod",
		BoundaryField.validate_world_catalog(unsupported_lod, catalog_min, catalog_size, capacity),
		controls,
		failures
	)
	_record_negative(
		"unknown_resident_chunk",
		BoundaryField.validate_residency_set(
			[{"coordinate": [99, 99, 99], "lod": 0}], catalog, capacity
		),
		controls,
		failures
	)
	_record_negative(
		"duplicate_resident_chunk",
		BoundaryField.validate_residency_set([catalog[0], catalog[0]], catalog, capacity),
		controls,
		failures
	)
	for correction in [
		{"id": "artificial_skirt", "cap_source": "synthetic_geometry", "hidden_overlap": false, "residency_coupled": false},
		{"id": "hidden_overlap", "cap_source": "density_field", "hidden_overlap": true, "residency_coupled": false},
		{"id": "resident_fallback_density", "cap_source": "density_field", "hidden_overlap": false, "residency_coupled": true},
	]:
		_record_negative(
			str(correction.get("id", "")),
			_validate_correction_policy(correction),
			controls,
			failures
		)
	var coupling_detected := bool(unloaded.get("resident_coupled_negative_detected", false))
	controls.append({
		"id": "resident_coupled_geometry_change",
		"status": "PASS" if coupling_detected else "FAIL",
		"injected_failure_detected": coupling_detected,
	})
	if not coupling_detected:
		failures.append("resident-coupled geometry negative control did not trigger")
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"control_count": controls.size(),
		"controls": controls,
		"failures": failures,
	}


static func _validate_correction_policy(policy: Dictionary) -> Dictionary:
	var valid := str(policy.get("cap_source", "")) == "density_field" \
		and not bool(policy.get("hidden_overlap", false)) \
		and not bool(policy.get("residency_coupled", false))
	return {
		"status": "PASS" if valid else "FAIL",
		"failures": [] if valid else ["forbidden topology correction"],
	}


static func _record_negative(
	control_id: String,
	validation: Dictionary,
	controls: Array[Dictionary],
	failures: Array[String]
) -> void:
	var detected := str(validation.get("status", "")) == "FAIL"
	controls.append({
		"id": control_id,
		"status": "PASS" if detected else "FAIL",
		"injected_failure_detected": detected,
		"detector_failures": validation.get("failures", []),
	})
	if not detected:
		failures.append("negative control was accepted: " + control_id)


static func _full_catalog(minimum: Vector3i, size: Vector3i) -> Array[Dictionary]:
	var catalog: Array[Dictionary] = []
	for z in range(size.z):
		for y in range(size.y):
			for x in range(size.x):
				var coordinate := minimum + Vector3i(x, y, z)
				catalog.append({
					"coordinate": [coordinate.x, coordinate.y, coordinate.z],
					"lod": 0,
				})
	return catalog


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


static func _segment_key(a: Vector3, b: Vector3) -> String:
	var a_key := _vector_key(a)
	var b_key := _vector_key(b)
	return a_key + "|" + b_key if a_key < b_key else b_key + "|" + a_key


static func _vector_key(value: Vector3) -> String:
	return "%d,%d,%d" % [
		roundi(value.x * 1000000.0),
		roundi(value.y * 1000000.0),
		roundi(value.z * 1000000.0),
	]


static func _vector3i(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() == 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i.ZERO
