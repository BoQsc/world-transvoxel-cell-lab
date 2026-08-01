@tool
extends RefCounted
class_name WtTerrainLabEditVisualEvidence

const EditField := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_edit_field.gd"
)

const WIDTH := 1280
const HEIGHT := 720
const BACKGROUND := Color(0.035, 0.045, 0.055, 1.0)
const PANEL_BACKGROUND := Color(0.075, 0.09, 0.105, 1.0)
const SOLID := Color(0.12, 0.68, 0.78, 1.0)
const CONSTRUCTED := Color(0.91, 0.48, 0.17, 1.0)
const SURFACE := Color(1.0, 0.86, 0.16, 1.0)
const GRID := Color(0.18, 0.22, 0.25, 1.0)


static func build_image() -> Image:
	var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	image.fill(BACKGROUND)
	var shapes := _shape_fixtures()
	var shape_panel_width := 176
	for index in range(shapes.size()):
		_draw_shape_panel(
			image,
			Rect2i(16 + index * 180, 16, shape_panel_width, 272),
			shapes[index]
		)
	var operations := _sequence_operations()
	for step in range(6):
		_draw_edit_panel(
			image,
			Rect2i(16 + step * 210, 320, 202, 376),
			operations.slice(0, step)
		)
	return image


static func pixel_signature(image: Image) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(image.get_data())
	return context.finish().hex_encode()


static func validate_reference(path: String, expected_signature: String) -> Dictionary:
	var generated := build_image()
	var generated_signature := pixel_signature(generated)
	var failures: Array[String] = []
	if not FileAccess.file_exists(path):
		failures.append("diagnostic visual is missing")
		return {
			"status": "FAIL",
			"generated_signature": generated_signature,
			"failures": failures,
		}
	var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
	var reference := texture.get_image() if texture != null else null
	if reference == null or reference.is_empty():
		failures.append("diagnostic visual could not load")
		return {
			"status": "FAIL",
			"generated_signature": generated_signature,
			"failures": failures,
		}
	var reference_signature := pixel_signature(reference)
	if reference.get_width() != WIDTH or reference.get_height() != HEIGHT:
		failures.append("diagnostic visual dimensions changed")
	if generated_signature != reference_signature:
		failures.append("fresh diagnostic visual differs from reference")
	if expected_signature.is_empty() or reference_signature != expected_signature:
		failures.append("diagnostic visual signature differs from standard")
	return {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"width": reference.get_width(),
		"height": reference.get_height(),
		"generated_signature": generated_signature,
		"reference_signature": reference_signature,
		"panel_count": 13,
		"shape_panels": [
			"sphere",
			"capsule",
			"swept_stroke",
			"rounded_box",
			"plane_stamp",
			"ellipsoid_stamp",
			"bounded_noise",
		],
		"sequence_panels": [
			"base_field",
			"sphere_dig",
			"swept_tunnel",
			"rounded_box_construct",
			"capsule_support_construct",
			"sphere_cut_through_construction",
		],
		"evidence_scope": "diagnostic_cross_sections_not_standalone_correctness",
		"failures": failures,
	}


static func _draw_shape_panel(image: Image, rect: Rect2i, operation: Dictionary) -> void:
	_fill_rect(image, rect, PANEL_BACKGROUND)
	for local_y in range(4, rect.size.y - 4):
		for local_x in range(4, rect.size.x - 4):
			var point := Vector3(
				lerpf(-4.0, 4.0, float(local_x - 4) / float(rect.size.x - 9)),
				lerpf(4.0, -4.0, float(local_y - 4) / float(rect.size.y - 9)),
				0.0
			)
			var density := EditField.shape_sdf(operation, point)
			var color := SOLID if density < 0.0 else PANEL_BACKGROUND
			if absf(density) <= 0.055:
				color = SURFACE
			image.set_pixel(rect.position.x + local_x, rect.position.y + local_y, color)
	_draw_border(image, rect)


