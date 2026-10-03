"""태화강 교량 및 울산대교 원본 형상 수집."""
import json
from pathlib import Path
import requests


class TaehwaBridgeCollector:
    def run(self):
        folder = Path(__file__).resolve().parents[2] / "data/raw/ulsan_metro_80km/bridges"
        folder.mkdir(parents=True, exist_ok=True)
        query = '''[out:json][timeout:90];(
nwr["name"~"울산대교|십리대밭교|삼호교|징검다리"](35.45,129.15,35.65,129.50);
nwr["bridge:name"~"울산대교|십리대밭교|삼호교"](35.45,129.15,35.65,129.50);
way["bridge"](35.49,129.36,35.54,129.43);
way["ford"](35.53,129.20,35.60,129.35);
way["bridge"](35.535,129.20,35.59,129.40);
way["ford"="stepping_stones"](35.53,129.20,35.60,129.35);
);out body geom;'''
        for endpoint in ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]:
            try:
                response = requests.post(endpoint, data={"data": query}, headers={"User-Agent": "UlsanTerrainProject/1.0 bridge-model-preparation"}, timeout=110)
                response.raise_for_status()
                data = response.json()
                if data.get("remark") or not data.get("elements"):
                    raise ValueError("불완전한 교량 응답")
                data["source_endpoint"] = endpoint
                (folder / "bridges_osm.json").write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
                for e in data["elements"]:
                    tags = e.get("tags", {})
                    if any(n in tags.get("bridge:name", "") for n in ["울산대교", "삼호교", "십리대밭교"]) or tags.get("ford"):
                        g = e.get("geometry", [])
                        print(json.dumps({"id": e["id"], "tags": tags, "ends": [g[0], g[-1]] if g else e.get("bounds", {})}, ensure_ascii=True), flush=True)
                return
            except (requests.RequestException, ValueError) as error:
                print(type(error).__name__, flush=True)
        raise RuntimeError("교량 API 수집 실패")


if __name__ == "__main__":
    TaehwaBridgeCollector().run()
