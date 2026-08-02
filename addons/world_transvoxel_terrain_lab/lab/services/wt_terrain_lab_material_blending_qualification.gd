@tool
extends RefCounted
class_name WtTerrainLabMaterialBlendingQualification

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const Statistics := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_statistics.gd"
)

const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/material_blending_standard.json"
)
const STANDARD_SCHEMA := "world_transvoxel.terrain_lab.material_blending_standard.v1"
const VISUAL_WIDTH := 1024
const VISUAL_HEIGHT := 640
const VISUAL_BACKGROUND := Color(0.035, 0.045, 0.055, 1.0)
const VISUAL_PANEL := Color(0.075, 0.09, 0.105, 1.0)
const VISUAL_GRID := Color(0.18, 0.22, 0.25, 1.0)
const WEIGHT_TIE_EPSILON := 0.000000000001


static func run() -> Dictionary:
	var standard := JsonLoader.load_dictionary(STANDARD_PATH)
	var failures: Array[String] = []
	_validate_standard(standard, failures)
	var exact := _run_exact_corpus(standard, failures)
	var performance := _benchmark(standard, failures)
	var visual := _validate_visual_evidence(standard, failures)
	return {
		"milestone": "TQP-18",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"qualification_status": (
			"QUALIFIED_REFERENCE_MATERIAL_BLENDING_V1"
			if str(visual.get("human_review", "")) == "ACCEPTED"
			else "IMPLEMENTED_PENDING_HUMAN_VISUAL_REVIEW"
		),
		"fixture_count": int(exact.get("fixture_count", 0)),
		"exact_corpus": exact,
		"performance": performance,
		"memory": Statistics.memory_metrics(),
		"provenance": Statistics.provenance("tqp18_material_blending_reference_v1"),
		"visual_evidence": visual,
		"qualified_scope": standard.get("qualified_scope", []),
		"explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
		"failures": failures,
	}


static func normalized_weights(source: Dictionary) -> Dictionary:
	var total := 0.0
	for material_id in source:
		total += maxf(float(source[material_id]), 0.0)
	var result := {}
	if total <= 0.0:
		return result
	for material_id_value in source:
		var material_id := int(material_id_value)
		var weight := maxf(float(source[material_id_value]), 0.0)
		if weight > 0.0:
			result[material_id] = weight / total
	return result


static func top_materials(source: Dictionary, maximum_count: int) -> Dictionary:
	if maximum_count <= 0:
		return {}
	var entries: Array[Dictionary] = []
	for material_id in source:
		var weight := maxf(float(source[material_id]), 0.0)
		if weight > 0.0:
			entries.append({"id": int(material_id), "weight": weight})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var weight_delta := float(a["weight"]) - float(b["weight"])
		if absf(weight_delta) > WEIGHT_TIE_EPSILON:
			return weight_delta > 0.0
		return int(a["id"]) < int(b["id"])
	)
	var selected := {}
	for index in range(mini(maximum_count, entries.size())):
		selected[int(entries[index]["id"])] = float(entries[index]["weight"])
	return normalized_weights(selected)


static func blend_weights(left: Dictionary, right: Dictionary, amount: float) -> Dictionary:
	var result := {}
	var material_ids := {}
	for material_id in left:
		material_ids[int(material_id)] = true
	for material_id in right:
		material_ids[int(material_id)] = true
	var clamped := clampf(amount, 0.0, 1.0)
	for material_id in material_ids:
		result[material_id] = lerpf(
			float(left.get(material_id, 0.0)),
			float(right.get(material_id, 0.0)),
			clamped
		)
	return normalized_weights(result)


static func dominant_material(weights: Dictionary) -> int:
	var best_id := -1
	var best_weight := -1.0
	for material_id_value in weights:
		var material_id := int(material_id_value)
		var weight := float(weights[material_id_value])
		if (
			weight > best_weight + WEIGHT_TIE_EPSILON
			or (absf(weight - best_weight) <= WEIGHT_TIE_EPSILON and material_id < best_id)
		):
			best_id = material_id
			best_weight = weight
	return best_id


static func reference_field(amount: float) -> Dictionary:
	var left := {1: 0.75, 2: 0.25}
	var right := {2: 0.20, 3: 0.80}
	return blend_weights(left, right, amount)


static func analytic_reference_field(amount: float) -> Dictionary:
	var clamped := clampf(amount, 0.0, 1.0)
	return {
		1: 0.75 * (1.0 - clamped),
		2: 0.25 * (1.0 - clamped) + 0.20 * clamped,
		3: 0.80 * clamped,
	}


