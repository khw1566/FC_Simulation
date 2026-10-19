// 3차원 바람장(WindFieldService)의 격자 텍스처. 구름 밀도장은 국지 바람 편차만큼 표본 위치를 밀어
// 지역별 바람 차이와 국지 교란(핵폭발 유입·상승·유출)에 구름이 끌려가고 밀려나게 한다.
uniform sampler3D wind_field_prev : filter_linear, repeat_disable;
uniform sampler3D wind_field_curr : filter_linear, repeat_disable;
uniform bool wind_field_active = false;
uniform vec3 wind_field_origin = vec3(0.0);
uniform vec3 wind_field_cell = vec3(1.0);
// 텍스처 차원(너비 x, 높이 z, 깊이 고도)
uniform vec3 wind_field_dims = vec3(1.0);
// 이전→현재 격자 보간(재합성 주기 동안 0→1)
uniform float wind_field_blend = 1.0;
// 바람 편차를 구름 변위로 바꾸는 시간(s)
uniform float wind_warp_seconds = 90.0;
// 층 평균 바람(구름 이동량에 이미 반영된 값)
uniform vec3 wind_layer_low = vec3(0.0);
uniform vec3 wind_layer_high = vec3(0.0);

vec3 wind_field_at(vec3 p) {
	vec3 g = (p - wind_field_origin) / wind_field_cell;
	vec3 uvw = (vec3(g.x, g.z, g.y) + 0.5) / wind_field_dims;
	return mix(textureLod(wind_field_prev, uvw, 0.0).xyz, textureLod(wind_field_curr, uvw, 0.0).xyz, wind_field_blend);
}

// 구름 표본 위치: 층 평균과 다른 국지 바람만큼 바람 아래쪽에서 온 구름을 읽는다.
// 연직 변위는 상승·하강 기류가 구름 높이를 들고 누르는 정도로 약하게 반영한다.
vec3 cloud_warp(vec3 p) {
	if (!wind_field_active) { return p; }
	float k = clamp((p.y - 1800.0) / 7200.0, 0.0, 1.0);
	vec3 dev = wind_field_at(p) - mix(wind_layer_low, wind_layer_high, k);
	dev = clamp(dev, vec3(-60.0), vec3(60.0));
	return p - vec3(dev.x, dev.y * 0.25, dev.z) * wind_warp_seconds;
}
