"""기존 Overpass API에서 수계를 새로 수집한다. 실패 응답은 캐시하지 않는다."""
import json
from pathlib import Path
import requests


class HydroRefresh:
    ROOT = Path(__file__).resolve().parents[2]

    def run(self):
        config = json.loads((self.ROOT / "config/ulsan_metro_80km.json").read_text(encoding="utf-8-sig"))
        b = config["bbox"]
        box = f"{b['south']-.03},{b['west']-.03},{b['north']+.03},{b['east']+.03}"
        query = f'''[out:json][timeout:180];(
way["natural"="coastline"]({box});
way["waterway"~"^(river|stream|canal)$"]({box});
nwr["natural"="water"]({box});
nwr["waterway"="riverbank"]({box});
nwr["landuse"="reservoir"]({box}););out body geom;'''
        folder = self.ROOT / "data/raw/ulsan_metro_80km/hydro_refresh"
        folder.mkdir(parents=True, exist_ok=True)
        for url in ("https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"):
            try:
                response = requests.post(url, data={"data": query}, timeout=210)
                response.raise_for_status()
                data = response.json()
                if data.get("remark") or not data.get("elements"):
                    raise ValueError("Incomplete API response")
                data["source_endpoint"] = url
                (folder / "water_raw.json").write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
                print(f"Saved {len(data['elements'])} elements", flush=True)
                return
            except (requests.RequestException, ValueError) as error:
                print(type(error).__name__, flush=True)
        raise RuntimeError("수계 API 수집 실패: 기존 자산 유지")


if __name__ == "__main__":
    HydroRefresh().run()