static func material_color(weights: Dictionary) -> Color:
	var palette := {
		1: Color("3a8f5b"),
		2: Color("d5a83f"),
		3: Color("497bc2"),
		4: Color("ba5a63"),
		5: Color("8f6db2"),
	}
	var color := Color(0.08, 0.09, 0.10, 1.0)
	for material_id in weights:
		color += (palette.get(int(material_id), Color.WHITE) as Color) * float(weights[material_id])
	color.a = 1.0
	return color


static func build_visual_image() -> Image:
	var image := Image.create(VISUAL_WIDTH, VISUAL_HEIGHT, false, Image.FORMAT_RGBA8)
	image.fill(VISUAL_BACKGROUND)
	_draw_continuous_panel(image, Rect2i(20, 20, 482, 286))
	_draw_transition_panel(image, Rect2i(522, 20, 482, 286))
	_draw_lod_panel(image, Rect2i(20, 326, 482, 294))
	_draw_reduction_panel(image, Rect2i(522, 326, 482, 294))
	return image


static func pixel_signature(image: Image) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(image.get_data())
	return context.finish().hex_encode()


static func _validate_standard(standard: Dictionary, failures: Array[String]) -> void:
	_expect(str(standard.get("schema", "")) == STANDARD_SCHEMA, "material standard schema changed", failures)
	_expect(str(standard.get("milestone", "")) == "TQP-18", "material standard milestone changed", failures)
	var weight: Dictionary = standard.get("weight_contract", {})
	_expect(int(weight.get("maximum_materials", 0)) == 4, "top-material count must be four", failures)
	_expect(is_equal_approx(float(weight.get("weight_tie_epsilon", 0.0)), WEIGHT_TIE_EPSILON), "weight tie epsilon changed", failures)
	_expect(str(weight.get("dominant_tie_break", "")) == "lowest_material_id", "tie policy changed", failures)
	var interpolation: Dictionary = standard.get("interpolation_contract", {})
	_expect(float(interpolation.get("weight_error_budget", 0.0)) > 0.0, "weight error budget is missing", failures)
	var fixture: Dictionary = standard.get("fixture_contract", {})
	_expect(int(fixture.get("gradient_steps", 0)) >= 257, "gradient corpus is too small", failures)
	_expect((fixture.get("qualified_lods", []) as Array).size() == 8, "LOD0-7 corpus is incomplete", failures)


