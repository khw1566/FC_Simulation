"""두 캠퍼스의 기존 건물 윤곽과 정밀 부지 모델링 미확보 항목을 색인한다."""
import argparse
import hashlib
import json
import math
from pathlib import Path


class CampusSiteIndexer:
    def __init__(self, root):
        self.root = Path(root)
        self.map_dir = self.root / "godot_project/assets/maps/ulsan_uc_west"

    @staticmethod
    def classify(name):
        name = name.strip()
        if "울산과학대" in name or name == "대학로 57":
            return "ulsan_college_west"
        if "울산대학교" in name or name == "대학로 93":
            return "university_of_ulsan"
        return None

    @staticmethod
    def footprint(points):
        if not isinstance(points, list):
            raise ValueError("건물 윤곽은 좌표 목록이어야 합니다.")
        ring = []
        for point in points:
            if not isinstance(point, list) or len(point) < 2:
                raise ValueError("잘못된 건물 윤곽 좌표입니다.")
            xy = [float(point[0]), float(point[1])]
            if not all(math.isfinite(v) for v in xy):
                raise ValueError("건물 윤곽에 유한하지 않은 좌표가 있습니다.")
            if not ring or ring[-1] != xy:
                ring.append(xy)
        if len(ring) > 1 and ring[0] == ring[-1]:
            ring.pop()
        if len(ring) < 3:
            raise ValueError("건물 윤곽에는 최소 세 꼭짓점이 필요합니다.")
        area = abs(sum(a[0] * b[1] - b[0] * a[1]
                       for a, b in zip(ring, ring[1:] + ring[:1]))) / 2
        if area <= 0:
            raise ValueError("건물 윤곽의 면적이 0입니다.")
        return ring, round(area, 3)

    @staticmethod
    def write(path, data):
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    def run(self):
        source = self.map_dir / "buildings_and_roads.json"
        data = json.loads(source.read_text(encoding="utf-8"))
        meta = json.loads((self.map_dir / "map_meta.json").read_text(encoding="utf-8"))
        records, rejected = [], []
        for building in data["buildings"]:
            campus = self.classify(building.get("name", ""))
            if campus is None:
                continue
            try:
                ring, area = self.footprint(building.get("polygon", []))
                height = float(building["height"])
                base = float(building["base_y"])
                if not math.isfinite(height) or not math.isfinite(base) or height <= 0:
                    raise ValueError("건물 높이 또는 기초 고도가 유효하지 않습니다.")
            except (ValueError, KeyError, TypeError) as error:
                rejected.append({"id": building.get("id"), "reason": str(error)})
                continue
            records.append({
                "building_id": building["id"], "name": building["name"],
                "campus_candidate": campus, "membership_verified": False,
                "footprint_world_xz_m": ring, "footprint_area_m2": area,
                "source_base_y_m": base, "source_height_m": height,
                "height_quality": "existing_source_not_survey_verified",
                "base_quality": "coarse_dem_derived",
                "site_boundary_world_xz_m": None,
                "surveyed_finished_floor_y_m": None,
                "vertical_datum": None,
                "retaining_walls": None, "stairs": None, "entrances": None,
                "replacement_model_path": None,
            })
        output = self.map_dir / "campus_sites.json"
        payload = {
            "map_id": meta["id"], "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "coordinate_system": "map_local_x_east_z_south_meters",
            "bbox": meta["bbox"], "world_size_meters": meta["world_size_meters"],
            "status": "inventory_only_not_surveyed_sites", "buildings": records,
            "rejected": rejected,
            "counts": {campus: sum(r["campus_candidate"] == campus for r in records)
                       for campus in ("university_of_ulsan", "ulsan_college_west")},
        }
        self.write(output, payload)
        entry = {
            "file_path": "res://assets/maps/ulsan_uc_west/campus_sites.json",
            "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
            "size_bytes": output.stat().st_size, "bbox": meta["bbox"],
            "min_elevation": meta["min_elevation"], "max_elevation": meta["max_elevation"],
            "resolution": None, "type": "campus_site_inventory", "counts": payload["counts"],
        }
        for manifest_path in (self.map_dir / "manifest.json",
                              self.root / "godot_project/assets/generated/manifest.json"):
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest.setdefault("assets", {})["ulsan_campus_sites"] = entry
            self.write(manifest_path, manifest)
        return {"counts": payload["counts"], "rejected_count": len(rejected)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="두 캠퍼스 건물 및 부지 준비 색인")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    print(json.dumps(CampusSiteIndexer(args.root).run(), ensure_ascii=False))
