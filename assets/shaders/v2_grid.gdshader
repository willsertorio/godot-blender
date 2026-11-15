// V2 studio floor: a measuring grid painted on a grey floor: a line every metre, a heavier one every five,
// faint half-metre ticks. Drawn from the mesh's own position (the room's frame), antialiased; far away the lines
// melt into the floor colour. (Colours are sRGB: the Compatibility renderer takes ALBEDO as stored.)
shader_type spatial;

uniform vec3 base = vec3(0.60, 0.62, 0.64);
uniform vec3 line = vec3(0.40, 0.42, 0.45);
uniform vec3 heavy = vec3(0.28, 0.30, 0.33);

varying vec3 pos;

void vertex() {
	pos = VERTEX;
}

float grid(vec2 p, float period, float width) {
	vec2 q = abs(fract(p / period + 0.5) - 0.5) * period;       // distance to the nearest line, each way
	vec2 w = fwidth(p);
	vec2 a = 1.0 - smoothstep(vec2(width * 0.5) - w, vec2(width * 0.5) + w, q);
	float fade = 1.0 - smoothstep(0.25, 0.6, max(w.x, w.y) / period);   // (a line thinner than a pixel dims instead of flickering)
	return max(a.x, a.y) * fade;
}

void fragment() {
	vec2 p = pos.xz;
	vec3 c = mix(base, line, 0.35 * grid(p, 0.5, 0.008));
	c = mix(c, line, grid(p, 1.0, 0.016));
	c = mix(c, heavy, grid(p, 5.0, 0.04));
	ALBEDO = c;
	ROUGHNESS = 0.72;
}
