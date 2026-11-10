shader_type spatial;
// Пол в клетку: по клеткам видно скорость и расстояние.
uniform vec4 color_a : source_color = vec4(0.36, 0.42, 0.47, 1.0);
uniform vec4 color_b : source_color = vec4(0.31, 0.37, 0.42, 1.0);
uniform float cell = 2.0;
varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 c = floor(wp.xz / cell);
	ALBEDO = mix(color_a.rgb, color_b.rgb, mod(c.x + c.y, 2.0));
	ROUGHNESS = 0.9;
}
