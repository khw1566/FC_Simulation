extends RefCounted
class_name RailwayTerrainVoid

const PATH = "res://assets/generated/railway/tunnel_void.png"
static var _image: Image

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
