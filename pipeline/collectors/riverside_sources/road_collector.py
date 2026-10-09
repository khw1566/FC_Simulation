"""Overpass에서 도로 중심선을 수집한다. 실패 응답은 캐시하지 않는다."""
import json
from pathlib import Path

import requests


class RiversideRoadCollector:
    def __init__(self, root, endpoints):
        self.root = Path(root)
        self.endpoints = endpoints
        self.output = self.root / "data/raw/taehwagang_dunchi/roads_raw.json"

    def collect(self, bbox, refresh=False):
        if self.output.exists() and not refresh:
            return json.loads(self.output.read_text(encoding="utf-8"))
        box = f"{bbox['south']},{bbox['west']},{bbox['north']},{bbox['east']}"
        query = f'''[out:json][timeout:180];(
way["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|service|cycleway|footway|path|pedestrian)(_link)?$"]({box}););out body geom;'''
        self.output.parent.mkdir(parents=True, exist_ok=True)
        for url in self.endpoints:
            try:
                response = requests.post(url, data={"data": query}, timeout=210,
                                         headers={"User-Agent": "FC-Simulation-Riverside/1 (taehwagang dunchi terrain)"})
                response.raise_for_status()
                data = response.json()
                if data.get("remark") or not data.get("elements"):
                    raise ValueError("불완전한 Overpass 응답")
                data["source_endpoint"] = url
                temporary = self.output.with_suffix(".tmp")
                temporary.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
                temporary.replace(self.output)
                print(f"[RiversideRoadCollector] {len(data['elements'])}개 도로 저장", flush=True)
                return data
            except (requests.RequestException, ValueError) as error:
                print(f"[RiversideRoadCollector] {url} 실패: {type(error).__name__}", flush=True)
        raise RuntimeError("도로 API 수집 실패")
