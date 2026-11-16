shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// The environment set's painted surfaces (walls, floors, crates, equipment): what the Blender materials of
// v2/scripts/setlib.py do, with what the exported meshes carry.
//  - base: the painted-plaster set projected as a box in object space, tinted (the Blender tint, linear);
//  - vertex colour (v2/scripts/export_set.py): R = ambient occlusion, G = 1 on the chamfered edges;
//  - paint knocked off the edges and in a few chips, down to `wear_color`; scratches; dirty patches and streaks
//    running down; dirt in the crevices; grime that has crept up from the floor (object y below `grime_height`:
//    the dungeon's merged meshes are in the world's frame, a prop's origin is at its foot);
//  - stripes = 1: black and yellow at 45 degrees instead of the tint (the hazard paint).
// Colour space: the Compatibility renderer takes ALBEDO as sRGB and its source_color hint converts nothing; the
// colour is worked out in linear here and handed back as sRGB (as v2_worn.gdshader does).
uniform sampler2D tex_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// (four lookups a pixel: colour, normal, and the imperfections map twice. It had six, all anisotropic, on every wall and
// floor of a Retina screen: the roughness map and the streaks' own lookup went; only colour and normal are anisotropic)
uniform sampler2D tex_imperfections : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec3 tint = vec3(0.76, 0.77, 0.76);
uniform vec3 wear_color = vec3(0.17, 0.17, 0.18);
uniform float tile = 0.9;               // metres per repeat of the paint set
uniform float wear = 0.8;               // paint gone from the edges
uniform float chips = 0.05;             // and in patches away from them
uniform float smudge = 0.75;            // dirty patches and streaks
uniform float cavity = 0.8;             // dirt in the crevices
uniform float grime = 0.55;             // dirt from the floor
uniform float grime_height = 0.3;
uniform vec2 rough_range = vec2(0.3, 0.6);
uniform float stripes = 0.0;
uniform float stripe_period = 0.115;

// One projection per triangle, not three blended: walls, floors and ceilings fill the screen with this shader, and
// box projection costs three samples a map (eighteen a pixel with the six lookups below; now six). `axis` is flat:
// the whole triangle uses the axis its first vertex faces, so nothing smears where a round part turns.
varying vec3 tri_pos;
varying flat int axis;
varying vec3 obj_pos;
varying float up;

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
	vec3 an = abs(n);
	axis = an.x > an.y ? (an.x > an.z ? 0 : 2) : (an.y > an.z ? 1 : 2);
	tri_pos = VERTEX * vec3(1.0, -1.0, 1.0);
	obj_pos = VERTEX;
	up = n.y;
}

vec2 plane(vec3 p) {
	return axis == 0 ? p.zy * vec2(-1.0, 1.0) : (axis == 1 ? p.xz : p.xy);
}

void fragment() {
	vec3 p = tri_pos / tile;
	vec3 base = tint;
	if (stripes > 0.5) {
		// (edges as wide as a pixel: from across a room the stripes are thinner than pixels and a hard edge crawled)
		float sv = dot(obj_pos, vec3(1.0 / stripe_period));
		float sw = clamp(fwidth(sv) * 1.5, 0.001, 0.5);
		float s = smoothstep(0.5 - sw, 0.5 + sw, abs(fract(sv) * 2.0 - 1.0));
		base = mix(vec3(0.6, 0.3, 0.0), vec3(0.03, 0.03, 0.032), s);
	}
	vec4 at = texture(tex_albedo, plane(p));
	vec3 alb = pow(at.rgb, vec3(2.2)) * base;
	vec3 imp = texture(tex_imperfections, plane(tri_pos / 0.7 + vec3(0.13))).rgb;            // fine: R scratches, G smudges, B dirt
	// broad patches, stretched down the walls (on floors and ceilings y is the normal: they stay round)
	vec3 imp_big = texture(tex_imperfections, plane(tri_pos * vec3(0.6, 0.22, 0.6) + vec3(0.41))).rgb;
	float rough = mix(rough_range.x, rough_range.y, 0.35 + 0.5 * imp.g);
	float ao = COLOR.r;
	float edge = COLOR.g;

	// paint off: the chamfered edges (broken up), a few chips, fine scratches
	float wm = edge * smoothstep(0.25, 0.6, imp.b + imp_big.b * 0.5) * wear * 1.3;
	wm += smoothstep(1.0 - chips * 1.6, 1.0 - chips * 1.6 + 0.1, imp_big.g * 0.6 + imp.b * 0.5);
	wm += smoothstep(0.3, 0.75, imp.r) * 0.3 * wear;
	wm = clamp(wm, 0.0, 1.0);

	// dirt: patches and streaks, the crevices, the floor
	float dirt = smoothstep(0.25, 0.75, imp_big.b * 1.3) * smudge * 0.55;
	dirt += (1.0 - smoothstep(0.1, 0.85, ao)) * cavity;
	float low = clamp(1.0 - obj_pos.y / grime_height, 0.0, 1.0) * (0.35 + 0.9 * imp_big.b) * grime * (1.0 - 0.7 * max(up, 0.0));
	dirt = clamp(dirt + low, 0.0, 1.0);
	alb = mix(alb, vec3(0.1, 0.095, 0.085), dirt * 0.75);
	rough = clamp(rough + 0.3 * dirt + (imp.g - 0.2) * 0.2, 0.05, 1.0);

	ALBEDO = pow(mix(alb, wear_color * (0.8 + 0.4 * imp.b), wm), vec3(1.0 / 2.2));
	METALLIC = 0.7 * wm;
	ROUGHNESS = mix(rough, 0.38, wm);
	AO = mix(1.0, ao, 0.6);
	AO_LIGHT_AFFECT = 0.35;
	NORMAL_MAP = texture(tex_normal, plane(p)).rgb;
	NORMAL_MAP_DEPTH = 0.35;
}
