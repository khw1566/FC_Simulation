"""기존 노반 리비전 입력 해시를 재확인하고 수계 입력 메타데이터를 보완한다."""
import hashlib
import json

from build import ROOT, digest, read, save


def complete():
    meta = read(ROOT/"godot_project/assets/maps/ulsan_metro_80km/map_meta.json")
    vector = ROOT/"godot_project"/meta["assets"]["buildings_roads"].removeprefix("res://")
    base = vector.parent/"road_formation"
    index = read(base/"index.json")
    height = ROOT/"godot_project"/index["height_source"].removeprefix("res://")
    water = ROOT/"godot_project"/meta["assets"]["watermask"].removeprefix("res://")
    states = {p:(p.stat().st_size,p.stat().st_mtime_ns,digest(p)) for p in (vector,height,water)}
    revision = hashlib.sha256((states[vector][2]+states[height][2]+states[water][2]+"formation_v1").encode()).hexdigest()[:16]
    assert revision==index["revision"],"입력 변경으로 메타데이터 보완 보류"
    index.update(water_source="res://"+water.relative_to(ROOT/"godot_project").as_posix(),water_sha256=states[water][2],
                 water_size=states[water][0],water_modified=int(water.stat().st_mtime))
    common_path = ROOT/"godot_project/assets/generated/manifest.json"
    common_before = common_path.read_bytes()
    common = json.loads(common_before)
    manifest = read(base/"manifest.json")
    for path,state in states.items():
        assert (path.stat().st_size,path.stat().st_mtime_ns,digest(path))==state
    save(base/"index.json",index)
    asset = manifest["assets"]["index.json"]
    asset["sha256"] = digest(base/"index.json")
    asset["metadata"].update(height_sha256=states[height][2],water_sha256=states[water][2])
    save(base/"manifest.json",manifest)
    common.setdefault("assets",{})["ulsan_road_formation"] = asset
    assert common_path.read_bytes()==common_before,"공유 매니페스트 동시 변경"
    save(common_path,common)
    save(ROOT/"results/road_formation/build.json",{k:v for k,v in index.items() if k!="tiles"}|
         {"tile_count":len(index["tiles"]),"bytes":sum((base/e["file"]).stat().st_size for e in index["tiles"].values())})
    print("노반 입력 벡터·DEM·수계 해시 일치, 선분 파일 유지")


if __name__=="__main__":
    complete()
