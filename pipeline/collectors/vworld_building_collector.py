import os
import json
import time
import requests

class VWorldBuildingCollector:
    """
    디지털 트윈국토(VWorld) 국가공간정보 Data API 2.0(LT_C_SPBD)을 활용하여
    정부 공공데이터 실측 건물 다각형 풋프린트 및 층수/건물명을 수집하는 수집기
    """
    BASE_URL = "https://api.vworld.kr/req/data"

    def __init__(self, config_path, api_key_path):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)
        with open(api_key_path, "r", encoding="utf-8") as f:
            self.keys = json.load(f)
        self.api_key = self.keys.get("vworld_api_key", "").strip()
        self.bbox = self.config.get("bbox", {})

    def fetch_buildings_bbox(self, bbox, output_json_path, max_records=5000):
        print(f"[VWorldBuildingCollector] Fetching buildings for bbox: {bbox}")
        os.makedirs(os.path.dirname(output_json_path), exist_ok=True)

        geom_filter = f"BOX({bbox['west']},{bbox['south']},{bbox['east']},{bbox['north']})"
        page = 1
        page_size = 100
        all_features = []
        total_records = None

        while True:
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
                "size": page_size
            }

            try:
                resp = requests.get(self.BASE_URL, params=params, timeout=20)
                if resp.status_code != 200:
                    print(f"[VWorldBuildingCollector] HTTP {resp.status_code} at page {page}")
                    break

                res_json = resp.json()
                response_body = res_json.get("response", {})
                if response_body.get("status") != "OK":
                    print(f"[VWorldBuildingCollector] Status {response_body.get('status')} at page {page}")
                    break

                record_info = response_body.get("record", {})
                if total_records is None:
                    total_records = int(record_info.get("total", 0))
                    print(f"[VWorldBuildingCollector] Total available buildings: {total_records}")

                features = response_body.get("result", {}).get("featureCollection", {}).get("features", [])
                if not features:
                    break

                all_features.extend(features)
                print(f"[VWorldBuildingCollector] Page {page}: Fetched {len(features)} buildings (Accumulated: {len(all_features)}/{total_records})")

                if len(all_features) >= total_records or len(all_features) >= max_records:
                    break

                page += 1
                time.sleep(0.1) # API 레이트 리밋 방지
            except Exception as e:
                print(f"[VWorldBuildingCollector] Error on page {page}: {e}")
                break

        out_data = {
            "type": "FeatureCollection",
            "bbox": bbox,
            "total_count": len(all_features),
            "features": all_features
        }

        with open(output_json_path, "w", encoding="utf-8") as f:
            json.dump(out_data, f, ensure_ascii=False, indent=2)

        print(f"[VWorldBuildingCollector] Saved {len(all_features)} buildings to {output_json_path}")
        return output_json_path

    def fetch_full_region_grid(self, full_bbox, output_json_path, grid_x=2, grid_y=2, max_per_cell=5000):
        """
        VWorld 1회 요청 면적 제한(10㎢)을 준수하기 위해
        5km x 5km 전체 바운딩 박스를 grid_x x grid_y(예: 2x2, 각 셀 6.25㎢)로 분할하여
        전 권역 건물을 고유 식별자(bd_mgt_sn) 기준으로 중복 없이 전수 수집하는 메서드
        """
        print(f"[VWorldBuildingCollector] Splitting region {full_bbox} into {grid_x}x{grid_y} grid cells...")
        os.makedirs(os.path.dirname(output_json_path), exist_ok=True)

        lat_step = (full_bbox["north"] - full_bbox["south"]) / float(grid_y)
        lon_step = (full_bbox["east"] - full_bbox["west"]) / float(grid_x)

        all_features = []
        seen_building_sns = set()

        cell_idx = 1
        total_cells = grid_x * grid_y

        for gy in range(grid_y):
            s_lat = full_bbox["south"] + gy * lat_step
            n_lat = full_bbox["south"] + (gy + 1) * lat_step

            for gx in range(grid_x):
                w_lon = full_bbox["west"] + gx * lon_step
                e_lon = full_bbox["west"] + (gx + 1) * lon_step

                cell_bbox = {
                    "south": round(s_lat, 6),
                    "north": round(n_lat, 6),
                    "west": round(w_lon, 6),
                    "east": round(e_lon, 6)
                }

                print(f"[VWorldBuildingCollector] === Processing Cell {cell_idx}/{total_cells} (S:{cell_bbox['south']}, W:{cell_bbox['west']}) ===")
                geom_filter = f"BOX({cell_bbox['west']},{cell_bbox['south']},{cell_bbox['east']},{cell_bbox['north']})"
                page = 1
                page_size = 100
                cell_total = None

                while True:
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
                        "size": page_size
                    }

                    try:
                        resp = requests.get(self.BASE_URL, params=params, timeout=20)
                        if resp.status_code != 200:
                            print(f"[VWorldBuildingCollector] Cell {cell_idx} HTTP {resp.status_code} at page {page}")
                            break

                        res_json = resp.json()
                        resp_body = res_json.get("response", {})
                        if resp_body.get("status") != "OK":
                            print(f"[VWorldBuildingCollector] Cell {cell_idx} Status {resp_body.get('status')} at page {page}")
                            break

                        rec_info = resp_body.get("record", {})
                        if cell_total is None:
                            cell_total = int(rec_info.get("total", 0))
                            print(f"[VWorldBuildingCollector] Cell {cell_idx} Total available: {cell_total}")

                        feats = resp_body.get("result", {}).get("featureCollection", {}).get("features", [])
                        if not feats:
                            break

                        added_in_page = 0
                        for f in feats:
                            sn = f.get("properties", {}).get("bd_mgt_sn", "")
                            if sn and sn in seen_building_sns:
                                continue
                            if sn:
                                seen_building_sns.add(sn)
                            all_features.append(f)
                            added_in_page += 1

                        print(f"[VWorldBuildingCollector] Cell {cell_idx} Page {page}: added {added_in_page} new buildings (Total accumulated: {len(all_features)})")

                        if page * page_size >= cell_total or page * page_size >= max_per_cell:
                            break

                        page += 1
                        time.sleep(0.08)
                    except Exception as e:
                        print(f"[VWorldBuildingCollector] Cell {cell_idx} error at page {page}: {e}")
                        break

                cell_idx += 1

        out_data = {
            "type": "FeatureCollection",
            "bbox": full_bbox,
            "total_count": len(all_features),
            "features": all_features
        }

        with open(output_json_path, "w", encoding="utf-8") as f:
            json.dump(out_data, f, ensure_ascii=False, indent=2)

        print(f"[VWorldBuildingCollector] Successfully fetched full region: {len(all_features)} buildings saved to {output_json_path}")
        return output_json_path

