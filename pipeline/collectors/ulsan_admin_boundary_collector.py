import json
import os

import requests


class UlsanAdminBoundaryCollector:
    DATA_URLS = {
        "sido": "https://raw.githubusercontent.com/DevMinGeonPark/mapcn-kr/main/data/sido.json",
        "sgg": "https://raw.githubusercontent.com/DevMinGeonPark/mapcn-kr/main/data/sgg.json",
        "emd": "https://raw.githubusercontent.com/DevMinGeonPark/mapcn-kr/main/data/emd.json",
        "ri_26": "https://raw.githubusercontent.com/DevMinGeonPark/mapcn-kr/main/data/ri/26.json",
        "ri_31": "https://raw.githubusercontent.com/DevMinGeonPark/mapcn-kr/main/data/ri/31.json",
        "ri_47": "https://raw.githubusercontent.com/DevMinGeonPark/mapcn-kr/main/data/ri/47.json",
        "ri_48": "https://raw.githubusercontent.com/DevMinGeonPark/mapcn-kr/main/data/ri/48.json",
    }

    def __init__(self, output_dir="data/raw/ulsan_metro_60km/boundaries"):
        self.output_dir = output_dir

    def collect(self):
        os.makedirs(self.output_dir, exist_ok=True)
        headers = {"User-Agent": "UlsanMetroTerrain/1.0 (administrative boundary preparation)"}
        for dataset, url in self.DATA_URLS.items():
            output_path = os.path.join(self.output_dir, f"ulsan_{dataset}_20260701.geojson")
            if os.path.exists(output_path) and os.path.getsize(output_path) > 1000:
                print(f"[UlsanAdminBoundaryCollector] Using cached {dataset}: {output_path}")
                continue
            response = requests.get(url, headers=headers, timeout=90)
            response.raise_for_status()
            payload = response.json()
            if not isinstance(payload, dict) or not payload.get("features"):
                raise ValueError(f"Invalid boundary GeoJSON: {url}")
            with open(output_path, "w", encoding="utf-8") as target:
                json.dump(payload, target, ensure_ascii=False)
            print(f"[UlsanAdminBoundaryCollector] Saved {dataset}: {len(payload['features'])} features")
        return self.output_dir


if __name__ == "__main__":
    UlsanAdminBoundaryCollector().collect()
