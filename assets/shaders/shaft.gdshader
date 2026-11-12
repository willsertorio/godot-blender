shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
// Fake light shaft under a ceiling light (alpha-blended: additive materials are drawn at full strength by the
// Compatibility renderer's extra pass for every shadowed light in range): a pale cone, brightest where you look through its middle, fading
// toward the floor (so it never draws a line where it meets it) and slowly drifting like lit dust.
uniform vec4 color : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform float strength = 0.16;
uniform float height = 4.0;
varying float h;
varying vec3 lp;

void vertex() {
	h = clamp(0.5 - VERTEX.y / height, 0.0, 1.0);   // 0 at the lamp, 1 at the floor
	lp = VERTEX;
}

void fragment() {
	float through = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float a = pow(through, 2.5) * pow(1.0 - h, 1.6) * smoothstep(0.0, 0.06, h);
	float drift = 0.85 + 0.15 * sin(lp.y * 3.0 + TIME * 0.35 + lp.x * 2.0) * sin(lp.z * 2.3 - TIME * 0.21);
	ALBEDO = color.rgb;
	ALPHA = a * strength * drift;
}
