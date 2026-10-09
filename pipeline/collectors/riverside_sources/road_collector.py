"""Overpass에서 도로 중심선을 수집한다. 실패 응답은 캐시하지 않는다.

전체 bbox 단일 질의는 공용 서버에서 504로 끝나기 쉬워 `split` x `split` 구획으로 나눠 받고 way id로 합친다.
구획 응답은 `roads_chunks/`에 캐시해 서버 과부하로 중단돼도 재실행 시 이어 받는다.
"""
import json
import time
from pathlib import Path

import requests


class RiversideRoadCollector:
    HIGHWAYS = "motorway|trunk|primary|secondary|tertiary|unclassified|residential|service|cycleway|footway|path|pedestrian"

    def __init__(self, root, endpoints, split=3):
        self.root = Path(root)
        self.endpoints = endpoints
        self.split = split
        self.output = self.root / "data/raw/taehwagang_dunchi/roads_raw.json"
        self.chunks = self.output.parent / "roads_chunks"

    def _query(self, box):
        query = f'[out:json][timeout:180];(way["highway"~"^({self.HIGHWAYS})(_link)?$"]({box}););out body geom;'
        for attempt in range(5):
            for url in self.endpoints:
                try:
                    response = requests.post(url, data={"data": query}, timeout=210,
                                             headers={"User-Agent": "FC-Simulation-Riverside/1 (taehwagang dunchi terrain)"})
                    response.raise_for_status()
                    data = response.json()
                    if data.get("remark"):
                        raise ValueError("불완전한 Overpass 응답")
                    return data, url
                except (requests.RequestException, ValueError) as error:
                    status = getattr(getattr(error, "response", None), "status_code", "")
                    print(f"[RiversideRoadCollector] {url} 실패: {type(error).__name__} {status}", flush=True)
            time.sleep(20 * (attempt + 1))
        raise RuntimeError("도로 API 수집 실패")

    def collect(self, bbox, refresh=False):
        if self.output.exists() and not refresh:
            return json.loads(self.output.read_text(encoding="utf-8"))
        self.output.parent.mkdir(parents=True, exist_ok=True)
        lat_step = (bbox["north"] - bbox["south"]) / self.split
        lon_step = (bbox["east"] - bbox["west"]) / self.split
        ways, endpoints = {}, set()
        for i in range(self.split):
            for j in range(self.split):
                south, west = bbox["south"] + i * lat_step, bbox["west"] + j * lon_step
                box = f"{south},{west},{south + lat_step},{west + lon_step}"
                chunk = self.chunks / f"{i}_{j}.json"
                if chunk.exists() and not refresh:
                    data = json.loads(chunk.read_text(encoding="utf-8"))
                else:
                    data, url = self._query(box)
                    data["source_endpoint"] = url
                    self.chunks.mkdir(parents=True, exist_ok=True)
                    chunk.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
                    time.sleep(3)
                endpoints.add(data.get("source_endpoint", ""))
                for element in data.get("elements", []):
                    ways[element["id"]] = element
        if not ways:
            raise RuntimeError("도로 API 수집 실패: 빈 응답")
        data = {"elements": list(ways.values()), "source_endpoint": sorted(endpoints)}
        temporary = self.output.with_suffix(".tmp")
        temporary.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        temporary.replace(self.output)
        print(f"[RiversideRoadCollector] {len(ways)}개 도로 저장", flush=True)
        return data
