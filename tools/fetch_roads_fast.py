import os
import json
import time
import requests

def fetch_roads():
    # 간몬 해협 핵심 도심 및 관문 (모지코, 시모노세키 도심, 단노우라 등)
    # south: 33.94, west: 130.92, north: 33.98, east: 130.98
    query = """[out:json][timeout:35];
(
  way["highway"~"residential|living_street|service|unclassified|track|footway|pedestrian|path|steps|cycleway"](33.94,130.92,33.98,130.98);
);
out body;
>;
out skel qt;
"""
    headers = {
        "User-Agent": "KanmonRoadsCollector/3.0 (Terrain Project)"
    }
    ep = "https://overpass-api.de/api/interpreter"
    print("Sending query to Overpass API...")
    resp = requests.post(ep, data={"data": query}, headers=headers, timeout=40)
    print("Status:", resp.status_code)
    if resp.status_code == 200:
        data = resp.json()
        ways = [e for e in data.get("elements", []) if e.get("type") == "way"]
        nodes = [e for e in data.get("elements", []) if e.get("type") == "node"]
        print(f"Retrieved {len(ways)} road ways, {len(nodes)} nodes.")
        out_path = "data/raw/infrastructure/kanmon_straits_detailed_roads.json"
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
        print("Successfully saved to:", out_path)
    else:
        print("Error response:", resp.text[:200])

if __name__ == "__main__":
    fetch_roads()
