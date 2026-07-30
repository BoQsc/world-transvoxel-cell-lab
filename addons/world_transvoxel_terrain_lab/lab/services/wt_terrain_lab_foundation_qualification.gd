@tool
extends RefCounted
class_name WtTerrainLabFoundationQualification

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)

const STANDARD_PATHS: Array[String] = [
	"res://addons/world_transvoxel_terrain_lab/standards/operating_envelope.json",
	"res://addons/world_transvoxel_terrain_lab/standards/authority_data_model.json",
	"res://addons/world_transvoxel_terrain_lab/standards/coordinate_precision_standard.json",
	"res://addons/world_transvoxel_terrain_lab/standards/resolution_error_standard.json",
	"res://addons/world_transvoxel_terrain_lab/standards/qualification_protocol.json",
]

const EXPECTED_SCHEMAS := {
	"TQP-01": "world_transvoxel.terrain_lab.operating_envelope.v1",
	"TQP-02": "world_transvoxel.terrain_lab.authority_data_model.v1",
	"TQP-03": "world_transvoxel.terrain_lab.coordinate_precision.v1",
	"TQP-04": "world_transvoxel.terrain_lab.resolution_error.v1",
	"TQP-05": "world_transvoxel.terrain_lab.qualification_protocol.v1",
}


static func run() -> Dictionary:
	var standards: Array[Dictionary] = []
	var failures: Array[String] = []
	for path in STANDARD_PATHS:
		var standard := JsonLoader.load_dictionary(path)
		standards.append(standard)
		if standard.is_empty():
			failures.append("missing or invalid standard: " + path)

	var results: Array[Dictionary] = []
	if failures.is_empty():
		results = [
			_qualify_operating_envelope(standards[0]),
			_qualify_authority_model(standards[1]),
			_qualify_coordinates(standards[2]),
			_qualify_resolution(standards[3]),
			_qualify_protocol(standards[4]),
		]
	for result in results:
		for failure_value in result.get("failures", []):
			failures.append(
				"%s: %s" % [str(result.get("milestone", "UNKNOWN")), str(failure_value)]
			)

	return {
		"schema": "world_transvoxel.terrain_lab.foundation_qualification.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"qualified_scope": [
			"reference CPU/Windows laboratory contracts for TQP-01 through TQP-05",
		],
		"explicitly_unqualified_scope": [
			"production terrain runtime",
			"GPU coordinate equivalence",
			"non-Windows platforms",
			"production visual quality",
		],
		"fixture_classes": ["positive", "boundary", "retained_negative"],
		"independent_invariants": [
			"integer chunk addressing round trip",
			"LOD scale derivation",
			"authority uniqueness",
			"benchmark evidence completeness",
		],
		"standard_signature": JsonLoader.stable_file_signature(STANDARD_PATHS),
		"milestones": results,
		"failures": failures,
	}


