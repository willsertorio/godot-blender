// Full-screen blur of the 3D view, in two passes: two ColorRects that cover the screen, in a CanvasLayer BELOW
// the HUD so the HUD stays sharp, the first with `dir` (1, 0), then a BackBufferCopy (so that the second reads what
// the first drew), then the second with `dir` (0, 1). V2Hud builds the three (`_build_blur`).
// Used on: hit taken (short pulse) and Signal lost (constant, strong).
//
// Each pass takes 17 samples of the screen along its direction, weighted as a Gaussian. (The first version read a
// mip level of the screen texture, `textureLod` with `filter_linear_mipmap`. In the browser build the screen
// texture has no usable mip chain: every lookup came back black, and the view went dark at each hit.)
// `amount` keeps its meaning: the mip level the blur looks like (2.5 ~ hit taken, 4.5 ~ Signal lost). Measured
// against that version: a mip level L looked like a Gaussian of sigma 0.74 * 2^L pixels.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 6.0) = 2.5;
uniform vec2 dir = vec2(1.0, 0.0);
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.0); // optional color wash, alpha = strength (second pass)

void fragment() {
	float sigma = 0.74 * exp2(amount) * step(0.01, amount);
	vec2 px = SCREEN_PIXEL_SIZE * dir * sigma * 0.3125;        // eight samples a side reach 2.5 sigma
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float w = 1.0;
	for (int i = 1; i <= 8; i++) {
		float x = float(i) * 0.3125;
		float wt = exp(-0.5 * x * x);
		c += (texture(screen_tex, SCREEN_UV + px * float(i)).rgb + texture(screen_tex, SCREEN_UV - px * float(i)).rgb) * wt;
		w += 2.0 * wt;
	}
	c /= w;
	c = mix(c, tint.rgb, tint.a);
	COLOR = vec4(c, 1.0);
}
