// V2 muzzle flash: the flame is drawn from the UVs on a canvas mesh (crossed planes + a square across the barrel),
// the same function as the Blender materials FlashFire / FlashCore (v2/scripts/build_pistol.py).
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform bool core = false;
uniform float energy = 5.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 b = vec2(UV.x, 1.0 - UV.y);                  // Blender's UV (glTF flips V)
	float seed = floor(TIME * 24.0) * 7.31;           // a new flame every frame
	float a;
	if (core) {                                       // a burst seen end-on: rays of uneven length
		float reach = mix(0.3, 1.0, smoothstep(0.35, 0.65, noise(normalize(b) * 2.6 + seed)));
		a = pow(clamp(1.0 - length(b) / reach, 0.0, 1.0), 1.7);
	} else {                                          // a tongue: widest a third of the way out, pointed at the tip
		float v = clamp(b.y, 0.0, 1.0);
		float edge = max(sqrt(v) * pow(1.0 - v, 1.2) * 2.3, 0.001);
		a = pow(clamp(1.0 - abs(b.x) / edge, 0.0, 1.0), 1.3);
	}
	a *= mix(0.3, 1.5, smoothstep(0.3, 0.7, noise(b * 3.2 + seed)));
	a *= mix(0.55, 1.25, noise(b * 10.0 + seed * 1.7));
	a = clamp(a, 0.0, 1.0);
	ALBEDO = mix(vec3(1.0, 0.27, 0.04), vec3(1.0, 0.86, 0.55), pow(a, 0.6)) * (1.0 + energy * pow(a, 1.2));
	ALPHA = clamp(a * 1.25, 0.0, 1.0);
}
