"""울산 광역권의 생활도로·보행로·산악 임도를 셀 단위로 수집한다."""

import json
import math
import subprocess
import sys
import time
from datetime import date
from pathlib import Path

import requests


class UlsanDetailedRoadCollector:
	ENDPOINTS = (
		"https://overpass-api.de/api/interpreter",
		"https://overpass.kumi.systems/api/interpreter",
	)
	HIGHWAYS = (
		"motorway|motorway_link|trunk|trunk_link|primary|primary_link|secondary|secondary_link|"
		"tertiary|tertiary_link|unclassified|residential|living_street|service|pedestrian|"
		"footway|path|steps|cycleway|track|bridleway|corridor"
	)
	CELLS_PER_RUN = 120
	REQUEST_DELAY_SECONDS = 1.1

	def __init__(self, root: Path):
		self.root = root
		self.config = json.loads((root / "config/ulsan_metro_60km.json").read_text(encoding="utf-8"))
		self.bbox = self.config["bbox"]
		self.raw_dir = root / "data/raw/ulsan_metro_60km/highways"
		self.cell_dir = self.raw_dir / "detailed_cells"
		self.cell_dir.mkdir(parents=True, exist_ok=True)
		self.raw_path = self.raw_dir / "overpass_ulsan_metro_highways.json"
		self.manifest_path = self.cell_dir / "manifest_progress.json"
		self.manifest = self._load_manifest()

	def _load_manifest(self):
		today = date.today().isoformat()
		data = json.loads(self.manifest_path.read_text(encoding="utf-8")) if self.manifest_path.exists() else {}
		if data.get("date") != today:
			data["date"] = today
			data["requests_today"] = 0
		data.setdefault("completed_cells", [])
		data.setdefault("failures", [])
		return data

	def _save_manifest(self):
		temp = self.manifest_path.with_suffix(".tmp")
		temp.write_text(json.dumps(self.manifest, ensure_ascii=False, indent=2), encoding="utf-8")
		temp.replace(self.manifest_path)

	def cells(self):
		lat_count = math.ceil((self.bbox["north"] - self.bbox["south"]) / 0.025)
		lon_count = math.ceil((self.bbox["east"] - self.bbox["west"]) / 0.025)
		result = []
		for y in range(lat_count):
			south = self.bbox["south"] + y * (self.bbox["north"] - self.bbox["south"]) / lat_count
			north = self.bbox["south"] + (y + 1) * (self.bbox["north"] - self.bbox["south"]) / lat_count
			for x in range(lon_count):
				west = self.bbox["west"] + x * (self.bbox["east"] - self.bbox["west"]) / lon_count
				east = self.bbox["west"] + (x + 1) * (self.bbox["east"] - self.bbox["west"]) / lon_count
				result.append({"cell_id": f"ulsan_roads_y{y:02d}_x{x:02d}", "south": south, "north": north, "west": west, "east": east})
		return result

	def _fetch_cell(self, cell):
		box = f"{cell['south']},{cell['west']},{cell['north']},{cell['east']}"
		query = f'[out:json][timeout:60];way["highway"~"^({self.HIGHWAYS})$"]({box});out body;>;out skel qt;'
		headers = {"User-Agent": "UlsanTerrainRoadCollector/1.0 (ODbL attribution in project)"}
		error = "요청 실패"
		for endpoint in self.ENDPOINTS:
			self.manifest["requests_today"] += 1
			self.manifest["last_request"] = {"cell_id": cell["cell_id"], "endpoint": endpoint, "time": time.strftime("%Y-%m-%dT%H:%M:%S%z")}
			self._save_manifest()
			try:
				response = requests.post(endpoint, data={"data": query}, headers=headers, timeout=75)
				if response.status_code == 200:
					payload = response.json()
					if isinstance(payload.get("elements"), list):
						return payload
					error = "응답 JSON에 elements가 없음"
				else:
					error = f"HTTP {response.status_code}"
			except Exception as exc:
				error = str(exc)
			time.sleep(self.REQUEST_DELAY_SECONDS)
		raise RuntimeError(error)

	def collect(self):
		cells = self.cells()
		done = set(self.manifest["completed_cells"])
		batch = [cell for cell in cells if cell["cell_id"] not in done][: self.CELLS_PER_RUN]
		if not batch:
			print(f"모든 도로 셀 완료: {len(done)}/{len(cells)}", flush=True)
			return
		for cell in batch:
			try:
				payload = self._fetch_cell(cell)
				target = self.cell_dir / f"{cell['cell_id']}.json"
				temp = target.with_suffix(".tmp")
				temp.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
				temp.replace(target)
				done.add(cell["cell_id"])
				self.manifest["completed_cells"] = sorted(done)
				self.manifest["failures"] = [item for item in self.manifest["failures"] if item["cell_id"] != cell["cell_id"]]
				self._save_manifest()
				ways = sum(element.get("type") == "way" for element in payload["elements"])
				print(f"완료 {cell['cell_id']}: 도로 {ways}개, 셀 {len(done)}/{len(cells)}", flush=True)
			except Exception as exc:
				self.manifest["failures"].append({"cell_id": cell["cell_id"], "error": str(exc), "time": time.strftime("%Y-%m-%dT%H:%M:%S%z")})
				self._save_manifest()
				print(f"중단 {cell['cell_id']}: {exc}", flush=True)
				break
			time.sleep(self.REQUEST_DELAY_SECONDS)
		self._merge_completed_cells()

	def _merge_completed_cells(self):
		if not self.manifest["completed_cells"]:
			return
		if not self.raw_path.exists():
			raise FileNotFoundError(f"기존 간선 도로 원본이 없습니다: {self.raw_path}")
		old = json.loads(self.raw_path.read_text(encoding="utf-8"))
		elements = list(old.get("elements", []))
		seen = {(element.get("type"), element.get("id")) for element in elements}
		added = 0
		for cell_id in self.manifest["completed_cells"]:
			path = self.cell_dir / f"{cell_id}.json"
			if not path.exists():
				continue
			payload = json.loads(path.read_text(encoding="utf-8"))
			for element in payload.get("elements", []):
				key = (element.get("type"), element.get("id"))
				if key not in seen:
					seen.add(key)
					elements.append(element)
					added += 1
		self.raw_path.write_text(json.dumps({"version": 1.0, "elements": elements}, ensure_ascii=False), encoding="utf-8")
		self.manifest["merged_element_count"] = len(elements)
		self.manifest["merged_added_elements"] = added
		self._save_manifest()
		print(f"원본 병합 완료: 요소 {len(elements)}개, 신규 {added}개", flush=True)
		if len(self.manifest["completed_cells"]) == len(self.cells()):
			self._build_runtime_roads()

	def _build_runtime_roads(self):
		integration = self.root / "tools/integrate_ulsan_metro_roads.py"
		godot = self.root / "tools/godot/Godot_v4.3-stable_win64_console.exe"
		restore = self.root / "pipeline/processors/restore_road_metadata.gd"
		subprocess.run([sys.executable, str(integration)], cwd=self.root, check=True)
		if godot.exists():
			subprocess.run([str(godot), "--headless", "--path", str(self.root / "godot_project"), "--script", str(restore)], cwd=self.root, check=True)
		self.manifest["runtime_integrated"] = True
		self.manifest["runtime_integrated_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
		self._save_manifest()


if __name__ == "__main__":
	project_root = Path(__file__).resolve().parents[2]
	UlsanDetailedRoadCollector(project_root).collect()
