shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray terrain_textures : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray terrain_normal_textures : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float texture_scale_m = 3.0;
uniform float triplanar_sharpness = 4.0;
uniform vec3 texture_world_origin = vec3(0.0);
uniform float slope_start = 0.22;
uniform float slope_end = 0.72;
uniform float height_low_m = 3.5;
uniform float height_high_m = 13.0;
uniform float wetness_height_m = 6.5;
uniform vec3 decal_center_world = vec3(5.5, 7.0, 2.5);
uniform float decal_radius_m = 2.2;
uniform float camera_detail_start_m = 18.0;
uniform float camera_detail_end_m = 70.0;

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

	vec3 x_sample_n = texture(terrain_normal_textures, vec3(coordinates.zy, layer)).xyz * 2.0 - 1.0;
	vec3 y_sample_n = texture(terrain_normal_textures, vec3(coordinates.xz, layer)).xyz * 2.0 - 1.0;
	vec3 z_sample_n = texture(terrain_normal_textures, vec3(coordinates.xy, layer)).xyz * 2.0 - 1.0;
	vec3 signs = vec3(
		world_normal.x < 0.0 ? -1.0 : 1.0,
		world_normal.y < 0.0 ? -1.0 : 1.0,
		world_normal.z < 0.0 ? -1.0 : 1.0
	);
	vec3 x_normal = vec3(x_sample_n.z * signs.x, x_sample_n.x, x_sample_n.y);
	vec3 y_normal = vec3(y_sample_n.x, y_sample_n.z * signs.y, y_sample_n.y);
	vec3 z_normal = vec3(z_sample_n.x, z_sample_n.y, z_sample_n.z * signs.z);
	vec3 mapped_world_normal = normalize(x_normal * weights.x + y_normal * weights.y + z_normal * weights.z);
	float camera_distance_m = distance(CAMERA_POSITION_WORLD, world_position);
	float camera_detail = 1.0 - smoothstep(camera_detail_start_m, camera_detail_end_m, camera_distance_m);
	vec3 final_world_normal = normalize(mix(world_normal, mapped_world_normal, 0.3 + camera_detail * 0.7));
	NORMAL = normalize((VIEW_MATRIX * vec4(final_world_normal, 0.0)).xyz);

	float slope_mask = smoothstep(slope_start, slope_end, 1.0 - abs(world_normal.y));
	float height_mask = smoothstep(height_low_m, height_high_m, global_texture_position.y);
	float wetness_mask = (1.0 - smoothstep(wetness_height_m - 1.5, wetness_height_m + 1.5, global_texture_position.y))
		* smoothstep(0.25, 0.85, abs(world_normal.y));
	float decal_distance = distance(global_texture_position.xz, decal_center_world.xz);
	float decal_mask = (1.0 - smoothstep(decal_radius_m * 0.72, decal_radius_m, decal_distance))
		* smoothstep(0.45, 0.85, abs(world_normal.y));

	vec3 slope_tint = vec3(0.76, 0.80, 0.82);
	vec3 high_tint = vec3(0.82, 0.90, 0.84);
	vec3 shaded = mix(surface, surface * slope_tint, slope_mask * 0.34);
	shaded = mix(shaded, shaded * high_tint, height_mask * 0.22);
	shaded = mix(shaded, shaded * vec3(0.40, 0.54, 0.58), wetness_mask * 0.58);
	shaded = mix(shaded, vec3(0.82, 0.22, 0.08), decal_mask * 0.72);

	ALBEDO = shaded;
	ROUGHNESS = mix(0.82 - slope_mask * 0.08, 0.27, wetness_mask);
	METALLIC = decal_mask * 0.08;
	SPECULAR = mix(0.35, 0.72, wetness_mask);
	AO = mix(1.0, 0.82, slope_mask * (1.0 - height_mask));
	AO_LIGHT_AFFECT = 0.45;
}
