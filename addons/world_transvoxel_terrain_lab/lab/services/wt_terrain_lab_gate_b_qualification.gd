@tool
extends RefCounted
class_name WtTerrainLabGateBQualification

const EditField := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_edit_field.gd"
)
const NativeEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_edit_native_evidence.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)
const VisualEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_edit_visual_evidence.gd"
)

const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/edit_gate_b_standard.json"
)
const VISUAL_PATH := (
	"res://labs/terrain_lab/results/edit_qualification_reference.png"
)
const BASE_CELL_SIZE_M := 0.5
const MAXIMUM_LOD := 7
const SOAK_OPERATION_COUNT := 2048
const POSITION_SCALE := 1000000.0


static func run() -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var probe := NativeEvidence.create_probe()
	var milestones: Array[Dictionary] = [
		_qualify_brush_corpus(probe),
		_qualify_digging(probe),
		_qualify_construction(probe),
		_qualify_resolvability(probe),
		_qualify_journal(),
		_qualify_long_soak(probe),
	]
	var standard := _load_json(STANDARD_PATH)
	var visual_standard: Dictionary = standard.get("visual_evidence", {})
	var visual := VisualEvidence.validate_reference(
		VISUAL_PATH,
		str(visual_standard.get("pixel_signature", ""))
	)
	var stable_summary := _stable_summary(milestones, visual)
	var standard_comparison := _compare_standard(
		stable_summary,
		standard.get("stable_expected", {})
	)
	var performance_comparison := _compare_performance(
		milestones,
		standard.get("performance_budgets", {})
	)
	var failures: Array[String] = []
	if probe == null:
		failures.append("world-transvoxel native chunk probe is unavailable")
	for milestone in milestones:
		for failure_value in milestone.get("failures", []):
			failures.append(
				"%s: %s" % [str(milestone.get("milestone", "UNKNOWN")), str(failure_value)]
			)
	if str(visual.get("status", "")) != "PASS":
		failures.append("diagnostic visual evidence failed")
	if visual.get("shape_panels", []) != visual_standard.get("shape_panels", []):
		failures.append("diagnostic shape panel order differs from standard")
	if visual.get("sequence_panels", []) != visual_standard.get("sequence_panels", []):
		failures.append("diagnostic edit sequence differs from standard")
	if str(standard_comparison.get("status", "")) != "PASS":
		failures.append("stable Gate B standard differs")
	if str(performance_comparison.get("status", "")) != "PASS":
		failures.append("Gate B reference performance budget failed")
	return {
		"schema": "world_transvoxel.terrain_lab.edit_gate_b_qualification.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"milestones": milestones,
		"stable_summary": stable_summary,
		"standard_comparison": standard_comparison,
		"performance_comparison": performance_comparison,
		"visual_evidence": visual,
		"provenance": Statistics.provenance("edit_gate_b_native_matrix_v1"),
		"memory": Statistics.memory_metrics(),
		"elapsed_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
		"failures": failures,
	}


static func _qualify_brush_corpus(probe: RefCounted) -> Dictionary:
	var failures: Array[String] = []
	var shapes := _shape_fixtures(Vector3.ZERO, 1.0)
	var shape_lines: Array[String] = []
	var native_lines: Array[String] = []
	var native_records: Array[Dictionary] = []
	for shape in shapes:
		var shape_id := str(shape.get("id", ""))
		_expect(EditField.shape_sdf(shape, Vector3.ZERO) <= 0.0, shape_id + " center is outside", failures)
		_expect(EditField.shape_sdf(shape, Vector3(20.0, 20.0, 20.0)) > 0.0, shape_id + " support escaped", failures)
		var bounds := EditField.operation_bounds(shape)
		_expect(bounds.has_point(Vector3.ZERO), shape_id + " bounds exclude center", failures)
		for y in range(-8, 9):
			for x in range(-8, 9):
				var point := Vector3(float(x) * 0.5, float(y) * 0.5, 0.0)
				shape_lines.append("%s:%d,%d:%d" % [
					shape_id,
					x,
					y,
					roundi(EditField.shape_sdf(shape, point) * 100000.0),
				])
		var native_field := EditField.new()
		native_field.terrain_profile = "empty"
		var native_shape := _translated_shape(shape, Vector3(4.0, 4.0, 4.0))
		native_shape["material"] = 7
		_expect(native_field.add_operation(native_shape), shape_id + " native operation rejected", failures)
		var native := _native_record(probe, native_field, Vector3i.ZERO, 0)
		_expect(str(native.get("status", "")) == "PASS", shape_id + " native mesh failed", failures)
		_expect(int(native.get("triangle_count", 0)) > 0, shape_id + " native mesh is empty", failures)
		_expect(7 in native.get("material_ids", []), shape_id + " native material missing", failures)
		native_records.append(native)
		native_lines.append(shape_id + ":" + str(native.get("geometry_signature", "")))
	var invalid_field := EditField.new()
	var invalid_operations := [
		{"id": "invalid-radius", "mode": "dig", "shape": "sphere", "radius_m": 0.0},
		{"id": "invalid-normal", "mode": "construct", "shape": "plane_stamp", "radius_m": 1.0, "normal": Vector3.ZERO},
		{"id": "invalid-rounding", "mode": "construct", "shape": "rounded_box", "radius_m": 1.0, "half_extents": Vector3.ONE, "rounding_m": 2.0},
		{"id": "invalid-noise", "mode": "dig", "shape": "bounded_noise", "radius_m": 1.0, "noise_amplitude_m": 2.0},
		{"id": "invalid-infinite-radius", "mode": "dig", "shape": "sphere", "radius_m": INF},
		{"id": "invalid-infinite-center", "mode": "construct", "shape": "sphere", "center": Vector3(INF, 0.0, 0.0), "radius_m": 1.0},
	]
	for operation in invalid_operations:
		_expect(not invalid_field.add_operation(operation), "invalid operation was accepted", failures)
	var timings: Array[float] = []
	for iteration in range(110):
		var timing_start := Time.get_ticks_usec()
		for shape in shapes:
			for sample_index in range(64):
				EditField.shape_sdf(shape, Vector3(
					float((sample_index * 13) % 17) - 8.0,
					float((sample_index * 7) % 11) - 5.0,
					float((sample_index * 5) % 19) - 9.0
				))
		if iteration >= 10:
			timings.append(float(Time.get_ticks_usec() - timing_start))
	var result := _result("TQP-09", shapes.size() * 291 + invalid_operations.size(), failures)
	result["shape_ids"] = shapes.map(func(shape: Dictionary) -> String: return str(shape["id"]))
	result["shape_signature"] = "\n".join(shape_lines).sha256_text()
	result["native_shape_signature"] = "\n".join(native_lines).sha256_text()
	result["native_records"] = native_records
	result["performance"] = Statistics.distribution(timings)
	return result


