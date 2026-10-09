"""생태 구역 분류용 OSM 식생·공원 다각형을 Overpass에서 받아 캐시한다."""
import json
import urllib.parse
import urllib.request
from pathlib import Path

QUERY = """[out:json][timeout:90];
(
 way["natural"~"^(wood|scrub|grassland|wetland)$"]({b});
 relation["natural"~"^(wood|scrub|grassland|wetland)$"]({b});
 way["landuse"~"^(forest|grass|meadow)$"]({b});
 relation["landuse"~"^(forest|grass|meadow)$"]({b});
 way["leisure"~"^(park|garden|pitch)$"]({b});
 relation["leisure"~"^(park|garden)$"]({b});
);
out geom;"""


class EcozoneLandcoverCollector:
    def __init__(self, cache_path, endpoints):
        self.cache_path = Path(cache_path)
        self.endpoints = endpoints

    def collect(self, bbox, refresh=False):
        if self.cache_path.exists() and not refresh:
            return json.loads(self.cache_path.read_text(encoding="utf-8"))
        box = f"{bbox['south']},{bbox['west']},{bbox['north']},{bbox['east']}"
        body = urllib.parse.urlencode({"data": QUERY.format(b=box)}).encode()
        errors = []
        for endpoint in self.endpoints:
            try:
                request = urllib.request.Request(endpoint, data=body, headers={"User-Agent": "fc-simulation-ecozones"})
                data = json.loads(urllib.request.urlopen(request, timeout=120).read())
            except Exception as error:  # 다음 엔드포인트로 대체
                errors.append(f"{endpoint}: {error}")
                continue
            data["source_endpoint"] = endpoint
            self.cache_path.parent.mkdir(parents=True, exist_ok=True)
            temporary = self.cache_path.with_suffix(".tmp")
            temporary.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
            temporary.replace(self.cache_path)
            return data
        raise RuntimeError("Overpass 수집 실패: " + "; ".join(errors))
