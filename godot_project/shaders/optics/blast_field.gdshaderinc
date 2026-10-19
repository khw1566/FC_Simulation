// 핵폭발과 기존 구름층의 상호작용: 기둥·갓이 뚫은 소산 구멍, 충격파 압축 증발과 감압 응결,
// 섬광·잔열 조명, 버섯구름 앞·뒤 구름 패스 분할 거리. 구름 렌더링·지면 그림자·광선 패스가 함께 쓴다.
uniform int blast_count = 0;
// xyz 폭심 지면점, w 충격파 반경(m)
uniform vec4 blast_a[4];
// xyz 갓 중심, w 갓 반경(m)
uniform vec4 blast_b[4];
// 충격파가 지나간 뒤 증발한 구름이 다시 차는 시간(s)
const float BLAST_CLOUD_RECOVERY = 150.0;
// x 섬광 밝기, y 섬광 조명 반경(m), z 잔열 발광 세기, w 전면 과압비
uniform vec4 blast_c[4];
// x 기둥 반경(예비), y 갓 반높이, z 소산 반경, w 충격파 두께(m)
uniform vec4 blast_d[4];
// rgb 잔열 발광색, w 폭발점 높이(월드 y)
uniform vec4 blast_e[4];
// x 먼지 파도 반경(없으면 0), y 먼지 파도 높이, z 기둥 상단 월드 높이
uniform vec4 blast_f[4];

// 수직 원기둥(xz 중심, 반경, y 범위) 진입 거리. 안쪽이면 0, 맞지 않으면 큰 값.
float blast_cylinder_entry(vec3 ro, vec3 rd, vec2 center, float radius, float y0, float y1) {
	if (radius <= 1.0 || y1 <= y0) { return 1.0e9; }
	vec2 oc = ro.xz - center;
	float a = dot(rd.xz, rd.xz);
	float c = dot(oc, oc) - radius * radius;
	float t_in = 0.0;
	float t_out = 1.0e9;
	if (a > 0.0000001) {
		float b = dot(oc, rd.xz);
		float disc = b * b - a * c;
		if (disc <= 0.0) { return 1.0e9; }
		float s = sqrt(disc);
		t_in = (-b - s) / a;
		t_out = (-b + s) / a;
	} else if (c > 0.0) {
		return 1.0e9;
	}
	// y 범위 구간과 교차
	if (abs(rd.y) > 0.0000001) {
		float ta = (y0 - ro.y) / rd.y;
		float tb = (y1 - ro.y) / rd.y;
		t_in = max(t_in, min(ta, tb));
		t_out = min(t_out, max(ta, tb));
	} else if (ro.y < y0 || ro.y > y1) {
		return 1.0e9;
	}
	if (t_out <= max(t_in, 0.0)) { return 1.0e9; }
	return max(t_in, 0.0);
}

// 지면 폭심에서 갓 중심으로 기운 기둥 축까지의 수평 거리
float blast_axis_distance(vec3 p, int i) {
	float k = clamp((p.y - blast_a[i].y) / max(blast_b[i].y - blast_a[i].y, 1.0), 0.0, 1.0);
	return length(p.xz - mix(blast_a[i].xz, blast_b[i].xz, k * k));
}

// 폭발점에서 dist 떨어진 지점을 충격파가 지날 때의 세기(0~1).
// 그 지점의 과압을 현재 전면 과압에서 거리 비로 근사하고, 제곱근을 써서 약한 원거리 전면도 남긴다.
float blast_shock_strength(float dist, int i) {
	float th = max(blast_d[i].w, 1.0);
	float ov = blast_c[i].w * pow(max(blast_a[i].w, 1.0) / max(dist, th), 1.5);
	return clamp(sqrt(max(ov, 0.0)) * 3.0, 0.0, 1.0);
}

// 충격파 전면이 막 지나는 구름의 응결 테(0~1): 하얗게 빛나는 고리로 보인다.
float blast_condensation(vec3 p) {
	float c = 0.0;
	for (int i = 0; i < 4; i++) {
		if (i >= blast_count) { break; }
		vec3 burst = vec3(blast_a[i].x, blast_e[i].w, blast_a[i].z);
		float th = max(blast_d[i].w, 1.0);
		float dist_b = distance(p, burst);
		float dr = dist_b - blast_a[i].w;
		// 전면 바로 뒤(감압 꼬리)에서 가장 짙다.
		float x = (dr + th) / (1.5 * th);
		c = max(c, blast_shock_strength(dist_b, i) * exp(-x * x));
	}
	return c;
}

