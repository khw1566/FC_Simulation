shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform float min_height = -50.0;
uniform float max_height = 650.0;

uniform vec4 sea_bottom_color : source_color = vec4(0.15, 0.22, 0.28, 1.0);
uniform vec4 wet_sand_color : source_color = vec4(0.48, 0.44, 0.35, 1.0);
uniform vec4 dry_sand_color : source_color = vec4(0.76, 0.72, 0.54, 1.0);
uniform vec4 coastal_cliff_color : source_color = vec4(0.30, 0.30, 0.32, 1.0);
uniform vec4 grass_color : source_color = vec4(0.24, 0.38, 0.18, 1.0);
uniform vec4 rock_color : source_color = vec4(0.40, 0.38, 0.35, 1.0);
uniform vec4 snow_color : source_color = vec4(0.85, 0.88, 0.90, 1.0);

// 등고선(Contour Line) 설정
uniform float contour_interval : hint_range(5.0, 100.0) = 25.0; // 25m 간격
uniform float contour_thickness : hint_range(0.5, 5.0) = 1.2;
uniform vec4 contour_color : source_color = vec4(0.12, 0.12, 0.12, 0.7);

// 수계 마스크 (하천, 호수 수면 절차적 매핑)
uniform sampler2D water_mask_texture : filter_linear_mipmap, repeat_disable;
#include "res://shaders/water_mask_filter.gdshaderinc"
#include "res://shaders/water_surface.gdshaderinc"
#include "res://shaders/ecozone_ground.gdshaderinc"
uniform sampler2D coast_height_texture : filter_linear, repeat_disable;
uniform bool has_coast_height = false;
uniform sampler2D railway_tunnel_void_texture : filter_nearest, repeat_disable;
uniform bool has_railway_tunnel_void = false;
uniform bool has_splatmap = false;
uniform sampler2D sea_mask_texture : filter_linear, repeat_disable;
uniform sampler2D lake_mask_texture : filter_linear, repeat_disable;
uniform bool has_sea_mask = false;
uniform bool has_lake_mask = false;
// 바다 수면 평면이 있는 지도에서 수면 관리자가 켠다. 평면 아래 수계 지형은 걷어낸다.
uniform bool has_sea_plane = false;
// 렌더링 전용 수계 거리장(있으면 이진 마스크 대신 경계·커버리지에 사용)
uniform sampler2D water_sdf_texture : filter_linear, repeat_disable;
uniform bool has_water_sdf = false;
uniform float sea_plane_level = 0.0;
// 4채널 지표 피복 스플랫맵 (R: 산림, G: 농경지/논밭, B: 도회지, A: 수계/하천)
uniform sampler2D splatmap_texture : filter_linear, repeat_disable;
uniform float world_size_meters = 28000.0;
// 별도 수면과 정밀 하상이 있는 태화강 구역만 기존 물색 지형을 걷는다.
uniform bool has_river_overlay = false;
uniform sampler2D river_overlay_mask : filter_nearest, repeat_disable;
uniform vec4 river_overlay_rect = vec4(0.0, 0.0, 1.0, 1.0);

// 바다 수면(kanmon_water.gdshader)과 완벽히 동기화된 하천 수면 디자인
uniform vec4 water_albedo : source_color = vec4(0.035, 0.16, 0.25, 1.0);
uniform vec4 shallow_water_color : source_color = vec4(0.10, 0.29, 0.34, 1.0);
uniform float river_wave_speed : hint_range(0.0, 2.0) = 0.35;
uniform float river_wave_scale : hint_range(0.01, 1.0) = 0.08;
uniform float river_wave_strength : hint_range(0.0, 1.0) = 0.07;

// 피복별 정밀 톤 (모노크롬 테마 친화적 자연색)
uniform vec4 forest_tone : source_color = vec4(0.18, 0.32, 0.16, 1.0); // 짙은 녹음 수목
uniform vec4 farmland_tone : source_color = vec4(0.42, 0.46, 0.28, 1.0); // 황록색 경작지/논밭
uniform vec4 urban_tone : source_color = vec4(0.38, 0.40, 0.42, 1.0); // 시멘트/아스팔트 도회지

// 렌더링 스타일 모드 토글 (false: 위성 피복 정밀 텍스처, true: 심플 등고선 모드)
uniform bool simple_contour_mode = false;
uniform vec4 simple_land_color : source_color = vec4(0.82, 0.84, 0.85, 1.0);
uniform vec4 simple_water_color : source_color = vec4(0.20, 0.28, 0.35, 1.0);

varying float v_world_y;
varying vec3 v_world_pos;
varying vec3 v_normal;

