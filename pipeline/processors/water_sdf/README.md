# 수계 렌더링 거리장
울산 80km 수계 마스크는 화소당 약 14m라 폭 6~25m 하천이 픽셀화되고 끊긴다. 이진 마스크는 도로·건물 계산이 그대로 쓰므로 두고, 셰이더 전용 `hydro/water_sdf.png`를 따로 만든다.
## 실행
```powershell
& 'C:\Users\work\AppData\Local\Programs\Python\Python312\python.exe' pipeline/processors/water_sdf/build_water_sdf.py --dry-run
& 'C:\Users\work\AppData\Local\Programs\Python\Python312\python.exe' pipeline/processors/water_sdf/build_water_sdf.py
```
- `--dry-run`: 통계와 `results/261010_WaterSdfPreview.jpg`(왼쪽 기존 마스크, 오른쪽 거리장)만 만든다.
- 수계 마스크나 하천 벡터가 바뀌면(예: hydro_leveling 재적용) 다시 실행한다. 생성 후 에셋 색인을 갱신한다.
## 처리
- 하천·호수: `river.geojson`, `lake.geojson`을 4배 해상도 타일로 그려 부호 거리를 구하고 지도 격자로 평균한다. 선형 수로는 최소 폭 16m.
- 바다: `sea_mask.png` 부호 거리를 1화소 가우시안으로 다듬는다. 실제 해안선은 지형이 해수면과 만나는 선이다.
- 수면 보정이 지운 비탈·급류: 현재 `water_mask.png`를 2화소 넓힌 영역 밖은 수면으로 살리지 않는다.
- 인코딩: 8bit, 128 기준 ±40m, 수면 안쪽 음수. 해석은 `godot_project/shaders/water_surface.gdshaderinc`.
## 결과(261010)
- 내륙 수면 4방향 연결 조각: 30,206개에서 1,761개, 내륙 수면 화소 8% 증가.
