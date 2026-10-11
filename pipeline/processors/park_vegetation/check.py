"""원본 임포터 없이 격리 복사본에서 모델과 소규모 조립을 확인한다."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


def main():
    root=Path(__file__).resolve().parents[3]
    project=root/"godot_project"
    stage=root/"previews/asset_browser/park_vegetation_check"
    report=root/"results/261009_park_vegetation"
    stage.mkdir(parents=True,exist_ok=True); report.mkdir(parents=True,exist_ok=True)
    seen=set(); hashes={}
    import hashlib
    def copy(relative):
        if relative in seen: return
        seen.add(relative)
        source=project/relative
        before=source.read_bytes()
        dest=stage/relative; dest.parent.mkdir(parents=True,exist_ok=True)
        dest.write_bytes(before)
        if source.read_bytes()!=before: raise RuntimeError("쓰기 중인 의존성: "+relative)
        hashes[relative]=hashlib.sha256(before).hexdigest()
        if source.suffix in (".gd",".tscn",".tres",".gdshader",".json"):
            for dep in re.findall(r'res://([^"\s\)]+)',before.decode("utf-8")):
                if (project/dep).is_file(): copy(dep)
    for path in (project/"assets/generated/park_vegetation").rglob("*"):
        if path.is_file() and path.suffix not in (".import",".uid"): copy(path.relative_to(project).as_posix())
    for folder in ("trees","bamboo"):
        for path in (project/"assets/generated"/folder).glob("*.scn"): copy(path.relative_to(project).as_posix())
    for name in ("check.gd","capture.gd"): shutil.copyfile(Path(__file__).with_name(name),stage/name)
    (stage/"project.godot").write_text('config_version=5\n[application]\nconfig/name="Park fixture"\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n',encoding="utf-8")
    env=os.environ.copy(); env["APPDATA"]=str(stage/"appdata"); env["LOCALAPPDATA"]=str(stage/"localdata")
    engine=str(root/"tools/godot/Godot_v4.3-stable_win64_console.exe")
    for name,args in (("import",["--headless","--editor","--import"]),
                      ("check",["--position","-32000,-32000","--script","res://check.gd"]),
                      ("capture",["--position","-32000,-32000","--script","res://capture.gd"])):
        result=subprocess.run([engine,"--path",str(stage),*args],capture_output=True,text=True,encoding="utf-8",
            env=env,timeout=60,creationflags=subprocess.CREATE_NO_WINDOW)
        log=result.stdout+result.stderr
        (report/f"{name}.log").write_text(log,encoding="utf-8")
        if result.returncode or "SCRIPT ERROR" in log or "ERROR:" in log: raise RuntimeError(log[-6500:])
        print(log[-1500:])
    for relative,expected in hashes.items():
        if hashlib.sha256((project/relative).read_bytes()).hexdigest()!=expected: raise RuntimeError("원본 변경 감지: "+relative)
    for path in stage.glob("*.png"): shutil.copyfile(path,report/path.name)
    (report/"source_hashes.json").write_text(json.dumps(hashes,indent=2),encoding="utf-8")


if __name__=="__main__": main()