static func _draw_edit_panel(image: Image, rect: Rect2i, operations: Array) -> void:
	_fill_rect(image, rect, PANEL_BACKGROUND)
	var field := EditField.new()
	for operation_value in operations:
		field.add_operation(operation_value)
	for local_y in range(4, rect.size.y - 4):
		for local_x in range(4, rect.size.x - 4):
			var point := Vector3(
				lerpf(0.0, 32.0, float(local_x - 4) / float(rect.size.x - 9)),
				lerpf(24.0, 0.0, float(local_y - 4) / float(rect.size.y - 9)),
				16.0
			)
			var density := field.density(point)
			var material := field.material_at(point, density)
			var color := PANEL_BACKGROUND
			if density < 0.0:
				color = CONSTRUCTED if material != EditField.BASE_MATERIAL else SOLID
			if absf(density) <= 0.08:
				color = SURFACE
			if local_x % 50 == 0 or local_y % 50 == 0:
				color = color.lerp(GRID, 0.20)
			image.set_pixel(rect.position.x + local_x, rect.position.y + local_y, color)
	_draw_border(image, rect)


static func _shape_fixtures() -> Array[Dictionary]:
	return [
		{"id": "sphere", "mode": "construct", "shape": "sphere", "center": Vector3.ZERO, "radius_m": 2.4},
		{"id": "capsule", "mode": "construct", "shape": "capsule", "segment_a": Vector3(-2.2, 0.0, 0.0), "segment_b": Vector3(2.2, 0.0, 0.0), "radius_m": 1.1},
		{"id": "swept", "mode": "construct", "shape": "swept_stroke", "segment_a": Vector3(-2.4, -1.4, 0.0), "segment_b": Vector3(2.4, 1.4, 0.0), "radius_m": 0.8},
		{"id": "box", "mode": "construct", "shape": "rounded_box", "center": Vector3.ZERO, "half_extents": Vector3(2.7, 1.8, 1.3), "rounding_m": 0.55, "radius_m": 1.0},
		{"id": "plane", "mode": "construct", "shape": "plane_stamp", "center": Vector3.ZERO, "normal": Vector3.UP, "radius_m": 3.0, "depth_m": 1.2},
		{"id": "ellipsoid", "mode": "construct", "shape": "ellipsoid_stamp", "center": Vector3.ZERO, "half_extents": Vector3(2.8, 1.5, 1.0), "radius_m": 1.0},
		{"id": "noise", "mode": "construct", "shape": "bounded_noise", "center": Vector3.ZERO, "radius_m": 2.4, "noise_amplitude_m": 0.35, "noise_frequency": 1.3},
	]


static func _sequence_operations() -> Array[Dictionary]:
	return [
		{"id": "visual-dig-1", "mode": "dig", "shape": "sphere", "center": Vector3(8.0, 11.0, 16.0), "radius_m": 4.0, "smoothing_m": 0.35},
		{"id": "visual-dig-2", "mode": "dig", "shape": "swept_stroke", "segment_a": Vector3(8.0, 8.0, 16.0), "segment_b": Vector3(22.0, 8.0, 16.0), "radius_m": 2.2, "smoothing_m": 0.25},
		{"id": "visual-build-1", "mode": "construct", "shape": "rounded_box", "center": Vector3(20.0, 14.0, 16.0), "half_extents": Vector3(5.0, 1.2, 2.5), "rounding_m": 0.45, "radius_m": 1.0, "material": 7},
		{"id": "visual-build-2", "mode": "construct", "shape": "capsule", "segment_a": Vector3(24.0, 12.0, 16.0), "segment_b": Vector3(24.0, 18.0, 16.0), "radius_m": 1.5, "material": 8},
		{"id": "visual-dig-3", "mode": "dig", "shape": "sphere", "center": Vector3(20.0, 14.0, 16.0), "radius_m": 1.4},
	]


static func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			image.set_pixel(x, y, color)


static func _draw_border(image: Image, rect: Rect2i) -> void:
	for x in range(rect.position.x, rect.end.x):
		image.set_pixel(x, rect.position.y, GRID)
		image.set_pixel(x, rect.end.y - 1, GRID)
	for y in range(rect.position.y, rect.end.y):
		image.set_pixel(rect.position.x, y, GRID)
		image.set_pixel(rect.end.x - 1, y, GRID)
