// V2 gloves and sleeves (skinned). The fabrics are projected from each vertex's REST position and REST normal
// (UV = rest x, y; UV2 = rest z, |normal x|; COLOR.b = |normal y|; positions normalised to the mesh's box), so the
// weave stays on the moving surface and each face keeps the projection it had before the arm was posed.
// COLOR.r = palm mask, COLOR.g = fingertip mask: knit back, leather palm, grippy tips with a seam line between them.
// Colour space: the Compatibility renderer takes ALBEDO as sRGB (it converts after this function) and its
// source_color hint converts nothing, so the Blender numbers (linear) are applied in linear here and the result
// is handed back as sRGB.
shader_type spatial;

uniform sampler2D knit_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D knit_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D leather_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec3 box_min = vec3(0.0);
uniform vec3 box_size = vec3(1.0);
uniform vec3 knit_tint = vec3(0.38, 0.4, 0.43);        // linear multipliers, as in Blender (v2/scripts/hands.py)
uniform vec3 leather_tint = vec3(1.95, 2.03, 2.21);
uniform vec3 tip_tint = vec3(1.0);
uniform float knit_scale = 0.11;
uniform float leather_scale = 0.03;
uniform float sleeve = 0.0;                           // 1 = the jacket sleeve: knit only, no masks
uniform float knit_bias = 2.5;
uniform int debug = 0;                                // 1 = masks, 2 = knit texture, 3 = rest position, 4 = weights

varying vec3 rest;
varying vec3 wgt;

void vertex() {
	rest = vec3(UV.x, 1.0 - UV.y, UV2.x) * box_size + box_min;
	vec3 n = vec3(1.0 - UV2.y, COLOR.b, 0.0);
	n.z = sqrt(max(0.0, 1.0 - n.x * n.x - n.y * n.y));
	n = pow(n, vec3(4.0));
	wgt = n / (n.x + n.y + n.z);
}

// (bias: the knit's threads are half a millimetre apart, about a pixel at arm's length: one mip level down they
// stop beating against the pixel grid)
vec3 tri(sampler2D t, vec3 p, float bias) {
	return texture(t, p.yz, bias).rgb * wgt.x + texture(t, p.xz, bias).rgb * wgt.y + texture(t, p.xy, bias).rgb * wgt.z;
}

vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }

void fragment() {
	vec3 knit = lin(tri(knit_albedo, rest / knit_scale, knit_bias)) * knit_tint;
	vec3 col = knit;
	float rough = 0.92;
	if (sleeve < 0.5) {
		float palm = smoothstep(0.49, 0.51, COLOR.r);
		float tip = smoothstep(0.49, 0.51, COLOR.g);
		vec3 lea = lin(tri(leather_albedo, rest / leather_scale, 1.5)) * leather_tint;
		col = mix(knit, lea, palm);
		col = mix(col, lin(tri(leather_albedo, rest / 0.012, 0.0)) * tip_tint, tip);
		rough = mix(0.92, 0.68, max(palm, tip));
		float seam = 1.0 - smoothstep(0.0, 0.07, min(abs(COLOR.r - 0.5), abs(COLOR.g - 0.5)));
		col *= 1.0 - 0.6 * seam;
	}
	ALBEDO = pow(col, vec3(1.0 / 2.2));
	ROUGHNESS = rough;
	if (debug > 0) {
		vec3 dv = vec3(COLOR.r, COLOR.g, 0.0);
		if (debug == 2) { dv = tri(knit_albedo, rest / knit_scale, knit_bias); }
		if (debug == 3) { dv = fract(rest / 0.004); }
		if (debug == 4) { dv = wgt; }
		ALBEDO = vec3(0.0); EMISSION = dv;
	}
	NORMAL_MAP = tri(knit_normal, rest / knit_scale, knit_bias);
	NORMAL_MAP_DEPTH = 0.6 * (1.0 - step(0.5, COLOR.r) * (1.0 - sleeve));
}
