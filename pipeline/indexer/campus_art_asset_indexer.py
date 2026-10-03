"""캠퍼스 영상 및 창작 모델 자산 메타데이터와 모듈 색인을 유지한다."""
import hashlib
import json
from pathlib import Path


class CampusArtAssetIndexer:
    def __init__(self, root: Path):
        self.root = root

    @staticmethod
    def write(path, data):
        path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")

    def run(self):
        folder = self.root / "godot_project/assets/maps/ulsan_uc_west"
        meta = json.loads((folder / "campus_imagery.json").read_text(encoding="utf-8"))
        recipe = {"mode": "imagery_guided_artistic_draft", "measured_accuracy": False,
                  "building_candidate_count": 106, "named_candidate_count": 75,
                  "imagery_zone_added_candidate_count": 31, "candidate_membership_verified": False,
                  "college_approximate_work_zone_xz": [[-620,-850],[-210,-850],[-210,-600],[-380,-560],[-610,-600]],
                  "pad_buffer_m": 3.0, "floor_spacing_m": 3.6,
                  "window_spacing_m": 3.2, "roof_parapet_height_m": 0.7,
                  "ground_elevation_source": "existing_COP30_heightmap",
                  "height_policy": "preserve_positive_source_height",
                  "features": ["windows","parapets","roof_equipment","canopies",
                               "estimated_steps","paved_pads","retaining_skirts"],
                  "not_modeled_in_3d": ["sports_fields","parking_markings","landscaping"],
                  "bbox": meta["bbox"], "min_elevation": -10, "max_elevation": 450}
        self.write(folder / "campus_art_model.json", recipe)
        for manifest_path in [folder / "manifest.json", self.root / "godot_project/assets/generated/manifest.json"]:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for filename in ["campus_imagery.png","campus_imagery.json","campus_art_model.json"]:
                path = folder / filename
                manifest.setdefault("assets", {})[filename] = {
                    "file_path": "res://assets/maps/ulsan_uc_west/"+filename,
                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                    "size_bytes": path.stat().st_size,"bbox":meta["bbox"],
                    "min_elevation": -10,"max_elevation":450,
                    "resolution":meta["resolution"] if filename.endswith(".png") else None,
                    "type":"imagery_guided_artistic_model", "surveyed":False}
            self.write(manifest_path,manifest)
        config_path = self.root / "config/ulsan_campus_quality.json"
        config = json.loads(config_path.read_text(encoding="utf-8"))
        config["status"] = "imagery_guided_artistic_draft"
        config["mode"] = "visual_quality_prioritized_over_measured_accuracy"
        config["acceptance"]["unknown_vertical_datum_blocks_terrain_replacement"] = False
        config["actual_native_imagery_spacing_approx_m"] = 0.97
        config["target_spacings_are_future_goals_not_achieved_accuracy"] = True
        self.write(config_path,config)
        modules = {
            "CampusArchitectureBuilder": "godot_project/scripts/terrain/campus_architecture_builder.gd",
            "CampusGroundOverlay": "godot_project/scripts/terrain/campus_ground_overlay.gd",
            "CampusPreview": "godot_project/scripts/terrain/campus_preview.gd",
            "CampusGeometryCheck": "godot_project/scripts/terrain/campus_geometry_check.gd",
            "CampusBuildingPolicy": "godot_project/scripts/terrain/campus_building_policy.gd",
            "CampusImageryCollector": "pipeline/collectors/campus_imagery_collector.py",
            "CampusArtAssetIndexer": "pipeline/indexer/campus_art_asset_indexer.py"}
        for index_path in [self.root / "module_index.json", self.root / "godot_project/module_index.json"]:
            index = json.loads(index_path.read_text(encoding="utf-8"))
            index["domains"]["campus_art_modeling"] = {
                "description":"영상 정합, 창작 캠퍼스 건축 보강, 미리보기와 자산 색인",
                "modules":[{"class_name": name,"path":path,
                            "lines":len((self.root/path).read_text(encoding="utf-8").splitlines())}
                           for name,path in modules.items()]}
            self.write(index_path,index)
        print("CAMPUS_ART_ASSETS_INDEXED=3")


if __name__ == "__main__":
    CampusArtAssetIndexer(Path(__file__).resolve().parents[2]).run()
