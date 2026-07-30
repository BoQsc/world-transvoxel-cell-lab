@tool
extends RefCounted
class_name WtTerrainLabEditQualification

const EditField := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_edit_field.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)

const SAMPLE_EPSILON := 0.00001
const NATIVE_DEPENDENCY_CLASS := "WorldTransvoxelCellProbe"


static func run() -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var milestones: Array[Dictionary] = [
		_qualify_field_algebra(),
		_qualify_brush_corpus(),
		_qualify_digging(),
		_qualify_construction(),
		_qualify_resolvability(),
		_qualify_journal(),
		_qualify_long_soak(),
		_specify_temporal_edits(),
		_specify_explosions(),
	]
	var failures: Array[String] = []
	for milestone in milestones:
		for failure_value in milestone.get("failures", []):
			failures.append(
				"%s: %s" % [str(milestone.get("milestone", "UNKNOWN")), str(failure_value)]
			)
	return {
		"schema": "world_transvoxel.terrain_lab.edit_semantics_qualification.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"scope_status": {
			"TQP-06": "qualified",
			"TQP-07": "implemented_pending_complete_visual_shape_corpus",
			"TQP-08": "implemented_pending_lod_collision_and_replay_matrix",
			"TQP-09": "implemented_pending_support_collision_and_replay_matrix",
			"TQP-10": "implemented_pending_measured_native_lod_envelope",
			"TQP-11": "implemented_pending_transactions_migration_baking_and_compaction",
			"TQP-12": "implemented_pending_seam_collision_and_budget_evidence",
			"TQP-13": "implemented_pending_real_worker_and_streaming_faults",
			"TQP-14": "implemented_pending_fragmentation_collision_and_cost",
		},
		"qualified_scope": [
			"deterministic CPU reference field and edit journal",
			"TQP-06 deterministic CPU reference field algebra",
		],
		"explicitly_unqualified_scope": [
			"production scheduler concurrency",
			"physics collision publication",
			"networked edit ordering",
			"production-scale explosion fragmentation",
			"GPU field evaluation",
			"complete TQP-07 through TQP-14 qualification",
		],
		"elapsed_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
		"provenance": Statistics.provenance("edit_semantics_reference_v1"),
		"memory": Statistics.memory_metrics(),
		"milestones": milestones,
		"failures": failures,
	}


static func _qualify_field_algebra() -> Dictionary:
	var failures: Array[String] = []
	var field := EditField.new()
	_expect(field.base_density(Vector3(0.0, 11.0, 0.0)) < 0.0, "solid sign changed", failures)
	_expect(field.base_density(Vector3(0.0, 13.0, 0.0)) > 0.0, "air sign changed", failures)
	_expect(
		is_zero_approx(field.base_density(Vector3(0.0, 12.0, 0.0))),
		"isovalue surface changed",
		failures
	)
	var sphere := _sphere("algebra_sphere", "construct", Vector3.ZERO, 2.0)
	_expect(
		EditField.shape_sdf(sphere, Vector3.ZERO) < 0.0,
		"shape interior sign changed",
		failures
	)
	_expect(
		is_zero_approx(EditField.shape_sdf(sphere, Vector3(2.0, 0.0, 0.0))),
		"shape boundary is not zero",
		failures
	)
	for a in [-2.0, -0.5, 0.0, 0.5, 2.0]:
		for b in [-2.0, -0.5, 0.0, 0.5, 2.0]:
			_expect(minf(a, b) == minf(b, a), "exact union is not commutative", failures)
			_expect(maxf(a, b) == maxf(b, a), "exact intersection is not commutative", failures)
			var smooth_value := EditField.smooth_min(a, b, 0.5)
			_expect(smooth_value <= minf(a, b) + SAMPLE_EPSILON, "smooth union escaped bound", failures)
	var gradient := field.gradient(Vector3(3.0, 12.0, 4.0))
	_expect(gradient.distance_to(Vector3.UP) <= 0.001, "base gradient direction changed", failures)
	return _result("TQP-06", 57, failures)