static func _qualify_digging(probe: RefCounted) -> Dictionary:
	var failures: Array[String] = []
	var records: Array[Dictionary] = []
	var geometry_lines: Array[String] = []
	for lod in range(MAXIMUM_LOD + 1):
		var cell_size := BASE_CELL_SIZE_M * float(1 << lod)
		var extent := cell_size * 16.0
		var center := Vector3.ONE * (extent * 0.5)
		var field := EditField.new()
		field.terrain_profile = "solid"
		var operation := {
			"id": "dig-lod-%d" % lod,
			"mode": "dig",
			"shape": "swept_stroke",
			"center": center,
			"segment_a": center - Vector3(cell_size * 3.0, 0.0, 0.0),
			"segment_b": center + Vector3(cell_size * 3.0, 0.0, 0.0),
			"radius_m": cell_size * 2.25,
			"smoothing_m": cell_size * 0.25,
		}
		_expect(field.add_operation(operation), "LOD%d dig operation rejected" % lod, failures)
		_expect(field.density(center) > 0.0, "LOD%d tunnel center remained solid" % lod, failures)
		_expect(field.density(Vector3.ZERO) < 0.0, "LOD%d dig escaped support" % lod, failures)
		var native := _native_record(probe, field, Vector3i.ZERO, lod)
		_expect(str(native.get("status", "")) == "PASS", "LOD%d native dig failed" % lod, failures)
		_expect(int(native.get("triangle_count", 0)) > 0, "LOD%d native dig is empty" % lod, failures)
		var replay := EditField.new()
		_expect(replay.reconstruct(field.serialized_journal()), "LOD%d dig replay failed" % lod, failures)
		var replay_native := _native_record(probe, replay, Vector3i.ZERO, lod)
		_expect(
			str(native.get("geometry_signature", "")) == str(replay_native.get("geometry_signature", "")),
			"LOD%d dig replay geometry changed" % lod,
			failures
		)
		records.append({
			"lod": lod,
			"cell_size_m": cell_size,
			"triangle_count": int(native.get("triangle_count", 0)),
			"geometry_signature": str(native.get("geometry_signature", "")),
			"collision_signature": str(native.get("collision_signature", "")),
		})
		geometry_lines.append("%d:%s" % [lod, str(native.get("geometry_signature", ""))])
	var seam_field := EditField.new()
	seam_field.terrain_profile = "solid"
	_expect(seam_field.add_operation({
		"id": "dig-boundary-stroke",
		"mode": "dig",
		"shape": "swept_stroke",
		"center": Vector3(8.0, 4.0, 4.0),
		"segment_a": Vector3(4.0, 4.0, 4.0),
		"segment_b": Vector3(12.0, 4.0, 4.0),
		"radius_m": 2.0,
	}), "boundary dig operation rejected", failures)
	var left := NativeEvidence.mesh_chunk(probe, seam_field, Vector3i.ZERO, 0)
	var right := NativeEvidence.mesh_chunk(probe, seam_field, Vector3i(1, 0, 0), 0)
	var seam := NativeEvidence.same_lod_seam(left, right, 0)
	_expect(str(seam.get("status", "")) == "PASS", "dig boundary seam failed", failures)
	_expect(int(seam.get("left_edge_count", 0)) > 0, "dig boundary fixture has no seam edges", failures)
	var result := _result("TQP-10", records.size() * 9 + 2, failures)
	result["lod_records"] = records
	result["geometry_signature"] = "\n".join(geometry_lines).sha256_text()
	result["boundary_seam"] = seam
	return result


