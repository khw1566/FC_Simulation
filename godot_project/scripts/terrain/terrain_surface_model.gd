extends RefCounted
class_name TerrainSurfaceModel

## 화면 최상세(LOD0) 지형 메시와 같은 청크 분할·격자·대각선 보간으로 전체 높이맵의 표면 고도를 계산한다.
## 원해상도 높이맵을 직접 보간하면 수십 m 간격 메시 정점 사이에서 보이는 지면과 최대 수십 m 어긋난다.
## 작업 스레드에서 읽기 전용으로 호출하므로 바인딩한 높이맵은 이후 수정하지 않는다.
var _image: Image
var _world := 1.0
var _chunks := Vector2i.ONE
var _resolution := 128
var _low := 0.0
var _high := 1.0

func _init(image: Image, world_size: float, chunks: Vector2i, resolution: int, low: float, high: float) -> void:
	_image = image
	_world = world_size
	_chunks = chunks
	_resolution = maxi(1, resolution)
	_low = low
	_high = high

func height(world_x: float, world_z: float) -> float:
	var w := _image.get_width()
	var h := _image.get_height()
	var uv := Vector2(world_x, world_z) / _world + Vector2(0.5, 0.5)
	var coord := Vector2i(clampi(floori(uv.x * _chunks.x), 0, _chunks.x - 1), clampi(floori(uv.y * _chunks.y), 0, _chunks.y - 1))
	# 지형 관리자의 청크 부분 이미지와 같은 원점·1픽셀 겹침 크기
	var tile := Vector2i(w / _chunks.x, h / _chunks.y)
	var origin := coord * tile
	var span := Vector2i(mini(tile.x + 1, w - origin.x), mini(tile.y + 1, h - origin.y))
	var local := (uv * Vector2(_chunks) - Vector2(coord)).clamp(Vector2.ZERO, Vector2.ONE)
	var grid := local * _resolution
	var cell := grid.floor().min(Vector2.ONE * (_resolution - 1))
	var f := grid - cell
	var a := _corner(cell / _resolution, origin, span)
	var b := _corner((cell + Vector2(1, 0)) / _resolution, origin, span)
	var c := _corner((cell + Vector2(0, 1)) / _resolution, origin, span)
	var d := _corner((cell + Vector2(1, 1)) / _resolution, origin, span)
	var value := a + f.x * (b - a) + f.y * (c - a) if f.x + f.y <= 1.0 else d + (1.0 - f.x) * (c - d) + (1.0 - f.y) * (b - d)
	return _low + value * (_high - _low)

## TerrainChunkMesher.sample_bilinear과 같은 에르미트 보간을 청크 부분 이미지 대신 전체 이미지 좌표로 계산한다.
func _corner(uv: Vector2, origin: Vector2i, span: Vector2i) -> float:
	var fx := clampf(uv.x * float(span.x - 1), 0.0, float(span.x - 1))
	var fy := clampf(uv.y * float(span.y - 1), 0.0, float(span.y - 1))
	var x0 := int(fx)
	var y0 := int(fy)
	var x1 := mini(x0 + 1, span.x - 1)
	var y1 := mini(y0 + 1, span.y - 1)
	var dx := fx - float(x0)
	var dy := fy - float(y0)
	dx = dx * dx * (3.0 - 2.0 * dx)
	dy = dy * dy * (3.0 - 2.0 * dy)
	var top := lerpf(_image.get_pixel(origin.x + x0, origin.y + y0).r, _image.get_pixel(origin.x + x1, origin.y + y0).r, dx)
	var bottom := lerpf(_image.get_pixel(origin.x + x0, origin.y + y1).r, _image.get_pixel(origin.x + x1, origin.y + y1).r, dx)
	return lerpf(top, bottom, dy)
