// 원본과 동일한 3D 밀도장을 제한된 표본으로 적분한다. 화면 전체 광선 비용 상한을 유지한다.
uniform bool clouds_active = true;
uniform float extinction = 0.04;
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);

float cloud_transmission(vec3 origin) {
	if (!clouds_active || sun_direction.y <= 0.015) { return 1.0; }
	// 각 활성 층의 중간 높이에서 적분: 높은 적란운 때문에 낮은 층을 건너뛰지 않는다.
	float optical_depth = 0.0;
	for (int i = 0; i < 4; i++) {
		float lo = cu_base;
		float hi = cu_top;
		float coverage = cu_coverage;
		if (i == 1) { lo = st_base; hi = st_top; coverage = st_coverage; }
		if (i == 2) { lo = as_base; hi = as_top; coverage = as_coverage; }
		if (i == 3) { lo = cb_base; hi = cb_top; coverage = cb_coverage; }
		if (coverage <= 0.001 || origin.y >= hi) { continue; }
		lo = max(lo, origin.y);
		float thickness = hi - lo;
		float height = mix(lo, hi, 0.42);
		vec3 p = origin + sun_direction * ((height - origin.y) / sun_direction.y);
		float hfrac;
		vec4 weather = cloud_weather(p, max(80.0, thickness / 4.0));
		float density = density_at(p, weather, 14000.0, false, hfrac);
		// 층이 중복될 때 불투명도가 과도해지지 않도록 제한한다.
		optical_depth += density * min(thickness / sun_direction.y, 4500.0) * extinction * 0.14;
	}
	if (ci_coverage > 0.001 && origin.y < ci_altitude) {
		vec3 p = origin + sun_direction * ((ci_altitude - origin.y) / sun_direction.y);
		float veil = wtex((p.xz + cirrus_offset) / 38000.0);
		optical_depth += smoothstep(1.0 - ci_coverage * 0.62, 1.35 - ci_coverage * 0.62, veil) * 0.28;
	}
	return exp(-min(optical_depth, 12.0));
}