static func _qualify_construction(probe: RefCounted) -> Dictionary:
	var failures: Array[String] = []
	var records: Array[Dictionary] = []
	var geometry_lines: Array[String] = []
	for lod in range(MAXIMUM_LOD + 1):
		var cell_size := BASE_CELL_SIZE_M * float(1 << lod)
		var extent := cell_size * 16.0
		var center := Vector3.ONE * (extent * 0.5)
		var field := EditField.new()
		field.terrain_profile = "empty"
		_expect(field.add_transaction("construct-lod-%d" % lod, [
			{
				"id": "construct-sphere-lod-%d" % lod,
				"mode": "construct",
				"shape": "sphere",
				"center": center,
				"radius_m": cell_size * 2.75,
				"material": 7,
				"support_role": "anchored_mass",
				"support_anchor": true,
			},
			{
				"id": "construct-span-lod-%d" % lod,
				"mode": "construct",
				"shape": "rounded_box",
				"center": center + Vector3(0.0, cell_size, 0.0),
				"half_extents": Vector3(cell_size * 3.0, cell_size, cell_size * 1.5),
				"radius_m": cell_size,
				"rounding_m": cell_size * 0.35,
				"material": 8,
				"support_role": "span",
			},
		]), "LOD%d construction transaction rejected" % lod, failures)
		_expect(field.density(center) < 0.0, "LOD%d construction center stayed empty" % lod, failures)
		_expect(field.material_at(center, field.density(center)) == 7, "LOD%d material provenance changed" % lod, failures)
		var document: Dictionary = JSON.parse_string(field.serialized_journal())
		var persisted_operations: Array = document.get("operations", [])
		_expect(bool((persisted_operations[0] as Dictionary).get("support_anchor", false)), "support metadata was not retained", failures)
		var native := _native_record(probe, field, Vector3i.ZERO, lod)
		_expect(str(native.get("status", "")) == "PASS", "LOD%d native construction failed" % lod, failures)
		_expect(int(native.get("triangle_count", 0)) > 0, "LOD%d native construction is empty" % lod, failures)
		_expect(7 in native.get("material_ids", []) or 8 in native.get("material_ids", []), "LOD%d constructed materials missing" % lod, failures)
		var replay := EditField.new()
		_expect(replay.reconstruct(field.serialized_journal()), "LOD%d construction replay failed" % lod, failures)
		var replay_native := _native_record(probe, replay, Vector3i.ZERO, lod)
		_expect(str(native.get("geometry_signature", "")) == str(replay_native.get("geometry_signature", "")), "LOD%d construction replay geometry changed" % lod, failures)
		records.append({
			"lod": lod,
			"cell_size_m": cell_size,
			"triangle_count": int(native.get("triangle_count", 0)),
			"material_ids": native.get("material_ids", []),
			"geometry_signature": str(native.get("geometry_signature", "")),
			"collision_signature": str(native.get("collision_signature", "")),
		})
		geometry_lines.append("%d:%s" % [lod, str(native.get("geometry_signature", ""))])
	var seam_field := EditField.new()
	seam_field.terrain_profile = "empty"
	_expect(seam_field.add_operation({
		"id": "construct-boundary-span",
		"mode": "construct",
		"shape": "rounded_box",
		"center": Vector3(8.0, 4.0, 4.0),
		"half_extents": Vector3(5.0, 2.0, 2.0),
		"rounding_m": 0.5,
		"radius_m": 1.0,
		"material": 8,
	}), "boundary construction rejected", failures)
	var left := NativeEvidence.mesh_chunk(probe, seam_field, Vector3i.ZERO, 0)
	var right := NativeEvidence.mesh_chunk(probe, seam_field, Vector3i(1, 0, 0), 0)
	var seam := NativeEvidence.same_lod_seam(left, right, 0)
	_expect(str(seam.get("status", "")) == "PASS", "construction boundary seam failed", failures)
	_expect(int(seam.get("left_edge_count", 0)) > 0, "construction boundary fixture has no seam edges", failures)
	var result := _result("TQP-11", records.size() * 11 + 2, failures)
	result["lod_records"] = records
	result["geometry_signature"] = "\n".join(geometry_lines).sha256_text()
	result["boundary_seam"] = seam
	return result


