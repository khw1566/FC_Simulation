"""전체 맵을 실행하지 않고 경사 지형·도로 단면·거리 묶음과 원본 해시를 확인한다."""
import hashlib
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
PROJECT = ROOT/"previews/asset_browser/road_formation_check/project"


def digest(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file,"sha256").hexdigest()


def save(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding="utf-8")


def copy_sources():
    pending = ["scripts/terrain/terrain_chunk_manager.gd","scripts/terrain/building_road_manager.gd"]
    copied = set()
    while pending:
        relative = pending.pop()
        if relative in copied:
            continue
        path = ROOT/"godot_project"/relative
        target = PROJECT/relative
        target.parent.mkdir(parents=True,exist_ok=True)
        before = path.stat()
        shutil.copy2(path,target)
        after = path.stat()
        assert (before.st_size,before.st_mtime_ns)==(after.st_size,after.st_mtime_ns)
        copied.add(relative)
        content = path.read_text(encoding="utf-8")
        pending.extend(re.findall(r'res://([^"\s]+\.(?:gdshaderinc|gdshader|gd))(?=")',content))
        pending.extend(include.removeprefix("res://") if include.startswith("res://") else (Path(relative).parent/include).as_posix()
                       for include in re.findall(r'#include "([^"]+)"',content))
    for name in ("check.gd","check_host.gd"):
        shutil.copy2(Path(__file__).parent/name,PROJECT/name)
    (PROJECT/"project.godot").write_text('config_version=5\n[application]\nconfig/name="RoadFormationCheck"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="rfc"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\nshader_cache/enabled=false\n',encoding="utf-8")
    return copied


def fixture():
    folder = PROJECT/"fixture"
    save(folder/"source.json",{})
    (folder/"height.bin").write_bytes(b"fixture")
    data = np.array([[-60,0,14,60,0,26,4,8,0]],dtype="<f4").tobytes()
    base = folder/"road_formation"
    base.mkdir(parents=True,exist_ok=True)
    (base/"0.f32").write_bytes(data)
    entry = {"file":"0.f32","count":1,"sha256":hashlib.sha256(data).hexdigest()}
    save(base/"index.json",{"version":1,"source_size":(folder/"source.json").stat().st_size,
         "source_modified":int((folder/"source.json").stat().st_mtime),"height_source":"res://fixture/height.bin",
         "height_size":7,"height_modified":int((folder/"height.bin").stat().st_mtime),
         "tiles":{f"{x},{z}":entry for x in (-1,0) for z in (-1,0)}})


def verify_assets():
    meta = json.loads((ROOT/"godot_project/assets/maps/ulsan_metro_80km/map_meta.json").read_text(encoding="utf-8"))
    source = ROOT/"godot_project"/meta["assets"]["buildings_roads"].removeprefix("res://")
    base = source.parent/"road_formation"
    index = json.loads((base/"index.json").read_text(encoding="utf-8"))
    assert digest(source)==index["source_sha256"]
    for prefix in ("height","water"):
        path = ROOT/"godot_project"/index[f"{prefix}_source"].removeprefix("res://")
        assert digest(path)==index[f"{prefix}_sha256"]
    seen = np.zeros(index["segments"],dtype=bool)
    count = 0
    for entry in index["tiles"].values():
        path = base/entry["file"]
        assert digest(path)==entry["sha256"]
        rows = np.fromfile(path,dtype="<f4").reshape(-1,9)
        assert len(rows)==entry["count"] and np.isfinite(rows).all()
        ids = rows[:,8].astype(int)
        assert ids.min()>=0 and ids.max()<len(seen)
        seen[ids] = True
        assert np.all(rows[:,6]>0) and np.all(rows[:,7]>0)
        count += 1
    assert seen.all()
    return {"tile_hashes":count,"unique_segments":int(seen.sum()),"source_vector_preserved":True,"height_and_water_preserved":True,"bytes":sum((base/e["file"]).stat().st_size for e in index["tiles"].values())}


def verify():
    copied = copy_sources()
    fixture()
    env = os.environ.copy()
    for key in ("APPDATA","LOCALAPPDATA"):
        env[key] = str(ROOT/"previews/road_formation_check/environment"/key.lower())
        Path(env[key]).mkdir(parents=True,exist_ok=True)
    godot = ROOT/"tools/godot/Godot_v4.3-stable_win64_console.exe"
    base = [str(godot),"--headless","--path",str(PROJECT)]
    imported = subprocess.run(base+["--editor","--quit"],env=env,capture_output=True,encoding="utf-8",errors="replace",timeout=90)
    (PROJECT.parent/"import.log").write_text(imported.stdout+imported.stderr,encoding="utf-8")
    if "SCRIPT ERROR" in imported.stderr or imported.returncode:
        raise RuntimeError("격리 의존성 확인 실패: import.log")
    checked = subprocess.run(base+["--script","res://check.gd","--quit-after","180"],env=env,capture_output=True,encoding="utf-8",errors="replace",timeout=90)
    log = checked.stdout+checked.stderr
    (PROJECT.parent/"check.log").write_text(log,encoding="utf-8")
    print(log[-4000:])
    if "ROAD_FORMATION_CHECK_OK" not in log or "SCRIPT ERROR" in log or checked.returncode:
        raise RuntimeError("경량 형상 확인 실패: check.log")
    report = json.loads((PROJECT/"verification.json").read_text(encoding="utf-8"))
    report["assets"] = verify_assets()
    report["source_sha256"] = {p:digest(PROJECT/p) for p in sorted(copied)}
    assert all(digest(ROOT/"godot_project"/p)==h for p,h in report["source_sha256"].items())
    save(ROOT/"results/road_formation/verification.json",report)
    print(json.dumps(report["assets"],ensure_ascii=False))


if __name__=="__main__":
    verify()
