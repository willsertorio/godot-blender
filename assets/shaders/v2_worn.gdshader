shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// V2 guns and robots: what the Blender materials do with Cycles-only nodes (edge wear from a bevelled normal,
// dirt from ambient occlusion), done here with a baked mask.
//  - base: a scanned set projected as a box in the part's own space (the same projection as StandardMaterial3D's
//    object-space triplanar, so parts with and without this shader match), tint and roughness range from Blender;
//  - mask (UV; v2/scripts/export_godot.py bake_mask): R = ambient occlusion, G = convex edges;
//  - paint worn down to `wear_color` on the edges, broken up by an imperfection map; scratches; dirt in the
//    crevices and in broad stains.
// Colour space: the Compatibility renderer takes ALBEDO as sRGB (it converts after this function) and its
// source_color hint converts nothing. The Blender numbers are linear, so the colour is worked out in linear
// here and handed back as sRGB.
uniform sampler2D tex_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_imperfections : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_mask : hint_default_white, filter_linear_mipmap;
uniform vec3 tint = vec3(1.0);          // linear, as in Blender
uniform float tile = 0.12;              // metres per repeat of the set
uniform float detail = 0.2;             // metres per repeat of the imperfection map
uniform vec2 rough_range = vec2(0.3, 0.6);
uniform float metallic = 0.0;
uniform float normal_strength = 1.0;
uniform float wear = 0.6;               // how much paint is gone from the edges
uniform vec3 wear_color = vec3(0.62);   // linear
uniform float wear_metal = 1.0;
uniform float cavity = 0.5;             // dirt in the crevices
uniform float scratch = 0.35;
uniform float grunge = 0.15;            // broad stains
uniform int debug = 0;                  // 1 = mask, 2 = wear, 3 = imperfections

varying vec3 tri_pos;
varying vec3 tri_w;

void vertex() {
	vec3 n = NORMAL;
	TANGENT = vec3(0.0, 0.0, -1.0) * abs(n.x);
	TANGENT += vec3(1.0, 0.0, 0.0) * abs(n.y);
	TANGENT += vec3(1.0, 0.0, 0.0) * abs(n.z);
	TANGENT = normalize(TANGENT);
	BINORMAL = vec3(0.0, 1.0, 0.0) * abs(n.x);
	BINORMAL += vec3(0.0, 0.0, -1.0) * abs(n.y);
	BINORMAL += vec3(0.0, 1.0, 0.0) * abs(n.z);
	BINORMAL = normalize(BINORMAL);
	tri_w = pow(abs(n), vec3(4.0));
	tri_w /= dot(tri_w, vec3(1.0));
	tri_pos = VERTEX * vec3(1.0, -1.0, 1.0);
}

vec4 tri(sampler2D s, vec3 w, vec3 p) {
	vec4 c = texture(s, p.xy) * w.z;
	c += texture(s, p.xz) * w.y;
	c += texture(s, p.zy * vec2(-1.0, 1.0)) * w.x;
	return c;
}

void fragment() {
	vec3 p = tri_pos / tile;
	vec3 alb = pow(tri(tex_albedo, tri_w, p).rgb, vec3(2.2)) * tint;
	float rough = mix(rough_range.x, rough_range.y, tri(tex_rough, tri_w, p).r);
	vec3 q = tri_pos / detail;
	vec3 imp = tri(tex_imperfections, tri_w, q + vec3(0.13)).rgb;               // fine: R scratches, G smudges, B dirt
	vec3 imp_big = tri(tex_imperfections, tri_w, q * 0.27 + vec3(0.41)).rgb;    // broad patches
	vec2 mk = texture(tex_mask, UV).rg;
	float ao = smoothstep(0.05, 0.7, mk.r);          // only the deep corners count
	float edge = smoothstep(0.3, 0.95, mk.g);        // (thin plates read as all edge in the mask: keep to the real corners)

	float patchy = smoothstep(0.15, 0.6, imp_big.b);
	float wm = edge * (0.45 + 0.9 * imp.b) * mix(0.5, 1.0, patchy) * wear * 1.7;
	wm += smoothstep(0.25, 0.7, imp.r) * scratch * wear * 0.8;                  // scratches down to the metal
	wm += smoothstep(0.55, 0.95, imp_big.g) * wear * 0.3;                       // a few rubbed patches
	wm = clamp(wm, 0.0, 1.0);

	float grime = clamp(imp_big.b * 0.8 + imp.b * 0.35 - 0.25, 0.0, 1.0) * grunge * 2.0 + (1.0 - ao) * cavity;
	grime = clamp(grime, 0.0, 1.0);
	alb *= 1.0 - 0.6 * grime;
	rough = rough + 0.25 * grime + (imp.g - 0.15) * 0.3 - imp.r * 0.15 * scratch;

	ALBEDO = pow(mix(alb, wear_color * (0.75 + 0.5 * imp.b), wm), vec3(1.0 / 2.2));
	METALLIC = mix(metallic, wear_metal, wm);
	ROUGHNESS = clamp(mix(rough, 0.3 + 0.2 * imp.g, wm), 0.05, 1.0);
	AO = mix(1.0, ao, 0.7);
	AO_LIGHT_AFFECT = 0.4;
	NORMAL_MAP = tri(tex_normal, tri_w, p).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	if (debug > 0) {
		vec3 dv = vec3(mk, 0.0);
		if (debug == 2) { dv = vec3(wm); }
		if (debug == 3) { dv = imp; }
		ALBEDO = vec3(0.0); METALLIC = 0.0; ROUGHNESS = 1.0; EMISSION = dv;
	}
}
