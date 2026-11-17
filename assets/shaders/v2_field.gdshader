shader_type spatial;
// The exit gate's field: a sheet of light that drifts upward in bands and shimmers. Alpha-blended (never additive:
// in the Compatibility renderer an additive surface is drawn again by every shadowed light's extra pass).
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform vec3 tint = vec3(0.71, 0.55, 1.0);
uniform float strength = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

void fragment() {
	vec3 p = (inverse(MODEL_MATRIX) * INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;      // metres, the gate's frame
	float bands = 0.5 + 0.5 * sin(p.y * 14.0 - TIME * 3.2);
	float fine = 0.5 + 0.5 * sin(p.y * 90.0 + TIME * 9.0);
	float flick = hash(vec2(floor(p.x * 22.0), floor(p.y * 6.0 - TIME * 2.0)));
	float edge = smoothstep(0.85, 0.55, abs(p.x)) ;                                    // brighter toward the jambs
	float a = 0.34 + 0.3 * bands + 0.1 * fine + 0.14 * step(0.9, flick) + 0.25 * (1.0 - edge);
	ALBEDO = tint * (0.75 + 0.5 * bands) * strength;
	ALPHA = clamp(a, 0.0, 0.92);
}
