shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray terrain_textures : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray terrain_normal_textures : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float texture_scale_m = 3.0;
uniform float triplanar_sharpness = 4.0;
uniform float diagnostic_mix : hint_range(0.0, 1.0) = 0.16;
uniform vec3 texture_world_origin = vec3(0.0);

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 weights = pow(abs(world_normal), vec3(triplanar_sharpness));
	weights /= max(weights.x + weights.y + weights.z, 0.00001);

	float encoded_material = round(COLOR.r * 255.0);
	float layer = encoded_material >= 5.0 ? 2.0 : (encoded_material >= 2.0 ? 1.0 : 0.0);
	vec3 global_texture_position = world_position + texture_world_origin;
	vec3 coordinates = global_texture_position / texture_scale_m;
	vec3 x_sample = texture(terrain_textures, vec3(coordinates.zy, layer)).rgb;
	vec3 y_sample = texture(terrain_textures, vec3(coordinates.xz, layer)).rgb;
	vec3 z_sample = texture(terrain_textures, vec3(coordinates.xy, layer)).rgb;
	vec3 surface = x_sample * weights.x + y_sample * weights.y + z_sample * weights.z;

	vec3 x_normal_sample = texture(terrain_normal_textures, vec3(coordinates.zy, layer)).xyz * 2.0 - 1.0;
	vec3 y_normal_sample = texture(terrain_normal_textures, vec3(coordinates.xz, layer)).xyz * 2.0 - 1.0;
	vec3 z_normal_sample = texture(terrain_normal_textures, vec3(coordinates.xy, layer)).xyz * 2.0 - 1.0;
	vec3 signs = vec3(
		world_normal.x < 0.0 ? -1.0 : 1.0,
		world_normal.y < 0.0 ? -1.0 : 1.0,
		world_normal.z < 0.0 ? -1.0 : 1.0
	);
	vec3 x_normal = vec3(x_normal_sample.z * signs.x, x_normal_sample.x, x_normal_sample.y);
	vec3 y_normal = vec3(y_normal_sample.x, y_normal_sample.z * signs.y, y_normal_sample.y);
	vec3 z_normal = vec3(z_normal_sample.x, z_normal_sample.y, z_normal_sample.z * signs.z);
	vec3 blended_world_normal = normalize(x_normal * weights.x + y_normal * weights.y + z_normal * weights.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(blended_world_normal, 0.0)).xyz);

	vec3 diagnostic = mix(vec3(0.15, 0.52, 0.31), vec3(0.92, 0.67, 0.19), step(4.5, encoded_material));
	ALBEDO = mix(surface, diagnostic, diagnostic_mix);
	ROUGHNESS = mix(0.82, 0.6, step(4.5, encoded_material));
	METALLIC = 0.0;
}
