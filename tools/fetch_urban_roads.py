import os
import json
import requests

def fetch_urban_roads():
    # 모지코 레트로, 시모노세키 항만/카라토 시장 일대 중심 실측 영역
    # south: 33.94, west: 130.92, north: 33.98, east: 130.97
    query = """[out:json][timeout:35];
(
  way["highway"="residential"](33.94,130.92,33.98,130.97);
  way["highway"="service"](33.94,130.92,33.98,130.97);
  way["highway"="footway"](33.94,130.92,33.98,130.97);
  way["highway"="pedestrian"](33.94,130.92,33.98,130.97);
  way["highway"="track"](33.94,130.92,33.98,130.97);
  way["highway"="path"](33.94,130.92,33.98,130.97);
  way["highway"="steps"](33.94,130.92,33.98,130.97);
);
out body;
>;
out skel qt;
"""
    headers = {"User-Agent": "KanmonCoreUrbanRoads/1.0"}
    endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter"
    ]
    
    out_file = "data/raw/infrastructure/kanmon_straits_detailed_roads.json"
    os.makedirs(os.path.dirname(out_file), exist_ok=True)

    for ep in endpoints:
        try:
            print(f"Requesting to {ep}...")
            resp = requests.post(ep, data={"data": query}, headers=headers, timeout=40)
            if resp.status_code == 200:
                data = resp.json()
                ways = [e for e in data.get("elements", []) if e.get("type") == "way"]
                print(f"Success! {len(ways)} detailed local roads collected.")
                with open(out_file, "w", encoding="utf-8") as f:
                    json.dump(data, f, ensure_ascii=False)
                return out_file
            else:
                print(f"Status: {resp.status_code}")
        except Exception as e:
            print(f"Error on {ep}: {e}")
            
    return None

if __name__ == "__main__":
    fetch_urban_roads()