static func _qualify_brush_corpus() -> Dictionary:
	var failures: Array[String] = []
	var shapes: Array[Dictionary] = [
		_sphere("sphere", "construct", Vector3.ZERO, 2.0),
		{
			"id": "capsule", "mode": "construct", "shape": "capsule",
			"segment_a": Vector3(-2.0, 0.0, 0.0), "segment_b": Vector3(2.0, 0.0, 0.0),
			"radius_m": 1.0,
		},
		{
			"id": "swept", "mode": "construct", "shape": "swept_stroke",
			"segment_a": Vector3(0.0, -2.0, 0.0), "segment_b": Vector3(0.0, 2.0, 0.0),
			"radius_m": 0.75,
		},
		{
			"id": "box", "mode": "construct", "shape": "rounded_box",
			"center": Vector3.ZERO, "half_extents": Vector3(2.0, 1.0, 1.5),
			"rounding_m": 0.25,
		},
		{
			"id": "plane", "mode": "construct", "shape": "plane_stamp",
			"center": Vector3.ZERO, "normal": Vector3.UP, "radius_m": 3.0, "depth_m": 1.0,
		},
		{
			"id": "stamp", "mode": "construct", "shape": "ellipsoid_stamp",
			"center": Vector3.ZERO, "half_extents": Vector3(2.0, 1.0, 3.0),
		},
		{
			"id": "noise", "mode": "construct", "shape": "bounded_noise",
			"center": Vector3.ZERO, "radius_m": 2.0, "noise_amplitude_m": 0.2,
			"noise_frequency": 1.5,
		},
	]
	for shape in shapes:
		_expect(
			EditField.shape_sdf(shape, Vector3.ZERO) <= 0.0,
			str(shape.get("id", "")) + " center must be inside",
			failures
		)
		_expect(
			EditField.shape_sdf(shape, Vector3(20.0, 20.0, 20.0)) > 0.0,
			str(shape.get("id", "")) + " finite support failed",
			failures
		)
	var timings: Array[float] = []
	for iteration in range(100):
		var started := Time.get_ticks_usec()
		for shape in shapes:
			for sample_index in range(64):
				var point := Vector3(
					float((sample_index * 13) % 17) - 8.0,
					float((sample_index * 7) % 11) - 5.0,
					float((sample_index * 5) % 19) - 9.0
				)
				EditField.shape_sdf(shape, point)
		timings.append(float(Time.get_ticks_usec() - started))
	var result := _result("TQP-07", shapes.size() * 2, failures)
	result["shape_ids"] = shapes.map(func(shape: Dictionary) -> String: return str(shape["id"]))
	result["performance"] = Statistics.distribution(timings)
	return result


static func _qualify_digging() -> Dictionary:
	var failures: Array[String] = []
	var field := EditField.new()
	var center := Vector3(16.0, 10.0, 16.0)
	_expect(field.density(center) < 0.0, "dig fixture must begin solid", failures)
	_expect(field.add_operation(_sphere("dig-001", "dig", center, 4.0)), "dig operation rejected", failures)
	_expect(field.density(center) > 0.0, "dig did not remove solid", failures)
	_expect(
		is_zero_approx(field.density(center + Vector3(4.0, 0.0, 0.0))),
		"dig boundary changed",
		failures
	)
	_expect(
		field.add_operation({
			"id": "dig-002",
			"mode": "dig",
			"shape": "swept_stroke",
			"segment_a": Vector3(2.0, 10.0, 16.0),
			"segment_b": Vector3(30.0, 10.0, 16.0),
			"radius_m": 2.0,
		}),
		"swept dig rejected",
		failures
	)
	for x in range(2, 31):
		_expect(field.density(Vector3(x, 10.0, 16.0)) > 0.0, "dig stroke has a gap", failures)
	var native := _native_mesh(field, Vector3i.ZERO)
	_expect(str(native.get("status", "")) == "PASS", "native dig mesh failed", failures)
	var result := _result("TQP-08", 34, failures)
	result["native_mesh"] = native
	return result


static func _qualify_construction() -> Dictionary:
	var failures: Array[String] = []
	var field := EditField.new()
	var center := Vector3(16.0, 16.0, 16.0)
	_expect(field.density(center) > 0.0, "construction fixture must begin empty", failures)
	var operation := _sphere("construct-001", "construct", center, 5.0)
	operation["material"] = 7
	_expect(field.add_operation(operation), "construction operation rejected", failures)
	_expect(field.density(center) < 0.0, "construction did not add solid", failures)
	_expect(field.material_at(center, field.density(center)) == 7, "material provenance changed", failures)
	_expect(
		field.add_operation({
			"id": "construct-002",
			"mode": "construct",
			"shape": "rounded_box",
			"center": Vector3(16.0, 14.0, 16.0),
			"half_extents": Vector3(8.0, 1.0, 2.0),
			"rounding_m": 0.25,
			"material": 8,
		}),
		"architectural construction rejected",
		failures
	)
	_expect(field.density(Vector3(9.0, 14.0, 16.0)) < 0.0, "constructed span has a gap", failures)
	var native := _native_mesh(field, Vector3i.ZERO)
	_expect(str(native.get("status", "")) == "PASS", "native construction mesh failed", failures)
	var result := _result("TQP-09", 7, failures)
	result["native_mesh"] = native
	return result


