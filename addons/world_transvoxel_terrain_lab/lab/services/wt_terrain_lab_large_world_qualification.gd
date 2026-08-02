@tool
extends RefCounted
class_name WtTerrainLabLargeWorldQualification

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)

const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/large_world_coordinate_standard.json"
)
const STANDARD_SCHEMA := "world_transvoxel.terrain_lab.large_world_coordinate_standard.v1"


static func run() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var failures: Array[String] = []
	_validate_standard(standard, failures)
	var corpus := _run_fixture_corpus(standard, failures)
	var performance := _benchmark(standard, failures)
	return {
		"milestone": "TQP-20",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"qualification_status": "QUALIFIED_CPU_LARGE_WORLD_COORDINATE_REFERENCE_V1",
		"fixture_count": int(corpus.get("fixture_count", 0)),
		"fixture_corpus": corpus,
		"performance": performance,
		"memory": Statistics.memory_metrics(),
		"provenance": Statistics.provenance("tqp20_cpu_large_world_coordinate_reference_v1"),
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"gpu_equivalence": str(standard.get("gpu_equivalence", "")),
		"failures": failures,
	}


static func _validate_standard(standard: Dictionary, failures: Array[String]) -> void:
	_expect(str(standard.get("schema", "")) == STANDARD_SCHEMA, "large-world standard schema changed", failures)
	_expect(str(standard.get("milestone", "")) == "TQP-20", "large-world standard milestone changed", failures)
	var authority: Dictionary = standard.get("authority", {})
	_expect(str(authority.get("sample_address", "")) == "signed_int64_xyz", "sample authority changed", failures)
	_expect(str(authority.get("saved_metric_address", "")).contains("decimal"), "saved coordinates must use decimal strings", failures)
	_expect(str(authority.get("invalid_saved_address", "")) == "reject_before_conversion", "invalid saved-coordinate policy changed", failures)
	_expect(str(authority.get("negative_division", "")) == "mathematical_floor", "negative division changed", failures)
	var contract: Dictionary = standard.get("coordinate_contract", {})
	_expect(int(contract.get("chunk_samples_per_axis", 0)) == 32, "chunk sample count changed", failures)
	_expect(int(contract.get("saved_metric_units_per_m", 0)) == 1000000, "saved metric precision changed", failures)
	_expect(str(standard.get("gpu_equivalence", "")).begins_with("UNQUALIFIED"), "GPU equivalence was promoted without evidence", failures)


