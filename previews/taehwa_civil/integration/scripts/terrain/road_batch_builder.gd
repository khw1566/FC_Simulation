extends RefCounted
class_name RoadBatchBuilder

## 스트리밍 도로 배치의 메시 배열 계산과 노드 조립.
## compute()는 장면 트리를 건드리지 않으므로 작업 스레드에서 실행한다.
## 교량 충돌 형상도 계산 단계에서 만들어 렌더링 메시를 다시 읽지 않는다.
const RoadMeshBuilder = preload("res://scripts/terrain/road_mesh_builder.gd")
const RoadClassifier = preload("res://scripts/terrain/road_segment_classifier.gd")
const VisibilityPolicy = preload("res://scripts/terrain/road_visibility_policy.gd")
const WALKING_TYPES := ["footway", "path", "steps", "pedestrian", "bridleway", "corridor"]
const SURFACE_SPLIT := 1500
# 벡터 스트림의 이탈 해제 여유 거리와 같은 값
const PAVED_EXTRA_RANGE := 4500.0

## 도로 메타데이터 보정. 멤버를 바꾸지 않으므로 작업 스레드에서 실행할 수 있다.
static func apply_metadata(roads: Array, entries: Dictionary) -> void:
	if entries.is_empty():
		return
	for road in roads:
		var metadata: Dictionary = entries.get(str(road.get("id", "")), {})
		if metadata.is_empty() or metadata.get("points_sha256", "") != JSON.stringify(road.get("points", [])).sha256_text():
			continue
		road["width"] = float(metadata.width)
		road["layer"] = metadata.layer
		road["osm_id"] = metadata.osm_id
		for key in ["bridge", "tunnel", "surface", "structure_tags_verified"]:
			if metadata.has(key):
				road[key] = metadata[key]

## 중복 판정 키를 미리 계산한다. 문자열 생성 비용이 커서 작업 스레드에서 처리한다.
static func attach_geometry_keys(roads: Array) -> void:
	for road in roads:
		road["_geometry_key"] = RoadClassifier.geometry_key(road)

