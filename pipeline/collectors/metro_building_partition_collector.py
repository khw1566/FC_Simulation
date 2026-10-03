import os
import json
import time
from datetime import date
import requests

class MetroBuildingPartitionCollector:
    """
    60km 광역 권역을 10㎢ 미만의 안전 셀로 분할하여,
    일일 API 호출 한도를 철저히 준수하면서 울산대 맵처럼 단계별 전수 수집하는 수집기
    """
    BASE_URL = "https://api.vworld.kr/req/data"

    def __init__(self, config_path="config/ulsan_metro_60km.json", key_path="data/api_keys.json", max_calls_per_day=700):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)
        with open(key_path, "r", encoding="utf-8") as f:
            self.keys = json.load(f)
        self.api_key = self.keys.get("vworld_api_key", "").strip()
        map_id = self.config.get("region_name", "ulsan_metro_60km")
        self.base_dir = f"godot_project/assets/maps/{map_id}/buildings_cache"
        self.max_calls_per_day = min(700, int(max_calls_per_day))
        os.makedirs(self.base_dir, exist_ok=True)
        self.manifest_path = os.path.join(self.base_dir, "manifest_progress.json")
        self._load_manifest()

    def _load_manifest(self):
        today_str = date.today().isoformat()
        if os.path.exists(self.manifest_path):
            with open(self.manifest_path, "r", encoding="utf-8") as f:
                self.manifest = json.load(f)
            if self.manifest.get("date") != today_str:
                self.manifest["date"] = today_str
                self.manifest["daily_api_calls"] = 0
                self._save_manifest()
        else:
            self.manifest = {
                "date": today_str,
                "completed_cells": [],
                "daily_api_calls": 0,
                "total_unique_buildings": 0,
                "seen_sns": []
            }

    def _save_manifest(self):
        with open(self.manifest_path, "w", encoding="utf-8") as f:
            json.dump(self.manifest, f, ensure_ascii=False, indent=2)

    def generate_phase_grid(self, phase_name, sub_bbox, grid_x=4, grid_y=4):
        """10㎢ 이하 단위 셀로 격자 분할"""
        lat_step = (sub_bbox["north"] - sub_bbox["south"]) / float(grid_y)
        lon_step = (sub_bbox["east"] - sub_bbox["west"]) / float(grid_x)
        cells = []
        for gy in range(grid_y):
            s_lat = sub_bbox["south"] + gy * lat_step
            n_lat = sub_bbox["south"] + (gy + 1) * lat_step
            for gx in range(grid_x):
                w_lon = sub_bbox["west"] + gx * lon_step
                e_lon = sub_bbox["west"] + (gx + 1) * lon_step
                cell_id = f"{phase_name}_y{gy}_x{gx}"
                cells.append({
                    "cell_id": cell_id,
                    "south": round(s_lat, 6),
                    "north": round(n_lat, 6),
                    "west": round(w_lon, 6),
                    "east": round(e_lon, 6)
                })
        return cells

    def run_daily_quota(self, cells, max_calls_per_day=None):
        seen_set = set(self.manifest.get("seen_sns", []))
        completed_cells = set(self.manifest.get("completed_cells", []))
        calls_done = 0
        limit = min(self.max_calls_per_day, int(max_calls_per_day or self.max_calls_per_day))
        remaining_budget = max(0, limit - int(self.manifest.get("daily_api_calls", 0)))

        print(f"[PartitionCollector] Starting batch run. Remaining daily budget: {remaining_budget} calls.")
        for c in cells:
            cid = c["cell_id"]
            if cid in completed_cells:
                print(f"[PartitionCollector] Cell {cid} already completed. Skipping.")
                continue

            if calls_done >= remaining_budget:
                print(f"[PartitionCollector] Daily call limit ({max_calls_per_day}) reached! Stopping for today.")
                break

            geom_filter = f"BOX({c['west']},{c['south']},{c['east']},{c['north']})"
            page = 1
            cell_features = []
            cell_file = os.path.join(self.base_dir, f"{cid}.json")
            cell_succeeded = True
            cell_sns = set()

            while True:
                if calls_done >= remaining_budget:
                    print(f"[PartitionCollector] Daily quota hit during cell {cid}. Will resume tomorrow.")
                    cell_succeeded = False
                    break

                params = {
                    "service": "data",
                    "request": "GetFeature",
                    "data": "LT_C_SPBD",
                    "key": self.api_key,
                    "format": "json",
                    "geometry": "true",
                    "attribute": "true",
                    "crs": "EPSG:4326",
                    "geomFilter": geom_filter,
                    "page": page,
                    "size": 100
                }

                calls_done += 1
                self.manifest["daily_api_calls"] += 1

                retries = 3
                success = False
                for attempt in range(1, retries + 1):
                    try:
                        resp = requests.get(self.BASE_URL, params=params, timeout=25)
                        if resp.status_code != 200:
                            print(f"[PartitionCollector] HTTP {resp.status_code} at {cid} p{page} (attempt {attempt}/{retries})")
                            time.sleep(1.0 * attempt)
                            continue
                        res_json = resp.json()
                        resp_body = res_json.get("response", {})
                        if resp_body.get("status") != "OK":
                            if resp_body.get("status") == "NOT_FOUND":
                                print(f"[PartitionCollector] No records for {cid} p{page}; treating as an empty cell.")
                                feats = []
                                success = True
                                break
                            print(f"[PartitionCollector] API status {resp_body.get('status')} at {cid} p{page} (attempt {attempt}/{retries})")
                            time.sleep(1.0 * attempt)
                            continue
                        feats = resp_body.get("result", {}).get("featureCollection", {}).get("features", [])
                        success = True
                        break
                    except Exception as e:
                        print(f"[PartitionCollector] Timeout/Error at {cid} p{page} (attempt {attempt}/{retries}): {e}")
                        time.sleep(1.5 * attempt)

                if not success:
                    cell_succeeded = False
                    self.manifest["last_api_error"] = {"cell_id": cid, "page": page, "error": f"Failed after {retries} retries", "time": time.strftime("%Y-%m-%dT%H:%M:%S%z")}
                    print(f"[PartitionCollector] Failed to fetch {cid} p{page} after retries; preserving cell for resume.")
                    break

                if not feats:
                    break

                for f in feats:
                    props = f.get("properties", {})
                    if props.get("sido") != "울산광역시" or props.get("sigungu") != "울주군":
                        continue
                    sn = props.get("bd_mgt_sn", "")
                    if sn and (sn in seen_set or sn in cell_sns):
                        continue
                    if sn:
                        cell_sns.add(sn)
                    cell_features.append(f)

                record_info = resp_body.get("record", {})
                total_rec = int(record_info.get("total", 0))
                if page * 100 >= total_rec:
                    break
                page += 1
                time.sleep(0.08)

            if not cell_succeeded:
                self.manifest["seen_sns"] = list(seen_set)
                self.manifest["total_unique_buildings"] = len(seen_set)
                self._save_manifest()
                break

            seen_set.update(cell_sns)

            with open(cell_file, "w", encoding="utf-8") as f:
                json.dump({"cell_id": cid, "features": cell_features}, f, ensure_ascii=False)

            completed_cells.add(cid)
            self.manifest["completed_cells"] = list(completed_cells)
            self.manifest["total_unique_buildings"] = len(seen_set)
            self.manifest["seen_sns"] = list(seen_set)
            self._save_manifest()
            print(f"[PartitionCollector] Cell {cid} finished with {len(cell_features)} buildings. Total calls: {calls_done}")

        print(f"[PartitionCollector] Session finished. Total calls executed: {calls_done}. Total unique buildings: {len(seen_set)}")

    def phase5_cells(self):
        """KTX울산역·언양·범서 중심 권역의 10㎢ 미만 셀."""
        bbox = {"south": 35.4800, "north": 35.6400, "west": 129.0700, "east": 129.2300}
        return self.generate_phase_grid("phase5_ulju_west", bbox, grid_x=5, grid_y=6)

if __name__ == "__main__":
    collector = MetroBuildingPartitionCollector()
    cells = collector.phase5_cells()
    print(f"[Main] Generated {len(cells)} safe cells for Phase 5 (Ulju west).")
    collector.run_daily_quota(cells, max_calls_per_day=700)
