shader_type spatial;
// Gloves / sleeves: flat tint + tiling textile detail (ambientCG CC0) layered over the
// character's own normal map (knuckles, creases). Detail albedo is normalised by its mean so
// the tint sets the overall colour and the texture only adds weave contrast.
uniform vec4 tint : source_color = vec4(0.05, 0.05, 0.06, 1.0);
uniform sampler2D base_normal : hint_normal;
uniform bool has_base_normal = false;
uniform sampler2D detail_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_rough : hint_roughness_gray, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 14.0;
uniform float detail_mean = 0.5;
uniform float albedo_contrast = 0.8;
uniform float normal_strength = 1.4;
uniform float rough_bias = 0.0;
uniform float sheen = 0.25;

void fragment() {
	vec2 duv = UV * tile;
	float lum = dot(texture(detail_albedo, duv).rgb, vec3(0.333));
	ALBEDO = tint.rgb * mix(1.0, lum / detail_mean, albedo_contrast);
	vec3 b = texture(detail_normal, duv).rgb * 2.0 - 1.0;
	b.xy *= normal_strength;
	vec3 a = has_base_normal ? texture(base_normal, UV).rgb * 2.0 - 1.0 : vec3(0.0, 0.0, 1.0);
	vec3 n = normalize(vec3(a.xy + b.xy, a.z * b.z));
	NORMAL_MAP = n * 0.5 + 0.5;
	ROUGHNESS = clamp(texture(detail_rough, duv).r + rough_bias, 0.05, 1.0);
	METALLIC = 0.0;
	// Cloth catches light at grazing angles.
	RIM = sheen;
	RIM_TINT = 0.6;
}
