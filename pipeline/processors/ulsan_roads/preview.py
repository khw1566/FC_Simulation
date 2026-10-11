"""전체 맵 대신 대표 6개 도로의 독립 메시 생성만 확인한다."""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from ulsan_roads.build import ROOT, read, save


def preview():
    report = read(ROOT/"results/ulsan_80km_roads/build_report.json")
    stage = ROOT/report["stage"]
    roads = read(stage/"buildings_and_roads.json")["roads"]
    chosen = []
    for label, predicate in (
        ("residential",lambda r:r["type"]=="residential" and not r["bridge"] and not r["tunnel"]),
        ("path",lambda r:r["type"]=="path" and not r["bridge"] and not r["tunnel"]),
        ("track",lambda r:r["type"]=="track" and not r["bridge"] and not r["tunnel"]),
        ("bridge",lambda r:r["bridge"] and not r["tunnel"]),
        ("tunnel",lambda r:r["tunnel"]),
        ("outer",lambda r:any(abs(p[0])>32000 or abs(p[2])>32000 for p in r["points"]) and not r["bridge"] and not r["tunnel"])):
        candidates = [r for r in roads if predicate(r) and 2<=len(r["points"])<=25]
        value = candidates[len(candidates)//2].copy()
        value["fixture_label"] = label
        chosen.append(value)
    project = ROOT/"previews/asset_browser/ulsan_80km_roads_check"
    scripts = project/"scripts/terrain"
    scripts.mkdir(parents=True,exist_ok=True)
    for name in ("road_batch_builder.gd","road_mesh_builder.gd","road_segment_classifier.gd","road_terrain_tessellator.gd"):
        shutil.copy2(ROOT/"godot_project/scripts/terrain"/name,scripts/name)
    meta = read(ROOT/"godot_project/assets/maps/ulsan_metro_80km/map_meta.json")
    from PIL import Image
    import numpy as np
    heightpath = ROOT/"godot_project"/meta["assets"]["heightmap"].removeprefix("res://")
    with Image.open(heightpath) as image:
        samples = np.asarray(image,dtype=np.float32)
    for road in chosen:
        heights = []
        for p in road["points"]:
            x = min(samples.shape[1]-1,max(0,round((p[0]/80000+.5)*(samples.shape[1]-1))))
            z = min(samples.shape[0]-1,max(0,round((p[2]/80000+.5)*(samples.shape[0]-1))))
            heights.append(round(float(samples[z,x])/65535*1330-30,3))
        road["fixture_ground"] = heights
    for label, kind, surface, expected in (("paved_cycleway","cycleway","asphalt","paved"),
                                           ("paved_track","track","concrete","paved"),
                                           ("gravel_service","service","gravel","unpaved")):
        chosen.append({"fixture_label":label,"fixture_ground":[0,0],"type":kind,"surface":surface,
                       "width":3,"points":[[0,0,0],[10,0,0]],"bridge":False,"tunnel":False,
                       "structure_tags_verified":True,"osm_id":None,"expected_kind":expected})
    save(project/"fixtures.json",chosen)
    (project/"project.godot").write_text('config_version=5\n[application]\nconfig/name="울산 도로 독립 확인"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',encoding="utf-8")
    (project/"check.gd").write_text('''extends SceneTree
const Batch = preload("res://scripts/terrain/road_batch_builder.gd")
var failed := false
func _initialize() -> void:
    var records: Array = []
    var roads: Array = JSON.parse_string(FileAccess.get_file_as_string("res://fixtures.json"))
    for road in roads:
        var origin := Vector3(float(road.points[0][0]), 0, float(road.points[0][2]))
        var heights: Array = road.fixture_ground
        var average: float = 0.0
        for h in heights:
            average += float(h)
        average /= heights.size()
        for p in road.points:
            p[0] = float(p[0])-origin.x
            p[2] = float(p[2])-origin.z
        # 실제 지형 높이의 대표 평균을 사용한 경량 메시 확인이다.
        var ground := func(_x, _z, _fallback): return average
        var water := func(_x, _z): return 0.0
        var result: Dictionary = Batch.compute([road], ground, water, Vector2(24,24), Vector2.ZERO)
        if road.has("expected_kind") and result[road.expected_kind].is_empty():
            failed = true
        var triangles: int = 0
        for key in ["paved", "walking", "unpaved", "tunnel", "bridge"]:
            for arrays in result[key]:
                var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
                for vertex in verts:
                    if not vertex.is_finite():
                        failed = true
                var indices = arrays[Mesh.ARRAY_INDEX]
                triangles += indices.size()/3 if indices is PackedInt32Array and indices.size()>0 else verts.size()/3
        if triangles == 0:
            failed = true
        records.append({"label":road.fixture_label,"osm_id":road.osm_id,"triangles":triangles})
    var file := FileAccess.open("res://mesh_check.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"passed":not failed,"cases":records,"full_world_run":false,"ground_basis":"source DEM point mean"},"  "))
    file.close()
    print("ROAD_FIXTURE_CHECK ",not failed)
    quit(1 if failed else 0)
''',encoding="utf-8")
    env = os.environ.copy()
    env["APPDATA"] = str(project/"appdata")
    env["LOCALAPPDATA"] = str(project/"localappdata")
    command = [str(ROOT/"tools/godot/Godot_v4.3-stable_win64_console.exe"),"--headless","--path",str(project),"--script","res://check.gd","--quit-after","120"]
    result = subprocess.run(command,env=env,capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=90)
    (project/"check.log").write_text(result.stdout+result.stderr,encoding="utf-8")
    print(result.stdout+result.stderr)
    if result.returncode or not (project/"mesh_check.json").exists():
        raise RuntimeError("독립 도로 메시 확인 실패")
    value = read(project/"mesh_check.json")
    assert value["passed"]
    save(ROOT/"results/ulsan_80km_roads/mesh_check.json",value)


if __name__=="__main__":
    preview()
