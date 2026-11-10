shader_type spatial;
// Exit portal field: a violet vortex spiralling inward, brightest at the rim, with a
// translucent dark centre so the room behind is half-visible. Uses object-space position
// (the disc is in the model's XY plane after import: x across, y up, centred at centre_y).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.706, 0.549, 1.0, 1.0);
uniform float radius = 1.08;
uniform float centre_y = 1.45;
uniform float energy = 0.85;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 p = vec2(local_pos.x, local_pos.y - centre_y) / radius;
	float r = length(p);
	float a = atan(p.y, p.x);
	float swirl = a + r * 5.0 - TIME * 1.6;
	float arms = 0.5 + 0.5 * sin(swirl * 4.0);
	float rings = 0.5 + 0.5 * sin(r * 22.0 - TIME * 3.0);
	float rim = smoothstep(0.55, 1.0, r);
	float core = smoothstep(0.35, 0.0, r);
	float sparkle = step(0.985, hash(floor(vec2(a * 12.0, r * 30.0 - TIME * 4.0))));
	float v = arms * (0.25 + 0.75 * r) * 0.55 + rings * rim * 0.35 + core * 0.4 + sparkle * 0.6;
	v *= smoothstep(1.02, 0.96, r);
	ALBEDO = tint.rgb * v * energy;
}
