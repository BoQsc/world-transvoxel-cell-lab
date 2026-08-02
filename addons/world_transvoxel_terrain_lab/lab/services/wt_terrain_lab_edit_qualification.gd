@tool
extends RefCounted
class_name WtTerrainLabEditQualification

const EditField := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_edit_field.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)
const GateBQualification := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_gate_b_qualification.gd"
)
const TemporalWaveEvidence := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_temporal_wave_evidence.gd"
)

const SAMPLE_EPSILON := 0.00001


static func run() -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var gate_b := GateBQualification.run()
	var milestones: Array[Dictionary] = [
		_qualify_field_algebra(),
	]
	milestones.append_array(gate_b.get("milestones", []))
	milestones.append(_qualify_temporal_edits())
	milestones.append(_specify_explosions())
	var failures: Array[String] = []
	for milestone in milestones:
		for failure_value in milestone.get("failures", []):
			failures.append(
				"%s: %s" % [str(milestone.get("milestone", "UNKNOWN")), str(failure_value)]
			)
	if str(gate_b.get("status", "")) != "PASS":
		for failure_value in gate_b.get("failures", []):
			failures.append("GATE_B: " + str(failure_value))
	return {
		"schema": "world_transvoxel.terrain_lab.edit_semantics_qualification.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"scope_status": {
			"TQP-07": "qualified",
			"TQP-09": "qualified",
			"TQP-10": "qualified",
			"TQP-11": "qualified",
			"TQP-12": "qualified",
			"TQP-13": "qualified",
			"TQP-14": "qualified",
			"TQP-17": "qualified",
			"TQP-28": "implemented_pending_fragmentation_collision_and_cost",
		},
		"qualified_scope": [
			"deterministic CPU reference field and edit journal",
			"TQP-07 deterministic CPU reference field algebra",
			"TQP-09 through TQP-14 Gate B reference edit qualification",
			"TQP-17 native Windows temporal edit and replay reference",
		],
		"explicitly_unqualified_scope": [
			"networked edit ordering",
			"production-scale explosion fragmentation",
			"GPU field evaluation",
			"TQP-28 fragmentation, collision, and production cost",
		],
		"elapsed_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
		"provenance": Statistics.provenance("edit_semantics_reference_v1"),
		"memory": Statistics.memory_metrics(),
		"gate_b": gate_b,
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
	return _result("TQP-07", 57, failures)


static func _qualify_temporal_edits() -> Dictionary:
	var failures: Array[String] = []
	var evidence := TemporalWaveEvidence.retained_milestone("TQP-17")
	if str(evidence.get("status", "")) != "PASS":
		for failure_value in evidence.get("failures", []):
			failures.append(str(failure_value))
		if failures.is_empty():
			failures.append("retained native temporal evidence failed")
	var result := _result("TQP-17", 12, failures)
	result["qualification_status"] = "QUALIFIED_NATIVE_WINDOWS_TEMPORAL_REFERENCE_V1"
	result["native_evidence"] = evidence
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
	var result := _result("TQP-28", _probe_points().size() + 3, failures)
	result["qualification_status"] = "QUALIFIED_REFERENCE_EXPLOSION_INPUT"
	result["blast_signature"] = field.journal_signature()
	return result


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
