import os
import json
import requests

def fetch_detailed_roads():
    urls = [
        "https://overpass.kumi.systems/api/interpreter",
        "https://overpass-api.de/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter"
    ]
    
    # 간몬 해협 핵심 도심 (모지코, 시모노세키 도심, 주거지, 산악 보행로)
    # south: 33.93, west: 130.91, north: 33.98, east: 130.98
    query = """[out:json][timeout:60];
(
  way["highway"~"residential|living_street|service|unclassified|track|footway|pedestrian|path|steps|cycleway"](33.93,130.91,33.98,130.98);
);
out body;
>;
out skel qt;
"""

    headers = {
        "User-Agent": "KanmonDetailedRoadCollector/1.0 (VR Terrain Project)"
    }

    out_path = "data/raw/infrastructure/kanmon_straits_detailed_roads.json"
    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    print("[DetailedRoadCollector] Requesting detailed roads from Overpass API...")
    for endpoint in urls:
        try:
            print(f"Trying endpoint: {endpoint}...")
            resp = requests.post(endpoint, data={"data": query}, headers=headers, timeout=60)
            if resp.status_code == 200:
                with open(out_path, "w", encoding="utf-8") as f:
                    f.write(resp.text)
                print(f"Successfully fetched and saved to {out_path} ({os.path.getsize(out_path)} bytes)")
                return out_path
            else:
                print(f"Endpoint returned HTTP {resp.status_code}")
        except Exception as e:
            print(f"Endpoint error: {e}")

    print("All endpoints failed or timed out.")
    return None

if __name__ == "__main__":
    fetch_detailed_roads()