static func _qualify_resolvability(probe: RefCounted) -> Dictionary:
	var failures: Array[String] = []
	var records: Array[Dictionary] = []
	var signature_lines: Array[String] = []
	var counts := {"pass": 0, "degraded": 0, "intentional_disappearance": 0}
	var feature_kinds := [
		"sphere_diameter",
		"tunnel_clearance",
		"wall_thickness",
		"curvature_radius",
		"smoothing_width",
		"noise_wavelength",
	]
	for lod in range(MAXIMUM_LOD + 1):
		var cell_size := BASE_CELL_SIZE_M * float(1 << lod)
		for feature_kind in feature_kinds:
			for feature_cells in [1.0, 2.0, 3.0, 4.0, 8.0]:
				var classification := _feature_classification(feature_cells)
				counts[classification] = int(counts[classification]) + 1
				var field := _resolvability_field(str(feature_kind), lod, feature_cells)
				var chunk := NativeEvidence.mesh_chunk(probe, field, Vector3i.ZERO, lod)
				var validation := NativeEvidence.validate_chunk(chunk)
				_expect(str(validation.get("status", "")) == "PASS", "%s LOD%d %.1f-cell mesh invalid" % [feature_kind, lod, feature_cells], failures)
				var triangle_count := int(validation.get("triangle_count", 0))
				if classification == "pass":
					_expect(triangle_count > 0, "%s LOD%d pass feature disappeared" % [feature_kind, lod], failures)
				var signature := NativeEvidence.chunk_signature(chunk)
				records.append({
					"feature": feature_kind,
					"lod": lod,
					"cell_size_m": cell_size,
					"feature_size_m": cell_size * feature_cells,
					"feature_cells": feature_cells,
					"classification": classification,
					"triangle_count": triangle_count,
					"observed": "present" if triangle_count > 0 else "disappeared",
					"geometry_signature": signature,
				})
				signature_lines.append("%s:%d:%.1f:%s:%d:%s" % [feature_kind, lod, feature_cells, classification, triangle_count, signature])
	_expect(records.size() == 240, "resolvability record count changed", failures)
	var result := _result("TQP-12", records.size(), failures)
	result["feature_kinds"] = feature_kinds
	result["classification_counts"] = counts
	result["matrix_signature"] = "\n".join(signature_lines).sha256_text()
	result["records"] = records
	return result


static func _qualify_journal() -> Dictionary:
	var failures: Array[String] = []
	var field := EditField.new()
	var transaction_one := [
		{"id": "journal-dig", "mode": "dig", "shape": "sphere", "center": Vector3(8.0, 10.0, 8.0), "radius_m": 2.5},
		{"id": "journal-build", "mode": "construct", "shape": "rounded_box", "center": Vector3(20.0, 15.0, 20.0), "half_extents": Vector3(3.0, 1.0, 2.0), "rounding_m": 0.25, "radius_m": 1.0, "material": 7},
	]
	_expect(field.add_transaction("transaction-001", transaction_one), "first transaction rejected", failures)
	var signature_after_first := field.journal_signature()
	_expect(not field.add_transaction("transaction-001", transaction_one), "duplicate transaction accepted", failures)
	_expect(field.journal_signature() == signature_after_first, "failed transaction mutated journal", failures)
	_expect(field.add_transaction("transaction-002", [
		{"id": "journal-span", "mode": "construct", "shape": "capsule", "segment_a": Vector3(12.0, 14.0, 12.0), "segment_b": Vector3(18.0, 14.0, 18.0), "radius_m": 1.2, "material": 8},
		{"id": "journal-opening", "mode": "dig", "shape": "sphere", "center": Vector3(15.0, 14.0, 15.0), "radius_m": 0.8},
	]), "second transaction rejected", failures)
	var full_signature := field.journal_signature()
	_expect(field.undo_latest_transaction() == "transaction-002", "transaction undo order changed", failures)
	_expect(field.set_transaction_enabled("transaction-002", true), "transaction redo failed", failures)
	_expect(field.journal_signature() == full_signature, "transaction undo/redo changed journal", failures)
	_expect(field.set_operation_enabled("journal-opening", false), "operation cancellation failed", failures)
	var points := _probe_points(128, 0xBACE1100)
	var compacted := field.compacted_serialized_journal()
	var compacted_field := EditField.new()
	_expect(compacted_field.reconstruct(compacted), "compacted journal reconstruction failed", failures)
	for point in points:
		_expect(is_equal_approx(field.density(point), compacted_field.density(point)), "compaction changed density", failures)
		_expect(field.material_at(point, field.density(point)) == compacted_field.material_at(point, compacted_field.density(point)), "compaction changed material", failures)
	var replay := EditField.new()
	_expect(replay.reconstruct(field.serialized_journal()), "journal replay failed", failures)
	var bake := field.bake_probe_snapshot(points)
	var replay_bake := replay.bake_probe_snapshot(points)
	_expect(str(bake.get("sample_signature", "")) == str(replay_bake.get("sample_signature", "")), "baked probe snapshot changed after replay", failures)
	var legacy_operations: Array[Dictionary] = []
	for operation in transaction_one:
		legacy_operations.append(EditField.canonical_operation(operation))
	var legacy_document := {
		"schema": EditField.JOURNAL_SCHEMA_V1,
		"operations": legacy_operations,
	}
	var migrated := EditField.new()
	migrated.terrain_profile = "solid"
	migrated.sample_scale_m = 3.0
	migrated.base_height_m = 99.0
	_expect(migrated.reconstruct(JSON.stringify(legacy_document)), "v1 journal migration failed", failures)
	var migrated_document: Dictionary = JSON.parse_string(migrated.serialized_journal())
	_expect(str(migrated_document.get("schema", "")) == EditField.JOURNAL_SCHEMA, "migration did not advance journal schema", failures)
	_expect(migrated.terrain_profile == "flat", "v1 migration profile default changed", failures)
	_expect(is_equal_approx(migrated.sample_scale_m, EditField.DEFAULT_SAMPLE_SCALE_M), "v1 migration sample scale default changed", failures)
	_expect(is_equal_approx(migrated.base_height_m, EditField.BASE_HEIGHT_M), "v1 migration base height default changed", failures)
	var atomic_before := field.serialized_journal()
	var invalid_document: Dictionary = JSON.parse_string(atomic_before)
	(invalid_document["operations"] as Array).append(
		(invalid_document["operations"] as Array)[0]
	)
	_expect(not field.reconstruct(JSON.stringify(invalid_document)), "duplicate journal operation accepted", failures)
	_expect(field.serialized_journal() == atomic_before, "failed reconstruction mutated field", failures)
	var result := _result("TQP-13", points.size() * 4 + 19, failures)
	result["journal_signature"] = field.journal_signature()
	result["compacted_journal_signature"] = compacted.sha256_text()
	result["bake_signature"] = str(bake.get("sample_signature", ""))
	result["migration_target"] = EditField.JOURNAL_SCHEMA
	result["transaction_count"] = 2
	result["operation_count"] = field.operations.size()
	return result