static func _run_exact_corpus(standard: Dictionary, failures: Array[String]) -> Dictionary:
	var fixture_count := 0
	var tolerance := float(
		(standard.get("interpolation_contract", {}) as Dictionary).get("weight_error_budget", 0.000001)
	)
	var normalization_cases := [
		{"source": {1: 2.0, 3: 1.0, 7: 1.0}, "expected": {1: 0.5, 3: 0.25, 7: 0.25}},
		{"source": {1: -4.0, 2: 0.0, 3: 2.0}, "expected": {3: 1.0}},
		{"source": {1: -1.0, 2: 0.0}, "expected": {}},
	]
	for fixture_value in normalization_cases:
		var actual := normalized_weights(fixture_value["source"])
		_expect_weights(actual, fixture_value["expected"], tolerance, "normalization", failures)
		fixture_count += 1

	var reduced := top_materials({9: 0.10, 4: 0.30, 1: 0.25, 7: 0.20, 3: 0.15}, 4)
	_expect(reduced.size() == 4 and not reduced.has(9), "top-four reduction retained the lowest weight", failures)
	_expect(absf(_weight_sum(reduced) - 1.0) <= tolerance, "top-four result is not normalized", failures)
	var tied := top_materials({9: 0.25, 7: 0.25, 5: 0.25, 3: 0.25, 1: 0.25}, 4)
	_expect(not tied.has(9) and tied.has(1), "top-four tie reduction did not prefer lower IDs", failures)
	_expect(top_materials({1: 1.0}, 0).is_empty(), "zero-count reduction must be empty", failures)
	fixture_count += 3

	var fixture_contract: Dictionary = standard.get("fixture_contract", {})
	var gradient_steps := int(fixture_contract.get("gradient_steps", 257))
	for index in range(gradient_steps):
		var amount := float(index) / float(gradient_steps - 1)
		var blended := blend_weights({1: 1.0}, {2: 1.0}, amount)
		_expect(absf(float(blended.get(1, 0.0)) - (1.0 - amount)) <= tolerance, "left gradient changed", failures)
		_expect(absf(float(blended.get(2, 0.0)) - amount) <= tolerance, "right gradient changed", failures)
		_expect(absf(_weight_sum(blended) - 1.0) <= tolerance, "gradient sum changed", failures)
		fixture_count += 1
	var epsilon := float(fixture_contract.get("categorical_epsilon", 0.000001))
	_expect(dominant_material(blend_weights({1: 1.0}, {2: 1.0}, 0.5 - epsilon)) == 1, "left categorical boundary changed", failures)
	_expect(dominant_material(blend_weights({1: 1.0}, {2: 1.0}, 0.5)) == 1, "categorical tie changed", failures)
	_expect(dominant_material(blend_weights({1: 1.0}, {2: 1.0}, 0.5 + epsilon)) == 2, "right categorical boundary changed", failures)
	_expect(dominant_material({}) == -1, "empty dominant material changed", failures)
	fixture_count += 4

	var subdivisions := int(fixture_contract.get("transition_subdivisions", 8))
	for field_index in range(33):
		var field_amount := float(field_index) / 32.0
		_expect_weights(reference_field(field_amount), analytic_reference_field(field_amount), tolerance, "analytic field", failures)
		fixture_count += 1
	for segment in range(subdivisions):
		var start := float(segment) / float(subdivisions)
		var finish := float(segment + 1) / float(subdivisions)
		var regular_left := reference_field(start)
		var regular_right := reference_field(finish)
		for local_index in range(5):
			var local_amount := float(local_index) / 4.0
			var world_amount := lerpf(start, finish, local_amount)
			var transition := blend_weights(regular_left, regular_right, local_amount)
			_expect_weights(transition, analytic_reference_field(world_amount), tolerance, "transition", failures)
			fixture_count += 1

	var lod_records: Array[Dictionary] = []
	for lod_value in fixture_contract.get("qualified_lods", []):
		var lod := int(lod_value)
		var segment_count := 1 << (7 - lod)
		var maximum_error := 0.0
		for segment in range(segment_count):
			var start := float(segment) / float(segment_count)
			var finish := float(segment + 1) / float(segment_count)
			var midpoint := (start + finish) * 0.5
			var reconstructed := blend_weights(reference_field(start), reference_field(finish), 0.5)
			maximum_error = maxf(maximum_error, _maximum_weight_error(reconstructed, analytic_reference_field(midpoint)))
			fixture_count += 1
		_expect(maximum_error <= tolerance, "LOD%d material continuity exceeded budget" % lod, failures)
		lod_records.append({"lod": lod, "maximum_weight_error": maximum_error})

	_expect_weights(blend_weights({1: 1.0}, {2: 1.0}, -10.0), {1: 1.0}, tolerance, "negative clamp", failures)
	_expect_weights(blend_weights({1: 1.0}, {2: 1.0}, 10.0), {2: 1.0}, tolerance, "positive clamp", failures)
	fixture_count += 2
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"fixture_count": fixture_count,
		"gradient_steps": gradient_steps,
		"transition_subdivisions": subdivisions,
		"lod_records": lod_records,
		"weight_error_budget": tolerance,
	}


static func _benchmark(standard: Dictionary, failures: Array[String]) -> Dictionary:
	var budget: Dictionary = standard.get("performance_budget", {})
	var warmup := int(budget.get("warmup_iterations", 10))
	var sample_count := int(budget.get("sample_count", 100))
	var blend_count := int(budget.get("blends_per_sample", 512))
	for warmup_index in range(warmup):
		_run_blend_batch(blend_count, warmup_index)
	var timings: Array[float] = []
	for sample in range(sample_count):
		var started := Time.get_ticks_usec()
		_run_blend_batch(blend_count, sample)
		timings.append(float(Time.get_ticks_usec() - started))
	var distribution := Statistics.distribution(timings)
	distribution["warmup_iterations"] = warmup
	distribution["blends_per_sample"] = blend_count
	distribution["budget_p95_usec"] = float(budget.get("p95_usec", 0.0))
	distribution["budget_evaluation"] = _budget_evaluation()
	_expect(int(distribution.get("sample_count", 0)) == sample_count, "material benchmark sample count changed", failures)
	if not Statistics.combined_program_run():
		_expect(float(distribution.get("p95_usec", INF)) <= float(budget.get("p95_usec", 0.0)), "material benchmark p95 exceeded budget", failures)
	return distribution