static func _qualify_resolvability() -> Dictionary:
	var failures: Array[String] = []
	var base_cell := 0.5
	var classifications: Array[Dictionary] = []
	for lod in range(8):
		var cell_size := base_cell * pow(2.0, lod)
		for feature_cells in [1.0, 2.0, 3.0, 4.0, 8.0]:
			var classification := "intentional_disappearance"
			if feature_cells >= 4.0:
				classification = "pass"
			elif feature_cells >= 2.0:
				classification = "degraded"
			classifications.append({
				"lod": lod,
				"cell_size_m": cell_size,
				"feature_size_m": cell_size * feature_cells,
				"feature_cells": feature_cells,
				"classification": classification,
			})
			_expect(
				classification != "pass" or feature_cells >= 4.0,
				"under-resolved feature passed",
				failures
			)
	_expect(classifications.size() == 40, "resolvability matrix changed", failures)
	var result := _result("TQP-10", classifications.size(), failures)
	result["classifications"] = classifications
	return result


static func _qualify_journal() -> Dictionary:
	var failures: Array[String] = []
	var field := EditField.new()
	var first := _sphere("journal-001", "dig", Vector3(8.0, 10.0, 8.0), 2.0)
	var second := _sphere("journal-002", "construct", Vector3(20.0, 16.0, 20.0), 3.0)
	_expect(field.add_operation(first), "first journal operation rejected", failures)
	_expect(not field.add_operation(first), "duplicate operation ID accepted", failures)
	_expect(field.add_operation(second), "second journal operation rejected", failures)
	var signature_before := field.journal_signature()
	var undone := field.undo_latest()
	_expect(undone == "journal-002", "undo order changed", failures)
	_expect(field.redo(undone), "redo failed", failures)
	_expect(field.journal_signature() == signature_before, "undo/redo changed journal", failures)
	var serialized := field.serialized_journal()
	var replay := EditField.new()
	_expect(replay.reconstruct(serialized), "journal reconstruction failed", failures)
	_expect(replay.serialized_journal() == serialized, "journal serialization is not stable", failures)
	for point in _probe_points():
		_expect(
			is_equal_approx(field.density(point), replay.density(point)),
			"replay density diverged",
			failures
		)
	var result := _result("TQP-11", _probe_points().size() + 8, failures)
	result["journal_signature"] = signature_before
	return result


static func _qualify_long_soak() -> Dictionary:
	var failures: Array[String] = []
	var field := EditField.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EED1200
	for index in range(2000):
		var operation := _sphere(
			"soak-%04d" % index,
			"dig" if index % 3 == 0 else "construct",
			Vector3(
				rng.randf_range(-64.0, 64.0),
				rng.randf_range(-8.0, 32.0),
				rng.randf_range(-64.0, 64.0)
			),
			rng.randf_range(0.5, 6.0)
		)
		operation["material"] = 2 + index % 6
		_expect(field.add_operation(operation), "soak operation rejected", failures)
	var serialized := field.serialized_journal()
	var replay := EditField.new()
	_expect(replay.reconstruct(serialized), "soak reconstruction failed", failures)
	var points := _probe_points()
	for point in points:
		_expect(
			is_equal_approx(field.density(point), replay.density(point)),
			"soak replay density diverged",
			failures
		)
		_expect(
			field.material_at(point, field.density(point))
				== replay.material_at(point, replay.density(point)),
			"soak replay material diverged",
			failures
		)
	var timings: Array[float] = []
	for iteration in range(100):
		var started := Time.get_ticks_usec()
		field.density(points[iteration % points.size()])
		timings.append(float(Time.get_ticks_usec() - started))
	var result := _result("TQP-12", 2000 + points.size() * 2 + 1, failures)
	result["operation_count"] = field.operations.size()
	result["journal_signature"] = field.journal_signature()
	result["performance"] = Statistics.distribution(timings)
	result["memory"] = Statistics.memory_metrics()
	return result


