// Thin horizontal scanlines over the Signal lost screen (1 dark px every 3 px).
shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	float line = step(mod(FRAGCOORD.y, 3.0), 1.0);
	COLOR = vec4(0.0, 0.0, 0.0, strength * line);
}