## 도로 목록의 메시 배열을 계산한다. sample_ground(x, z, fallback), sample_water(x, z)는 스레드 안전해야 한다.
static func compute(roads: Array, sample_ground: Callable, sample_water: Callable, terrain_step: Vector2, terrain_origin: Vector2, formed_ground: bool = false) -> Dictionary:
	var result := {"paved": [], "walking": [], "unpaved": [], "tunnel": [], "bridge": [], "bridge_shapes": [], "tunnel_segments": []}
	result["surface_groups"] = {}
	result["formed_ground"] = formed_ground
	var surfaces: Dictionary = {}
	var counts: Dictionary = {}
	var tunnel_st := _begin()
	var bridge_st := _begin()
	var tunnel_count := 0
	var bridge_count := 0
	var tunnel_segments: Array[Dictionary] = []
	for r in roads:
		var raw_pts: Array = r.get("points", [])
		if raw_pts.size() < 2:
			continue
		var width: float = float(r.get("width", 8.0))
		# 1단계: 도로 선분을 곡률 적응형으로 세분화
		var sub_pts: Array[Vector3] = RoadMeshBuilder.subdivide_polyline(raw_pts)
		if sub_pts.size() < 2:
			continue
		# 2단계: 실제 지형 고도 및 수계 마스크 샘플링
		var ground_y_list: Array[float] = []
		var water_mask_list: Array[float] = []
		for p in sub_pts:
			ground_y_list.append(float(sample_ground.call(p.x, p.z, p.y)))
			water_mask_list.append(float(sample_water.call(p.x, p.z)))
		var segment_types := RoadClassifier.classify(r, sub_pts, water_mask_list)
		var first: int = 0
		while first < segment_types.size():
			var kind: int = segment_types[first]
			var last: int = first + 1
			while last < segment_types.size() and segment_types[last] == kind:
				last += 1
			var section: Array[Vector3] = []
			var section_ground: Array[float] = []
			for index in range(first, last + 1):
				section.append(sub_pts[index])
				section_ground.append(ground_y_list[index])
			if kind == 0:
				var road_type := str(r.get("type", ""))
				var surface := str(r.get("surface", ""))
				var loose := surface in ["unpaved", "gravel", "fine_gravel", "dirt", "ground", "sand", "grass", "mud", "compacted"]
				var sealed := surface in ["asphalt", "concrete", "concrete:plates", "paved", "paving_stones", "sett"]
				var key := "walking" if road_type in WALKING_TYPES else ("unpaved" if loose or (road_type == "track" and not sealed) else "paved")
				var clearance: float = 0.24 if key == "walking" else (0.32 if key == "unpaved" else 0.85)
				var tier_name := VisibilityPolicy.tier(r)
				for piece in VisibilityPolicy.pieces(section, section_ground):
					var group := "%s:%s:%d:%d" % [key,tier_name,piece.cell.x,piece.cell.y]
					if not surfaces.has(group):
						surfaces[group] = _begin()
						counts[group] = 0
						result.surface_groups[group] = {"kind":key,"tier":tier_name,"arrays":[]}
					RoadMeshBuilder.build_surface_road(surfaces[group], piece.points, piece.heights, width, sample_ground, terrain_step, terrain_origin, clearance, formed_ground, piece)
					counts[group] += 1
					if counts[group] >= SURFACE_SPLIT:
						_flush(surfaces[group], counts[group], result.surface_groups[group].arrays)
						counts[group] = 0
			elif kind == 1:
				RoadMeshBuilder.build_universal_bridge(bridge_st, section, section_ground, width)
				bridge_count += 1
			else:
				# 광역 수집 데이터의 Y=0은 실측 터널 고도가 아니라 미지정 값이다.
				if str(r.get("id", "")).begins_with("rd_metro_") or r.get("projected_source", false):
					var cumulative: Array[float] = [0.0]
					for index in range(1, section.size()):
						cumulative.append(cumulative[-1] + section[index].distance_to(section[index - 1]))
					for index in range(section.size()):
						section[index].y = lerpf(section_ground[0], section_ground[-1], cumulative[index] / maxf(0.01, cumulative[-1])) + 0.2
				RoadMeshBuilder.build_mountain_tunnel(tunnel_st, section, width, tunnel_segments)
				tunnel_count += 1
			first = last
	for group in surfaces:
		var info: Dictionary = result.surface_groups[group]
		_flush(surfaces[group], counts[group], info.arrays)
		result[info.kind].append_array(info.arrays)
	_flush(tunnel_st, tunnel_count, result.tunnel)
	_flush(bridge_st, bridge_count, result.bridge)
	for arrays in result.bridge:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(arrays[Mesh.ARRAY_VERTEX])
		result.bridge_shapes.append(shape)
	result.tunnel_segments = tunnel_segments
	return result

## 계산 결과로 도로 노드를 만든다. 메인 스레드에서 호출한다.
static func attach(host: Node3D, result: Dictionary) -> Node3D:
	var container := Node3D.new()
	container.name = "RoadsContainer"
	host.add_child(container)
	var materials := {"paved":host.road_material,"walking":host.walking_path_material,"unpaved":host.unpaved_road_material}
	for info in result.get("surface_groups", {}).values():
		for arrays in info.arrays:
			var instance := _instance(container, arrays, materials[info.kind], "%s_%s" % [info.kind,info.tier])
			instance.visibility_range_end = VisibilityPolicy.distance(info.tier,host.max_view_distance)
			instance.visibility_range_end_margin = 200.0
			instance.set_meta("road_visibility_tier", info.tier)
			instance.set_meta("formed_ground", result.get("formed_ground", false))
			host._configure_road_bounds(instance)
	for arrays in result.tunnel:
		_instance(container, arrays, host.tunnel_wall_material, "Tunnels")
	for index in result.bridge.size():
		var bridge := _instance(container, result.bridge[index], host.bridge_truss_material, "Bridges")
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = result.bridge_shapes[index]
		body.add_child(shape)
		bridge.add_child(body)
	return container

static func _instance(container: Node3D, arrays: Array, material: Material, node_name: String) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	container.add_child(instance)
	return instance

static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

static func _flush(st: SurfaceTool, count: int, target: Array) -> void:
	if count <= 0:
		return
	var arrays := st.commit_to_arrays()
	st.clear()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertices = arrays[Mesh.ARRAY_VERTEX]
	if vertices is PackedVector3Array and not vertices.is_empty():
		target.append(arrays)
