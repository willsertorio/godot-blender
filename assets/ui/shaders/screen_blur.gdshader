// Full-screen blur of the 3D view. Put on a ColorRect that covers the screen,
// in a CanvasLayer BELOW the HUD so the HUD stays sharp.
// Used on: hit taken (short pulse) and Signal lost (constant, strong).
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 6.0) = 2.5; // mip level; 2.5 ~ hit taken, 4.5 ~ Signal lost
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.0); // optional color wash, alpha = strength

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, amount).rgb;
	c = mix(c, tint.rgb, tint.a);
	COLOR = vec4(c, 1.0);
}