static func _run_fixture_corpus(standard: Dictionary, failures: Array[String]) -> Dictionary:
	var contract: Dictionary = standard.get("coordinate_contract", {})
	var precision: Dictionary = standard.get("precision_budget", {})
	var fixture: Dictionary = standard.get("fixture_contract", {})
	var chunk_samples := int(contract.get("chunk_samples_per_axis", 32))
	var units_per_m := int(contract.get("saved_metric_units_per_m", 1000000))
	var sample_scale_m := float(contract.get("sample_scale_m", 0.5))
	var fixture_count := 0

	var sample_fixtures: Array[int] = [
		-2000000000, -1000001, -65, -64, -33, -32, -31, -1,
		0, 1, 31, 32, 33, 64, 65, 1000001, 2000000000,
	]
	var address_records: Array[Dictionary] = []
	for sample in sample_fixtures:
		var address := _sample_address(sample, chunk_samples)
		var chunk := int(address["chunk"])
		var local := int(address["local"])
		_expect(local >= 0 and local < chunk_samples, "local sample escaped chunk", failures)
		_expect(chunk * chunk_samples + local == sample, "sample address did not round trip", failures)
		address_records.append({"sample": sample, "chunk": chunk, "local": local})
		fixture_count += 1
	_expect(int((_sample_address(-1, chunk_samples))["chunk"]) == -1, "negative adjacent chunk changed", failures)
	_expect(int((_sample_address(-32, chunk_samples))["local"]) == 0, "negative exact boundary changed", failures)
	_expect(int((_sample_address(-33, chunk_samples))["chunk"]) == -2, "negative lower chunk changed", failures)
	fixture_count += 3

	var metric_fixtures: Array[float] = [
		-1000000000.0, -32768.25, -4097.0, -0.000001,
		0.0, 0.000001, 4097.0, 32768.25, 1000000000.0,
	]
	var maximum_render_error_m := 0.0
	var maximum_cpu_round_trip_error_m := 0.0
	var origin_shift_count := 0
	for world_m in metric_fixtures:
		var global_units := roundi(world_m * float(units_per_m))
		var rebuilt_world_m := float(global_units) / float(units_per_m)
		var cpu_round_trip_error_m := absf(rebuilt_world_m - world_m)
		maximum_cpu_round_trip_error_m = maxf(maximum_cpu_round_trip_error_m, cpu_round_trip_error_m)
		_expect(cpu_round_trip_error_m <= float(precision.get("cpu_metric_round_trip_error_m", 0.0)), "CPU metric round trip exceeded budget", failures)
		var origin_units := _quantized_origin_units(global_units, contract, units_per_m)
		var local_units := global_units - origin_units
		if origin_units != 0:
			origin_shift_count += 1
		var maximum_local_units := roundi(float(contract.get("maximum_local_magnitude_m", 0.0)) * float(units_per_m))
		_expect(absi(local_units) <= maximum_local_units, "origin-relative coordinate exceeded local bound", failures)
		_expect(origin_units + local_units == global_units, "origin shift changed global coordinate", failures)
		var render_local := Vector3(float(local_units) / float(units_per_m), 0.0, 0.0).x
		var render_error_m := absf(render_local - float(local_units) / float(units_per_m))
		maximum_render_error_m = maxf(maximum_render_error_m, render_error_m)
		_expect(render_error_m <= float(precision.get("render_local_error_m", 0.0)), "render-local precision exceeded budget", failures)
		var saved := _saved_axis(global_units)
		var parsed := _parse_saved_axis(saved)
		_expect(parsed == global_units, "saved metric coordinate changed", failures)
		fixture_count += 1

	var vector_fixtures := [
		[-1000000000000000, 0, 1000000000000000],
		[-4097000000, 8192000000, 4097000000],
		[-1, 1, -32768250000],
		[0, 0, 0],
		[32768250000, -8192000000, 4097000000],
	]
	for vector_value in vector_fixtures:
		var local_components: Array[float] = []
		for axis_units_value in vector_value:
			var axis_units := int(axis_units_value)
			var axis_origin := _quantized_origin_units(axis_units, contract, units_per_m)
			var axis_local := axis_units - axis_origin
			_expect(axis_origin + axis_local == axis_units, "3D origin reconstruction changed", failures)
			local_components.append(float(axis_local) / float(units_per_m))
		var vector_render_local := Vector3(local_components[0], local_components[1], local_components[2])
		for axis in range(3):
			_expect(
				absf(vector_render_local[axis] - local_components[axis]) <= float(precision.get("render_local_error_m", 0.0)),
				"3D render-local precision exceeded budget",
				failures
			)
		fixture_count += 1

	var save_record := {
		"schema": "world_transvoxel.coordinate_fixture.v1",
		"x_um": _saved_axis(-1000000000000000),
		"y_um": _saved_axis(123456789012345),
		"z_um": _saved_axis(1000000000000000),
	}
	var encoded := JSON.stringify(save_record)
	var decoded_value = JSON.parse_string(encoded)
	_expect(decoded_value is Dictionary, "saved-coordinate JSON did not decode", failures)
	if decoded_value is Dictionary:
		var decoded: Dictionary = decoded_value
		_expect(_parse_saved_axis(str(decoded.get("x_um", ""))) == -1000000000000000, "negative saved coordinate lost precision", failures)
		_expect(_parse_saved_axis(str(decoded.get("y_um", ""))) == 123456789012345, "middle saved coordinate lost precision", failures)
		_expect(_parse_saved_axis(str(decoded.get("z_um", ""))) == 1000000000000000, "positive saved coordinate lost precision", failures)
	fixture_count += 4
	for invalid_saved_value in ["", "0.0", "1e3", "--1", " 1"]:
		_expect(not _is_saved_axis_valid(invalid_saved_value), "invalid saved coordinate was accepted", failures)
		fixture_count += 1

	var distant_edit_count := int(fixture.get("distant_edit_count", 64))
	var distant_records: Array[Dictionary] = []
	for index in range(distant_edit_count):
		var sign_value := -1 if index % 2 == 0 else 1
		var center_units := sign_value * (500000000000000 + index * 7919000000)
		var sample := roundi(float(center_units) / float(units_per_m) / sample_scale_m)
		var address := _sample_address(sample, chunk_samples)
		var saved := _saved_axis(center_units)
		_expect(_parse_saved_axis(saved) == center_units, "distant edit save address changed", failures)
		_expect(int(address["chunk"]) * chunk_samples + int(address["local"]) == sample, "distant edit chunk address changed", failures)
		if index < 8:
			distant_records.append({"center_um": saved, "sample": sample, "address": address})
		fixture_count += 1

	var traversal_steps := int(fixture.get("long_traversal_steps", 100000))
	var global_units: int = -750000000000000
	var expected_units := global_units
	var traversal_signature_parts: Array[String] = []
	for step in range(traversal_steps):
		var delta_units: int = ((step * 7919) % 2000001 - 1000000) * 1000
		global_units += delta_units
		expected_units += delta_units
		if step % 997 == 0:
			var origin_units := _quantized_origin_units(global_units, contract, units_per_m)
			var local_units := global_units - origin_units
			_expect(origin_units + local_units == global_units, "long traversal origin reconstruction changed", failures)
			_expect(_parse_saved_axis(_saved_axis(global_units)) == global_units, "long traversal save reconstruction changed", failures)
			traversal_signature_parts.append(str(global_units))
			fixture_count += 1
	_expect(global_units == expected_units, "long traversal accumulated integer drift", failures)
	fixture_count += 1

	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"fixture_count": fixture_count,
		"sample_address_records": address_records,
		"origin_shift_count": origin_shift_count,
		"maximum_render_error_m": maximum_render_error_m,
		"render_error_budget_m": float(precision.get("render_local_error_m", 0.0)),
		"maximum_cpu_round_trip_error_m": maximum_cpu_round_trip_error_m,
		"cpu_round_trip_error_budget_m": float(precision.get("cpu_metric_round_trip_error_m", 0.0)),
		"saved_coordinate_encoding": "signed_decimal_string_micrometers",
		"distant_edit_count": distant_edit_count,
		"distant_edit_records": distant_records,
		"long_traversal_steps": traversal_steps,
		"long_traversal_signature": "|".join(traversal_signature_parts).sha256_text(),
		"long_traversal_error_units": global_units - expected_units,
	}


