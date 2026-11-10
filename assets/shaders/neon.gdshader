shader_type spatial;
// Animated neon for every material named Neon* (see scripts/material_lib.gd).
// Unshaded HDR colour so glow picks it up, with a slow travelling shimmer along the
// strip (UVs are in metres, so the wave has the same pitch on every piece).
render_mode unshaded, cull_back;

uniform vec4 neon_color : source_color = vec4(0.133, 0.898, 1.0, 1.0);
uniform float energy = 2.6;
uniform float flow_speed = 0.6;
uniform float flow_amount = 0.18;
uniform float flicker = 0.0; // 0..1, used for damaged/telegraph strips

void fragment() {
	float wave = sin((UV.x + UV.y) * 1.6 - TIME * flow_speed * 6.2831);
	float f = 1.0 - flow_amount * 0.5 + flow_amount * 0.5 * wave;
	f *= 1.0 - flicker * step(0.85, fract(sin(floor(TIME * 18.0)) * 43758.5453));
	ALBEDO = neon_color.rgb * energy * f;
}
