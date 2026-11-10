shader_type spatial;
// Голова Комбеза: кожа + рисованное 2D-лицо, спроецированное на переднюю часть сферы.
uniform vec4 skin : source_color = vec4(0.96, 0.78, 0.62, 1.0);
uniform sampler2D face : source_color, filter_linear_mipmap, repeat_disable;
uniform float face_size = 0.76;
uniform float face_drop = 0.1;
varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec3 n = normalize(lp);
	vec3 col = skin.rgb;
	if (n.z < -0.15) {
		vec2 uv = vec2(0.5 - n.x / (2.0 * face_size), 0.5 - (n.y + face_drop) / (2.0 * face_size));
		if (uv.x > 0.0 && uv.x < 1.0 && uv.y > 0.0 && uv.y < 1.0) {
			vec4 f = texture(face, uv);
			col = mix(col, f.rgb, f.a);
		}
	}
	ALBEDO = col;
	ROUGHNESS = 0.75;
}