static func _benchmark(standard: Dictionary, failures: Array[String]) -> Dictionary:
	var contract: Dictionary = standard.get("coordinate_contract", {})
	var budget: Dictionary = standard.get("performance_budget", {})
	var warmup := int(budget.get("warmup_iterations", 10))
	var sample_count := int(budget.get("sample_count", 100))
	var round_trips := int(budget.get("coordinate_round_trips_per_sample", 1024))
	for warmup_index in range(warmup):
		_run_coordinate_batch(contract, round_trips, warmup_index)
	var timings: Array[float] = []
	for sample in range(sample_count):
		var started := Time.get_ticks_usec()
		_run_coordinate_batch(contract, round_trips, sample)
		timings.append(float(Time.get_ticks_usec() - started))
	var distribution := Statistics.distribution(timings)
	distribution["warmup_iterations"] = warmup
	distribution["coordinate_round_trips_per_sample"] = round_trips
	distribution["budget_p95_usec"] = float(budget.get("p95_usec", 0.0))
	_expect(int(distribution.get("sample_count", 0)) == sample_count, "coordinate benchmark sample count changed", failures)
	_expect(float(distribution.get("p95_usec", INF)) <= float(budget.get("p95_usec", 0.0)), "coordinate benchmark p95 exceeded budget", failures)
	return distribution


static func _run_coordinate_batch(contract: Dictionary, round_trips: int, seed: int) -> void:
	var chunk_samples := int(contract.get("chunk_samples_per_axis", 32))
	var units_per_m := int(contract.get("saved_metric_units_per_m", 1000000))
	for index in range(round_trips):
		var sample: int = ((index * 104729 + seed * 7919) % 4000000001) - 2000000000
		var address := _sample_address(sample, chunk_samples)
		var rebuilt := int(address["chunk"]) * chunk_samples + int(address["local"])
		var global_units := rebuilt * 500000
		_parse_saved_axis(_saved_axis(global_units))
		_quantized_origin_units(global_units, contract, units_per_m)


static func _sample_address(sample: int, chunk_samples: int) -> Dictionary:
	var chunk := _floor_div(sample, chunk_samples)
	return {"chunk": chunk, "local": sample - chunk * chunk_samples}


static func _floor_div(value: int, divisor: int) -> int:
	var quotient: int = value / divisor
	var remainder := value % divisor
	if remainder < 0:
		quotient -= 1
	return quotient


static func _quantized_origin_units(global_units: int, contract: Dictionary, units_per_m: int) -> int:
	var threshold_units := roundi(float(contract.get("shift_threshold_m", 0.0)) * float(units_per_m))
	if absi(global_units) <= threshold_units:
		return 0
	var quantum_units := roundi(float(contract.get("shift_quantum_m", 0.0)) * float(units_per_m))
	return _floor_div(global_units, quantum_units) * quantum_units


static func _saved_axis(value_units: int) -> String:
	return str(value_units)


static func _parse_saved_axis(value: String) -> int:
	if not _is_saved_axis_valid(value):
		return 0
	return value.to_int()


static func _is_saved_axis_valid(value: String) -> bool:
	return value.is_valid_int()


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
