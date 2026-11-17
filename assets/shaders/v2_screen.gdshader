shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;
// A display of the environment set (console, wall panel, instruments): a faint grid, blocks of read-out that
// change now and then, a scan line. Drawn in object space, so it needs no UVs.
uniform vec3 tint = vec3(0.2, 0.9, 0.85);
uniform float cells = 13.0;             // blocks per metre
uniform float strength = 1.0;

varying vec3 pos;
varying vec3 nrm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

void vertex() {
	pos = VERTEX;
	nrm = NORMAL;
}

void fragment() {
	// the two axes that lie in the screen's plane
	vec3 a = abs(nrm);
	vec2 uv = a.y > 0.7 ? pos.xz : vec2(a.x > a.z ? pos.z : pos.x, pos.y);
	vec2 g = uv * cells * 2.0;
	float grid = max(step(0.94, fract(g.x)), step(0.94, fract(g.y))) * 0.22;
	vec2 cell = floor(uv * cells);
	float lit = step(0.8, hash(cell + floor(TIME * 0.35 + hash(cell) * 5.0)));
	vec2 f = abs(fract(uv * cells) - 0.5);
	float frame = lit * step(0.34, max(f.x, f.y));
	float scan = 0.06 * step(0.985, fract(uv.y * 1.3 - TIME * 0.12));
	float v = 0.05 + max(grid, frame) + scan;
	ALBEDO = (vec3(0.01, 0.03, 0.035) + tint * v * 1.6) * strength;
}
