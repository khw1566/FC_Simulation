shader_type canvas_item;
// 완성된 화면 위에 충격파 굴절 고리, 화구 눈부심, 섬광 백화(whiteout)를 합성한다.
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform mat3 cam_basis = mat3(1.0);
uniform vec3 cam_origin = vec3(0.0);
uniform float tan_half_fov = 0.6;
uniform float aspect = 1.7777;
uniform int shock_count = 0;
// xyz 중심, w 반경(m)
uniform vec4 shock_sphere[4];
// x 굴절 세기(UV), y 두께(m), z 지면 높이, w 밝기 테 세기
uniform vec4 shock_params[4];
uniform int glare_count = 0;
// xy 화면 UV, z 세기, w 크기(UV)
uniform vec4 glare[4];
uniform vec4 glare_tint[4];
uniform float flash_amount = 0.0;
uniform vec3 flash_tint = vec3(1.0);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 ndc = uv * 2.0 - 1.0;
	vec3 dir = normalize(cam_basis * vec3(ndc.x * tan_half_fov * aspect, -ndc.y * tan_half_fov, -1.0));
	mat3 to_view = transpose(cam_basis);
	vec2 offset = vec2(0.0);
	float rim = 0.0;
	for (int i = 0; i < 4; i++) {
		if (i >= shock_count) { break; }
		vec3 oc = shock_sphere[i].xyz - cam_origin;
		float radius = shock_sphere[i].w;
		float b = dot(oc, dir);
		float l2 = dot(oc, oc);
		// 껍질 바깥에서 볼 때만 접선 방향 굴절이 생긴다.
		if (b <= 0.0 || l2 < radius * radius) { continue; }
		vec3 closest = cam_origin + dir * b;
		if (closest.y < shock_params[i].z) { continue; }
		float dist = sqrt(max(l2 - b * b, 0.0));
		float x = (dist - radius) / max(shock_params[i].y, 1.0);
		float g = x * exp(-x * x);
		vec3 outward = to_view * normalize(closest - shock_sphere[i].xyz);
		offset += vec2(outward.x, -outward.y) * g * shock_params[i].x;
		rim += exp(-x * x * 2.0) * shock_params[i].w;
	}
	vec3 color = textureLod(screen_tex, clamp(uv + offset, vec2(0.0), vec2(1.0)), 0.0).rgb;
	color += vec3(rim);
	for (int i = 0; i < 4; i++) {
		if (i >= glare_count) { break; }
		vec2 d = (uv - glare[i].xy) * vec2(aspect, 1.0);
		float r = length(d);
		float size = max(glare[i].w, 0.0005);
		float halo = exp(-r / size) + 0.25 * exp(-r / (size * 6.0));
		float streak = exp(-abs(d.y) / (size * 0.12)) * exp(-abs(d.x) / (size * 9.0)) * 0.35;
		color += glare_tint[i].rgb * glare[i].z * (halo + streak);
	}
	color = mix(color, flash_tint, clamp(flash_amount, 0.0, 1.0));
	COLOR = vec4(color, 1.0);
}
