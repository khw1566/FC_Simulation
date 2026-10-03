import os
import json
import time
import requests

class DetailedRoadCollector:
    """
    OpenStreetMap Overpass API를 통해
    간몬 해협 일대의 일반도로(1차선/2차선 주거도로, 이면도로, 비포장도로, 보행자 전용 도로/인도, 산책로, 계단 등)를
    그리드 분할 방식으로 전수 수집하는 수집기
    """
    OVERPASS_URLS = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter"
    ]

    def __init__(self, config_path):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)
        self.bbox = self.config["bbox"]

    def fetch_detailed_roads(self, output_dir, force_refresh=False):
        os.makedirs(output_dir, exist_ok=True)
        output_file = os.path.join(output_dir, f"{self.config['region_name']}_detailed_roads.json")

        if not force_refresh and os.path.exists(output_file) and os.path.getsize(output_file) > 1000000:
            print(f"[DetailedRoadCollector] Existing dataset found: {output_file}")
            return output_file

        # 간몬 해협 핵심 도심 및 주거/산림 생활권 중심 영역 (0.04도 스텝으로 2x3 분할)
        # BBox: 남 33.92 ~ 북 34.00, 서 130.90 ~ 동 131.02
        lat_step = 0.04
        lon_step = 0.04

        lats = []
        cur_lat = 33.92
        while cur_lat < 33.999:
            lats.append((round(cur_lat, 4), round(cur_lat + lat_step, 4)))
            cur_lat += lat_step

        lons = []
        cur_lon = 130.90
        while cur_lon < 131.019:
            lons.append((round(cur_lon, 4), round(cur_lon + lon_step, 4)))
            cur_lon += lon_step

        print(f"[DetailedRoadCollector] Fetching detailed roads across {len(lats)}x{len(lons)} cells...")
        all_elements = []
        seen_ids = set()

        headers = {
            "User-Agent": "KanmonRoadsCollector/2.0 (Terrain Project)"
        }

        # 대상 도로 분류 태그
        highway_filter = "residential|unclassified|living_street|service|track|footway|pedestrian|path|steps|cycleway"

        for i, (s_lat, n_lat) in enumerate(lats):
            for j, (w_lon, e_lon) in enumerate(lons):
                cell_idx = i * len(lons) + j + 1
                total_cells = len(lats) * len(lons)
                print(f"[DetailedRoadCollector] [{cell_idx}/{total_cells}] Fetching cell: Lat {s_lat}~{n_lat}, Lon {w_lon}~{e_lon}...")

                query = f"""[out:json][timeout:45];
(
  way["highway"~"{highway_filter}"]({s_lat},{w_lon},{n_lat},{e_lon});
);
out body;
>;
out skel qt;
"""
                success = False
                for ep in self.OVERPASS_URLS:
                    try:
                        resp = requests.post(ep, data={"data": query}, headers=headers, timeout=50)
                        if resp.status_code == 200:
                            data = resp.json()
                            elems = data.get("elements", [])
                            added_ways = 0
                            for el in elems:
                                k = (el.get("type"), el.get("id"))
                                if k not in seen_ids:
                                    seen_ids.add(k)
                                    all_elements.append(el)
                                    if el.get("type") == "way":
                                        added_ways += 1
                            print(f"  -> Success ({ep})! Added {added_ways} roads. (Total items: {len(all_elements)})")
                            success = True
                            time.sleep(1.0)
                            break
                        else:
                            print(f"  -> {ep} returned {resp.status_code}")
                    except Exception as err:
                        print(f"  -> {ep} error: {err}")
                    time.sleep(1.0)

                if not success:
                    print(f"  -> Warning: Cell {cell_idx} failed from all endpoints.")

        result = {
            "version": 0.6,
            "elements": all_elements
        }
        with open(output_file, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False)
        print(f"[DetailedRoadCollector] Completed! Exported {len(all_elements)} elements to {output_file}")
        return output_file

if __name__ == "__main__":
    collector = DetailedRoadCollector("config/kanmon_region.json")
    collector.fetch_detailed_roads("data/raw/infrastructure", force_refresh=True)
