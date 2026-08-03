shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray terrain_textures : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray terrain_normal_textures : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float texture_scale_m = 3.0;
uniform float triplanar_sharpness = 4.0;
uniform vec3 texture_world_origin = vec3(0.0);
uniform vec3 decal_center_global = vec3(96.0, 21.0, 40.0);
uniform float decal_radius_m = 4.0;
uniform int diagnostic_mode : hint_range(0, 5) = 0;

varying vec3 world_position;
varying vec3 world_normal;
varying vec2 primary_material;
varying vec4 generated_low;
varying vec4 generated_high;
varying vec4 authored_low;
varying vec4 authored_high;

vec3 triplanar_albedo(vec3 coordinates, vec3 weights, float layer) {
	vec3 x_sample = texture(terrain_textures, vec3(coordinates.zy, layer)).rgb;
	vec3 y_sample = texture(terrain_textures, vec3(coordinates.xz, layer)).rgb;
	vec3 z_sample = texture(terrain_textures, vec3(coordinates.xy, layer)).rgb;
	return x_sample * weights.x + y_sample * weights.y + z_sample * weights.z;
}

vec3 triplanar_normal(vec3 coordinates, vec3 weights, float layer, vec3 signs) {
	vec3 x_sample = texture(terrain_normal_textures, vec3(coordinates.zy, layer)).xyz * 2.0 - 1.0;
	vec3 y_sample = texture(terrain_normal_textures, vec3(coordinates.xz, layer)).xyz * 2.0 - 1.0;
	vec3 z_sample = texture(terrain_normal_textures, vec3(coordinates.xy, layer)).xyz * 2.0 - 1.0;
	vec3 x_normal = vec3(x_sample.z * signs.x, x_sample.x, x_sample.y);
	vec3 y_normal = vec3(y_sample.x, y_sample.z * signs.y, y_sample.y);
	vec3 z_normal = vec3(z_sample.x, z_sample.y, z_sample.z * signs.z);
	return normalize(x_normal * weights.x + y_normal * weights.y + z_normal * weights.z);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	primary_material = UV2;
	generated_low = CUSTOM0;
	generated_high = CUSTOM1;
	authored_low = CUSTOM2;
	authored_high = CUSTOM3;
}

