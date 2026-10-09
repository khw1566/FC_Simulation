"""Overpass에서 태화강 수면 다각형과 하천 중심선을 수집한다. 실패 응답은 캐시하지 않는다."""
import json
from pathlib import Path

import requests


class RiversideWaterCollector:
    def __init__(self, root, water_settings):
        self.root = Path(root)
        self.settings = water_settings
        self.output = self.root / "data/raw/taehwagang_dunchi/water_raw.json"

    def collect(self, bbox, refresh=False):
        if self.output.exists() and not refresh:
            return json.loads(self.output.read_text(encoding="utf-8"))
        box = f"{bbox['south'] - .01},{bbox['west'] - .01},{bbox['north'] + .01},{bbox['east'] + .01}"
        query = f'''[out:json][timeout:180];(
way["waterway"~"^(river|stream|canal)$"]({box});
nwr["natural"="water"]({box});
nwr["waterway"="riverbank"]({box}););out body geom;'''
        self.output.parent.mkdir(parents=True, exist_ok=True)
        for url in self.settings["overpass_endpoints"]:
            try:
                response = requests.post(url, data={"data": query}, timeout=210)
                response.raise_for_status()
                data = response.json()
                if data.get("remark") or not data.get("elements"):
                    raise ValueError("불완전한 Overpass 응답")
                data["source_endpoint"] = url
                temporary = self.output.with_suffix(".tmp")
                temporary.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
                temporary.replace(self.output)
                print(f"[RiversideWaterCollector] {len(data['elements'])}개 수계 요소 저장", flush=True)
                return data
            except (requests.RequestException, ValueError) as error:
                print(f"[RiversideWaterCollector] {url} 실패: {type(error).__name__}", flush=True)
        raise RuntimeError("수계 API 수집 실패: 기존 자산 유지")