static func _qualify_long_soak(probe: RefCounted) -> Dictionary:
	var failures: Array[String] = []
	var field := EditField.new()
	field.base_height_m = 12.25
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EED1200
	var append_timings: Array[float] = []
	var checkpoints: Array[Dictionary] = []
	for batch in range(int(SOAK_OPERATION_COUNT / 8)):
		var transaction: Array[Dictionary] = []
		for offset in range(8):
			var index := batch * 8 + offset
			transaction.append(_soak_operation(index, rng))
		var append_started := Time.get_ticks_usec()
		_expect(field.add_transaction("soak-tx-%04d" % batch, transaction), "soak transaction rejected", failures)
		if batch >= 10:
			append_timings.append(float(Time.get_ticks_usec() - append_started))
		if (batch + 1) % 64 == 0:
			var serialized_checkpoint := field.serialized_journal()
			var replay_checkpoint := EditField.new()
			_expect(replay_checkpoint.reconstruct(serialized_checkpoint), "checkpoint replay failed", failures)
			var checkpoint_points := _probe_points(64, 0x120000 + batch)
			var source_bake := field.bake_probe_snapshot(checkpoint_points)
			var replay_bake := replay_checkpoint.bake_probe_snapshot(checkpoint_points)
			_expect(str(source_bake.get("sample_signature", "")) == str(replay_bake.get("sample_signature", "")), "checkpoint sample signature changed", failures)
			checkpoints.append({
				"operation_count": field.operations.size(),
				"journal_signature": field.journal_signature(),
				"sample_signature": str(source_bake.get("sample_signature", "")),
			})
	for transaction_index in range(0, int(SOAK_OPERATION_COUNT / 8), 17):
		_expect(field.set_transaction_enabled("soak-tx-%04d" % transaction_index, false), "soak transaction cancellation failed", failures)
	var compacted := field.compacted_serialized_journal()
	var replay := EditField.new()
	_expect(replay.reconstruct(compacted), "soak compacted replay failed", failures)
	var final_points := _probe_points(256, 0x5EED12FF)
	var source_bake := field.bake_probe_snapshot(final_points)
	var replay_bake := replay.bake_probe_snapshot(final_points)
	_expect(str(source_bake.get("sample_signature", "")) == str(replay_bake.get("sample_signature", "")), "soak final replay changed samples", failures)
	var chunks: Array[Dictionary] = []
	var replay_chunks: Array[Dictionary] = []
	var chunk_by_key := {}
	var geometry_lines: Array[String] = []
	var collision_failures := 0
	for x in range(-1, 2):
		for z in range(-1, 2):
			var coordinate := Vector3i(x, 1, z)
			var chunk := NativeEvidence.mesh_chunk(probe, field, coordinate, 0)
			var replay_chunk := NativeEvidence.mesh_chunk(probe, replay, coordinate, 0)
			var validation := NativeEvidence.validate_chunk(chunk)
			var collision := NativeEvidence.collision_evidence(chunk, field.sample_scale_m)
			_expect(str(validation.get("status", "")) == "PASS", "soak native chunk invalid", failures)
			if str(collision.get("status", "")) != "PASS":
				collision_failures += 1
			var signature := NativeEvidence.chunk_signature(chunk)
			_expect(signature == NativeEvidence.chunk_signature(replay_chunk), "soak replay geometry changed", failures)
			chunks.append(chunk)
			replay_chunks.append(replay_chunk)
			chunk_by_key[_chunk_key(coordinate)] = chunk
			geometry_lines.append(_chunk_key(coordinate) + ":" + signature)
	_expect(collision_failures == 0, "soak collision publication failed", failures)
	var seam_records: Array[Dictionary] = []
	for x in range(-1, 1):
		for z in range(-1, 2):
			seam_records.append(NativeEvidence.same_lod_seam(
				chunk_by_key[_chunk_key(Vector3i(x, 1, z))],
				chunk_by_key[_chunk_key(Vector3i(x + 1, 1, z))],
				0
			))
	for x in range(-1, 2):
		for z in range(-1, 1):
			seam_records.append(NativeEvidence.same_lod_seam(
				chunk_by_key[_chunk_key(Vector3i(x, 1, z))],
				chunk_by_key[_chunk_key(Vector3i(x, 1, z + 1))],
				2
			))
	var seam_failures := 0
	for seam in seam_records:
		if str(seam.get("status", "")) != "PASS":
			seam_failures += 1
	_expect(seam_failures == 0, "soak same-LOD seam mismatch", failures)
	var query_timings: Array[float] = []
	for iteration in range(110):
		var query_started := Time.get_ticks_usec()
		for point_index in range(64):
			field.density(final_points[(iteration + point_index) % final_points.size()])
		if iteration >= 10:
			query_timings.append(float(Time.get_ticks_usec() - query_started))
	var mesh_timings: Array[float] = []
	for iteration in range(110):
		var mesh_started := Time.get_ticks_usec()
		NativeEvidence.mesh_chunk(
			probe,
			field,
			Vector3i(iteration % 3 - 1, 1, int(iteration / 3) % 3 - 1),
			0
		)
		if iteration >= 10:
			mesh_timings.append(float(Time.get_ticks_usec() - mesh_started))
	var result := _result("TQP-14", SOAK_OPERATION_COUNT + checkpoints.size() * 64 + chunks.size() + seam_records.size(), failures)
	result["operation_count"] = field.operations.size()
	result["enabled_operation_count"] = (JSON.parse_string(compacted) as Dictionary).get("operations", []).size()
	result["checkpoint_count"] = checkpoints.size()
	result["checkpoints"] = checkpoints
	result["journal_signature"] = field.journal_signature()
	result["compacted_journal_signature"] = compacted.sha256_text()
	result["sample_signature"] = str(source_bake.get("sample_signature", ""))
	result["geometry_signature"] = "\n".join(geometry_lines).sha256_text()
	result["chunk_count"] = chunks.size()
	result["seam_count"] = seam_records.size()
	result["seam_failures"] = seam_failures
	result["seams"] = seam_records
	result["collision_failures"] = collision_failures
	result["spatial"] = field.spatial_metrics()
	result["journal_bytes"] = compacted.to_utf8_buffer().size()
	result["performance"] = {
		"transaction_append": Statistics.distribution(append_timings),
		"query_batch_64": Statistics.distribution(query_timings),
		"native_chunk_rebuild": Statistics.distribution(mesh_timings),
	}
	result["memory"] = Statistics.memory_metrics()
	return result