float blast_density_scale(vec3 p) {
	float s = 1.0;
	for (int i = 0; i < 4; i++) {
		if (i >= blast_count) { break; }
		// 1. 고온 상승 기둥과 갓이 기존 구름을 증발·밀어내 구멍을 남긴다.
		float clear_r = blast_d[i].z;
		float column = 1.0 - smoothstep(clear_r * 0.65, clear_r * 1.1, blast_axis_distance(p, i));
		column *= 1.0 - smoothstep(blast_b[i].y, blast_b[i].y + blast_d[i].y, p.y);
		vec3 q = p - blast_b[i].xyz;
		float e = length(vec2(length(q.xz) / max(blast_b[i].w, 1.0), q.y / max(blast_d[i].y, 1.0)));
		float cap = 1.0 - smoothstep(0.8, 1.15, e);
		s *= 1.0 - max(column, cap);
		// 2. 충격파: 전면이 지나는 순간 단열 팽창 꼬리에서 구름이 응결해 짙고 하얗게 부풀었다가,
		//    압축 가열로 증발해 사라지고 수 분에 걸쳐 다시 찬다. 과압의 제곱근을 써서 수십 km 밖까지 보인다.
		vec3 burst = vec3(blast_a[i].x, blast_e[i].w, blast_a[i].z);
		float th = max(blast_d[i].w, 1.0);
		float radius = max(blast_a[i].w, 1.0);
		float dist_b = distance(p, burst);
		float dr = dist_b - radius;
		float k = blast_shock_strength(dist_b, i);
		float front = exp(-(dr * dr) / (th * th));
		float behind = max(-dr, 0.0);
		float vanish = (1.0 - exp(-behind / (2.0 * th))) * exp(-behind / (340.0 * BLAST_CLOUD_RECOVERY));
		s *= 1.0 + 2.5 * k * front;
		// 구름층은 광학적으로 매우 두꺼워 밀도를 조금 줄여서는 그대로 불투명하다. 제곱으로 깎아 실제로 뚫리게 한다.
		float evaporate = clamp(k * vanish, 0.0, 0.97);
		s *= (1.0 - evaporate) * (1.0 - evaporate);
	}
	return s;
}

// 섬광(백색)과 갓 속 잔열(적색 계열)이 구름에 비추는 빛
vec3 blast_light(vec3 p) {
	vec3 sum = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		if (i >= blast_count) { break; }
		vec3 d = p - blast_b[i].xyz;
		float dd = dot(d, d);
		float lr = blast_c[i].y * blast_c[i].y;
		sum += vec3(1.0, 0.97, 0.92) * blast_c[i].x * lr / (lr + dd);
		float gr = max(blast_b[i].w * 2.5, 500.0);
		gr *= gr;
		sum += blast_e[i].rgb * blast_c[i].z * gr / (gr + dd);
	}
	return sum;
}

// 버섯구름 경계(갓 타원체, 기둥·먼지 파도 원기둥)에 광선이 처음 들어가는 거리.
// 구름층은 이 거리에서 앞·뒤 패스로 나뉘어 버섯구름 볼륨을 사이에 두고 그려진다.
// 경계는 실제 형상보다 약간 크게 잡아, 버섯구름 앞에 있는 구름이 뒤쪽으로 잘못 분류되는 범위를 줄인다.
float blast_split_distance(vec3 ro, vec3 rd) {
	float best = 1.0e9;
	for (int i = 0; i < 4; i++) {
		if (i >= blast_count) { break; }
		vec3 radii = vec3(blast_b[i].w * 1.25, blast_d[i].y * 1.3, blast_b[i].w * 1.25);
		if (radii.x > 1.0) {
			vec3 o = (ro - blast_b[i].xyz) / radii;
			vec3 d = rd / radii;
			float a = dot(d, d);
			float b = dot(o, d);
			float c = dot(o, o) - 1.0;
			float disc = b * b - a * c;
			if (disc > 0.0) {
				float t = (-b - sqrt(disc)) / a;
				best = min(best, c < 0.0 ? 0.0 : (t > 0.0 ? t : best));
			}
		}
		// 기둥: 지면 폭심과 갓 중심 사이 기운 축을 덮는 수직 원기둥
		float drift = length(blast_b[i].xz - blast_a[i].xz);
		best = min(best, blast_cylinder_entry(ro, rd, mix(blast_a[i].xz, blast_b[i].xz, 0.5), blast_d[i].x * 1.6 + drift * 0.5, blast_a[i].y - 50.0, blast_f[i].z));
		// 지면 먼지 파도
		if (blast_f[i].x > 1.0) {
			best = min(best, blast_cylinder_entry(ro, rd, blast_a[i].xz, blast_f[i].x * 1.1, blast_a[i].y - blast_f[i].y * 0.5, blast_a[i].y + blast_f[i].y * 1.5));
		}
	}
	return best;
}
