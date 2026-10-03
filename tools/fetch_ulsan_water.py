import os
import sys
import json
import requests
import numpy as np
from PIL import Image

def main():
    bbox = {'south': 35.5220, 'north': 35.5670, 'west': 129.2279, 'east': 129.2831}
    s, w, n, e = bbox['south'], bbox['west'], bbox['north'], bbox['east']
    
    query = f"""[out:json][timeout:40];
    (
      way["natural"="water"]({s},{w},{n},{e});
      way["waterway"]({s},{w},{n},{e});
      relation["natural"="water"]({s},{w},{n},{e});
    );
    out body;
    >;
    out skel qt;"""

    urls = [
        'https://overpass-api.de/api/interpreter',
        'https://lz4.overpass-api.de/api/interpreter',
        'https://overpass.kumi.systems/api/interpreter'
    ]
    headers = {
        "User-Agent": "UlsanVRProject/1.0 (VR Terrain Pipeline)"
    }
    print("[UlsanWater] Fetching water data from Overpass API...")
    raw_water_json = os.path.abspath('data/raw/ulsan_uc_west/waterways/ulsan_water.json')
    os.makedirs(os.path.dirname(raw_water_json), exist_ok=True)
    
    fetched = False
    for url in urls:
        try:
            print(f"[UlsanWater] Trying endpoint: {url}...")
            resp = requests.post(url, data={'data': query}, headers=headers, timeout=45)
            if resp.status_code == 200 and len(resp.text) > 100:
                with open(raw_water_json, 'w', encoding='utf-8') as f:
                    f.write(resp.text)
                print(f"[UlsanWater] Saved water JSON to: {raw_water_json} ({os.path.getsize(raw_water_json)} bytes)")
                fetched = True
                break
            else:
                print(f"[UlsanWater] HTTP {resp.status_code}")
        except Exception as exc:
            print(f"[UlsanWater] Error on {url}: {exc}")

    if not fetched:
        print("[UlsanWater] Warning: All endpoints failed, keeping fallback empty JSON")
        if not os.path.exists(raw_water_json):
            with open(raw_water_json, 'w', encoding='utf-8') as f:
                json.dump({"elements": []}, f)

    sys.path.insert(0, os.path.abspath('pipeline'))
    from processors.watermask_processor import WatermaskProcessor
    cfg_path = os.path.abspath('config/ulsan_uc_west.json')
    wm_proc = WatermaskProcessor(cfg_path)
    wm_out = os.path.abspath('godot_project/assets/maps/ulsan_uc_west/ulsan_watermask_8bit.png')
    wm_proc.generate_water_mask(raw_water_json, wm_out)
    print("[UlsanWater] Generated ulsan_watermask_8bit.png successfully!")

if __name__ == '__main__':
    main()
