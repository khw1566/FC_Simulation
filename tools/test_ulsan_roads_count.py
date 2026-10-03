import os
import json
import requests

def test_ulsan_road_count():
    bbox = {'south': 35.2742, 'north': 35.8148, 'west': 128.9233, 'east': 129.5877}
    s, n, w, e = bbox['south'], bbox['north'], bbox['west'], bbox['east']
    query = f"""[out:json][timeout:60];
    (
      way["highway"~"motorway|trunk|primary|secondary|tertiary|residential|unclassified"]({s},{w},{n},{e});
    );
    out count;
    """
    url = "https://overpass-api.de/api/interpreter"
    print("Testing Overpass road query for 60km bbox...")
    try:
        r = requests.post(url, data={"data": query}, headers={"User-Agent": "UlsanMetroRoadTest/1.0"}, timeout=45)
        print("Status:", r.status_code)
        if r.status_code == 200:
            print("Response:", r.json().get("elements", []))
        else:
            print("Error text:", r.text[:200])
    except Exception as exc:
        print("Exception:", exc)

if __name__ == "__main__":
    test_ulsan_road_count()