static func _budget_evaluation() -> String:
	return "OBSERVATION_ONLY_COMBINED_RUN" if Statistics.combined_program_run() else "ENFORCED_FOCUSED_RUN"


static func _run_blend_batch(blend_count: int, seed: int) -> void:
	for index in range(blend_count):
		var amount := float((index * 31 + seed * 17) % 1024) / 1023.0
		blend_weights({1: 0.75, 2: 0.25}, {2: 0.20, 3: 0.80}, amount)


static func _validate_visual_evidence(standard: Dictionary, failures: Array[String]) -> Dictionary:
	var visual: Dictionary = standard.get("visual_evidence", {})
	var image_path := str(visual.get("image", ""))
	var automated := str(visual.get("automated_status", ""))
	var expected_hash := str(visual.get("sha256", ""))
	var expected_pixel_signature := str(visual.get("pixel_signature", ""))
	var generated := build_visual_image()
	var generated_signature := pixel_signature(generated)
	_expect(FileAccess.file_exists(image_path), "material visual evidence image is missing", failures)
	var reference: Image = null
	if FileAccess.file_exists(image_path):
		_expect(FileAccess.get_sha256(image_path) == expected_hash, "material visual evidence hash changed", failures)
		reference = Image.load_from_file(ProjectSettings.globalize_path(image_path))
	_expect(reference != null and not reference.is_empty(), "material visual evidence could not load", failures)
	var reference_signature := ""
	if reference != null and not reference.is_empty():
		reference_signature = pixel_signature(reference)
		_expect(reference.get_width() == VISUAL_WIDTH and reference.get_height() == VISUAL_HEIGHT, "material visual dimensions changed", failures)
		_expect(reference_signature == generated_signature, "fresh material visual differs from retained evidence", failures)
		_expect(reference_signature == expected_pixel_signature, "material visual pixel signature changed", failures)
		_validate_visual_pixels(reference, failures)
	_expect(automated == "PASS", "material visual automated checks have not passed", failures)
	return {
		"capture_id": str(visual.get("capture_id", "")),
		"image": image_path,
		"sha256": expected_hash,
		"pixel_signature": reference_signature,
		"generated_pixel_signature": generated_signature,
		"automated_status": automated,
		"human_review": str(visual.get("human_review", "PENDING")),
		"panels": [
			"continuous_and_categorical",
			"regular_transition_interpolation",
			"lod0_to_lod7_continuity",
			"top_four_and_tie_policy",
		],
	}


static func _draw_continuous_panel(image: Image, rect: Rect2i) -> void:
	_fill_rect(image, rect, VISUAL_PANEL)
	for local_x in range(4, rect.size.x - 4):
		var amount := float(local_x - 4) / float(rect.size.x - 9)
		var blended := blend_weights({1: 1.0}, {2: 1.0}, amount)
		var smooth_color := material_color(blended)
		var categorical_color := material_color({dominant_material(blended): 1.0})
		for local_y in range(4, rect.size.y - 4):
			var color := smooth_color if local_y < rect.size.y / 2 else categorical_color
			image.set_pixel(rect.position.x + local_x, rect.position.y + local_y, color)
	_draw_border(image, rect)


static func _draw_transition_panel(image: Image, rect: Rect2i) -> void:
	_fill_rect(image, rect, VISUAL_PANEL)
	var subdivisions := 8
	for local_x in range(4, rect.size.x - 4):
		var amount := float(local_x - 4) / float(rect.size.x - 9)
		var segment := mini(floori(amount * float(subdivisions)), subdivisions - 1)
		var start := float(segment) / float(subdivisions)
		var finish := float(segment + 1) / float(subdivisions)
		var local_amount := (amount - start) / (finish - start)
		var transition := blend_weights(reference_field(start), reference_field(finish), local_amount)
		var color := material_color(transition)
		for local_y in range(4, rect.size.y - 4):
			image.set_pixel(rect.position.x + local_x, rect.position.y + local_y, color)
	for boundary in range(1, subdivisions):
		var x := rect.position.x + 4 + roundi(float(rect.size.x - 9) * float(boundary) / float(subdivisions))
		for y in range(rect.position.y + 4, rect.end.y - 4):
			image.set_pixel(x, y, VISUAL_GRID.lerp(image.get_pixel(x, y), 0.35))
	_draw_border(image, rect)