static func _native_record(
	probe: RefCounted,
	field: RefCounted,
	coordinate: Vector3i,
	lod: int
) -> Dictionary:
	var started := Time.get_ticks_usec()
	var chunk := NativeEvidence.mesh_chunk(probe, field, coordinate, lod)
	var validation := NativeEvidence.validate_chunk(chunk)
	var collision := NativeEvidence.collision_evidence(chunk, float(field.get("sample_scale_m")))
	var failures: Array = validation.get("failures", []).duplicate()
	if str(collision.get("status", "")) != "PASS":
		failures.append("collision publication differs from native mesh")
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"lod": lod,
		"coordinate": coordinate,
		"vertex_count": int(validation.get("vertex_count", 0)),
		"triangle_count": int(validation.get("triangle_count", 0)),
		"material_ids": validation.get("material_ids", []),
		"geometry_signature": NativeEvidence.chunk_signature(chunk),
		"collision_signature": str(collision.get("published_signature", "")),
		"elapsed_usec": Time.get_ticks_usec() - started,
		"failures": failures,
	}


static func _resolvability_field(
	feature_kind: String,
	lod: int,
	feature_cells: float
) -> RefCounted:
	var field := EditField.new()
	var cell_size := BASE_CELL_SIZE_M * float(1 << lod)
	var extent := cell_size * 16.0
	var center := Vector3.ONE * (extent * 0.5)
	var feature_size := cell_size * feature_cells
	var operations: Array[Dictionary] = []
	match feature_kind:
		"sphere_diameter":
			field.terrain_profile = "empty"
			operations.append({"id": "feature", "mode": "construct", "shape": "sphere", "center": center, "radius_m": feature_size * 0.5, "material": 7})
		"tunnel_clearance":
			field.terrain_profile = "solid"
			operations.append({"id": "feature", "mode": "dig", "shape": "capsule", "segment_a": center - Vector3(cell_size * 3.0, 0.0, 0.0), "segment_b": center + Vector3(cell_size * 3.0, 0.0, 0.0), "radius_m": feature_size * 0.5})
		"wall_thickness":
			field.terrain_profile = "empty"
			operations.append({"id": "feature", "mode": "construct", "shape": "plane_stamp", "center": center, "normal": Vector3.UP, "radius_m": extent * 0.32, "depth_m": feature_size, "material": 7})
		"curvature_radius":
			field.terrain_profile = "empty"
			operations.append({"id": "feature", "mode": "construct", "shape": "rounded_box", "center": center, "half_extents": Vector3.ONE * cell_size * 4.0, "rounding_m": minf(feature_size * 0.5, cell_size * 3.9), "radius_m": cell_size, "material": 7})
		"smoothing_width":
			field.terrain_profile = "empty"
			operations.append({"id": "feature-a", "mode": "construct", "shape": "sphere", "center": center - Vector3(cell_size * 2.0, 0.0, 0.0), "radius_m": cell_size * 3.0, "smoothing_m": feature_size, "material": 7})
			operations.append({"id": "feature-b", "mode": "construct", "shape": "sphere", "center": center + Vector3(cell_size * 2.0, 0.0, 0.0), "radius_m": cell_size * 3.0, "smoothing_m": feature_size, "material": 7})
		"noise_wavelength":
			field.terrain_profile = "empty"
			operations.append({"id": "feature", "mode": "construct", "shape": "bounded_noise", "center": center, "radius_m": extent * 0.26, "noise_amplitude_m": cell_size * 0.35, "noise_frequency": 1.0 / maxf(feature_size, 0.0001), "material": 7})
	for operation in operations:
		field.add_operation(operation)
	return field


