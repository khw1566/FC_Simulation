"""전체 경계 일괄 수집과 분할 재개 수집. 런타임 자산은 변경하지 않는다."""
import argparse
import hashlib
import json
import math
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class RoadCollector:
    ENDPOINTS = ["https://overpass-api.de/api/interpreter",
                 "https://overpass.kumi.systems/api/interpreter"]

    def __init__(self):
        self.config = json.loads((ROOT / "config/ulsan_metro_80km.json").read_text(encoding="utf-8"))
        self.folder = ROOT / "data/raw/ulsan_metro_80km/highways"
        self.folder.mkdir(parents=True, exist_ok=True)
        self.progress = self.folder / "progress.json"
        self.signature = hashlib.sha256(json.dumps(self.config["bbox"], sort_keys=True).encode()).hexdigest()
        self.state = json.loads(self.progress.read_text(encoding="utf-8")) if self.progress.exists() else {}
        if self.state and self.state.get("bbox_sha256") != self.signature:
            raise RuntimeError("기존 수집 경계가 달라 별도 경로가 필요합니다")
        self.state.update(bbox_sha256=self.signature, bbox=self.config["bbox"], query_policy="all_highway_meta_geom_v1")
        self.state.setdefault("completed", {})
        self.state.setdefault("failures", {})

    @staticmethod
    def save(path, data):
        temp = path.with_suffix(".tmp")
        temp.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        temp.replace(path)

    def cells(self):
        b = self.config["bbox"]
        ny = math.ceil((b["north"] - b["south"]) / .025)
        nx = math.ceil((b["east"] - b["west"]) / .025)
        for y in range(ny):
            for x in range(nx):
                yield f"ulsan80_y{y:02}_x{x:02}", {
                    "south": b["south"] + (b["north"]-b["south"])*y/ny,
                    "north": b["south"] + (b["north"]-b["south"])*(y+1)/ny,
                    "west": b["west"] + (b["east"]-b["west"])*x/nx,
                    "east": b["west"] + (b["east"]-b["west"])*(x+1)/nx}

    def fetch(self, name, bbox, timeout):
        target = self.folder / f"{name}.json"
        previous = self.state["completed"].get(name)
        if previous and target.exists() and hashlib.sha256(target.read_bytes()).hexdigest() == previous["sha256"]:
            print(f"재사용 {name}", flush=True)
            return True
        # 경계 부근 노드가 밖에 있는 도로도 확보하도록 약 1km 여유를 둔다.
        pad = .01
        box = f"{bbox['south']-pad},{bbox['west']-pad},{bbox['north']+pad},{bbox['east']+pad}"
        query = f'[out:json][timeout:{timeout}][maxsize:536870912];way["highway"]({box});out meta geom;'
        for endpoint in self.ENDPOINTS:
            started = time.time()
            try:
                print(f"수집 {name}: {endpoint}", flush=True)
                req = urllib.request.Request(endpoint, data=urllib.parse.urlencode({"data": query}).encode(),
                    headers={"User-Agent": "Ulsan80RoadCoverage/1.0"})
                with urllib.request.urlopen(req, timeout=timeout+60) as response:
                    raw = response.read()
                payload = json.loads(raw)
                if payload.get("remark") or not isinstance(payload.get("elements"), list):
                    raise ValueError(payload.get("remark", "elements 배열 없음"))
                for way in payload["elements"]:
                    if way.get("type") != "way" or len(way.get("nodes", [])) != len(way.get("geometry", [])):
                        raise ValueError("불완전한 도로 노드열")
                    if any("lat" not in p or "lon" not in p for p in way["geometry"]):
                        raise ValueError("좌표 없는 도로 노드")
                temp = target.with_suffix(".download")
                temp.write_bytes(raw)
                temp.replace(target)
                self.state["completed"][name] = {
                    "sha256": hashlib.sha256(raw).hexdigest(), "ways": len(payload["elements"]),
                    "bbox": bbox, "endpoint": endpoint, "elapsed_seconds": round(time.time()-started, 2),
                    "osm_base": payload.get("osm3s", {}).get("timestamp_osm_base"),
                    "collected_at": time.strftime("%Y-%m-%dT%H:%M:%S%z")}
                self.state["failures"].pop(name, None)
                self.save(self.progress, self.state)
                print(f"완료 {name}: {len(payload['elements'])} ways, {len(raw)} bytes", flush=True)
                return True
            except Exception as exc:
                self.state["failures"][name] = {"error": str(exc), "endpoint": endpoint}
                self.save(self.progress, self.state)
                print(f"실패 {name}: {exc}", flush=True)
                time.sleep(2)
        return False

    def run(self, cells_only=False, limit=1044):
        # 일괄 응답은 같은 bbox 전체 쿼리의 완결된 응답으로 저장한다.
        # 분할 모드는 일괄 쿼리가 시간/메모리 제한에 걸릴 때만 사용한다.
        if not cells_only and self.fetch("full_80km", self.config["bbox"], 240):
            self.state["coverage_mode"] = "full_bbox"
            self.state["coverage_complete"] = True
        else:
            self.state["coverage_mode"] = "cells"
            remaining = [(name, box) for name, box in self.cells() if name not in self.state["completed"]]
            for name, box in remaining[:limit]:
                if not self.fetch(name, box, 60):
                    break
                time.sleep(1.2)
            self.state["coverage_complete"] = all(name in self.state["completed"] for name, _ in self.cells())
        self.save(self.progress, self.state)
        return self.state["coverage_complete"]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cells-only", action="store_true")
    parser.add_argument("--limit", type=int, default=1044)
    args = parser.parse_args()
    raise SystemExit(0 if RoadCollector().run(args.cells_only, args.limit) else 2)
