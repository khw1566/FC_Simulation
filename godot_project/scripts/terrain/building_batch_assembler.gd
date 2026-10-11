extends RefCounted
class_name BuildingBatchAssembler

## 스트리밍 건물 배치를 1,500m 공간 청크로 나누고 메시 노드를 붙인다.
## 대체 판정(공항·유적·공단·철도 랜드마크)과 노드 생성은 메인 스레드에서,
## 메시 배열 계산은 compute()로 분리해 작업 스레드에서 실행할 수 있게 한다.
const BuildingMeshBuilder = preload("res://scripts/terrain/building_mesh_builder.gd")
const CampusGround = preload("res://scripts/terrain/campus_ground_overlay.gd")
const CampusPolicy = preload("res://scripts/terrain/campus_building_policy.gd")

## 대체 대상을 빼고 청크 좌표별로 건물을 묶는다. 메인 스레드에서 호출한다.
static func group(host: Node3D, buildings: Array) -> Dictionary:
	if host.buildings_roads_path.contains("ulsan_uc_west"):
		CampusPolicy.mark_imagery_candidates(buildings)
		if not host._campus_ground_loaded:
			CampusGround.build(host, host._sample_ground_height, 5000.0 / 512.0, -2500.0)
			host._campus_ground_loaded = true
	var chunks: Dictionary = {}
	for b in buildings:
		# 수집 자료의 0 높이는 미지정 값일 수 있다. 실제 기초 높이는 메시 계산에서 지형을 샘플링해 정한다.
		var center_arr: Array = b.get("center", [0, 0, 0])
		var cx: float = float(center_arr[0])
		var cz: float = float(center_arr[2])
		var poly_arr: Array = b.get("polygon", [])
		if poly_arr.size() >= 3:
			cx = 0.0
			cz = 0.0
			for p in poly_arr:
				if p is Array and p.size() >= 2:
					cx += float(p[0])
					cz += float(p[1])
			cx /= float(poly_arr.size())
			cz /= float(poly_arr.size())
		if host._airport_manager != null and host._airport_manager.replaces_building(cx, cz):
			continue
		if host._heritage_manager != null and host._heritage_manager.replaces_building(cx, cz, str(b.get("name", ""))):
			continue
		if host._industrial_suppression.replaces(cx, cz):
			continue
		if host._bridge_manager != null and host._bridge_manager.replaces_building(cx, cz):
			continue
		if host._railway_manager != null and host._railway_manager.landmarks != null and host._railway_manager.landmarks.replaces_building(cx, cz):
			continue
		var coord := Vector2i(int(floor(cx / host.chunk_size)), int(floor(cz / host.chunk_size)))
		if not chunks.has(coord):
			chunks[coord] = []
		chunks[coord].append(b)
	return chunks

## 청크별 메시 배열을 계산한다. 장면 트리를 바꾸지 않으므로 작업 스레드에서 실행할 수 있다.
static func compute(chunks: Dictionary, sample_ground: Callable) -> Dictionary:
	var results := {}
	for coord in chunks:
		results[coord] = BuildingMeshBuilder.compute_arrays(chunks[coord], sample_ground)
	return results

## 계산 결과로 청크 노드를 만들어 붙인다. 메인 스레드에서 호출한다.
static func attach(host: Node3D, results: Dictionary) -> Node3D:
	if results.is_empty():
		return null
	var container := Node3D.new()
	container.name = "BuildingsContainer"
	host.add_child(container)
	host._batch_serial += 1
	var serial: int = host._batch_serial
	for coord in results:
		var chunk_node := Node3D.new()
		chunk_node.name = "Chunk_%d_%d" % [coord.x, coord.y]
		container.add_child(chunk_node)
		var chunk_center := Vector2((float(coord.x) + 0.5) * host.chunk_size, (float(coord.y) + 0.5) * host.chunk_size)
		BuildingMeshBuilder.apply_arrays(results[coord], chunk_node, host.building_material, host._sample_ground_height)
		_register(host,chunk_node,coord,chunk_center,serial)
	host._last_cull_check_pos = Vector3.INF
	return container

static func attach_streamed(host: Node3D, results: Dictionary) -> Node3D:
	if results.is_empty():
		return null
	var container := Node3D.new()
	container.name = "BuildingsContainer"
	host.add_child(container)
	host._batch_serial += 1
	var serial: int = host._batch_serial
	for coord in results:
		if not is_instance_valid(container) or not container.is_inside_tree():
			return null
		var chunk_node := Node3D.new()
		chunk_node.name = "Chunk_%d_%d" % [coord.x,coord.y]
		chunk_node.visible = false
		container.add_child(chunk_node)
		await BuildingMeshBuilder.apply_arrays_streamed(results[coord],chunk_node,host.building_material,host._sample_ground_height)
		if not is_instance_valid(chunk_node) or not chunk_node.is_inside_tree():
			return null
		var center := Vector2((float(coord.x)+.5)*host.chunk_size,(float(coord.y)+.5)*host.chunk_size)
		_register(host,chunk_node,coord,center,serial)
		chunk_node.visible = true if host.player_node==null else chunk_node.visible
	host._last_cull_check_pos = Vector3.INF
	return container

static func _register(host: Node3D, node: Node3D, coord: Vector2i, center: Vector2, serial: int) -> void:
	var info := {"node":node,"center_2d":center,"minor":node.get_node_or_null("MinorBuildings")}
	host._building_chunk_nodes[Vector3i(coord.x,coord.y,serial)] = info
	var player: Node3D = host.player_node
	if player:
		node.visible = false
		host._apply_chunk_visibility(info,Vector2(player.global_position.x,player.global_position.z),player.global_position.y>=host._high_cull_altitude)
