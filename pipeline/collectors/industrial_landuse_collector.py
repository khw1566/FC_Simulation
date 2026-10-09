"""울산 80km 지도 범위의 OSM 산업 용지(landuse=industrial) 경계를 수집한다."""
import json
import sys
import time
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[2]
OVERPASS_URLS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
]


class IndustrialLanduseCollector:
    def __init__(self, map_id="ulsan_metro_80km"):
        self.map_id = map_id
        meta_path = ROOT / f"godot_project/assets/maps/{map_id}/map_meta.json"
        self.bbox = json.loads(meta_path.read_text(encoding="utf-8-sig"))["bbox"]
        self.output = ROOT / f"data/raw/{map_id}/industrial/landuse_industrial.json"

    TILES = 4  # 넓은 범위를 한 번에 요청하면 서버 시간 초과가 나므로 격자로 나눈다.

    def tiles(self):
        b = self.bbox
        lat_step = (b["north"] - b["south"]) / self.TILES
        lon_step = (b["east"] - b["west"]) / self.TILES
        for row in range(self.TILES):
            for col in range(self.TILES):
                yield (b["south"] + lat_step * row, b["west"] + lon_step * col,
                       b["south"] + lat_step * (row + 1), b["west"] + lon_step * (col + 1))

    def query(self, tile):
        area = "(%.6f,%.6f,%.6f,%.6f)" % tile
        return f"""
        [out:json][timeout:180];
        (
          way["landuse"="industrial"]{area};
          relation["landuse"="industrial"]{area};
          way["landuse"="port"]{area};
          relation["landuse"="port"]{area};
        );
        out tags geom;
        """

    def run(self, refresh=False):
        if self.output.exists() and not refresh:
            print("기존 수집 자료 사용:", self.output.relative_to(ROOT))
            return self.output
        self.output.parent.mkdir(parents=True, exist_ok=True)
        elements = {}
        for tile in self.tiles():
            for element in self.fetch(tile):
                elements[(element["type"], element["id"])] = element
            time.sleep(2)
        data = {"elements": list(elements.values()),
                "collected": {"bbox": self.bbox, "tiles": self.TILES, "unix_time": int(time.time())}}
        temp = self.output.with_suffix(".tmp")
        temp.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        temp.replace(self.output)
        print("산업 용지", len(elements), "건 저장:", self.output.relative_to(ROOT))
        return self.output

    def fetch(self, tile):
        last_error = None
        for endpoint in OVERPASS_URLS:
            for _ in range(2):
                try:
                    response = requests.post(endpoint, data={"data": self.query(tile)}, timeout=240)
                    if response.status_code == 200:
                        return response.json().get("elements", [])
                    last_error = f"{endpoint} HTTP {response.status_code}"
                except (requests.RequestException, ValueError) as error:
                    last_error = f"{endpoint} {error}"
                time.sleep(5)
        raise RuntimeError("Overpass 수집 실패: " + str(last_error))


if __name__ == "__main__":
    IndustrialLanduseCollector().run(refresh="--refresh" in sys.argv)