void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	v_world_pos = wp.xyz;
	v_world_y = wp.y;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (has_river_overlay) {
		vec2 river_uv = (v_world_pos.xz - river_overlay_rect.xy) / river_overlay_rect.zw;
		if (all(greaterThanEqual(river_uv, vec2(0.0))) && all(lessThanEqual(river_uv, vec2(1.0)))) {
			if (texture(river_overlay_mask, river_uv).r > 0.5) { discard; }
		}
	}
	// 경사도 (0: 완전 평지, 1: 수직 절벽)
	float slope = 1.0 - max(dot(v_normal, vec3(0.0, 1.0, 0.0)), 0.0);
	float rock_factor = smoothstep(0.18, 0.45, slope);
	
	// 전역 지형 UV 좌표 (스플랫맵 및 수계 마스크 공용)
	vec2 world_uv = vec2(
		(v_world_pos.x + world_size_meters * 0.5) / world_size_meters,
		(v_world_pos.z + world_size_meters * 0.5) / world_size_meters
	);

	// 수계 마스크 샘플링 (하천 및 호수 물 표면)
	if (has_railway_tunnel_void && world_uv.x>=0.0 && world_uv.x<=1.0 && world_uv.y>=0.0 && world_uv.y<=1.0) {
		vec4 opening = texture(railway_tunnel_void_texture,world_uv);
		float floor_y = mix(min_height,max_height,(opening.r*65280.0+opening.g*255.0)/65535.0);
		if (opening.b>0.75 && v_world_y>=floor_y && v_world_y<=floor_y+opening.a*255.0) { discard; }
	}
	float water_mask = 0.0;
	if (world_uv.x >= 0.0 && world_uv.x <= 1.0 && world_uv.y >= 0.0 && world_uv.y <= 1.0) {
		water_mask = smooth_water_mask(water_mask_texture, world_uv);
	}
	float water_sdf_m = 1000.0;
	if (has_water_sdf) {
		// 미분(fwidth)이 균일한 제어 흐름에서 계산되도록 유니폼 조건만 둔다.
		water_sdf_m = decode_water_sdf(texture(water_sdf_texture, clamp(world_uv, vec2(0.0), vec2(1.0))).r);
		water_mask = water_sdf_alpha(water_sdf_m, fwidth(water_sdf_m));
	}
	bool in_water_zone = has_water_sdf ? water_sdf_m < WATER_SDF_ZONE_M : water_mask > 0.02;
	// 바다 수면 평면이 덮는 수계(해수면 아래 지형)는 걷어낸다. 평면과 같은 마스크·같은 필터를 써서
	// 해안선은 마스크 경계가 아니라 지형이 해수면과 만나는 선이 되고, 동일 높이 깜빡임과
	// 저해상도 삼각형이 수면 위로 튀어나오는 문제를 함께 막는다. 고도가 있는 내륙 수계는 제거하지 않는다.
	if (has_sea_plane && in_water_zone) {
		float bed_y = has_coast_height ? mix(min_height, max_height, texture(coast_height_texture, world_uv).r) : v_world_y;
		if (min(bed_y, v_world_y) < sea_plane_level + 0.02) { discard; }
	} else if (has_coast_height && has_sea_mask && texture(sea_mask_texture, world_uv).r >= 0.5) {
		float bed_y = mix(min_height, max_height, texture(coast_height_texture, world_uv).r);
		if (bed_y < -0.1) { discard; }
	}

	vec3 col;

	if (simple_contour_mode) {
		// [단순 등고선 심플 모드]
		if (v_world_y < 0.0) {
			col = simple_water_color.rgb;
		} else {
			col = simple_land_color.rgb;
			col = ecozone_blend(col, v_world_pos.xz, length(CAMERA_POSITION_WORLD - v_world_pos));
			if (v_world_y < 15.0) {
				col = mix(col, coastal_cliff_color.rgb, rock_factor * 0.5);
			} else {
				col = mix(col, rock_color.rgb, rock_factor * 0.6);
			}
		}
	} else {
		// [위성 피복 정밀 텍스처 모드 (기본값)]
		// 해수면 아래(Y <= 0.0m)는 3D 수면 메쉬의 투과 배경이 되는 깨끗한 해저 지형으로 렌더링
		if (v_world_y <= 0.0) {
			col = sea_bottom_color.rgb;
		} else if (v_world_y < 0.6) {
			// 해발 0m ~ 0.6m 해안선 직벽/항만 방파제/호안 콘크리트 및 조간대
			float t = clamp(v_world_y / 0.6, 0.0, 1.0);
			col = mix(coastal_cliff_color.rgb, wet_sand_color.rgb, t);
		} else if (v_world_y < 2.5) {
			// 해발 0.6m ~ 2.5m 해안 단구/부두 평탄면/백사장
			float t = clamp((v_world_y - 0.6) / 1.9, 0.0, 1.0);
			col = mix(wet_sand_color.rgb, dry_sand_color.rgb, t);
		} else if (v_world_y < 12.0) {
			// 해안가 완충 초지
			float t = clamp((v_world_y - 2.5) / 9.5, 0.0, 1.0);
			col = mix(dry_sand_color.rgb, grass_color.rgb, t);
		} else if (v_world_y < 250.0) {
			float t = clamp((v_world_y - 12.0) / 238.0, 0.0, 1.0);
			col = mix(grass_color.rgb, rock_color.rgb, t);
		} else {
			float t = clamp((v_world_y - 250.0) / 500.0, 0.0, 1.0);
			col = mix(rock_color.rgb, snow_color.rgb, t);
		}

		// 4채널 스플랫맵 샘플링 및 육상 바이옴 믹스
		if (has_splatmap && world_uv.x >= 0.0 && world_uv.x <= 1.0 && world_uv.y >= 0.0 && world_uv.y <= 1.0 && v_world_y >= 0.6) {
			vec4 splat = texture(splatmap_texture, world_uv);
			// 산림/산악 수목 믹스 (R)
			if (splat.r > 0.05) {
				col = mix(col, forest_tone.rgb, splat.r * 0.75);
			}
			// 농경지/논밭 믹스 (G)
			if (splat.g > 0.05) {
				col = mix(col, farmland_tone.rgb, splat.g * 0.85);
			}
			// 도회지/아스팔트 믹스 (B): 강/하천/바다 수계 마스크 영역(water_mask > 0.05)에서는 건물 텍스처 노출 엄격 차단
			if (splat.b > 0.05 && water_mask < 0.05) {
				col = mix(col, urban_tone.rgb, splat.b * 0.80);
			}
		}

		// 태화강 둔치 생태 구역 바닥(잔디·억새·갈대 등). 연결되지 않은 지도에서는 has_ecozone=false로 무시된다.
		col = ecozone_blend(col, v_world_pos.xz, length(CAMERA_POSITION_WORLD - v_world_pos));

		// 해안가 절벽 및 일반 급경사 암벽 믹스
		if (v_world_y < 15.0) {
			col = mix(col, coastal_cliff_color.rgb, rock_factor);
		} else {
			col = mix(col, rock_color.rgb, rock_factor);
		}
	}

	// 등고선 (해수면 위인 v_world_y > 0.0 이상에서 출력)
	if (v_world_y > 0.0) {
		float dist_to_line = abs(fract(v_world_y / contour_interval - 0.5) - 0.5) * contour_interval;
		float line_width = fwidth(v_world_y) * contour_thickness + 0.3;
		float contour_alpha = 1.0 - smoothstep(0.0, line_width, dist_to_line);

		float major_dist = abs(fract(v_world_y / (contour_interval * 4.0) - 0.5) - 0.5) * (contour_interval * 4.0);
		float major_width = fwidth(v_world_y) * (contour_thickness * 1.6) + 0.5;
		float major_alpha = 1.0 - smoothstep(0.0, major_width, major_dist);

		float line_intensity = simple_contour_mode ? 0.9 : 0.5;
		float water_suppression = 1.0 - smoothstep(0.05, 0.40, water_mask);
		float final_contour = clamp(contour_alpha * line_intensity + major_alpha * line_intensity, 0.0, 1.0) * water_suppression;
		col = mix(col, contour_color.rgb, final_contour * contour_color.a);
	}

	// 육지 내륙 하천/호수: 바다 수면 평면과 같은 water_surface 함수로 색·물결·반사를 만든다.
	// 해수면 아래 수계는 위에서 걷어냈으므로 여기서는 해수면 위 수계만 칠해진다.
	vec3 river_normal = v_normal;
	vec2 mask_footprint = fwidth(world_uv) * vec2(textureSize(water_mask_texture, 0));
	float distant_water = smoothstep(0.75, 2.0, max(mask_footprint.x, mask_footprint.y));
	float water_coverage = has_water_sdf ? water_mask : mix(smoothstep(0.15, 0.55, water_mask), water_mask, distant_water);
	float shading_coverage = has_water_sdf ? water_sdf_shading_coverage(water_sdf_m) : water_mask;
	if (!has_sea_plane && has_sea_mask) {
		water_coverage *= 1.0 - step(0.5, texture(sea_mask_texture, world_uv).r);
	}
	bool is_water = water_coverage > 0.001;
	float view_distance = length(CAMERA_POSITION_WORLD - v_world_pos);

	if (is_water) {
		vec3 river_col = water_surface_color(shading_coverage, 0.0, v_world_pos.xz, TIME);
		float lake = has_lake_mask ? texture(lake_mask_texture, world_uv).r : 0.0;
		river_col = mix(river_col, vec3(0.09, 0.22, 0.23), lake * 0.7);
		col = mix(col, river_col, water_coverage);
		river_normal = normalize(mix(v_normal, water_surface_normal(v_world_pos.xz, TIME, view_distance), water_coverage));
	}

	ALBEDO = col;
	NORMAL = normalize((VIEW_MATRIX * vec4(river_normal, 0.0)).xyz);

	if (is_water) {
		float land_roughness = mix(0.75, 0.90, rock_factor);
		ROUGHNESS = mix(land_roughness, water_surface_roughness(shading_coverage, view_distance), water_coverage);
		SPECULAR = mix(0.15, water_surface_specular(view_distance), water_coverage);
	} else {
		ROUGHNESS = (v_world_y < 0.0) ? 0.80 : mix(0.75, 0.90, rock_factor);
		SPECULAR = (v_world_y < 0.0) ? 0.05 : 0.15;
	}
}
