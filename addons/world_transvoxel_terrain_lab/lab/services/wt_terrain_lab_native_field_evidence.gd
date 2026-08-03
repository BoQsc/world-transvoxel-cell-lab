@tool
extends RefCounted
class_name WtTerrainLabNativeFieldEvidence

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)

const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/native_field_standard.json"
)


static func validate_retained() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var report := JsonLoader.load_dictionary(str(standard.get("evidence", "")))
	return validate_report(report, standard)


static func validate_report(report: Dictionary, standard: Dictionary = {}) -> Dictionary:
	if standard.is_empty():
		standard = JsonLoader.load_dictionary(STANDARD_PATH)
	var failures: Array[String] = []
	_expect(
		str(standard.get("schema", ""))
			== "world_transvoxel.terrain_lab.native_field_standard.v1",
		"native field standard schema changed",
		failures
	)
	_expect(
		str(report.get("schema", ""))
			== "world_transvoxel.terrain_lab.native_field_qualification.v1",
		"native field report schema changed",
		failures
	)
	_expect(
		str(report.get("standard_id", "")) == str(standard.get("standard_id", "")),
		"native field report standard changed",
		failures
	)
	_expect(
		str(report.get("authority", "")) == str(standard.get("authority", "")),
		"native field report authority changed",
		failures
	)
	_expect(bool(report.get("retained_complete", false)), "native field report is filtered", failures)
	_expect(str(report.get("status", "")) == "PASS", "native field report failed", failures)
	var contract: Dictionary = report.get("contract", {})
	_expect(str(contract.get("status", "")) == "PASS", "TQP-28 contract failed", failures)
	var required_contract_checks := [
		"density_sign",
		"valid_configuration",
		"analytical_sign_boundary",
		"isovalue_ownership",
		"world_units",
		"gradient",
		"material_sampling",
		"interpolation",
		"composition_order",
		"deterministic_seed",
		"chunk_lod_sample_identity",
		"large_coordinate",
		"frequency_limits",
		"feature_resolution_limits",
		"negative_configuration",
	]
	var check_status := {}
	for check_value in contract.get("checks", []):
		var check: Dictionary = check_value
		check_status[str(check.get("id", ""))] = str(check.get("status", ""))
	for check_id in required_contract_checks:
		_expect(
			str(check_status.get(check_id, "")) == "PASS",
			"TQP-28 missing passing check " + check_id,
			failures
		)
	var corpus: Dictionary = report.get("corpus", {})
	var budgets: Dictionary = standard.get("budgets", {})
	_expect(
		int(corpus.get("fixture_count", 0)) >= int(budgets.get("minimum_fixture_count", 0)),
		"TQP-29 fixture coverage is incomplete",
		failures
	)
	_expect(
		int(corpus.get("native_chunk_count", 0))
			>= int(budgets.get("minimum_native_chunk_count", 0)),
		"TQP-29 native chunk coverage is incomplete",
		failures
	)
	_expect(
		int(corpus.get("same_lod_seam_count", 0))
			>= int(budgets.get("minimum_same_lod_seam_count", 0)),
		"TQP-29 same-LOD seam coverage is incomplete",
		failures
	)
	for feature in standard.get("required_feature_inventory", []):
		_expect(
			str(feature) in corpus.get("observed_features", []),
			"TQP-29 missing feature " + str(feature),
			failures
		)
	var expected: Dictionary = standard.get("stable_expected", {})
	_expect(
		not str(expected.get("corpus_field_signature", "")).is_empty(),
		"standard lacks retained corpus field signature",
		failures
	)
	_expect(
		not str(expected.get("corpus_geometry_signature", "")).is_empty(),
		"standard lacks retained corpus geometry signature",
		failures
	)
	_expect(
		str(corpus.get("field_signature", "")) == str(expected.get("corpus_field_signature", "")),
		"corpus field signature changed",
		failures
	)
	_expect(
		str(corpus.get("geometry_signature", ""))
			== str(expected.get("corpus_geometry_signature", "")),
		"corpus native geometry signature changed",
		failures
	)
	var expected_fixtures: Dictionary = expected.get("fixtures", {})
	var observed_fixtures := {}
	for fixture_value in corpus.get("fixtures", []):
		var fixture: Dictionary = fixture_value
		var fixture_id := str(fixture.get("fixture_id", ""))
		observed_fixtures[fixture_id] = fixture
		_expect(str(fixture.get("status", "")) == "PASS", fixture_id + " failed", failures)
		_expect(
			str(fixture.get("field_signature", ""))
				== str((expected_fixtures.get(fixture_id, {}) as Dictionary).get("field_signature", "")),
			fixture_id + " field signature changed",
			failures
		)
		_expect(
			str(fixture.get("geometry_signature", ""))
				== str((expected_fixtures.get(fixture_id, {}) as Dictionary).get("geometry_signature", "")),
			fixture_id + " geometry signature changed",
			failures
		)
		_expect(
			str(fixture.get("geometry_signature", ""))
				== str(fixture.get("warm_geometry_signature", "")),
			fixture_id + " cold/warm geometry changed",
			failures
		)
		_expect(
			int(fixture.get("triangle_count", 0)) > 0,
			fixture_id + " has no native triangles",
			failures
		)
		_expect(
			int(fixture.get("native_chunk_count", 0)) == 8
				and int(fixture.get("seam_count", 0)) == 12,
			fixture_id + " does not retain the complete 2x2x2 native seam window",
			failures
		)
		var topology: Dictionary = fixture.get("topology", {})
		_expect(str(topology.get("status", "")) == "PASS", fixture_id + " topology failed", failures)
		_expect(
			int(topology.get("interior_open_edge_count", -1)) == 0,
			fixture_id + " has interior open edges",
			failures
		)
		_expect(
			int(topology.get("nonmanifold_edge_count", -1)) == 0,
			fixture_id + " has nonmanifold edges",
			failures
		)
		var repro: Dictionary = fixture.get("minimized_repro", {})
		var expected_fixture: Dictionary = {}
		for standard_fixture_value in standard.get("fixtures", []):
			var standard_fixture: Dictionary = standard_fixture_value
			if str(standard_fixture.get("id", "")) == fixture_id:
				expected_fixture = standard_fixture
				break
		_expect(
			str(repro.get("runner", "")).ends_with("run_native_field_validation.gd")
				and (repro.get("arguments", []) as Array).size() == 2,
			fixture_id + " lacks a focused minimized repro",
			failures
		)
		_expect(
			repro.get("fixture", {}) == expected_fixture,
			fixture_id + " minimized repro differs from the current standard fixture",
			failures
		)
	for fixture_value in standard.get("fixtures", []):
		var fixture: Dictionary = fixture_value
		var fixture_id := str(fixture.get("id", ""))
		_expect(observed_fixtures.has(fixture_id), "missing retained fixture " + fixture_id, failures)
		_expect(expected_fixtures.has(fixture_id), "missing expected fixture " + fixture_id, failures)
	var performance: Dictionary = report.get("performance", {})
	_expect(
		int(performance.get("elapsed_usec", 0)) > 0
			and int(performance.get("elapsed_usec", 0))
				<= int(budgets.get("maximum_total_usec", 0)),
		"native field debug regression duration exceeded",
		failures
	)
	var fixture_distribution: Dictionary = performance.get("fixture_distribution", {})
	_expect(
		int(fixture_distribution.get("sample_count", 0))
			>= int(budgets.get("minimum_fixture_count", 0)),
		"native field fixture timing distribution is incomplete",
		failures
	)
	_expect(
		float(fixture_distribution.get("p95_usec", INF))
			<= float(budgets.get("maximum_fixture_p95_usec", 0.0)),
		"native field fixture p95 exceeded",
		failures
	)
	var provenance: Dictionary = report.get("provenance", {})
	_expect(
		str(provenance.get("os", ""))
			== str((standard.get("runtime_profile", {}) as Dictionary).get("platform", "")),
		"native field retained platform changed",
		failures
	)
	for key in [
		"workload_signature",
		"architecture",
		"godot_version",
		"build_type",
		"cpu",
		"driver",
		"backend_revision",
		"native_dependency",
	]:
		_expect(not str(provenance.get(key, "")).is_empty(), "native field provenance lacks " + key, failures)
	return {
		"schema": "world_transvoxel.terrain_lab.native_field_evidence_validation.v1",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"qualification_status": (
			"QUALIFIED_NATIVE_WINDOWS_FIELD_AND_COMPLEX_LOD0_CORPUS_V1"
			if failures.is_empty()
			else "FAILED"
		),
		"scope_status": {
			"TQP-28": "qualified_native_field_generation_and_sampling_contract_v1"
				if failures.is_empty() else "failed_native_field_contract",
			"TQP-29": "qualified_complex_native_lod0_field_corpus_v1"
				if failures.is_empty() else "failed_complex_native_field_corpus",
		},
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


static func retained_qualification() -> Dictionary:
	var validation := validate_retained()
	if str(validation.get("status", "")) != "PASS":
		return validation
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	return JsonLoader.load_dictionary(str(standard.get("evidence", "")))


static func _expect(condition: bool, failure: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(failure)
