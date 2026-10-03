# 지도 원본 압축 보관

- 실행용 맵은 `godot_project/assets/maps/maps_registry.json`에 등록된 6개만 사용한다.
- 울산 60km 구버전과 시모노세키항 3km, 울산 80km 수집 캐시 및 병합 원본은 ZIP으로 보관한다.
- 압축 전후 모든 원본 파일의 개수·크기·SHA-256을 검증했다. ZIP 파일 자체의 해시는 `manifest.json`에 기록한다.
- 실행용 울산 80km 건물·도로 JSON과 `vector_stream`은 유지한다. 이를 삭제하면 현재 스트리밍 로더가 실행되지 않는다.
- 기존 울산 자료 재수집·80km 재병합·60km 원본을 사용하는 지형 재생성을 실행하기 전에는 필요한 원본을 복원해야 한다. 게임 실행에는 복원이 필요 없다.

```powershell
# 울산 80km 외곽 재수집 캐시만 복원
powershell -File pipeline/indexer/compact_map_sources.ps1 -Restore -SourceName ulsan_80km_collection_cache

# 기존 60km 코어 자료 복원
powershell -File pipeline/indexer/compact_map_sources.ps1 -Restore -SourceName ulsan_metro_60km_source

# 80km 병합 원본 복원
powershell -File pipeline/indexer/compact_map_sources.ps1 -Restore -SourceName ulsan_80km_merged_source
```

- 복원은 기존 폴더를 덮어쓰지 않는다. ZIP 해시를 확인한 뒤 원래 위치로 풀며 맵 선택 목록을 바꾸지 않는다.
- 구버전 분할 캐시는 ZIP 시간 정밀도 차이로 재생성이 필요할 수 있다. 실행용 80km 분할 캐시는 이번 정리에서 변경하지 않았다.
- 이미 존재하는 보관 ZIP은 다시 압축할 때 덮어쓰지 않는다. 원본 재생성 후에는 보관본 버전을 별도로 관리한다.
- 큐슈 항목은 이전처럼 칸몬해협 자산을 공유하는 준비용 맵이다. 별도 큐슈 실측 지형은 아직 수집되지 않았다.
