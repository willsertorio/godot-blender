shader_type canvas_item;
// Title / end screen backdrop: dark field with a slowly drifting perspective neon grid.
uniform float alpha = 1.0;

void fragment() {
	vec2 uv = UV;
	vec3 col = vec3(0.006, 0.012, 0.022);
	// Floor grid below the horizon, receding.
	float horizon = 0.62;
	if (uv.y > horizon) {
		float d = (uv.y - horizon);
		float z = 0.18 / d;
		float x = (uv.x - 0.5) * z * 3.0;
		float zz = z + TIME * 0.6;
		float gx = abs(fract(x) - 0.5);
		float gz = abs(fract(zz) - 0.5);
		float line = smoothstep(0.47, 0.5, max(gx, gz));
		float fade = clamp(d * 3.0, 0.0, 1.0);
		col += vec3(0.133, 0.898, 1.0) * line * fade * 0.55;
	}
	// Horizon glow.
	col += vec3(0.133, 0.898, 1.0) * exp(-abs(uv.y - horizon) * 40.0) * 0.35;
	// Vignette.
	float v = smoothstep(1.1, 0.3, length((uv - 0.5) * vec2(1.4, 1.0)));
	COLOR = vec4(col * v, alpha);
}
