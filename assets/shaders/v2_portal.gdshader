shader_type spatial;
// The exit portal's field (reference 22): light spiralling into the middle, cyan with orange sparks. Alpha-blended
// (never additive: in the Compatibility renderer an additive surface is drawn again by every shadowed light's pass).
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform float strength = 1.0;

varying vec3 pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

void vertex() {
	pos = VERTEX;
}

void fragment() {
	vec2 q = vec2(pos.x, (pos.y - 1.35) * 0.55);            // the field is tall: its middle, squeezed to a circle
	float r = length(q);
	float ang = atan(q.y, q.x);
	float swirl = ang + 2.6 / (r + 0.25) - TIME * 1.1;      // arms that wind tighter toward the middle
	float arms = 0.5 + 0.5 * sin(swirl * 3.0 + sin(r * 9.0 - TIME * 2.0));
	float rings = 0.5 + 0.5 * sin(r * 26.0 - TIME * 5.0 + ang * 2.0);
	float v = pow(arms, 2.2) * (0.55 + 0.45 * rings);
	float spark = step(0.965, hash(vec2(floor(swirl * 5.0), floor(r * 30.0 - TIME * 6.0))));
	vec3 col = mix(vec3(0.0, 0.08, 0.14), vec3(0.25, 0.95, 1.0), v) + vec3(1.0, 0.45, 0.08) * spark * 0.9;
	col += vec3(0.6, 1.0, 1.0) * smoothstep(0.35, 0.0, r) * 0.6;      // the bright heart
	ALBEDO = col * strength;
	ALPHA = clamp(0.72 + 0.28 * v + spark, 0.0, 0.97);
}
