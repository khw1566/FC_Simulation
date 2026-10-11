"""도로 전용 도구와 경량 확인 모듈을 기존 색인에 병합한다."""
import json
import sys
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from ulsan_roads.build import ROOT, save


def register():
    modules = []
    for folder in (ROOT/"pipeline/processors/ulsan_roads",ROOT/"pipeline/collectors/ulsan_roads"):
        for path in sorted(folder.glob("*.py")):
            content = path.read_text(encoding="utf-8")
            modules.append({"path":path.relative_to(ROOT).as_posix(),"lines":len(content.splitlines()),
                            "responsibility":content.splitlines()[0].strip('"')})
        save(folder/"module_index.json",{"description":"울산 80km 전 범위 도로 도구","modules":[m for m in modules if Path(m["path"]).parent.as_posix()==folder.relative_to(ROOT).as_posix()]})
    path = ROOT/"module_index.json"
    before = path.read_bytes()
    doc = json.loads(before)
    doc["domains"]["ulsan_80km_roads"] = {"description":"전체 도로 수집·변환·리비전 게시·경량 검증","modules":modules}
    if path.read_bytes()!=before:
        raise RuntimeError("모듈 색인 동시 변경")
    temp=path.with_suffix(".roads.tmp")
    temp.write_text(json.dumps(doc,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    if path.read_bytes()!=before:
        temp.unlink()
        raise RuntimeError("모듈 색인 동시 변경")
    temp.replace(path)
    preview = ROOT/"previews/asset_browser/ulsan_80km_roads_check"
    if preview.exists():
        save(preview/"module_index.json",{"modules":[{"path":"check.gd","responsibility":"대표 6종 도로 메시 생성 확인"}],
             "dependencies":[m.name for m in (preview/"scripts/terrain").glob("*.gd")]})


if __name__=="__main__":
    register()
