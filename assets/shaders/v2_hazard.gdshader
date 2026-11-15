// V2 hazard bands: Blender's material is a diagonal Wave texture in object space cut into black and yellow
// (v2/scripts/build_room.py hazard_material). Same stripes here: 7 cm apart along x + y + z.
// (colours are Blender's linear numbers, handed to the Compatibility renderer as sRGB)
shader_type spatial;

varying vec3 pos;

void vertex() {
	pos = VERTEX;
}

void fragment() {
	float f = 0.5 + 0.5 * sin((pos.x + pos.y - pos.z) * 90.0 - 1.5708);      // (Blender z-up -> y-up: y = -z)
	float w = max(fwidth(f), 0.001);
	float yellow = smoothstep(0.5 - w, 0.5 + w, f);                          // (far away the stripes melt into their mean)
	ALBEDO = pow(mix(vec3(0.02), vec3(0.8, 0.55, 0.02), yellow), vec3(1.0 / 2.2));
	ROUGHNESS = 0.5;
}
