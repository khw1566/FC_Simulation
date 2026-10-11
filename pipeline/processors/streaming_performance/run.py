"""전체 지도 대신 실제 밀집 512m 타일·도로 업로드를 별도 프로젝트에서 측정한다."""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/"pipeline/processors/road_formation"))
import verify
from profiles import sample


def fixture(project):
    verify.PROJECT = project
    copied = verify.copy_sources()
    pending = ["scripts/views/performance_hud.gd","scripts/testing/prebaked_rail_baker.gd"]
    while pending:
        relative = pending.pop()
        if relative in copied:
            continue
        source_path = ROOT/"godot_project"/relative
        target = project/relative
        target.parent.mkdir(parents=True,exist_ok=True)
        before = source_path.stat()
        shutil.copy2(source_path,target)
        assert source_path.stat().st_mtime_ns==before.st_mtime_ns
        copied.add(relative)
        pending.extend(re.findall(r'res://([^"\s]+\.gd)(?=")',source_path.read_text(encoding="utf-8")))
    verify.fixture()
    meta = json.loads((ROOT/"godot_project/assets/maps/ulsan_metro_80km/map_meta.json").read_text(encoding="utf-8"))
    source = ROOT/"godot_project"/meta["assets"]["buildings_roads"].removeprefix("res://")
    base = source.parent/"road_formation"
    original = json.loads((base/"index.json").read_text(encoding="utf-8"))
    entries = sorted(original["tiles"].items(),key=lambda e:e[1]["count"],reverse=True)[:12]
    index_path = project/"fixture/road_formation/index.json"
    index = json.loads(index_path.read_text(encoding="utf-8"))
    keys = []
    for number,(key,entry) in enumerate(entries):
        path = project/f"fixture/road_formation/cold_{number}.f32"
        shutil.copy2(base/entry["file"],path)
        index["tiles"][key] = entry|{"file":path.name}
        keys.append([int(v) for v in key.split(",")])
    verify.save(index_path,index)
    verify.save(project/"perf_config.json",{"cold_tiles":keys})
    center = (np.array(keys[0])+.5)*512
    rows = np.fromfile(base/entries[0][1]["file"],dtype="<f4").reshape(-1,9)
    folder = project/"dense"
    verify.save(folder/"source.json",{})
    height = ROOT/"godot_project"/original["height_source"].removeprefix("res://")
    with Image.open(height) as image:
        heights = np.asarray(image,dtype=np.float32)/65535*(meta["max_elevation"]-meta["min_elevation"])+meta["min_elevation"]
    xs,zs = np.meshgrid(np.linspace(center[0]-256,center[0]+256,65),np.linspace(center[1]-256,center[1]+256,65))
    (folder/"height.bin").write_bytes(sample(heights,xs,zs,80000).astype("<f4").tobytes())
    formed = folder/"road_formation"
    formed.mkdir(parents=True,exist_ok=True)
    (formed/"0.f32").write_bytes(rows.tobytes())
    entry = {"file":"0.f32","count":len(rows),"sha256":verify.digest(formed/"0.f32")}
    verify.save(formed/"index.json",{"version":1,"source_size":2,"source_modified":int((folder/"source.json").stat().st_mtime),
                "height_source":"res://dense/height.bin","height_size":(folder/"height.bin").stat().st_size,
                "height_modified":int((folder/"height.bin").stat().st_mtime),"tiles":{f"{keys[0][0]},{keys[0][1]}":entry}})
    verify.save(folder/"config.json",{"x":float(center[0]),"z":float(center[1]),"segments":len(rows)})
    return copied


def run(phase):
    project = ROOT/f"previews/asset_browser/streaming_check/{phase}/project"
    if phase=="before":
        saved = json.loads((ROOT/"results/streaming_performance/before.json").read_text(encoding="utf-8"))
        copied = set(saved["source_sha256"])
        assert all(verify.digest(project/p)==h for p,h in saved["source_sha256"].items()), "변경 전 보존 소스가 필요합니다"
    else:
        copied = fixture(project)
    shutil.copy2(Path(__file__).parent/"measure.gd",project/"measure.gd")
    # 변경 전 프로젝트에는 새 함수가 없어 정적 참조를 제거한다.
    script = (project/"measure.gd").read_text(encoding="utf-8").replace('if Batch.has_method("attach_streamed"):',f'if {str(phase=="after").lower()}:')
    script = script.replace('const OPTIMIZED := false',f'const OPTIMIZED := {str(phase=="after").lower()}')
    if phase=="before":
        script = script.replace('Batch.attach_streamed(host,result)','Batch.attach(host,result)')
    (project/"measure.gd").write_text(script,encoding="utf-8")
    env = os.environ.copy()
    for key in ("APPDATA","LOCALAPPDATA"):
        env[key] = str(ROOT/f"previews/sp_env/{key.lower()}")
        Path(env[key]).mkdir(parents=True,exist_ok=True)
    godot = str(ROOT/"tools/godot/Godot_v4.3-stable_win64_console.exe")
    for name,args in (("import",["--headless","--editor","--quit"]),
                      ("measure",["--rendering-method","forward_plus","--script","res://measure.gd"])):
        result = subprocess.run([godot,"--path",str(project),*args],env=env,capture_output=True,encoding="utf-8",errors="replace",timeout=120)
        log = result.stdout+result.stderr
        (project.parent/f"{name}.log").write_text(log,encoding="utf-8")
        print(log[-3500:],flush=True)
        assert not result.returncode and "SCRIPT ERROR" not in log
        if name=="measure":
            assert "STREAMING_MEASUREMENT_OK" in log
    doc = json.loads((project/"measurement.json").read_text(encoding="utf-8"))
    doc["source_sha256"] = {p:verify.digest(project/p) for p in sorted(copied)}
    verify.save(ROOT/f"results/streaming_performance/{phase}.json",doc)


if __name__=="__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("phase",choices=["before","after"])
    run(parser.parse_args().phase)
