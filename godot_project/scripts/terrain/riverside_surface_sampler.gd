extends RefCounted

## 화면에 그려지는 지형 메시(최상세 LOD) 표면 높이. 높이맵을 직접 보간하면 수십 m 간격 메시 정점 사이에서
## 보이는 지면과 수 m까지 어긋나 보도가 뜨거나 묻히므로, 청크 메시와 같은 삼각형 보간을 쓴다.
## 보도는 3 km 안에서만 그리고 그 거리의 청크는 항상 최상세 LOD라 LOD 0 표면에 맞춘다.

var _manager: Node3D

func _init(terrain_manager: Node3D) -> void:
	_manager = terrain_manager

func height(world_x: float, world_z: float) -> float:
	var chunk = _chunk_at(world_x, world_z)
	if chunk == null or chunk.heightmap_image == null:
		return float(_manager.get_terrain_elevation(world_x, world_z))
	var resolution: int = chunk.base_resolution
	var uv: Vector2 = (Vector2(world_x - chunk.chunk_center.x, world_z - chunk.chunk_center.z) / chunk.chunk_world_size + Vector2(0.5, 0.5)).clamp(Vector2.ZERO, Vector2.ONE)
	var grid: Vector2 = uv * resolution
	var cell: Vector2 = grid.floor().min(Vector2.ONE * (resolution - 1))
	var f: Vector2 = grid - cell
	var w: int = chunk.heightmap_image.get_width()
	var h: int = chunk.heightmap_image.get_height()
	var a: float = chunk._sample_bilinear(cell.x / resolution, cell.y / resolution, w, h)
	var b: float = chunk._sample_bilinear((cell.x + 1) / resolution, cell.y / resolution, w, h)
	var c: float = chunk._sample_bilinear(cell.x / resolution, (cell.y + 1) / resolution, w, h)
	var d: float = chunk._sample_bilinear((cell.x + 1) / resolution, (cell.y + 1) / resolution, w, h)
	var value: float = a + f.x * (b - a) + f.y * (c - a) if f.x + f.y <= 1.0 else d + (1.0 - f.x) * (c - d) + (1.0 - f.y) * (b - d)
	var surface: float = chunk.elev_min + value * (chunk.elev_max - chunk.elev_min)
	# 넓은 도로의 노반 어깨가 둔치까지 닿으면 지형 메시도 보정되므로 같은 보정을 따른다.
	if chunk.road_grader:
		surface = chunk.road_grader.corrected_height(Vector3(world_x, surface, world_z))
	if chunk.railway_grader:
		surface = chunk.railway_grader.corrected_height(Vector3(world_x, surface, world_z))
	return surface

func _chunk_at(world_x: float, world_z: float):
	if not "active_chunks" in _manager:
		return null
	var size: float = _manager.terrain_world_size
	var uv: Vector2 = Vector2(world_x, world_z) / size + Vector2(0.5, 0.5)
	var nx: int = _manager.grid_chunks_x
	var ny: int = _manager.grid_chunks_y
	var coord := Vector2i(clampi(floori(uv.x * nx), 0, nx - 1), clampi(floori(uv.y * ny), 0, ny - 1))
	return _manager.active_chunks.get(coord)
