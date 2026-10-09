"""원본 임포터 없이 격리 복사본의 GLB·씬·포트·조립을 확인한다."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[3]
PROJECT=ROOT/"godot_project"
STAGE=ROOT/"previews/asset_browser/harbor_assets_check"


def copy(relative,seen):
    if relative in seen: return
    seen.add(relative)
    source=PROJECT/relative; target=STAGE/relative
    target.parent.mkdir(parents=True,exist_ok=True)
    before=source.read_bytes(); target.write_bytes(before)
    if source.read_bytes()!=before: raise RuntimeError("원본 쓰기 중 보류: "+relative)
    if source.suffix in (".tscn",".gd",".gdshader"):
        text=before.decode("utf-8")
        for resource in re.findall(r'res://([^"\s]+\.(?:tscn|glb|gd|gdshader))',text): copy(resource,seen)
        if source.suffix==".tscn":
            target.write_text(text.replace('.glb"','.scn"'),encoding="utf-8")


def main():
    STAGE.mkdir(parents=True,exist_ok=True)
    descriptor=os.open(STAGE/"writer.lock",os.O_CREAT|os.O_EXCL|os.O_WRONLY)
    try:
        seen=set()
        folder="assets/generated/harbor_assets/"
        for source in (PROJECT/folder).glob("*.tscn"): copy(folder+source.name,seen)
        shutil.copy2(PROJECT/folder/"catalog.json",STAGE/"catalog.json")
        shutil.copy2(Path(__file__).parent/"verify.gd",STAGE/"verify.gd")
        (STAGE/"glbs.json").write_text(json.dumps(sorted(p for p in seen if p.endswith(".glb"))),encoding="utf-8")
        (STAGE/"project.godot").write_text('config_version=5\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',encoding="utf-8")
        env=os.environ.copy(); env["APPDATA"]=str(STAGE/"user_data"); Path(env["APPDATA"]).mkdir(exist_ok=True)
        result=subprocess.run([str(ROOT/"tools/godot/Godot_v4.3-stable_win64_console.exe"),"--path",str(STAGE),
            "--rendering-method","gl_compatibility","--resolution","64x64","--position","-32000,-32000", "--script","res://verify.gd"],
            env=env,capture_output=True,text=True,encoding="utf-8",timeout=90,creationflags=subprocess.CREATE_NO_WINDOW)
        (STAGE/"verify.log").write_text(result.stdout+result.stderr,encoding="utf-8")
        print(result.stdout.strip())
        if result.returncode or "SCRIPT ERROR" in result.stderr or "ERROR:" in result.stderr: raise RuntimeError(result.stdout+result.stderr)
    finally:
        os.close(descriptor); (STAGE/"writer.lock").unlink()


if __name__=="__main__": main()
