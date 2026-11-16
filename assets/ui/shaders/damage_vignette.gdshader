// Orange damage vignette, stronger on the side the hit came from.
// Put on a full-screen ColorRect above the blur, below the HUD panels.
shader_type canvas_item;

uniform vec4 tint : source_color = vec4(1.0, 0.35, 0.04, 0.4);
uniform float intensity : hint_range(0.0, 1.0) = 0.0; // animate 1 -> 0 over ~0.6 s on each hit
uniform vec2 hit_dir = vec2(-1.0, -0.3); // screen-space direction toward the attacker (x right, y down)

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float edge = smoothstep(0.55, 1.2, length(p * vec2(1.0, 1.15)));
	float side = max(dot(normalize(p + vec2(0.0001)), normalize(hit_dir)), 0.0);
	float a = (edge * 0.7 + edge * side * 0.9) * intensity;
	COLOR = vec4(tint.rgb, clamp(tint.a * a * 1.6, 0.0, 1.0));
}
