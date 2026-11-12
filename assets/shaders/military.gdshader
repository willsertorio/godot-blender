shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Worn military hardware for the from-scratch models (no UVs): triplanar PBR in the part's own space, plus
//  - edge wear: the paint is rubbed off convex edges. Edges are found per pixel from how fast the shaded normal
//    turns across the surface (screen-space curvature of the bevels), so no baked masks or UVs are needed;
//  - scratches / smudges / dirt from a packed imperfection map (R / G / B), at two scales so it never tiles;
//  - crevice darkening on concave bevels.

// No source_color hint: the sRGB -> linear conversion is done explicitly below (the hint did not convert the
// VRAM-compressed sets in the Compatibility renderer, which made every base colour several times too bright).
uniform sampler2D tex_albedo : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_metal : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_imperfections : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
// Baked per-model mask (blender/scripts/export_new_assets.py), read through UV1: R = ambient occlusion,
// G = edge mask (convex edges). Without it the edges come from screen-space curvature (thin, sub-pixel on bevels).
uniform sampler2D tex_mask : hint_default_white, filter_linear_mipmap;
uniform bool use_mask = false;
uniform float albedo_contrast = 0.55;  // 1 = the scan's own mottling, 0 = flat colour
uniform vec4 tint : source_color = vec4(1.0);
uniform float brightness = 1.0;      // the scanned sets are very dark; lifts the base colour to a real finish
uniform float metallic = 0.0;
uniform bool use_metal_map = false;
uniform float rough_scale = 1.0;
uniform float tile = 0.12;            // metres per texture repeat
uniform float normal_strength = 1.0;
uniform float wear = 0.6;             // how much paint is gone from the edges (0 = none)
uniform vec4 wear_color : source_color = vec4(0.62, 0.62, 0.6, 1.0);
uniform float wear_metallic = 1.0;
uniform float wear_rough = 0.32;
uniform float edge_radius = 0.0015;   // a bevel this tight (m) counts as a full edge
uniform float scratch = 0.5;
uniform float dirt = 0.4;
uniform int debug = 0;               // 1 edge, 2 wear mask, 3 imperfections, 4 base albedo

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
	vec3 alb = pow(tri(tex_albedo, tri_w, p).rgb, vec3(2.2));
	vec3 alb_mean = pow(textureLod(tex_albedo, vec2(0.5), 20.0).rgb, vec3(2.2));   // smallest mip = the set's mean
	alb = mix(alb_mean, alb, albedo_contrast) * tint.rgb * brightness;
	float rough = tri(tex_rough, tri_w, p).r * rough_scale;
	float metal = use_metal_map ? tri(tex_metal, tri_w, p).r * metallic : metallic;
	vec3 imp = tri(tex_imperfections, tri_w, p * 0.61 + vec3(0.13)).rgb;        // fine
	vec3 imp_big = tri(tex_imperfections, tri_w, p * 0.17 + vec3(0.41)).rgb;    // broad patches

	// Signed curvature (1/m): positive on convex bevels, negative in creases.
	vec3 n = normalize(NORMAL);
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	float curv = (dot(dFdx(n), dpx) + dot(dFdy(n), dpy)) / max(dot(dpx, dpx) + dot(dpy, dpy), 1e-10);
	float edge = smoothstep(0.3, 1.0, curv * edge_radius);
	float crease = smoothstep(0.3, 1.0, -curv * edge_radius);
	float ao = 1.0;
	if (use_mask) {
		vec2 mk = texture(tex_mask, UV).rg;
		ao = mk.r;
		edge = max(edge, smoothstep(0.08, 0.75, mk.g));
		crease = max(crease, smoothstep(0.55, 0.1, ao) * 0.8);
	}

	float patchy = smoothstep(0.15, 0.6, imp_big.b);
	float wear_mask = edge * (0.45 + 0.9 * imp.b) * mix(0.5, 1.0, patchy) * wear * 1.7;
	wear_mask += smoothstep(0.25, 0.7, imp.r) * scratch * wear * 0.8;            // scratches down to the metal
	wear_mask += smoothstep(0.55, 0.95, imp_big.g) * wear * 0.35;                // a few rubbed patches
	wear_mask = clamp(wear_mask, 0.0, 1.0);

	float grime = clamp(imp_big.b * 0.8 + imp.b * 0.35 - 0.25 + (1.0 - ao) * 0.9, 0.0, 1.0) * dirt;   // dirt collects in the crevices
	alb *= 1.0 - 0.45 * grime;
	alb *= 1.0 - 0.5 * crease;
	rough = rough + 0.25 * grime + (imp.g - 0.15) * 0.35 - imp.r * 0.15 * scratch;

	ALBEDO = mix(alb, wear_color.rgb * (0.75 + 0.5 * imp.b), wear_mask);
	METALLIC = mix(metal, wear_metallic, wear_mask);
	ROUGHNESS = clamp(mix(rough, wear_rough + 0.2 * imp.g, wear_mask), 0.05, 1.0);
	AO = min(1.0 - 0.6 * crease, mix(1.0, ao, 0.85));
	AO_LIGHT_AFFECT = 0.55;   // baked occlusion also dims direct light in the crevices
	NORMAL_MAP = tri(tex_normal, tri_w, p).rgb;
	if (debug > 0) {
		vec3 dv = alb;
		if (debug == 1) { dv = vec3(edge, crease, 0.0); }
		if (debug == 2) { dv = vec3(wear_mask); }
		if (debug == 3) { dv = imp; }
		ALBEDO = vec3(0.0); METALLIC = 0.0; ROUGHNESS = 1.0; EMISSION = dv;
	}
	NORMAL_MAP_DEPTH = normal_strength;
}
