shader_type spatial;
// Пол ресторана: мраморные кольца вокруг центральной колонны.
uniform vec4 color_a : source_color = vec4(0.60, 0.56, 0.49, 1.0);
uniform vec4 color_b : source_color = vec4(0.20, 0.30, 0.34, 1.0);
uniform vec4 color_line : source_color = vec4(0.72, 0.58, 0.30, 1.0);
varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float r = length(wp.xz);
	float a = atan(wp.z, wp.x);
	float ring = floor(r / 1.4);
	float seg = floor((a + 3.14159) / 6.28318 * (8.0 + ring * 6.0));
	float pick = mod(ring + seg, 2.0);
	vec3 c = mix(color_a.rgb, color_b.rgb, pick * 0.35 + step(8.4, r) * 0.65);
	float edge = 1.0 - smoothstep(0.0, 0.03, 0.5 - abs(fract(r / 1.4) - 0.5));
	c = mix(c, color_line.rgb, edge);
	ALBEDO = c;
	ROUGHNESS = 0.5;
}
