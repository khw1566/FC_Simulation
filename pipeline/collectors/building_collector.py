import os
import json
import time
import requests

class BuildingCollector:
    """
    OpenStreetMap Overpass API를 활용하여
    간몬 해협 전체 영역(33.80~34.05, 130.80~131.10)의 건물을
    그리드 분할 쿼리로 안정적으로 전수 수집하는 모듈
    """
    OVERPASS_URLS = [
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter"
    ]

    def __init__(self, config_path):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)
        self.bbox = self.config["bbox"]

    def fetch_buildings(self, output_dir, force_refresh=False):
        os.makedirs(output_dir, exist_ok=True)
        output_file = os.path.join(output_dir, f"{self.config['region_name']}_buildings.json")

        if not force_refresh and os.path.exists(output_file) and os.path.getsize(output_file) > 10000000:
            print(f"[BuildingCollector] Existing full-region building dataset found: {output_file}")
            return output_file

        # BBox 전체 범위: Lat 33.80 ~ 34.05 (0.25도), Lon 130.80 ~ 131.10 (0.30도)
        # 안정적인 API 응답을 위해 5x6 (총 30개 그리드 셀, 셀당 0.05도)로 분할 요청
        lat_step = 0.05
        lon_step = 0.05

        lats = []
        cur_lat = self.bbox["south"]
        while cur_lat < self.bbox["north"] - 0.001:
            lats.append((round(cur_lat, 4), round(min(cur_lat + lat_step, self.bbox["north"]), 4)))
            cur_lat += lat_step

        lons = []
        cur_lon = self.bbox["west"]
        while cur_lon < self.bbox["east"] - 0.001:
            lons.append((round(cur_lon, 4), round(min(cur_lon + lon_step, self.bbox["east"]), 4)))
            cur_lon += lon_step

        print(f"[BuildingCollector] Splitting full region into {len(lats)}x{len(lons)} ({len(lats)*len(lons)} cells)...")

        all_elements = []
        seen_element_keys = set()
        headers = {
            "User-Agent": "KanmonFullRegionVR/2.0 (Terrain Engineering Project)"
        }

        # 기존 파일이 있다면 유효 데이터 보존 병합
        if os.path.exists(output_file):
            try:
                with open(output_file, "r", encoding="utf-8") as f:
                    old_data = json.load(f)
                    for elem in old_data.get("elements", []):
                        k = (elem.get("type"), elem.get("id"))
                        if k not in seen_element_keys:
                            seen_element_keys.add(k)
                            all_elements.append(elem)
                print(f"[BuildingCollector] Preserved {len(all_elements)} existing elements for seeding.")
            except Exception as e:
                print(f"[BuildingCollector] Existing file read warning: {e}")

        total_cells = len(lats) * len(lons)
        cell_idx = 0

        for s_lat, n_lat in lats:
            for w_lon, e_lon in lons:
                cell_idx += 1
                cell_bbox = f"{s_lat},{w_lon},{n_lat},{e_lon}"
                print(f"[{cell_idx}/{total_cells}] Fetching cell [{cell_bbox}]...")

                query = f"""[out:json][timeout:60];
(
  way["building"]({cell_bbox});
);
out body;
>;
out skel qt;
"""
                fetched = False
                for ep in self.OVERPASS_URLS:
                    try:
                        resp = requests.post(ep, data={"data": query}, headers=headers, timeout=50)
                        if resp.status_code == 200:
                            data = resp.json()
                            elems = data.get("elements", [])
                            added_count = 0
                            for el in elems:
                                key = (el.get("type"), el.get("id"))
                                if key not in seen_element_keys:
                                    seen_element_keys.add(key)
                                    all_elements.append(el)
                                    added_count += 1
                            print(f"  -> Success from {ep.split('/')[2]}: +{added_count} elements (Total: {len(all_elements)})")
                            fetched = True
                            time.sleep(0.5)
                            break
                        else:
                            print(f"  -> {ep.split('/')[2]} returned HTTP {resp.status_code}, trying next endpoint...")
                    except Exception as ex:
                        print(f"  -> {ep.split('/')[2]} error: {ex}")
                        time.sleep(0.5)

                if not fetched:
                    print(f"  [!] Cell [{cell_bbox}] failed across all endpoints. Continuing next cell.")

        # 최종 저장
        with open(output_file, "w", encoding="utf-8") as f:
            json.dump({"version": 0.6, "elements": all_elements}, f)

        building_ways = [e for e in all_elements if e.get("type") == "way" and "building" in e.get("tags", {})]
        print("==================================================")
        print(f"[BuildingCollector] Completed! Total elements: {len(all_elements)}")
        print(f"[BuildingCollector] Total unique building footprints: {len(building_ways)}")
        print(f"[BuildingCollector] Saved to: {output_file} ({os.path.getsize(output_file)} bytes)")
        print("==================================================")
        return output_file

if __name__ == "__main__":
    collector = BuildingCollector("config/kanmon_region.json")
    collector.fetch_buildings("data/raw/buildings", force_refresh=True)
