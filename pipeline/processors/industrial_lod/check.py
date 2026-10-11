"""임포트·씬·거리 전환을 원본 프로젝트 밖에서만 확인한다."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


def main():
    root=Path(__file__).resolve().parents[3]
    project=root/"godot_project"
    stage=root/"previews/asset_browser/industrial_lod_check"
    stage.mkdir(parents=True,exist_ok=True)
    seen=set()
    def copy(relative):
        if relative in seen: return
        seen.add(relative)
        source=project/relative
        if not source.is_file(): raise RuntimeError("의존성 누락: "+relative)
        before=source.read_bytes()
        dest=stage/relative
        dest.parent.mkdir(parents=True,exist_ok=True)
        dest.write_bytes(before)
        if source.read_bytes()!=before: raise RuntimeError("쓰기 중인 의존성 보류: "+relative)
        if source.suffix in (".gd",".tscn",".tres",".gdshader"):
            for dependency in re.findall(r'res://([^"\s\)]+)',before.decode("utf-8")):
                copy(dependency)
    manifest=json.loads((project/"assets/generated/industrial_lod/manifest.json").read_text(encoding="utf-8"))
    autos=[]
    for entry in manifest["assets"].values():
        copy(entry["scene_path"][6:])
        meta=entry["metadata"]
        if meta["lod_level"]==1:
            family,key=meta["source_asset"].split("/")
            relative=f"assets/generated/industrial_lod/{family}/{key}_auto_lod.tscn"
            copy(relative)
            autos.append("res://"+relative)
    (stage/"expected.json").write_text(json.dumps({"assets":list(manifest["assets"].values()),"auto_scenes":autos}),encoding="utf-8")
    shutil.copy2(Path(__file__).with_name("check.gd"),stage/"check.gd")
    (stage/"project.godot").write_text('config_version=5\n[application]\nconfig/name="Industrial LOD fixture"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',encoding="utf-8")
    env=os.environ.copy()
    env["APPDATA"]=str(stage/"appdata")
    env["LOCALAPPDATA"]=str(stage/"localdata")
    engine=str(root/"tools/godot/Godot_v4.3-stable_win64_console.exe")
    report=root/"results/261009_industrial_lod"
    for name,args in (("import",["--editor","--import"]),("check",["--script","res://check.gd"])):
        result=subprocess.run([engine,"--headless","--path",str(stage),*args],capture_output=True,
            text=True,encoding="utf-8",env=env,timeout=60,creationflags=subprocess.CREATE_NO_WINDOW)
        log=result.stdout+result.stderr
        (report/(name+".log")).write_text(log,encoding="utf-8")
        if result.returncode or "SCRIPT ERROR" in log or "ERROR:" in log:
            raise RuntimeError(log[-6000:])
        if name=="check":
            if "INDUSTRIAL LOD OK: 56 models, 28 selectors" not in log: raise RuntimeError(log)
            print(log)


if __name__=="__main__": main()
