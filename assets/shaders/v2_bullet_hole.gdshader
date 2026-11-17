shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_disabled;
// A bullet strike on a painted panel, drawn on a quad 0.24 m across laid on the surface: the hole, the crater
// knocked out round it (bare material, shaded as a hollow: its normal leans toward the middle, so the room's
// light from above darkens its upper wall and catches its lower one), the paint flaked off beyond the crater's
// edge, a few cracks running out, a breath of soot. `seed` makes each of the variants different; the quad is
// turned at random as well.
// Colours are written as they should look (the Compatibility renderer takes ALBEDO as sRGB).

uniform float seed = 0.0;
const float SIZE = 0.24;

varying vec2 plane;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	plane = VERTEX.xy * SIZE;                               // metres from the strike, in the quad's plane
}

void fragment() {
	float r = length(plane);
	vec2 dir = plane / max(r, 0.00001);
	float ang = atan(plane.y, plane.x);
	float s = seed * 17.3;
	// the outlines wander with the direction
	float na = noise(dir * 1.7 + s);
	float nb = noise(dir * 4.1 + s + 31.0);
	float nc = noise(dir * 9.0 + s + 57.0);
	float hole_r = 0.0042 * (0.85 + 0.4 * nb);
	float crater_r = 0.011 + 0.010 * na + 0.004 * nb + 0.002 * nc;
	float chip_r = crater_r + 0.004 + 0.014 * nb * nb + 0.004 * nc;
	float grain = noise(plane * 420.0 + s);
	float blotch = noise(plane * 70.0 + s);

	// soot
	float soot = (1.0 - smoothstep(chip_r, 0.075, r)) * (0.35 + 0.65 * blotch) * 0.42;
	vec3 col = vec3(0.05, 0.05, 0.055);
	float alpha = soot;

	// cracks: one in most of nine sectors, each with its own direction, length and wander
	float sectors = 9.0;
	float k = floor(ang / 6.2831853 * sectors + 0.5 + seed);
	float crack = 0.0;
	for (float j = -1.0; j <= 1.0; j += 1.0) {
		float id = k + j;
		float h1 = hash(vec2(id, s));
		float h2 = hash(vec2(id + 7.0, s + 3.0));
		if (h1 < 0.72) {
			float a0 = (id - seed + (h2 - 0.5) * 0.7) / sectors * 6.2831853;
			a0 += (noise(vec2(r * 55.0, id + s)) - 0.5) * 0.22;
			float len = chip_r + 0.012 + 0.07 * h2 * h2;
			float d = r * abs(sin(ang - a0));
			float ahead = cos(ang - a0);
			float w = 0.0011 * (1.0 - smoothstep(chip_r, len, r)) + 0.00015;
			crack = max(crack, (1.0 - smoothstep(w * 0.5, w, d)) * step(0.0, ahead) * step(r, len) * step(crater_r, r));
		}
	}
	col = mix(col, vec3(0.045), crack);
	alpha = max(alpha, crack * 0.9);

	// paint flaked off: the primer under it, a dark line where the paint's broken edge stands
	float chip = 1.0 - smoothstep(chip_r - 0.0012, chip_r, r);
	vec3 primer = vec3(0.76, 0.75, 0.72) * (0.85 + 0.2 * grain);
	col = mix(col, primer, chip);
	alpha = mix(alpha, 1.0, chip);
	float lip = smoothstep(chip_r - 0.0035, chip_r - 0.0012, r) * chip;
	col *= 1.0 - 0.45 * lip;

	// the crater: bare material, darker toward the hole
	float crater = 1.0 - smoothstep(crater_r - 0.0015, crater_r, r);
	float depth = 1.0 - smoothstep(hole_r, crater_r, r);       // 1 at the hole, 0 at the crater's edge
	vec3 bare = mix(vec3(0.46, 0.45, 0.44), vec3(0.2, 0.2, 0.2), depth * 0.75) * (0.75 + 0.5 * grain);
	col = mix(col, bare, crater);

	// the hole
	float hole = 1.0 - smoothstep(hole_r, hole_r + 0.0012, r);
	col = mix(col, vec3(0.012), hole);

	// the hollow's walls lean toward the middle
	vec3 out_view = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(dir, 0.0, 0.0)).xyz);
	float slope = crater * (1.0 - hole) * (0.7 + 0.5 * depth) + lip * 0.5;
	NORMAL = normalize(NORMAL - out_view * slope);

	ALBEDO = col;
	ALPHA = alpha * (1.0 - smoothstep(0.1, 0.118, r));
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
}
