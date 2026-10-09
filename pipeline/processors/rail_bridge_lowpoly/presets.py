"""격리 복사본에만 적용하는 반복 부재·곡선 경량 설정."""
PATCHES = {
 "railway_track_builder.gd": [("1.2 if slab else 0.75", "6.0 if slab else 4.0")],
 "railway_bridge_geometry.gd": [("length / 1.2", "length / 6.0"), ("length / 8.0", "length / 32.0"), ("length / 2.5", "length / 10.0")],
 "railway_bridge_structures.gd": [("length / 2.0", "length / 8.0"), ("(i + 0.5) * 2)", "(i + 0.5) * 8)"), ("maxi(4, int(ceil(length / 9.0)))", "maxi(3, int(ceil(length / 24.0)))"), ("maxi(16, int(ceil(length / 3.0)))", "8"), ("range(5)", "range(2)"), ("/ 5.0", "/ 2.0")],
 "bridge_landmark_builder.gd": [("length / 8.0", "length / 24.0"), ("range(4)", "range(1)"), ("range(80)", "range(12)"), ("/ 80.0", "/ 12.0"), ("range(40)", "range(8)"), ("/ 40.0", "/ 8.0")],
 "pedestrian_bridge_geometry.gd": [("a.distance_to(b) / 2.0", "a.distance_to(b) / 8.0"), ("range(count * 5)", "range(0)")],
 "seonbawi_bridge_asset.gd": [("length / 2.0", "length / 16.0"), ("i * 2.0", "i * 16.0")],
}

def apply(stage):
    for name, replacements in PATCHES.items():
        path = stage / "scripts/terrain" / name
        source = path.read_text(encoding="utf-8")
        for before, after in replacements:
            if before not in source:
                raise RuntimeError(f"생성기 변경을 확인하세요: {name}: {before}")
            source = source.replace(before, after)
        path.write_text(source, encoding="utf-8")