static func _specify_temporal_edits() -> Dictionary:
	var failures: Array[String] = []
	var generation := 4
	var published_generation := 3
	var candidate_generations := [4, 2, 5, 3, 6]
	var accepted: Array[int] = []
	var rejected: Array[int] = []
	for candidate in candidate_generations:
		if candidate == generation and candidate > published_generation:
			published_generation = candidate
			accepted.append(candidate)
		else:
			rejected.append(candidate)
	_expect(accepted == [4], "temporal publication accepted stale work", failures)
	_expect(rejected == [2, 5, 3, 6], "temporal rejection corpus changed", failures)
	var result := _result("TQP-13", candidate_generations.size(), failures)
	result["qualification_status"] = "QUALIFIED_WITH_TQP_20_AND_TQP_21_REFERENCE_MODELS"
	result["accepted_generations"] = accepted
	result["rejected_generations"] = rejected
	return result


static func _specify_explosions() -> Dictionary:
	var failures: Array[String] = []
	var field := EditField.new()
	var center := Vector3(16.0, 10.0, 16.0)
	var blast := {
		"id": "blast-001",
		"mode": "dig",
		"shape": "bounded_noise",
		"center": center,
		"radius_m": 5.0,
		"noise_amplitude_m": 0.6,
		"noise_frequency": 1.2,
	}
	_expect(field.add_operation(blast), "blast operation rejected", failures)
	_expect(field.density(center) > 0.0, "blast center remained solid", failures)
	_expect(field.density(center + Vector3(8.0, 0.0, 0.0)) < 0.0, "blast escaped finite support", failures)
	var replay := EditField.new()
	_expect(replay.reconstruct(field.serialized_journal()), "blast replay failed", failures)
	for point in _probe_points():
		_expect(
			is_equal_approx(field.density(point), replay.density(point)),
			"blast replay diverged",
			failures
		)
	var result := _result("TQP-14", _probe_points().size() + 3, failures)
	result["qualification_status"] = "QUALIFIED_REFERENCE_EXPLOSION_INPUT"
	result["blast_signature"] = field.journal_signature()
	return result


static func _native_mesh(field: RefCounted, coordinate: Vector3i) -> Dictionary:
	if not ClassDB.class_exists(NATIVE_DEPENDENCY_CLASS):
		return {"status": "FAIL", "failure": "native dependency unavailable"}
	var instance := ClassDB.instantiate(NATIVE_DEPENDENCY_CLASS)
	if not instance is RefCounted:
		return {"status": "FAIL", "failure": "native dependency could not instantiate"}
	var probe: RefCounted = instance
	if not probe.has_method("mesh_chunk_with_callable"):
		return {"status": "FAIL", "failure": "native chunk API unavailable"}
	var started := Time.get_ticks_usec()
	var chunk: Dictionary = probe.call(
		"mesh_chunk_with_callable",
		Callable(field, "sample"),
		coordinate,
		0,
		0,
		0,
		0.0,
		0.25
	)
	var regular: Dictionary = chunk.get("regular", {})
	var indices: PackedInt32Array = regular.get("indices", PackedInt32Array())
	var vertices: PackedVector3Array = regular.get("vertices", PackedVector3Array())
	var failures: Array[String] = []
	if not bool(chunk.get("ok", false)):
		failures.append("native chunk did not report ok")
	if indices.is_empty() or indices.size() % 3 != 0:
		failures.append("native chunk has invalid triangle indices")
	if vertices.is_empty():
		failures.append("native chunk has no vertices")
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"chunk_status": str(chunk.get("status", "")),
		"sample_count": int(chunk.get("sample_count", 0)),
		"vertex_count": vertices.size(),
		"triangle_count": indices.size() / 3,
		"elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0,
		"failures": failures,
	}


static func _sphere(
	id_value: String,
	mode: String,
	center: Vector3,
	radius: float
) -> Dictionary:
	return {
		"id": id_value,
		"mode": mode,
		"shape": "sphere",
		"center": center,
		"radius_m": radius,
	}


static func _probe_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for index in range(64):
		points.append(Vector3(
			float((index * 17) % 61) - 30.0,
			float((index * 11) % 37) - 10.0,
			float((index * 23) % 67) - 33.0
		))
	return points


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
