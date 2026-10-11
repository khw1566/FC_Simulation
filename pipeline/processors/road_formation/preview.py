"""합성 경사면 GPU 비교와 실제 밀집 도로 128m 구역만 독립 실행한다."""
import json
import os
import shutil
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image

from profiles import sample
from verify import PROJECT, ROOT, digest, save


def dense_fixture():
    meta = json.loads((ROOT/"godot_project/assets/maps/ulsan_metro_80km/map_meta.json").read_text(encoding="utf-8"))
    base = ROOT/"godot_project"/meta["assets"]["buildings_roads"].removeprefix("res://")
    base = base.parent/"road_formation"
    index = json.loads((base/"index.json").read_text(encoding="utf-8"))
    entry = max(index["tiles"].values(),key=lambda e:e["count"])
    rows = np.fromfile(base/entry["file"],dtype="<f4").reshape(-1,9)
    mids = (rows[:,:2]+rows[:,3:5])*.5
    cells = np.floor(mids/128).astype(int)
    unique,counts = np.unique(cells,axis=0,return_counts=True)
    center = (unique[counts.argmax()]+.5)*128
    margin = rows[:,6]+rows[:,7]
    keep = np.all(np.minimum(rows[:,:2],rows[:,3:5])-margin[:,None]<=center+64,axis=1)
    keep &= np.all(np.maximum(rows[:,:2],rows[:,3:5])+margin[:,None]>=center-64,axis=1)
    rows = rows[keep].copy()
    rows[:,8] = np.arange(len(rows))
    folder = PROJECT/"dense"
    save(folder/"source.json",{})
    height = ROOT/"godot_project"/index["height_source"].removeprefix("res://")
    with Image.open(height) as image:
        heights = np.asarray(image,dtype=np.float32)/65535*(meta["max_elevation"]-meta["min_elevation"])+meta["min_elevation"]
    xs,zs = np.meshgrid(np.linspace(center[0]-64,center[0]+64,65),np.linspace(center[1]-64,center[1]+64,65))
    (folder/"height.bin").write_bytes(sample(heights,xs,zs,80000).astype("<f4").tobytes())
    formed = folder/"road_formation"
    formed.mkdir(parents=True,exist_ok=True)
    (formed/"0.f32").write_bytes(rows.tobytes())
    entry = {"file":"0.f32","count":len(rows),"sha256":digest(formed/"0.f32")}
    lo,hi = np.floor((center-64)/512).astype(int),np.floor((center+64)/512).astype(int)
    save(formed/"index.json",{"version":1,"source_size":(folder/"source.json").stat().st_size,
         "source_modified":int((folder/"source.json").stat().st_mtime),"height_source":"res://dense/height.bin",
         "height_size":(folder/"height.bin").stat().st_size,"height_modified":int((folder/"height.bin").stat().st_mtime),
         "tiles":{f"{x},{z}":entry for x in range(lo[0],hi[0]+1) for z in range(lo[1],hi[1]+1)}})
    save(folder/"config.json",{"x":int(center[0]),"z":int(center[1]),"segments":len(rows)})


def run():
    dense_fixture()
    env = os.environ.copy()
    for key in ("APPDATA","LOCALAPPDATA"):
        env[key] = str(ROOT/"previews/road_formation_check/environment"/key.lower())
    godot = str(ROOT/"tools/godot/Godot_v4.3-stable_win64_console.exe")
    for name in ("render.gd","dense_check.gd"):
        shutil.copy2(Path(__file__).parent/name,PROJECT/name)
    results = {}
    for name,flags,marker in (("dense_check",["--headless"],"DENSE_ROAD_CHECK_OK"),
                              ("render",["--rendering-method","forward_plus","--position","80,80"],"ROAD_RENDER_OK")):
        result = subprocess.run([godot,"--path",str(PROJECT),*flags,"--script",f"res://{name}.gd"],env=env,
                                capture_output=True,encoding="utf-8",errors="replace",timeout=90)
        log = result.stdout+result.stderr
        (PROJECT.parent/f"{name}.log").write_text(log,encoding="utf-8")
        print(log[-3000:],flush=True)
        assert marker in log and "SCRIPT ERROR" not in log and result.returncode==0
        filename = "dense.json" if name=="dense_check" else "render.json"
        results[name] = json.loads((PROJECT/filename).read_text(encoding="utf-8"))
    for name in ("before.png","after.png"):
        shutil.copy2(PROJECT/name,ROOT/"results/road_formation"/name)
    save(ROOT/"results/road_formation/preview.json",results)


if __name__=="__main__":
    run()
