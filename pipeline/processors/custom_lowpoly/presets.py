"""원본 생성기를 보존하고 작업 공간의 복사본만 단순화한다."""
PYTHON = {
 "industrial/preview.py": [("범용 공단 에셋", "커스텀 경량 에셋"), ("} triangles", "} 삼각형")],
 "vessels/mesh.py": [("axis = [b[i]-a[i] for i in range(3)]", "segments = min(8, segments)\n        axis = [b[i]-a[i] for i in range(3)]")],
 "vessels/designs.py": [("range(9)", "range(3)"), ("i*.075", "i*.30"), ("for offset in (-4,-2,0,2,4):", "for offset in ():")],
 "industrial/geometry.py": [("(8 if hemisphere else 16), 24", "(4 if hemisphere else 8), 12"), ("segments=24", "segments=8"), ("range(16)", "range(8)"), ("math.pi/8", "math.pi/4"), ("range(24)", "range(8)"), ("math.pi/12", "math.pi/4"), ("top/.4", "top/1.6"), ("i*.4", "i*1.6")],
 "industrial/structures.py": [("rows,segments=16,32", "rows,segments=4,12"), ("point(0,i*2)", "point(0,i*segments/16)"), ("range(8)", "range(3)"), ("range(-84,85,12)", "range(-84,85,36)")],
 "industrial/factories.py": [("int(length/2),8)", "int(length/2),24)"), ("range(1,6)", "range(1,6,2)")],
 "industrial/cranes.py": [("abs(x1-x0)/3", "abs(x1-x0)/12")],
 "industrial/pipes.py": [("i*math.pi/16", "i*math.pi/6"), ("range(9)", "range(4)")],
 "wolsong/design.py": [("segments, rings = 40, 10", "segments, rings = 12, 3"), ("range(-310,320,18)", "range(-310,320,54)")],
 "taehwagang/station.py": [("range(-52,53,4)", "range(-52,53,12)"), ("range(28)", "range(8)"), ("width/28", "width/8")],
 "taehwagang/rail_yard.py": [("range(-279,-31,2)", "range(-279,-31,8)"), ("range(-278,-28,12)", "range(-278,-28,36)")],
}
GODOT = {
 "heritage_mesh_builder.gd": [("height / 0.65", "height / 2.4"), ("(2.0 - 0.4 * float(row) / courses)", "(8.0 - 1.6 * float(row) / courses)"), ("length / 2.0", "length / 8.0"), ("range(45)", "range(7)"), ("/ 44.0", "/ 6.0"), ('"stone%d" % random.randi_range(0, 4)', '"stone2"')],
 "heritage_model_builder.gd": [("range(23)", "range(7)"), ("i * 0.527", "i * 1.93")],
 "airport_mesh_builder.gd": [("range(33)", "range(9)"), ("/ 32.0", "/ 8.0")],
 "airfield_surface_builder.gd": [("width / 10", "width / 30"), ("depth / 20", "depth / 60"), ("a.distance_to(b) / 10", "a.distance_to(b) / 30")],
 "regional_airport_mesh_builder.gd": [('const Layout = preload', 'const RunwayLabel = preload("res://scripts/terrain/lowpoly_runway_label.gd")\nconst Layout = preload'), ('_surfaces.marking.append_from(text, 0, Transform3D(Basis(side * sign_value, -direction * sign_value, Vector3.UP), origin))', 'RunwayLabel.append(_surfaces.marking, designations[end_index], Transform3D(Basis(side * sign_value, -direction * sign_value, Vector3.UP), origin))'),("a.distance_to(b) / 8", "a.distance_to(b) / 24"), ("int(length), 60", "int(length), 120")],
}


def patch(base, table):
    for name, replacements in table.items():
        path = base / name
        source = path.read_text(encoding="utf-8")
        for before, after in replacements:
            if before not in source:
                raise RuntimeError(f"생성기 수정 지점 확인 필요: {name}: {before}")
            source = source.replace(before, after)
        path.write_text(source, encoding="utf-8")
