extends SceneTree
const Batch = preload("res://scripts/terrain/road_batch_builder.gd")
var failed := false
func _initialize() -> void:
    var records: Array = []
    var roads: Array = JSON.parse_string(FileAccess.get_file_as_string("res://fixtures.json"))
    for road in roads:
        var origin := Vector3(float(road.points[0][0]), 0, float(road.points[0][2]))
        var heights: Array = road.fixture_ground
        var average: float = 0.0
        for h in heights:
            average += float(h)
        average /= heights.size()
        for p in road.points:
            p[0] = float(p[0])-origin.x
            p[2] = float(p[2])-origin.z
        # 실제 지형 높이의 대표 평균을 사용한 경량 메시 확인이다.
        var ground := func(_x, _z, _fallback): return average
        var water := func(_x, _z): return 0.0
        var result: Dictionary = Batch.compute([road], ground, water, Vector2(24,24), Vector2.ZERO)
        if road.has("expected_kind") and result[road.expected_kind].is_empty():
            failed = true
        var triangles: int = 0
        for key in ["paved", "walking", "unpaved", "tunnel", "bridge"]:
            for arrays in result[key]:
                var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
                for vertex in verts:
                    if not vertex.is_finite():
                        failed = true
                var indices = arrays[Mesh.ARRAY_INDEX]
                triangles += indices.size()/3 if indices is PackedInt32Array and indices.size()>0 else verts.size()/3
        if triangles == 0:
            failed = true
        records.append({"label":road.fixture_label,"osm_id":road.osm_id,"triangles":triangles})
    var file := FileAccess.open("res://mesh_check.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"passed":not failed,"cases":records,"full_world_run":false,"ground_basis":"source DEM point mean"},"  "))
    file.close()
    print("ROAD_FIXTURE_CHECK ",not failed)
    quit(1 if failed else 0)
