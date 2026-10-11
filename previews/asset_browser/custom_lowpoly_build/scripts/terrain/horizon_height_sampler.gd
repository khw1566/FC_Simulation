extends RefCounted
class_name HorizonHeightSampler

## 상세 경계와 실제 광역 Web Mercator 고도 자료를 같은 지도 좌표로 표본화한다.
var map: Dictionary
var local_atlas: Dictionary
var regional_atlas: Dictionary
var regional_values := PackedFloat32Array()

func configure(catalog: Dictionary, map_id: String) -> void:
	map = catalog.maps[map_id]
	local_atlas = catalog.atlases[map.atlas_id]
	regional_atlas = catalog.get("regional", catalog.atlases[map.regional_atlas_id])
	if regional_atlas.has("height_file"):
		regional_values = FileAccess.get_file_as_bytes(regional_atlas.height_file).to_float32_array()

func local_height(x: float, z: float) -> float:
	var size: float = map.world_size_meters
	return _bilinear(local_atlas, x/size+0.5, z/size+0.5)

func height(x: float, z: float) -> float:
	if map.get("flat", false):
		return local_height(0.0, 0.0)
	var bbox: Dictionary = map.bbox
	var size: float = map.world_size_meters
	var lon := lerpf(bbox.west, bbox.east, x/size+0.5)
	var lat := lerpf(bbox.north, bbox.south, z/size+0.5)
	var region: Dictionary = regional_atlas.bbox
	var u := (lon-float(region.west))/(float(region.east)-float(region.west))
	var v := (mercator(region.north)-mercator(lat))/(mercator(region.north)-mercator(region.south))
	# 자료 밖에는 산맥을 복제하지 않는다.
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return -1.0
	return _bilinear(regional_atlas, u, v)

func mercator(latitude: float) -> float:
	return log(tan(PI*0.25+deg_to_rad(clampf(latitude,-85.0,85.0))*0.5))

func _bilinear(atlas: Dictionary, u: float, v: float) -> float:
	var n: int = atlas.resolution
	var fx := clampf(u, 0.0, 1.0)*float(n-1)
	var fy := clampf(v, 0.0, 1.0)*float(n-1)
	var x := int(fx)
	var y := int(fy)
	var x1 := mini(x+1, n-1)
	var y1 := mini(y+1, n-1)
	var top: float
	var bottom: float
	if atlas.has("height_file") and regional_values.size() == n*n:
		top = lerpf(regional_values[y*n+x], regional_values[y*n+x1], fx-x)
		bottom = lerpf(regional_values[y1*n+x], regional_values[y1*n+x1], fx-x)
	else:
		top = lerpf(float(atlas.heights[y][x]), float(atlas.heights[y][x1]), fx-x)
		bottom = lerpf(float(atlas.heights[y1][x]), float(atlas.heights[y1][x1]), fx-x)
	return lerpf(top, bottom, fy-y)