static func _feature_classification(feature_cells: float) -> String:
	if feature_cells >= 4.0:
		return "pass"
	if feature_cells >= 2.0:
		return "degraded"
	return "intentional_disappearance"


static func _shape_fixtures(center: Vector3, scale: float) -> Array[Dictionary]:
	return [
		{"id": "sphere", "mode": "construct", "shape": "sphere", "center": center, "radius_m": 2.0 * scale},
		{"id": "capsule", "mode": "construct", "shape": "capsule", "center": center, "segment_a": center + Vector3(-2.0, 0.0, 0.0) * scale, "segment_b": center + Vector3(2.0, 0.0, 0.0) * scale, "radius_m": 1.0 * scale},
		{"id": "swept_stroke", "mode": "construct", "shape": "swept_stroke", "center": center, "segment_a": center + Vector3(0.0, -2.0, 0.0) * scale, "segment_b": center + Vector3(0.0, 2.0, 0.0) * scale, "radius_m": 0.75 * scale},
		{"id": "rounded_box", "mode": "construct", "shape": "rounded_box", "center": center, "half_extents": Vector3(2.0, 1.0, 1.5) * scale, "rounding_m": 0.25 * scale, "radius_m": scale},
		{"id": "plane_stamp", "mode": "construct", "shape": "plane_stamp", "center": center, "normal": Vector3.UP, "radius_m": 3.0 * scale, "depth_m": 1.0 * scale},
		{"id": "ellipsoid_stamp", "mode": "construct", "shape": "ellipsoid_stamp", "center": center, "half_extents": Vector3(2.0, 1.0, 2.5) * scale, "radius_m": scale},
		{"id": "bounded_noise", "mode": "construct", "shape": "bounded_noise", "center": center, "radius_m": 2.0 * scale, "noise_amplitude_m": 0.2 * scale, "noise_frequency": 1.5 / scale},
	]


static func _translated_shape(source: Dictionary, center: Vector3) -> Dictionary:
	var result := source.duplicate(true)
	var source_center: Vector3 = source.get("center", Vector3.ZERO)
	var offset := center - source_center
	result["center"] = center
	if source.has("segment_a"):
		result["segment_a"] = (source.get("segment_a", Vector3.ZERO) as Vector3) + offset
	if source.has("segment_b"):
		result["segment_b"] = (source.get("segment_b", Vector3.ZERO) as Vector3) + offset
	return result


static func _soak_operation(index: int, rng: RandomNumberGenerator) -> Dictionary:
	var center := Vector3(
		rng.randf_range(-96.0, 96.0),
		rng.randf_range(4.0, 20.0),
		rng.randf_range(-96.0, 96.0)
	)
	var radius := rng.randf_range(0.6, 5.5)
	var operation := {
		"id": "soak-%04d" % index,
		"mode": "dig" if index % 3 == 0 else "construct",
		"shape": "sphere",
		"center": center,
		"radius_m": radius,
		"material": 2 + index % 7,
		"smoothing_m": 0.0 if index % 5 else minf(radius * 0.2, 0.8),
	}
	match index % 4:
		1:
			operation["shape"] = "capsule"
			operation["segment_a"] = center - Vector3(radius, 0.0, radius * 0.5)
			operation["segment_b"] = center + Vector3(radius, 0.0, radius * 0.5)
		2:
			operation["shape"] = "rounded_box"
			operation["half_extents"] = Vector3(radius, maxf(radius * 0.45, 0.3), radius * 0.7)
			operation["rounding_m"] = minf(radius * 0.2, maxf(radius * 0.4, 0.2))
		3:
			operation["shape"] = "bounded_noise"
			operation["noise_amplitude_m"] = radius * 0.15
			operation["noise_frequency"] = rng.randf_range(0.4, 1.8)
	return operation


static func _probe_points(count: int, seed_value: int) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var points: Array[Vector3] = []
	for index in range(count):
		points.append(Vector3(
			rng.randf_range(-112.0, 112.0),
			rng.randf_range(-8.0, 32.0),
			rng.randf_range(-112.0, 112.0)
		))
	return points