static func _draw_lod_panel(image: Image, rect: Rect2i) -> void:
	_fill_rect(image, rect, VISUAL_PANEL)
	var row_height := (rect.size.y - 8) / 8
	for lod in range(8):
		var segment_count := 1 << (7 - lod)
		var y_start := rect.position.y + 4 + lod * row_height
		var y_end := rect.position.y + 4 + (lod + 1) * row_height
		for local_x in range(4, rect.size.x - 4):
			var amount := float(local_x - 4) / float(rect.size.x - 9)
			var segment := mini(floori(amount * float(segment_count)), segment_count - 1)
			var start := float(segment) / float(segment_count)
			var finish := float(segment + 1) / float(segment_count)
			var local_amount := (amount - start) / (finish - start)
			var reconstructed := blend_weights(reference_field(start), reference_field(finish), local_amount)
			for y in range(y_start, y_end):
				image.set_pixel(rect.position.x + local_x, y, material_color(reconstructed))
		for x in range(rect.position.x + 4, rect.end.x - 4):
			image.set_pixel(x, y_start, VISUAL_GRID)
	_draw_border(image, rect)


static func _draw_reduction_panel(image: Image, rect: Rect2i) -> void:
	_fill_rect(image, rect, VISUAL_PANEL)
	for local_x in range(4, rect.size.x - 4):
		var amount := float(local_x - 4) / float(rect.size.x - 9)
		var source := {
			1: 0.30,
			2: 0.25,
			3: 0.20,
			4: 0.15 + amount * 0.20,
			5: 0.35 - amount * 0.20,
		}
		var reduced := top_materials(source, 4)
		var blend_color := material_color(reduced)
		var categorical := material_color({dominant_material(reduced): 1.0})
		for local_y in range(4, rect.size.y - 4):
			var color := blend_color if local_y < rect.size.y / 2 else categorical
			image.set_pixel(rect.position.x + local_x, rect.position.y + local_y, color)
	_draw_border(image, rect)


static func _validate_visual_pixels(image: Image, failures: Array[String]) -> void:
	var left := image.get_pixel(28, 80)
	var right := image.get_pixel(494, 80)
	_expect(_color_delta(left, right) > 0.25, "material visual gradient endpoints are indistinct", failures)
	var categorical_left := image.get_pixel(250, 250)
	var categorical_right := image.get_pixel(272, 250)
	_expect(_color_delta(categorical_left, categorical_right) > 0.15, "material categorical boundary is indistinct", failures)
	for lod in range(8):
		var y := 326 + 4 + lod * 35 + 18
		var amount := 0.37
		var x := 20 + 4 + roundi(float(482 - 9) * amount)
		var expected := material_color(analytic_reference_field(amount))
		_expect(_color_delta(image.get_pixel(x, y), expected) <= 0.02, "LOD%d visual row changed" % lod, failures)


static func _color_delta(left: Color, right: Color) -> float:
	return maxf(absf(left.r - right.r), maxf(absf(left.g - right.g), absf(left.b - right.b)))


static func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			image.set_pixel(x, y, color)


static func _draw_border(image: Image, rect: Rect2i) -> void:
	for x in range(rect.position.x, rect.end.x):
		image.set_pixel(x, rect.position.y, VISUAL_GRID)
		image.set_pixel(x, rect.end.y - 1, VISUAL_GRID)
	for y in range(rect.position.y, rect.end.y):
		image.set_pixel(rect.position.x, y, VISUAL_GRID)
		image.set_pixel(rect.end.x - 1, y, VISUAL_GRID)


static func _expect_weights(
	actual: Dictionary,
	expected: Dictionary,
	tolerance: float,
	label: String,
	failures: Array[String]
) -> void:
	var material_ids := {}
	for material_id in actual:
		material_ids[int(material_id)] = true
	for material_id in expected:
		material_ids[int(material_id)] = true
	for material_id in material_ids:
		_expect(
			absf(float(actual.get(material_id, 0.0)) - float(expected.get(material_id, 0.0))) <= tolerance,
			"%s material %d weight changed" % [label, material_id],
			failures
		)


static func _maximum_weight_error(left: Dictionary, right: Dictionary) -> float:
	var material_ids := {}
	for material_id in left:
		material_ids[int(material_id)] = true
	for material_id in right:
		material_ids[int(material_id)] = true
	var maximum_error := 0.0
	for material_id in material_ids:
		maximum_error = maxf(
			maximum_error,
			absf(float(left.get(material_id, 0.0)) - float(right.get(material_id, 0.0)))
		)
	return maximum_error


static func _weight_sum(weights: Dictionary) -> float:
	var result := 0.0
	for material_id in weights:
		result += float(weights[material_id])
	return result


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
