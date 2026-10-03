import os
import json
import requests

class InfrastructureCollector:
    OVERPASS_URLS = [
        "https://overpass.kumi.systems/api/interpreter",
        "https://overpass-api.de/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter"
    ]

    def __init__(self, config_path):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)

    def fetch_roads_railways_coastline(self, output_dir):
        os.makedirs(output_dir, exist_ok=True)
        bbox = self.config["bbox"]
        output_file = os.path.join(output_dir, f"{self.config['region_name']}_infra.json")

        if os.path.exists(output_file) and os.path.getsize(output_file) > 10000:
            print(f"[InfrastructureCollector] Existing infra data found: {output_file}")
            return output_file

        # 쿼리 경량화: 주요 간선도로(고속도로/국도) 및 철도, 해안선만 타깃
        query = f"""
        [out:json][timeout:90];
        (
          way["natural"="coastline"]({bbox['south']},{bbox['west']},{bbox['north']},{bbox['east']});
          way["highway"~"motorway|trunk|primary"]({bbox['south']},{bbox['west']},{bbox['north']},{bbox['east']});
          way["railway"="rail"]({bbox['south']},{bbox['west']},{bbox['north']},{bbox['east']});
        );
        out body;
        >;
        out skel qt;
        """

        headers = {
            "User-Agent": "KanmonVirtualVR/1.0 (Terrain Data Ingestion)"
        }

        print("[InfrastructureCollector] Fetching coastline, primary roads, and railways from Overpass API...")
        for endpoint in self.OVERPASS_URLS:
            try:
                resp = requests.post(endpoint, data={"data": query}, headers=headers, timeout=90)
                if resp.status_code == 200:
                    with open(output_file, "w", encoding="utf-8") as f:
                        f.write(resp.text)
                    print(f"[InfrastructureCollector] Saved infra data to {output_file} ({os.path.getsize(output_file)} bytes)")
                    return output_file
                else:
                    print(f"[InfrastructureCollector] Endpoint {endpoint} returned {resp.status_code}, trying next...")
            except Exception as e:
                print(f"[InfrastructureCollector] Endpoint error {endpoint}: {e}")

        # 모든 엔드포인트 실패 시 기존 waterways 파일로부터 해안선이라도 추출하는 비상 폴백
        fallback_water = os.path.join(os.path.dirname(output_dir), "waterways", f"{self.config['region_name']}_water.json")
        if os.path.exists(fallback_water):
            print("[InfrastructureCollector] Overpass endpoints busy. Using existing coastline data as fallback.")
            import shutil
            shutil.copy(fallback_water, output_file)
            return output_file

        raise RuntimeError("Failed to download infrastructure from Overpass API.")
