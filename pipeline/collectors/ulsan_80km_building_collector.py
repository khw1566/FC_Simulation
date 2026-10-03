"""80km 맵 외곽 건물을 셀별로 수집하고 일일 VWorld 요청 예산을 추적한다."""

import hashlib
import json
import math
import os
import time
from datetime import date, datetime
from pathlib import Path

import requests


class Ulsan80kmBuildingCollector:
    BASE_URL = "https://api.vworld.kr/req/data"
    MAP_ID = "ulsan_metro_80km"
    REQUEST_DELAY_SECONDS = 0.1
    PAGE_SIZE = 1000
    MAX_CELL_AREA_KM2 = 2.0

    def __init__(self, root: Path):
        self.root = root
        self.config = json.loads((root / "config/ulsan_metro_80km.json").read_text(encoding="utf-8"))
        self.key = os.environ.get("VWORLD_API_KEY", "").strip()
        if not self.key:
            raise ValueError("검증한 인증키를 VWORLD_API_KEY 환경변수로 전달해야 합니다.")
        self.domain = os.environ.get(
            "VWORLD_DOMAIN", self.config.get("vworld_request", {}).get("domain", "")
        ).strip()
        if not self.domain:
            raise ValueError("인증키에 등록한 서비스 URL을 VWORLD_DOMAIN으로 전달해야 합니다.")
        self.cache_dir = root / "godot_project/assets/maps/ulsan_metro_80km/buildings_cache"
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.manifest_path = self.cache_dir / "manifest_progress.json"
        self.manifest = self._load_manifest()

    def _load_manifest(self):
        today = date.today().isoformat()
        if self.manifest_path.exists():
            data = json.loads(self.manifest_path.read_text(encoding="utf-8"))
        else:
            data = {"map_id": self.MAP_ID, "completed_cells": [], "seen_sns": [], "total_unique_buildings": 0}
        if data.get("date") != today:
            data["date"] = today
            data["daily_api_calls"] = 0
        data.setdefault("completed_cells", [])
        data.setdefault("seen_sns", [])
        data.setdefault("total_unique_buildings", len(data["seen_sns"]))
        return data

    def save(self):
        temp = self.manifest_path.with_name(
            f"{self.manifest_path.stem}.{os.getpid()}.tmp"
        )
        serialized = json.dumps(self.manifest, ensure_ascii=False, indent=2)
        for attempt in range(5):
            temp.write_text(serialized, encoding="utf-8")
            try:
                temp.replace(self.manifest_path)
                return
            except PermissionError:
                if attempt == 4:
                    raise
                time.sleep(0.1 * (attempt + 1))

    def _index_cache_asset(self, path, payload):
        """수집한 2D 벡터 캐시를 맵별·공용 자산 목록에 등록한다."""
        raw = path.read_bytes()
        entry = {
            "file_path": str(path.resolve()), "type": "building_vector_cache",
            "format": "JSON", "sha256": hashlib.sha256(raw).hexdigest(),
            "size_bytes": len(raw), "bbox": payload["bbox"],
            "elevation": {"min_meters": None, "max_meters": None,
                          "note": "2D 원본 벡터에 절대고도 정보 없음"},
            "resolution": {"type": "vector", "feature_count": len(payload["features"])},
        }
        indexes = (
            (self.cache_dir.parent / "manifest.json", f"buildings_cache/{path.name}"),
            (self.root / "godot_project/assets/generated/manifest.json",
             f"{self.MAP_ID}/buildings_cache/{path.name}"),
        )
        for index_path, asset_id in indexes:
            index = json.loads(index_path.read_text(encoding="utf-8-sig")) if index_path.exists() else {}
            index.setdefault("assets", {})[asset_id] = entry
            index["last_updated"] = datetime.now().astimezone().isoformat()
            index_path.parent.mkdir(parents=True, exist_ok=True)
            temp = index_path.with_suffix(".tmp")
            temp.write_text(json.dumps(index, ensure_ascii=False, indent=2), encoding="utf-8")
            temp.replace(index_path)

    @staticmethod
    def _cell_area_km2(south, north, west, east):
        radius = 6371.0088
        return radius**2 * math.radians(east - west) * abs(math.sin(math.radians(north)) - math.sin(math.radians(south)))

    def phase1_cells(self):
        """과거 실행 인터페이스를 유지하며 전체 80km 외곽 셀을 반환한다."""
        return self.outer_cells()

    def outer_cells(self):
        bbox = self.config["bbox"]
        core = self.config.get("core_60km_bbox", {
            "south": 35.2742, "north": 35.8148,
            "west": 128.9233, "east": 129.5877,
        })
        # 기존 60km 경계 밖의 남·북·서·동 네 띠를 모두 포함한다.
        regions = {
            "phase1_80km_outer_north": {"south": core["north"], "north": bbox["north"], "west": bbox["west"], "east": bbox["east"]},
            "phase1_80km_outer_east": {"south": core["south"], "north": core["north"], "west": core["east"], "east": bbox["east"]},
            "phase2_80km_outer_south": {"south": bbox["south"], "north": core["south"], "west": bbox["west"], "east": bbox["east"]},
            "phase2_80km_outer_west": {"south": core["south"], "north": core["north"], "west": bbox["west"], "east": core["west"]},
        }
        cells = []
        for name, box in regions.items():
            lat_step = lon_step = float(self.config["quota_limits"]["cell_step_deg"])
            ny = math.ceil((box["north"] - box["south"]) / lat_step)
            nx = math.ceil((box["east"] - box["west"]) / lon_step)
            for y in range(ny):
                for x in range(nx):
                    cell = {
                        "cell_id": f"{name}_2km2_y{y:02d}_x{x:02d}",
                        "south": box["south"] + y * (box["north"] - box["south"]) / ny,
                        "north": box["south"] + (y + 1) * (box["north"] - box["south"]) / ny,
                        "west": box["west"] + x * (box["east"] - box["west"]) / nx,
                        "east": box["west"] + (x + 1) * (box["east"] - box["west"]) / nx,
                    }
                    cell["area_km2"] = self._cell_area_km2(cell["south"], cell["north"], cell["west"], cell["east"])
                    if cell["area_km2"] > self.MAX_CELL_AREA_KM2:
                        raise ValueError(f"셀 면적 초과: {cell['cell_id']}={cell['area_km2']:.3f} km²")
                    if cell["south"] < cell["north"]:
                        cells.append(cell)
        return cells

    def _fetch_page(self, cell, page):
        area = self._cell_area_km2(cell["south"], cell["north"], cell["west"], cell["east"])
        if area > self.MAX_CELL_AREA_KM2:
            raise ValueError(f"공식 API 조회 면적 상한 초과: {area:.3f} km² > 2 km²")
        params = {
            "service": "data", "version": "2.0", "request": "GetFeature", "data": "LT_C_SPBD",
            "key": self.key, "format": "json", "geometry": "true", "attribute": "true",
            "domain": self.domain,
            "crs": "EPSG:4326",
            "geomFilter": f"BOX({cell['west']},{cell['south']},{cell['east']},{cell['north']})",
            "page": page, "size": self.PAGE_SIZE,
        }
        last_error = None
        for attempt in range(1, 3):
            self.manifest["daily_api_calls"] = int(self.manifest.get("daily_api_calls", 0)) + 1
            self.manifest.setdefault("request_log", []).append({"time": datetime.now().astimezone().isoformat(), "cell_id": cell["cell_id"], "page": page})
            self.save()
            try:
                response = requests.get(self.BASE_URL, params=params, timeout=20)
                body = response.json().get("response", {})
                if response.status_code == 200 and body.get("status") in ("OK", "NOT_FOUND"):
                    time.sleep(self.REQUEST_DELAY_SECONDS)
                    return body
                error = body.get("error") or {}
                code = str(error.get("code", "UNKNOWN_ERROR"))
                last_error = f"HTTP {response.status_code}, status={body.get('status')}, code={code}"
                last_error = last_error.replace(self.key, "[REDACTED]")
                # 인증·파라미터·사용량 오류는 같은 요청을 반복해도 해결되지 않는다.
                if code not in ("SYSTEM_ERROR", "UNKNOWN_ERROR"):
                    break
                if 400 <= response.status_code < 500:
                    break
            except Exception as exc:  # Keep quota and checkpoint accounting conservative.
                last_error = f"{type(exc).__name__}: request failed; details omitted to protect credentials."
            time.sleep(attempt)
        raise RuntimeError(last_error or "요청 실패")

    def run(self, cells):
        done = set(self.manifest["completed_cells"])
        seen = set(self.manifest["seen_sns"])
        for cell in cells:
            cid = cell["cell_id"]
            if cid in done:
                continue
            features = []
            cell_seen = set()
            page = 1
            try:
                while True:
                    body = self._fetch_page(cell, page)
                    page_features = (body.get("result") or {}).get("featureCollection", {}).get("features", [])
                    record_total = int(body.get("record", {}).get("total", len(page_features)))
                    for feature in page_features:
                        props = feature.get("properties", {})
                        # 좌표의 실제 도형 중심이 요청 셀 안에 있는지 확인한다.
                        if not self._feature_in_cell(feature, cell):
                            continue
                        sn = str(props.get("bd_mgt_sn", "")).strip()
                        if sn and (sn in seen or sn in cell_seen):
                            continue
                        if sn:
                            cell_seen.add(sn)
                        features.append(feature)
                    if page * self.PAGE_SIZE >= record_total or not page_features:
                        break
                    page += 1
                    time.sleep(0.1)
                payload = {"cell_id": cid, "bbox": {key: cell[key] for key in ("south", "north", "west", "east")}, "area_km2": round(cell["area_km2"], 5), "features": features}
                path = self.cache_dir / f"{cid}.json"
                raw = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
                path.write_text(raw, encoding="utf-8")
                self._index_cache_asset(path, payload)
                seen.update(cell_seen)
                done.add(cid)
                self.manifest["completed_cells"] = sorted(done)
                self.manifest["seen_sns"] = sorted(seen)
                self.manifest["total_unique_buildings"] = len(seen)
                self.manifest.pop("last_api_error", None)
                self.manifest.setdefault("cell_stats", {})[cid] = {"feature_count": len(features), "pages": page, "sha256": hashlib.sha256(raw.encode("utf-8")).hexdigest(), "area_km2": round(cell["area_km2"], 5)}
                self.save()
                print(f"완료 {cid}: 피처 {len(features)}, 페이지 {page}, 오늘 호출 {self.manifest['daily_api_calls']}", flush=True)
            except Exception as exc:
                self.manifest["last_api_error"] = {"cell_id": cid, "page": page, "error": str(exc), "time": datetime.now().astimezone().isoformat()}
                self.manifest["seen_sns"] = sorted(seen)
                self.save()
                print(f"중단 {cid} 페이지 {page}: {exc}", flush=True)
                break
        print(f"대상 처리 상태: 누적 완료 {len(done)}, 전체 고유 건물 {len(seen)}, 오늘 요청 {self.manifest['daily_api_calls']}", flush=True)

    @staticmethod
    def _feature_in_cell(feature, cell):
        geometry = feature.get("geometry", {})
        coords = geometry.get("coordinates", [])
        points = []

        def walk(value):
            if isinstance(value, list) and len(value) >= 2 and all(isinstance(v, (int, float)) for v in value[:2]):
                points.append(value[:2])
            elif isinstance(value, list):
                for child in value:
                    walk(child)

        walk(coords)
        if not points:
            return False
        lon = sum(point[0] for point in points) / len(points)
        lat = sum(point[1] for point in points) / len(points)
        return cell["west"] <= lon <= cell["east"] and cell["south"] <= lat <= cell["north"]


if __name__ == "__main__":
    project_root = Path(__file__).resolve().parents[2]
    collector = Ulsan80kmBuildingCollector(project_root)
    phase_cells = collector.outer_cells()
    print(f"검증 통과: 전체 외곽 후보 셀 {len(phase_cells)}, 최대 면적 {max(c['area_km2'] for c in phase_cells):.3f} km², 기존 60km 코어와 분리", flush=True)
    collector.run(phase_cells)