static func _stable_summary(milestones: Array[Dictionary], visual: Dictionary) -> Dictionary:
	var by_id := {}
	for milestone in milestones:
		by_id[str(milestone.get("milestone", ""))] = milestone
	return {
		"TQP-09": {
			"shape_ids": by_id["TQP-09"].get("shape_ids", []),
			"shape_signature": by_id["TQP-09"].get("shape_signature", ""),
			"native_shape_signature": by_id["TQP-09"].get("native_shape_signature", ""),
		},
		"TQP-10": {
			"lod_count": (by_id["TQP-10"].get("lod_records", []) as Array).size(),
			"geometry_signature": by_id["TQP-10"].get("geometry_signature", ""),
			"seam_failures": int((by_id["TQP-10"].get("boundary_seam", {}) as Dictionary).get("left_only_count", -1)) + int((by_id["TQP-10"].get("boundary_seam", {}) as Dictionary).get("right_only_count", -1)),
		},
		"TQP-11": {
			"lod_count": (by_id["TQP-11"].get("lod_records", []) as Array).size(),
			"geometry_signature": by_id["TQP-11"].get("geometry_signature", ""),
			"seam_failures": int((by_id["TQP-11"].get("boundary_seam", {}) as Dictionary).get("left_only_count", -1)) + int((by_id["TQP-11"].get("boundary_seam", {}) as Dictionary).get("right_only_count", -1)),
		},
		"TQP-12": {
			"record_count": (by_id["TQP-12"].get("records", []) as Array).size(),
			"classification_counts": by_id["TQP-12"].get("classification_counts", {}),
			"matrix_signature": by_id["TQP-12"].get("matrix_signature", ""),
		},
		"TQP-13": {
			"journal_signature": by_id["TQP-13"].get("journal_signature", ""),
			"compacted_journal_signature": by_id["TQP-13"].get("compacted_journal_signature", ""),
			"bake_signature": by_id["TQP-13"].get("bake_signature", ""),
			"migration_target": by_id["TQP-13"].get("migration_target", ""),
		},
		"TQP-14": {
			"operation_count": by_id["TQP-14"].get("operation_count", 0),
			"checkpoint_count": by_id["TQP-14"].get("checkpoint_count", 0),
			"chunk_count": by_id["TQP-14"].get("chunk_count", 0),
			"seam_count": by_id["TQP-14"].get("seam_count", 0),
			"seam_failures": by_id["TQP-14"].get("seam_failures", -1),
			"collision_failures": by_id["TQP-14"].get("collision_failures", -1),
			"sample_signature": by_id["TQP-14"].get("sample_signature", ""),
			"geometry_signature": by_id["TQP-14"].get("geometry_signature", ""),
		},
		"visual_pixel_signature": visual.get("reference_signature", ""),
	}


static func _compare_standard(actual: Dictionary, expected: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	if expected.is_empty():
		failures.append("stable_expected is missing")
	else:
		_compare_value(actual, expected, "stable_expected", failures)
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"failures": failures,
	}


static func _compare_value(
	actual: Variant,
	expected: Variant,
	path: String,
	failures: Array[String]
) -> void:
	if typeof(actual) in [TYPE_INT, TYPE_FLOAT] \
			and typeof(expected) in [TYPE_INT, TYPE_FLOAT]:
		if not is_equal_approx(float(actual), float(expected)):
			failures.append("%s expected=%s actual=%s" % [path, str(expected), str(actual)])
		return
	if typeof(actual) != typeof(expected):
		failures.append(path + " type differs")
		return
	if expected is Dictionary:
		for key in expected:
			if not (actual as Dictionary).has(key):
				failures.append(path + "." + str(key) + " is missing")
				continue
			_compare_value((actual as Dictionary)[key], expected[key], path + "." + str(key), failures)
		return
	if expected is Array:
		if actual != expected:
			failures.append(path + " differs")
		return
	if actual != expected:
		failures.append("%s expected=%s actual=%s" % [path, str(expected), str(actual)])


static func _compare_performance(
	milestones: Array[Dictionary],
	budgets: Dictionary
) -> Dictionary:
	var failures: Array[String] = []
	var by_id := {}
	for milestone in milestones:
		by_id[str(milestone.get("milestone", ""))] = milestone
	var brush_p95 := float((by_id["TQP-09"].get("performance", {}) as Dictionary).get("p95_usec", INF))
	var soak_performance: Dictionary = by_id["TQP-14"].get("performance", {})
	var append_p95 := float((soak_performance.get("transaction_append", {}) as Dictionary).get("p95_usec", INF))
	var query_p95 := float((soak_performance.get("query_batch_64", {}) as Dictionary).get("p95_usec", INF))
	var mesh_p95 := float((soak_performance.get("native_chunk_rebuild", {}) as Dictionary).get("p95_usec", INF))
	var journal_bytes := int(by_id["TQP-14"].get("journal_bytes", 0))
	var largest_bucket := int((by_id["TQP-14"].get("spatial", {}) as Dictionary).get("largest_bucket", 0))
	var measured := {
		"brush_batch_p95_usec": brush_p95,
		"transaction_append_p95_usec": append_p95,
		"query_batch_64_p95_usec": query_p95,
		"native_chunk_rebuild_p95_usec": mesh_p95,
		"journal_bytes": journal_bytes,
		"largest_spatial_bucket": largest_bucket,
	}
	for key in measured:
		if not budgets.has(key):
			failures.append("missing performance budget: " + str(key))
			continue
		if float(measured[key]) > float(budgets[key]):
			failures.append("%s budget=%s measured=%s" % [str(key), str(budgets[key]), str(measured[key])])
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"scope": "reference_debug_workload_not_production_frame_budget",
		"measured": measured,
		"budgets": budgets,
		"failures": failures,
	}


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func _chunk_key(coordinate: Vector3i) -> String:
	return "%d:%d:%d" % [coordinate.x, coordinate.y, coordinate.z]


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
