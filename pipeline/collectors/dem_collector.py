import os
import json
import requests

class DemCollector:
    BASE_URL = "https://portal.opentopography.org/API/globaldem"

    def __init__(self, config_path, api_key_path):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)
        with open(api_key_path, "r", encoding="utf-8") as f:
            self.keys = json.load(f)
        self.api_key = self.keys.get("opentopography_api_key", "").strip()

    def fetch_dem(self, output_dir):
        os.makedirs(output_dir, exist_ok=True)
        bbox = self.config["bbox"]
        dataset = self.config["dem"]["dataset"]
        output_file = os.path.join(output_dir, f"{self.config['region_name']}_{dataset}.tif")

        if os.path.exists(output_file) and os.path.getsize(output_file) > 1024:
            print(f"[DemCollector] Existing DEM file found: {output_file}")
            return output_file

        params = {
            "demtype": dataset,
            "south": bbox["south"],
            "north": bbox["north"],
            "west": bbox["west"],
            "east": bbox["east"],
            "outputFormat": "GTiff",
            "API_Key": self.api_key
        }

        print(f"[DemCollector] Requesting DEM from OpenTopography ({dataset})...")
        print(f"  Bounds: S={bbox['south']}, N={bbox['north']}, W={bbox['west']}, E={bbox['east']}")

        response = requests.get(self.BASE_URL, params=params, stream=True, timeout=120)
        if response.status_code != 200:
            raise RuntimeError(f"OpenTopography API returned error {response.status_code}: {response.text}")

        with open(output_file, "wb") as f:
            for chunk in response.iter_content(chunk_size=65536):
                if chunk:
                    f.write(chunk)

        print(f"[DemCollector] DEM successfully saved to {output_file} ({os.path.getsize(output_file)} bytes)")
        return output_file