void fragment() {
	vec3 axis_weights = pow(abs(world_normal), vec3(triplanar_sharpness));
	axis_weights /= max(axis_weights.x + axis_weights.y + axis_weights.z, 0.00001);
	vec4 generated_a = max(generated_low, vec4(0.0));
	vec4 generated_b = max(generated_high, vec4(0.0));
	vec4 authored_a = max(authored_low, vec4(0.0));
	vec4 authored_b = max(authored_high, vec4(0.0));
	float generated_sum = dot(generated_a + generated_b, vec4(1.0));
	float authored_sum = dot(authored_a + authored_b, vec4(1.0));
	vec4 selected_a = generated_a;
	vec4 selected_b = generated_b;
	if (authored_sum >= generated_sum && authored_sum > 0.0001) {
		selected_a = authored_a;
		selected_b = authored_b;
		float maximum_weight = max(max(selected_a.x, selected_a.y), max(selected_a.z, selected_a.w));
		maximum_weight = max(maximum_weight, max(max(selected_b.x, selected_b.y), max(selected_b.z, selected_b.w)));
		selected_a = vec4(
			step(maximum_weight - 0.00001, selected_a.x),
			step(maximum_weight - 0.00001, selected_a.y) * step(selected_a.x + 0.00001, maximum_weight),
			step(maximum_weight - 0.00001, selected_a.z) * step(selected_a.x + selected_a.y + 0.00001, maximum_weight),
			step(maximum_weight - 0.00001, selected_a.w) * step(selected_a.x + selected_a.y + selected_a.z + 0.00001, maximum_weight)
		);
		selected_b *= step(dot(selected_a, vec4(1.0)), 0.00001);
	}
	float selected_sum = max(dot(selected_a + selected_b, vec4(1.0)), 0.00001);
	selected_a /= selected_sum;
	selected_b /= selected_sum;

	vec3 global_texture_position = world_position + texture_world_origin;
	vec3 coordinates = global_texture_position / texture_scale_m;
	vec3 surface = vec3(0.0);
	surface += triplanar_albedo(coordinates, axis_weights, 0.0) * selected_a.x;
	surface += triplanar_albedo(coordinates, axis_weights, 1.0) * selected_a.y;
	surface += triplanar_albedo(coordinates, axis_weights, 2.0) * selected_a.z;
	surface += triplanar_albedo(coordinates, axis_weights, 3.0) * selected_a.w;
	surface += triplanar_albedo(coordinates, axis_weights, 4.0) * selected_b.x;
	surface += triplanar_albedo(coordinates, axis_weights, 5.0) * selected_b.y;
	surface += triplanar_albedo(coordinates, axis_weights, 6.0) * selected_b.z;
	surface += triplanar_albedo(coordinates, axis_weights, 7.0) * selected_b.w;

	float dominant_layer = 0.0;
	float dominant_weight = selected_a.x;
	if (selected_a.y > dominant_weight) { dominant_layer = 1.0; dominant_weight = selected_a.y; }
	if (selected_a.z > dominant_weight) { dominant_layer = 2.0; dominant_weight = selected_a.z; }
	if (selected_a.w > dominant_weight) { dominant_layer = 3.0; dominant_weight = selected_a.w; }
	if (selected_b.x > dominant_weight) { dominant_layer = 4.0; dominant_weight = selected_b.x; }
	if (selected_b.y > dominant_weight) { dominant_layer = 5.0; dominant_weight = selected_b.y; }
	if (selected_b.z > dominant_weight) { dominant_layer = 6.0; dominant_weight = selected_b.z; }
	if (selected_b.w > dominant_weight) { dominant_layer = 7.0; }
	vec3 signs = vec3(
		world_normal.x < 0.0 ? -1.0 : 1.0,
		world_normal.y < 0.0 ? -1.0 : 1.0,
		world_normal.z < 0.0 ? -1.0 : 1.0
	);
	vec3 mapped_world_normal = triplanar_normal(
		coordinates, axis_weights, dominant_layer, signs
	);
	vec3 final_world_normal = normalize(mix(world_normal, mapped_world_normal, 0.7));
	NORMAL = normalize((VIEW_MATRIX * vec4(final_world_normal, 0.0)).xyz);

	float decal_distance = distance(global_texture_position.xz, decal_center_global.xz);
	float decal_mask = (1.0 - smoothstep(decal_radius_m * 0.72, decal_radius_m, decal_distance))
		* smoothstep(0.4, 0.82, abs(world_normal.y));
	vec3 shaded = mix(surface, vec3(0.96, 0.21, 0.05), decal_mask * 0.74);
	if (diagnostic_mode == 1) {
		ALBEDO = vec3(0.0);
		EMISSION = selected_a.xyz + vec3(selected_a.w, selected_b.x, selected_b.y) * 0.5
			+ vec3(selected_b.z, selected_b.w, 0.0) * 0.35;
	} else if (diagnostic_mode == 2) {
		ALBEDO = vec3(0.0);
		EMISSION = authored_sum > generated_sum ? vec3(1.0, 0.55, 0.08) : vec3(0.08, 0.58, 1.0);
	} else if (diagnostic_mode == 3) {
		ALBEDO = vec3(0.0);
		EMISSION = axis_weights;
	} else if (diagnostic_mode == 4) {
		ALBEDO = vec3(0.0);
		EMISSION = final_world_normal * 0.5 + 0.5;
	} else if (diagnostic_mode == 5) {
		ALBEDO = vec3(0.0);
		EMISSION = vec3(decal_mask, 0.12, 1.0 - decal_mask);
	} else {
		ALBEDO = shaded;
		ROUGHNESS = mix(0.88, 0.62, clamp(authored_sum, 0.0, 1.0));
		SPECULAR = 0.34;
	}
}
