import os
import json
import requests

class DistrictCollector:
    OVERPASS_URLS = [
        "https://overpass-api.de/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter"
    ]

    def __init__(self, config_path):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)

    def fetch_boundaries_and_landmarks(self, output_dir):
        os.makedirs(output_dir, exist_ok=True)
        bbox = self.config["bbox"]
        output_file = os.path.join(output_dir, f"{self.config['region_name']}_boundaries.json")

        if os.path.exists(output_file) and os.path.getsize(output_file) > 5000:
            print(f"[DistrictCollector] Existing boundary data found: {output_file}")
            return output_file

        # 시모노세키시, 기타큐슈시(모지구, 고쿠라키타구) 행정구역 및 주요 랜드마크 쿼리
        query = f"""
        [out:json][timeout:120];
        (
          relation["boundary"="administrative"]["admin_level"~"7|8"]({bbox['south']},{bbox['west']},{bbox['north']},{bbox['east']});
          node["historic"]({bbox['south']},{bbox['west']},{bbox['north']},{bbox['east']});
          node["tourism"~"attraction|viewpoint"]({bbox['south']},{bbox['west']},{bbox['north']},{bbox['east']});
          way["bridge"="suspension"]({bbox['south']},{bbox['west']},{bbox['north']},{bbox['east']});
        );
        out body;
        >;
        out skel qt;
        """

        print("[DistrictCollector] Requesting real administrative boundaries & landmarks from Overpass API...")
        for endpoint in self.OVERPASS_URLS:
            try:
                resp = requests.post(endpoint, data={"data": query}, timeout=120)
                if resp.status_code == 200:
                    with open(output_file, "w", encoding="utf-8") as f:
                        f.write(resp.text)
                    print(f"[DistrictCollector] Successfully saved boundary data to {output_file} ({os.path.getsize(output_file)} bytes)")
                    return output_file
                else:
                    print(f"[DistrictCollector] Endpoint {endpoint} returned {resp.status_code}, retrying...")
            except Exception as e:
                print(f"[DistrictCollector] Endpoint error {endpoint}: {e}")

        raise RuntimeError("Failed to download administrative boundaries from Overpass API.")
