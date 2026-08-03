shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	float slope = smoothstep(0.18, 0.78, 1.0 - abs(world_normal.y));
	float authored = step(0.5, UV2.y);
	float detail = 0.94 + 0.06 * sin(world_position.x * 0.15 + world_position.z * 0.11);
	vec3 ground = vec3(0.19, 0.48, 0.28);
	vec3 rock = vec3(0.38, 0.43, 0.44);
	vec3 authored_surface = vec3(0.74, 0.48, 0.16);
	vec3 base = mix(ground, rock, slope) * detail;
	ALBEDO = mix(base, authored_surface, authored * 0.72);
	ROUGHNESS = mix(0.9, 0.72, authored);
	METALLIC = 0.0;
}
