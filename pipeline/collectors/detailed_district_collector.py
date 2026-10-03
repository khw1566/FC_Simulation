import os
import json
import requests

class DetailedDistrictCollector:
    OVERPASS_URLS = [
        "https://overpass-api.de/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter"
    ]

    def __init__(self, config_path):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)

    def fetch_all_subdistricts(self, output_dir):
        os.makedirs(output_dir, exist_ok=True)
        bbox = self.config["bbox"]
        output_file = os.path.join(output_dir, f"{self.config['region_name']}_detailed_subdistricts.json")

        if os.path.exists(output_file) and os.path.getsize(output_file) > 50000:
            print(f"[DetailedDistrictCollector] Existing subdistrict data found: {output_file}")
            return output_file

        # admin_level 7(시/군), 8(구/정), 9, 10(초/정목/동리 町・丁目) 전체 수집
        # 또한 place=suburb, quarter, neighbourhood 및 주요 관광/역사/항만 태그 전량 수집
        query = f"""
        [out:json][timeout:180];
        (
          relation["boundary"="administrative"]["admin_level"~"7|8|9|10"]({bbox['south']},{bbox['west']},{bbox['north']},{bbox['east']});
          way["boundary"="administrative"]["admin_level"~"8|9|10"]({bbox['south']},{bbox['west']},{bbox['north']},{bbox['east']});
          node["place"~"suburb|quarter|neighbourhood|town|village"]({bbox['south']},{bbox['west']},{bbox['north']},{bbox['east']});
          node["historic"]({bbox['south']},{bbox['west']},{bbox['north']},{bbox['east']});
          node["tourism"~"attraction|viewpoint"]({bbox['south']},{bbox['west']},{bbox['north']},{bbox['east']});
        );
        out body;
        >;
        out skel qt;
        """

        print("[DetailedDistrictCollector] Fetching ALL fine-grained administrative subdistricts (level 7~10) from Overpass API...")
        for endpoint in self.OVERPASS_URLS:
            try:
                resp = requests.post(endpoint, data={"data": query}, timeout=180)
                if resp.status_code == 200:
                    with open(output_file, "w", encoding="utf-8") as f:
                        f.write(resp.text)
                    print(f"[DetailedDistrictCollector] Saved detailed subdistricts to {output_file} ({os.path.getsize(output_file)} bytes)")
                    return output_file
                else:
                    print(f"[DetailedDistrictCollector] Endpoint {endpoint} returned {resp.status_code}, retrying...")
            except Exception as e:
                print(f"[DetailedDistrictCollector] Endpoint error {endpoint}: {e}")

        raise RuntimeError("Failed to download detailed subdistricts from Overpass API.")
