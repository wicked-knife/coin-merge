shader_type canvas_item;
render_mode unshaded;

uniform sampler2D streak_texture : source_color, filter_linear, repeat_disable;
uniform vec2 sweep_offset = vec2(-182.417, -119.181);

void fragment() {
	// 复用原版 LaserLight，以黄色槽底的透明度遮罩裁掉外溢光线。
	vec2 point = (UV - vec2(0.5)) * vec2(110.0, 200.0) - sweep_offset;
	float diagonal = 0.70710678;
	vec2 streak_uv = vec2(point.x + point.y, point.y - point.x) * diagonal;
	streak_uv = streak_uv / vec2(152.409, 296.64) + vec2(0.5);
	vec4 streak = texture(streak_texture, clamp(streak_uv, vec2(0.0), vec2(1.0)));
	float inside = step(0.0, streak_uv.x) * step(streak_uv.x, 1.0)
		* step(0.0, streak_uv.y) * step(streak_uv.y, 1.0);
	COLOR = vec4(streak.rgb, streak.a * COLOR.a * inside);
}