static func _qualify_operating_envelope(standard: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	_expect_schema("TQP-01", standard, failures)
	var world: Dictionary = standard.get("world", {})
	var workload: Dictionary = standard.get("workload", {})
	var budgets: Dictionary = standard.get("budgets", {})
	var targets: Dictionary = standard.get("targets", {})
	var multiplayer: Dictionary = standard.get("multiplayer", {})
	var art_direction: Dictionary = standard.get("art_direction", {})
	_expect(
		float(world.get("horizontal_min_m", 0.0))
			< float(world.get("horizontal_max_m", 0.0)),
		"horizontal range must be increasing",
		failures
	)
	_expect(
		float(world.get("vertical_min_m", 0.0))
			< float(world.get("vertical_max_m", 0.0)),
		"vertical range must be increasing",
		failures
	)
	for key in [
		"smallest_important_feature_m",
		"view_distance_m",
		"maximum_camera_speed_mps",
	]:
		_expect(float(world.get(key, 0.0)) > 0.0, "world." + key + " must be positive", failures)
	_expect(
		int(workload.get("burst_edits_per_second", 0))
			>= int(workload.get("sustained_edits_per_second", 0)),
		"burst edit rate must cover sustained rate",
		failures
	)
	_expect(
		float(budgets.get("terrain_cpu_p95_ms", 0.0))
			< float(budgets.get("frame_ms", 0.0)),
		"terrain CPU budget must fit the frame budget",
		failures
	)
	_expect(
		int(budgets.get("peak_memory_mib", 0))
			>= int(budgets.get("retained_memory_mib", 0)),
		"peak memory must cover retained memory",
		failures
	)
	_expect(
		"Windows" in targets.get("platforms", []),
		"reference platform must be explicit",
		failures
	)
	_expect(
		not (multiplayer.get("explicitly_unqualified", []) as Array).is_empty(),
		"unqualified multiplayer scope must be explicit",
		failures
	)
	_expect(
		str(art_direction.get("production_pleasantness", "")) == "UNQUALIFIED",
		"production visual pleasantness must remain unqualified",
		failures
	)
	return _result("TQP-01", 10, failures)


static func _qualify_authority_model(standard: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	_expect_schema("TQP-02", standard, failures)
	var records: Array = standard.get("records", [])
	var names := {}
	for record_value in records:
		var record: Dictionary = record_value
		var name := str(record.get("name", ""))
		_expect(not name.is_empty(), "record name is required", failures)
		_expect(not names.has(name), "record name is duplicated: " + name, failures)
		names[name] = true
		_expect(
			not str(record.get("authority", "")).is_empty(),
			"record authority is required: " + name,
			failures
		)
		_expect(
			not str(record.get("lifecycle", "")).is_empty(),
			"record lifecycle is required: " + name,
			failures
		)
		_expect(record.has("persistent"), "record persistence is required: " + name, failures)
		_expect(record.has("derived"), "record derivation is required: " + name, failures)
	_expect(records.size() == 9, "the reference model must contain nine records", failures)
	var invariants: Array = standard.get("invariants", [])
	for required in [
		"one_authority_per_record",
		"derived_records_are_reconstructible",
		"publication_rejects_stale_dependency_signatures",
		"persistent_records_are_versioned_and_checksummed",
		"runtime_caches_never_override_source_authority",
	]:
		_expect(required in invariants, "missing authority invariant: " + required, failures)
	return _result("TQP-02", records.size() * 6 + 6, failures)


static func _qualify_coordinates(standard: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	_expect_schema("TQP-03", standard, failures)
	var chunk_size := int(standard.get("chunk_samples_per_axis", 0))
	_expect(chunk_size == 32, "reference chunk size must be 32 samples", failures)
	_expect(
		str(standard.get("negative_division", "")) == "mathematical_floor",
		"negative addressing must use mathematical floor",
		failures
	)
	var fixture_values: Array[int] = [
		-1000000, -65, -64, -33, -32, -31, -1, 0, 1, 31, 32, 33, 64, 65, 1000000,
	]
	for value in fixture_values:
		var chunk := _floor_div(value, chunk_size)
		var local := value - chunk * chunk_size
		_expect(local >= 0 and local < chunk_size, "local address outside chunk", failures)
		_expect(chunk * chunk_size + local == value, "integer address did not round trip", failures)
		if value == -1:
			_expect(chunk == -1 and local == 31, "negative boundary fixture changed", failures)
		if value == -32:
			_expect(chunk == -1 and local == 0, "exact negative boundary fixture changed", failures)
		if value == -33:
			_expect(chunk == -2 and local == 31, "negative adjacent fixture changed", failures)
	var floating_origin: Dictionary = standard.get("floating_origin", {})
	var threshold := float(floating_origin.get("shift_threshold_m", 0.0))
	var quantum := float(floating_origin.get("shift_quantum_m", 0.0))
	var maximum_local := float(floating_origin.get("maximum_local_magnitude_m", 0.0))
	_expect(threshold > 0.0 and quantum > 0.0, "floating-origin values must be positive", failures)
	_expect(maximum_local >= threshold + quantum, "local bound must cover one shift quantum", failures)
	var global_fixtures: Array[float] = [
		-32768.25, -4097.0, -4096.0, 0.0, 4096.0, 4097.0, 32768.25,
	]
	for global_value in global_fixtures:
		var origin: float = _quantized_origin(global_value, threshold, quantum)
		var local: float = global_value - origin
		_expect(absf(local) <= maximum_local, "floating-origin local bound exceeded", failures)
		_expect(
			is_equal_approx(origin + local, global_value),
			"floating-origin conversion did not round trip",
			failures
		)
	var precision: Dictionary = standard.get("precision_budgets", {})
	_expect(
		int(precision.get("integer_round_trip_error_samples", -1)) == 0,
		"integer round-trip budget must be zero",
		failures
	)
	_expect(
		str(standard.get("gpu_coordinate_equivalence", "")).begins_with("UNQUALIFIED"),
		"GPU equivalence must remain explicitly unqualified",
		failures
	)
	return _result("TQP-03", fixture_values.size() * 2 + 21, failures)


static func _qualify_resolution(standard: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	_expect_schema("TQP-04", standard, failures)
	var base_cell := float(standard.get("base_cell_size_m", 0.0))
	var maximum_lod := int(standard.get("maximum_lod", -1))
	var lods: Array = standard.get("lods", [])
	var classification: Dictionary = standard.get("feature_classification", {})
	var pass_cells := float(classification.get("pass_minimum_cells", 0.0))
	var degraded_cells := float(classification.get("degraded_minimum_cells", 0.0))
	_expect(base_cell > 0.0, "base cell size must be positive", failures)
	_expect(lods.size() == maximum_lod + 1, "LOD table must cover zero through maximum", failures)
	_expect(pass_cells > degraded_cells, "pass threshold must exceed degraded threshold", failures)
	for index in range(lods.size()):
		var lod: Dictionary = lods[index]
		var expected_cell := base_cell * pow(2.0, index)
		_expect(int(lod.get("lod", -1)) == index, "LOD sequence changed", failures)
		_expect(
			is_equal_approx(float(lod.get("cell_size_m", 0.0)), expected_cell),
			"LOD cell size is not base multiplied by two",
			failures
		)
		_expect(
			is_equal_approx(float(lod.get("pass_feature_m", 0.0)), expected_cell * pass_cells),
			"LOD pass feature threshold changed",
			failures
		)
		_expect(
			is_equal_approx(
				float(lod.get("degraded_feature_m", 0.0)),
				expected_cell * degraded_cells
			),
			"LOD degraded feature threshold changed",
			failures
		)
	_expect(
		str(standard.get("density_downsampling", "")) == "not_authoritative",
		"density downsampling must not become authority",
		failures
	)
	return _result("TQP-04", lods.size() * 4 + 5, failures)


static func _qualify_protocol(standard: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	_expect_schema("TQP-05", standard, failures)
	var states: Array = standard.get("promotion_states", [])
	for required in ["proposed", "specified", "implemented", "qualified", "production", "blocked"]:
		_expect(required in states, "missing promotion state: " + required, failures)
	var benchmark: Dictionary = standard.get("benchmark", {})
	_expect(int(benchmark.get("warmup_iterations", 0)) >= 10, "warmup policy is too weak", failures)
	_expect(int(benchmark.get("minimum_samples", 0)) >= 100, "sample policy is too weak", failures)
	for quantile in ["p50", "p95", "p99", "worst"]:
		_expect(
			quantile in benchmark.get("required_quantiles", []),
			"missing required quantile: " + quantile,
			failures
		)
	for metric in ["retained_bytes", "peak_bytes"]:
		_expect(
			metric in benchmark.get("required_memory_metrics", []),
			"missing memory metric: " + metric,
			failures
		)
	for metadata in [
		"workload_signature",
		"build_type",
		"os",
		"architecture",
		"cpu",
		"gpu",
		"driver",
		"godot_version",
		"backend_revision",
	]:
		_expect(
			metadata in benchmark.get("required_metadata", []),
			"missing provenance field: " + metadata,
			failures
		)
	var fixtures: Dictionary = standard.get("fixtures", {})
	for fixture_class in ["positive", "boundary", "retained_negative"]:
		_expect(
			fixture_class in fixtures.get("required_classes", []),
			"missing fixture class: " + fixture_class,
			failures
		)
	var visual: Dictionary = standard.get("visual", {})
	_expect(bool(visual.get("correctness_is_separate", false)), "visual correctness must be separate", failures)
	_expect(bool(visual.get("fixed_camera_required", false)), "fixed cameras must be required", failures)
	_expect(bool(visual.get("human_review_required", false)), "human review must be required", failures)
	var qualification: Dictionary = standard.get("qualification", {})
	for key in [
		"dependency_closure_required",
		"explicit_unqualified_scope_required",
		"machine_report_required",
		"regression_test_required",
		"production_requires_release_bundle",
	]:
		_expect(bool(qualification.get(key, false)), "qualification rule disabled: " + key, failures)
	return _result("TQP-05", 34, failures)


static func _expect_schema(
	milestone: String,
	standard: Dictionary,
	failures: Array[String]
) -> void:
	_expect(
		str(standard.get("schema", "")) == str(EXPECTED_SCHEMAS[milestone]),
		"schema mismatch",
		failures
	)


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


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


static func _floor_div(value: int, divisor: int) -> int:
	var quotient := int(value / divisor)
	var remainder := value % divisor
	if remainder < 0:
		quotient -= 1
	return quotient


static func _quantized_origin(
	global_value: float,
	threshold: float,
	quantum: float
) -> float:
	if absf(global_value) <= threshold:
		return 0.0
	return floorf(global_value / quantum) * quantum
