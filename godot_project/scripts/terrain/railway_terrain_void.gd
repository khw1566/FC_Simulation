extends RefCounted
class_name RailwayTerrainVoid

const SourceSignature = preload("res://scripts/terrain/source_signature.gd")
const PATH = "res://assets/generated/railway/tunnel_void.png"
static var _image: Image
static var _bounds: Dictionary = {}
static var _bounds_ready := false
const BUCKET_SIZE := 512.0

static func configure_bounds(_data: Dictionary) -> void:
	_bounds.clear()
	_bounds_ready = false
	var manifest_path := "res://assets/generated/terrain_quality/ulsan_metro_80km/light/manifest.json"
	if not FileAccess.file_exists(manifest_path):
		return
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary:
		return
	var record: Dictionary = manifest.get("assets", {}).get("tunnel_buckets", {})
	var path := str(record.get("file_path", ""))
	if not FileAccess.file_exists(path):
		return
	var index = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not index is Dictionary or int(index.get("bucket_size", 0)) != int(BUCKET_SIZE):
		return
	var source := FileAccess.open(PATH, FileAccess.READ)
	if source == null or not SourceSignature.matches(PATH, source.get_length(), int(index.get("source_size", -1)), int(index.get("source_modified", -1)), str(index.get("source_sha256", ""))):
		return
	for bucket in index.get("buckets", []):
		_bounds[Vector2i(int(bucket[0]), int(bucket[1]))] = true
	_bounds_ready = true

static func _has_tunnel(lower: Vector2, upper: Vector2) -> bool:
	if not _bounds_ready:
		return true
	for y in range(floori(lower.y / BUCKET_SIZE), floori(upper.y / BUCKET_SIZE) + 1):
		for x in range(floori(lower.x / BUCKET_SIZE), floori(upper.x / BUCKET_SIZE) + 1):
			if _bounds.has(Vector2i(x, y)):
				return true
	return false

static func enabled() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var selection := tree.root.get_node_or_null("MapSelectionService") if tree else null
	return selection != null and selection.selected_map != null and selection.selected_map.id=="ulsan_metro_80km"

static func image() -> Image:
	if _image==null and FileAccess.file_exists(PATH):
		_image = Image.load_from_file(PATH)
	return _image

static func floor_at(point: Vector3) -> float:
	if not enabled() or image()==null:
		return INF
	var uv := Vector2(point.x,point.z)/80000.0+Vector2(0.5,0.5)
	if uv.x<0 or uv.x>1 or uv.y<0 or uv.y>1:
		return INF
	var color := _image.get_pixel(clampi(roundi(uv.x*(_image.get_width()-1)),0,_image.get_width()-1),clampi(roundi(uv.y*(_image.get_height()-1)),0,_image.get_height()-1))
	if color.b<0.75:
		return INF
	var floor := -30.0+(color.r*65280.0+color.g*255.0)/65535.0*1330.0
	if point.y<floor-1.0 or point.y>floor+color.a*255.0:
		return INF
	return floor+1.5

static func collision_shape(mesh: ArrayMesh,transform: Transform3D) -> Shape3D:
	if not enabled() or image()==null:
		return mesh.create_trimesh_shape()
	var faces := mesh.get_faces()
	var result := PackedVector3Array()
	for i in range(0,faces.size(),3):
		var a := transform*faces[i]
		var b := transform*faces[i+1]
		var c := transform*faces[i+2]
		if intersects(a,b,c):
			continue
		result.append_array(PackedVector3Array([faces[i],faces[i+1],faces[i+2]]))
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(result)
	return shape

static func intersects(a: Vector3,b: Vector3,c: Vector3) -> bool:
	var lower := Vector2(minf(a.x,minf(b.x,c.x)),minf(a.z,minf(b.z,c.z)))
	var upper := Vector2(maxf(a.x,maxf(b.x,c.x)),maxf(a.z,maxf(b.z,c.z)))
	if not _has_tunnel(lower, upper):
		return false
	var size := _image.get_width()-1
	var start := Vector2i((lower/80000.0+Vector2(0.5,0.5))*size)
	var finish := Vector2i((upper/80000.0+Vector2(0.5,0.5))*size)+Vector2i.ONE
	var ymin := minf(a.y,minf(b.y,c.y))
	var ymax := maxf(a.y,maxf(b.y,c.y))
	for y in range(maxi(0,start.y),mini(size+1,finish.y+1)):
		for x in range(maxi(0,start.x),mini(size+1,finish.x+1)):
			var color := _image.get_pixel(x,y)
			if color.b>0.25:
				var floor := -30.0+(color.r*65280.0+color.g*255.0)/65535.0*1330.0
				if color.b>0.75 and ymax>=floor and ymin<=floor+color.a*255.0:
					return true
	return false
