shader_type canvas_item;
// Edge-weighted tint (damage flash, low-health pulse). COLOR comes from the ColorRect.
void fragment() {
	float r = length((UV - 0.5) * vec2(1.6, 1.2));
	COLOR.a *= smoothstep(0.25, 1.0, r) * 0.85 + 0.15;
}
