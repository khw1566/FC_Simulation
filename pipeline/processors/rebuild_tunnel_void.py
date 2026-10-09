"""기존 철도 종단(alignment.json)으로 터널 지형 제거 마스크만 다시 생성한다."""
import hashlib
import json
import os
from pathlib import Path
from PIL import Image
from build_railway_alignment import RailwayAlignmentBuilder

ROOT = Path(__file__).resolve().parents[2]


def main():
    railway = ROOT/"godot_project/assets/generated/railway"
    meta = json.loads((ROOT/"godot_project/assets/maps/ulsan_metro_80km/map_meta.json").read_text(encoding="utf-8-sig"))
    alignment = json.loads((railway/"alignment.json").read_text(encoding="utf-8"))
    target = railway/"tunnel_void.png"
    with Image.open(target) as image:
        shape = (image.height, image.width)
    void = RailwayAlignmentBuilder().build_void(shape, alignment["tracks"], alignment["tunnels"], meta["world_size_meters"], meta)
    temp = target.with_name(target.name+f".{os.getpid()}.tmp.png")
    Image.fromarray(void).save(temp)
    os.replace(temp, target)
    # 공유 매니페스트의 마스크 해시를 새 파일에 맞춘다.
    shared = ROOT/"godot_project/assets/generated/manifest.json"
    manifest = json.loads(shared.read_text(encoding="utf-8-sig"))
    record = manifest.get("assets", {}).get("railway_tunnel_void")
    if record is not None:
        record["sha256"] = hashlib.sha256(target.read_bytes()).hexdigest()
        shared.write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({"file": str(target.relative_to(ROOT)), "tunnel_pixels": int((void[..., 2] > 191).sum())}))


if __name__ == "__main__":
    main()
