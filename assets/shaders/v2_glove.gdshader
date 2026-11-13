// V2 gloves and sleeves (skinned). The fabrics are projected from each vertex's REST position (UV = rest x, y;
// UV2.x = rest z; normalised to the mesh's box), so the weave stays on the moving surface. COLOR.r = palm mask,
// COLOR.g = fingertip mask: knit back, leather palm, grippy tips with a seam line between them.
shader_type spatial;

uniform sampler2D knit_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D knit_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D leather_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec3 box_min = vec3(0.0);
uniform vec3 box_size = vec3(1.0);
uniform vec3 knit_tint : source_color = vec3(0.38, 0.4, 0.43);
uniform vec3 leather_tint : source_color = vec3(0.3, 0.31, 0.34);
uniform vec3 tip_tint : source_color = vec3(0.16, 0.16, 0.17);
uniform float knit_scale = 0.11;
uniform float leather_scale = 0.03;
uniform float sleeve = 0.0;                           // 1 = the jacket sleeve: knit only, no masks

varying vec3 rest;
varying vec3 wgt;

void vertex() {
	rest = vec3(UV.x, 1.0 - UV.y, UV2.x) * box_size + box_min;
	vec3 n = pow(abs(NORMAL), vec3(4.0));
	wgt = n / (n.x + n.y + n.z);
}

vec3 tri(sampler2D t, vec3 p) {
	return texture(t, p.yz).rgb * wgt.x + texture(t, p.xz).rgb * wgt.y + texture(t, p.xy).rgb * wgt.z;
}

void fragment() {
	vec3 knit = tri(knit_albedo, rest / knit_scale) * knit_tint;
	vec3 col = knit;
	float rough = 0.92;
	if (sleeve < 0.5) {
		float palm = smoothstep(0.49, 0.51, COLOR.r);
		float tip = smoothstep(0.49, 0.51, COLOR.g);
		vec3 lea = tri(leather_albedo, rest / leather_scale) * leather_tint * 2.2;
		col = mix(knit, lea, palm);
		col = mix(col, tri(leather_albedo, rest / 0.012) * tip_tint * 2.0, tip);
		rough = mix(0.92, 0.68, max(palm, tip));
		float seam = 1.0 - smoothstep(0.0, 0.07, min(abs(COLOR.r - 0.5), abs(COLOR.g - 0.5)));
		col *= 1.0 - 0.6 * seam;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	NORMAL_MAP = tri(knit_normal, rest / knit_scale);
	NORMAL_MAP_DEPTH = 0.6 * (1.0 - step(0.5, COLOR.r) * (1.0 - sleeve));
}
