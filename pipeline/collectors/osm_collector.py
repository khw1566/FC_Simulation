import os
import json
import requests

class OsmCollector:
    OVERPASS_URLS = [
        "https://overpass-api.de/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter"
    ]

    def __init__(self, config_path):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)

    def fetch_waterways(self, output_dir):
        os.makedirs(output_dir, exist_ok=True)
        bbox = self.config["bbox"]
        output_file = os.path.join(output_dir, f"{self.config['region_name']}_water.json")

        if os.path.exists(output_file) and os.path.getsize(output_file) > 1024:
            print(f"[OsmCollector] Existing OSM water file found: {output_file}")
            return output_file

        query = f"""
        [out:json][timeout:90];
        (
          way["natural"="coastline"]({bbox['south']},{bbox['west']},{bbox['north']},{bbox['east']});
          way["waterway"="river"]({bbox['south']},{bbox['west']},{bbox['north']},{bbox['east']});
          way["waterway"="stream"]({bbox['south']},{bbox['west']},{bbox['north']},{bbox['east']});
          relation["natural"="water"]({bbox['south']},{bbox['west']},{bbox['north']},{bbox['east']});
        );
        out body;
        >;
        out skel qt;
        """

        print("[OsmCollector] Requesting coastline and water bodies from Overpass API...")
        for endpoint in self.OVERPASS_URLS:
            try:
                response = requests.post(endpoint, data={"data": query}, timeout=90)
                if response.status_code == 200:
                    with open(output_file, "w", encoding="utf-8") as f:
                        f.write(response.text)
                    print(f"[OsmCollector] Saved water vector data to {output_file}")
                    return output_file
                else:
                    print(f"[OsmCollector] Endpoint {endpoint} returned {response.status_code}, trying fallback...")
            except Exception as e:
                print(f"[OsmCollector] Failed to reach {endpoint}: {e}")

        raise RuntimeError("All Overpass API endpoints failed.")
