extends Node3D
## 생성 단계 전용: 16bit 원본에서 추출한 고도와 터널 마스크를 읽는다.
var height: Image
var mask: Image
var center := Vector2.ZERO
var size := 0.0
var grader: RefCounted

func configure(data: Dictionary) -> void:
	center = Vector2(data.center[0], data.center[1])
	size = float(data.world_size)
	var raw := FileAccess.get_file_as_bytes("res://inputs/height.rf32")
	height = Image.create_from_data(raw.decode_u32(0), raw.decode_u32(4), false, Image.FORMAT_RF, raw.slice(8))
	raw = FileAccess.get_file_as_bytes("res://inputs/void.rgba8")
	mask = Image.create_from_data(raw.decode_u32(0), raw.decode_u32(4), false, Image.FORMAT_RGBA8, raw.slice(8))
	grader = preload("res://scripts/terrain/railway_terrain_grader.gd").new()
	grader.configure(data)

func get_terrain_elevation(x: float, z: float) -> float:
	var uv := ((Vector2(x,z)-center)/size+Vector2.ONE*0.5).clamp(Vector2.ZERO,Vector2.ONE)
	var pixel := uv*float(height.get_width()-1)
	var a := Vector2i(pixel.floor())
	var b := (a+Vector2i.ONE).min(Vector2i.ONE*(height.get_width()-1))
	var f := pixel-Vector2(a)
	var value := lerpf(lerpf(height.get_pixel(a.x,a.y).r,height.get_pixel(b.x,a.y).r,f.x),lerpf(height.get_pixel(a.x,b.y).r,height.get_pixel(b.x,b.y).r,f.x),f.y)
	return grader.corrected_height(Vector3(x,-30.0+value*1330.0,z))

func collision(mesh: ArrayMesh) -> ConcavePolygonShape3D:
	var faces := mesh.get_faces()
	var output := PackedVector3Array()
	for i in range(0,faces.size(),3):
		var a := faces[i]
		var b := faces[i+1]
		var c := faces[i+2]
		var lower := Vector2(a.x,a.z).min(Vector2(b.x,b.z)).min(Vector2(c.x,c.z))
		var upper := Vector2(a.x,a.z).max(Vector2(b.x,b.z)).max(Vector2(c.x,c.z))
		var lo := Vector2i((lower/size+Vector2.ONE*0.5)*float(mask.get_width()-1))
		var hi := Vector2i((upper/size+Vector2.ONE*0.5)*float(mask.get_width()-1))+Vector2i.ONE
		var removed := false
		for y in range(maxi(0,lo.y),mini(mask.get_height(),hi.y+1)):
			for x in range(maxi(0,lo.x),mini(mask.get_width(),hi.x+1)):
				var color := mask.get_pixel(x,y)
				var floor_y := -30.0+(color.r*65280.0+color.g*255.0)/65535.0*1330.0
				if color.b>0.75 and maxf(a.y,maxf(b.y,c.y))>=floor_y and minf(a.y,minf(b.y,c.y))<=floor_y+color.a*255.0:
					removed = true
		if not removed:
			output.append_array(PackedVector3Array([a,b,c]))
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(output)
	return shape
