"""활성 SVG 도로 계층과 확대 타일의 산출물을 확인한다."""
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from ulsan_roads.build import ROOT,read,save


def check():
    meta=read(ROOT/"godot_project/assets/maps/ulsan_metro_80km/map_meta.json")
    folder=(ROOT/"godot_project"/meta["assets"]["tactical_map"].removeprefix("res://")).parent
    tree=ET.parse(folder/"map.svg")
    group=next(g for g in tree.iter() if g.get("id")=="roads")
    tiles=list((folder/"tiles").glob("*.svg"))
    assert len(tiles)==256
    count=meta["coverage"]["roads"]["runtime_roads"]
    assert read(folder/"tiles.json")["counts"]["roads"]==count
    # 자가 교차 선형은 클리핑 과정에서 MultiLineString이 되어 여러 path로 표현된다.
    assert len(group)>=count
    for tile in tiles:
        assert ET.parse(tile).getroot().get("viewBox")
    result={"passed":True,"road_features":count,"rendered_paths":len(group),"tiles":len(tiles),"svg":meta["assets"]["tactical_map"],
            "preview":str((folder/"preview.png").resolve())}
    save(ROOT/"results/ulsan_80km_roads/map_check.json",result)
    print(json.dumps(result,ensure_ascii=False),flush=True)


if __name__=="__main__":
    check()
