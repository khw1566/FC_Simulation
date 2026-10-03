"""칸몬 전용 건물 생성 자료와 공간 캐시의 해시·범위·정밀도를 색인한다."""
import hashlib
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "processors"))
from vector_stream_cache import VectorStreamCache
from building_source_store import BuildingSourceStore


class KanmonBuildingIndexer:
    ROOT = Path(__file__).resolve().parents[2]

    @staticmethod
    def digest(path):
        return BuildingSourceStore.digest(path)

    @staticmethod
    def read(path):
        return json.loads(path.read_text(encoding="utf-8-sig"))

    def run(self):
        folder = self.ROOT / "godot_project/assets/maps/kanmon_straits"
        meta = self.read(folder / "map_meta.json")
        asset = folder / "buildings_20261003/buildings_and_roads.json"
        data = self.read(asset)
        used, changed = set(), False
        for building in data["buildings"]:
            if building["id"] in used:
                building["id"] += "_part_" + hashlib.sha256(json.dumps(building["polygon"]).encode()).hexdigest()[:10]
                changed = True
            used.add(building["id"])
        if changed:
            asset.write_text(json.dumps(data,ensure_ascii=False,separators=(",",":")),encoding="utf-8")
            VectorStreamCache(asset).build()
        index_path = asset.parent / "vector_stream/index.json"
        index = self.read(index_path)
        assert index["source_sha256"] == self.digest(asset)
        assert len(used) == len(data["buildings"]) == index["counts"]["buildings"]
        assert all(all(-14000.01 <= value <= 14000.01 for point in building["polygon"] for value in point) for building in data["buildings"])
        for batch in index["batches"]:
            assert self.digest(index_path.parent / batch["file"]) == batch["sha256"]
        old = self.read(folder / "buildings_and_roads.json")
        assert old["roads"] == data["roads"]
        assert old["breakwaters"] == data["breakwaters"]
        base = {"bbox": meta["bbox"], "elevation": {"min_meters": min(b["base_y"] for b in data["buildings"]), "max_meters": max(b["base_y"]+b["height"] for b in data["buildings"])}}

        def entry(path, resolution):
            return {**base,"file_path":"res://"+path.relative_to(self.ROOT/"godot_project").as_posix(),"sha256":self.digest(path),"size_bytes":path.stat().st_size,"resolution":resolution}

        entries = {
            "kanmon_buildings_20261003": entry(asset,{"type":"building_footprints","buildings":len(data["buildings"])}),
            "kanmon_buildings_stream_20261003": entry(index_path,{"type":"spatial_vector_batches","batches":len(index["batches"]),"counts":index["counts"]}),
            "kanmon_buildings_road_metadata": entry(asset.parent/"road_metadata.json",{"type":"road_metadata","roads":len(data["roads"])}),
            "kanmon_map_meta": entry(folder/"map_meta.json",{"type":"map_metadata"})}
        entries["kanmon_buildings_stream_20261003"]["source_sha256"] = index["source_sha256"]
        entries["kanmon_buildings_stream_20261003"]["batch_hashes"] = "각 배치 SHA-256은 인덱스에 기록"
        for manifest_path in [folder/"manifest.json",self.ROOT/"godot_project/assets/generated/manifest.json"]:
            manifest = self.read(manifest_path)
            manifest["assets"].update(entries)
            for existing in manifest["assets"].values():
                if existing.get("file_path") == "res://assets/maps/kanmon_straits/map_meta.json":
                    existing["sha256"] = self.digest(folder/"map_meta.json")
                    existing["size_bytes"] = (folder/"map_meta.json").stat().st_size
            manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
        audit = {"passed":True,"unique_ids":len(used),"validated_batches":len(index["batches"]),"roads_unchanged":True,"breakwaters_unchanged":True,"bbox_valid":True,"source_hashes":{name:self.digest(self.ROOT/"data/raw/buildings"/name) for name in ["kanmon_straits_buildings_20261003.json","kanmon_gsi_buildings_20261003.json"]},"asset_sha256":self.digest(asset)}
        (self.ROOT/"results/261003_kanmon_building_asset_validation.json").write_text(json.dumps(audit,ensure_ascii=False,indent=2),encoding="utf-8")
        print(json.dumps(audit),flush=True)


if __name__ == "__main__":
    KanmonBuildingIndexer().run()
