# 하천·호수 수면 평탄화 보정
울산 80km 지도에서 수면 질감이 산비탈을 타고 오르는 문제를 고친다. 기존 수계 단계는 해안만 정형하고 하천·호수 마스크를 원 지형 위에 그대로 칠했다.
## 실행
```powershell
& '<python.exe>' pipeline/processors/hydro_leveling/apply.py --dry-run
& '<python.exe>' pipeline/processors/hydro_leveling/apply.py --root <프로젝트 루트>
```
- `--dry-run`: 통계와 `results/261009_HydroLevelingPreview.jpg`(왼쪽 보정 전, 오른쪽 보정 후)만 만든다.
- 적용 전 원본을 `data/archives/hydro_leveling_backup_<시각>/`에 복사한다.
## 처리
- 호수: 성분마다 하위 10% 고도를 수위로 삼아 평탄화한다. 수위보다 4m 이상 높은 화소는 다각형이 비탈로 번진 것으로 보고 수면에서 뺀다.
- 하천: 반경 30m 하곡 바닥을 하도 안에서 매끄럽게 한 수면 아래로 하도를 정지한다. 원 고도가 수면보다 6m 넘게 높은 화소와 수면 경사 8% 초과 계류는 수면에서 뺀다.
- 지형은 낮추기만 한다. 기슭은 30~45m 폭으로 잇고 호수 기슭 절토는 3m 이하로 제한한다.
- 실행 높이맵 `generated/railway/graded_heightmap_16bit.png`와 `hydro/coastal_heightmap_16bit.png`에 같은 보정량을 적용하고, 철도 정지가 바꾼 화소는 철도 값을 유지한다.
- 갱신 파일: 두 높이맵, `river_mask.png`, `lake_mask.png`, `water_mask.png`, `hydro_leveling_report.json`, 지도 `manifest.json`.
## 검증 기준
- 수면 내부(경계 1화소 제외) 지형 경사 15% 초과 비율: 보정 전 5.2%, 보정 후 0.01%.
