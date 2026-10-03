import json
import requests

def test_query():
    q = '[out:json][timeout:25];(way["highway"~"motorway|trunk|primary|secondary|tertiary|residential|service|unclassified|track|footway|pedestrian|path"](33.95,130.93,33.97,130.96););out count;'
    r = requests.post('https://overpass-api.de/api/interpreter', data={'data': q}, headers={'User-Agent': 'KanmonVR/1.0'}, timeout=30)
    print("Status:", r.status_code)
    print("Elements:", r.json().get("elements", []))

if __name__ == "__main__":
    test_query()
