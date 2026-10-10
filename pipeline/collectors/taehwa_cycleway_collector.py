"""태화강 자전거길 원자료(OSM 자전거길·하천 중심선)를 Overpass에서 받아 캐시한다.

실행: python -m pipeline.collectors.taehwa_cycleway_collector [--force]
"""
from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "config" / "taehwa_cycleway.json"
ENDPOINTS = ("https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter")
USER_AGENT = "FC-Simulation-Riverside/1 (taehwagang cycleway)"


def _query(query: str) -> dict:
    last_error = None
    for attempt in range(3):
        for url in ENDPOINTS:
            try:
                response = requests.post(url, data={"data": query}, timeout=240, headers={"User-Agent": USER_AGENT})
                response.raise_for_status()
                return response.json()
            except (requests.RequestException, ValueError) as error:
                last_error = error
        time.sleep(2 ** (attempt + 1))
    raise RuntimeError(f"Overpass 요청 실패: {last_error}")


def collect(force: bool = False) -> tuple[Path, Path]:
    config = json.loads(CONFIG.read_text(encoding="utf-8"))
    raw_dir = ROOT / config["raw_dir"]
    raw_dir.mkdir(parents=True, exist_ok=True)
    s, w, n, e = config["collect_bbox"]
    box = f"({s},{w},{n},{e})"
    ways_path = raw_dir / "cycleways_raw.json"
    rivers_path = raw_dir / "rivers_raw.json"
    if force or not ways_path.exists():
        query = (f'[out:json][timeout:180];(way["highway"="cycleway"]{box};'
                 f'way["highway"~"^(path|footway|track)$"]["bicycle"="designated"]{box};);out geom tags;')
        ways_path.write_text(json.dumps(_query(query), ensure_ascii=False), encoding="utf-8")
    if force or not rivers_path.exists():
        # 한글 이름 조건은 일부 서버에서 실패하므로 이름 있는 하천을 모두 받아 여기서 거른다
        query = f'[out:json][timeout:180];way["waterway"="river"]["name"]{box};out geom tags;'
        data = _query(query)
        data["elements"] = [e for e in data["elements"] if e.get("tags", {}).get("name") == config["river_name"]]
        rivers_path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    return ways_path, rivers_path


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true", help="캐시가 있어도 다시 받는다")
    for path in collect(parser.parse_args().force):
        print(path)
