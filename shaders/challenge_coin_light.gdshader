shader_type canvas_item;
render_mode unshaded;
uniform sampler2D streak_texture : source_color, filter_linear, repeat_disable;
uniform vec2 sweep_offset = vec2(-199.9, -212.5);
void fragment() {
	vec4 mask = texture(TEXTURE, UV);
	vec2 point = (UV - vec2(0.5)) * vec2(102.2, 237.5) - vec2(sweep_offset.x, -sweep_offset.y);
	float angle = radians(50.0);
	vec2 local = vec2(point.x * cos(angle) - point.y * sin(angle), point.x * sin(angle) + point.y * cos(angle));
	vec2 uv = local / vec2(152.409, 296.64) + vec2(0.5);
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	vec4 streak = texture(streak_texture, clamp(uv, vec2(0.0), vec2(1.0)));
	COLOR = vec4(streak.rgb, mask.a * streak.a * COLOR.a * inside);
}
