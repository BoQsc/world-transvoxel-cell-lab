shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 lod_tint = vec3(0.72, 1.0, 0.76);

varying vec3 world_position;
varying vec3 world_normal;
varying float material_id;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	material_id = UV2.x;
}

void fragment() {
	float slope = 1.0 - abs(world_normal.y);
	float authored = step(0.5, UV2.y);
	vec3 soil = vec3(0.19, 0.43, 0.25);
	vec3 rock = vec3(0.36, 0.39, 0.40);
	vec3 authored_surface = vec3(0.64, 0.48, 0.20);
	vec3 base = mix(soil, rock, smoothstep(0.22, 0.72, slope));
	base = mix(base, authored_surface, authored * 0.72);

	vec2 chunk_phase = abs(fract(world_position.xz / 16.0) - vec2(0.5));
	float chunk_edge = 1.0 - smoothstep(0.462, 0.495, max(chunk_phase.x, chunk_phase.y));
	float height_detail = 0.94 + 0.06 * sin(world_position.x * 0.17 + world_position.z * 0.11);
	ALBEDO = mix(base * lod_tint * height_detail, vec3(0.06, 0.12, 0.11), chunk_edge * 0.32);
	ROUGHNESS = mix(0.88, 0.7, authored);
	METALLIC = 0.0;
}
