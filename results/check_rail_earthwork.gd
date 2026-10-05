extends SceneTree

const Grader = preload("res://scripts/terrain/railway_terrain_grader.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var grader := Grader.new()
	grader.configure({"tracks":[{"bridge":false,"tunnel":false,"points":[[-120,5,-18],[120,10,32]]}]})
	var failures: Array[String] = []
	var samples := 0
	var vertices := 0
	for resolution in [1,2,4]:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var cells := grader.cells(Vector2(-64,-64),128,resolution)
		var step: float = 128.0/resolution
		for cy in resolution:
			for cx in resolution:
				var a := Vector3(-64+cx*step,40,-64+cy*step)
				var b := a+Vector3(step,0,0)
				var c := a+Vector3(0,0,step)
				var d := a+Vector3(step,0,step)
				var segments: Array = cells.get(Vector2i(cx,cy),[])
				grader.add_triangle(surface,a,b,c,Vector3.ZERO,segments)
				grader.add_triangle(surface,b,d,c,Vector3.ZERO,segments)
		var mesh := surface.commit()
		var faces := mesh.get_faces()
		vertices += faces.size()
		for index in range(10,90):
			var t := float(index)/100.0
			var point := Vector3(-120+240*t,5+5*t,-18+50*t)
			if absf(point.x)>60:
				continue
			for offset in [-1.9,0.0,1.9]:
				var target := Vector2(point.x,point.z+offset)
				var found := false
				for triangle in range(0,faces.size(),3):
					var a := faces[triangle]
					var b := faces[triangle+1]
					var c := faces[triangle+2]
					var av := Vector2(a.x,a.z)
					var bv := Vector2(b.x,b.z)-av
					var cv := Vector2(c.x,c.z)-av
					var relative := target-av
					var denominator := bv.cross(cv)
					if absf(denominator)<0.00001:
						continue
					var u := relative.cross(cv)/denominator
					var v := bv.cross(relative)/denominator
					if u>=-0.00001 and v>=-0.00001 and u+v<=1.00001:
						var height := a.y+u*(b.y-a.y)+v*(c.y-a.y)
						if height>point.y-0.35:
							failures.append("LOD %d에서 지형이 철로 바닥을 덮음" % resolution)
						found = true
						break
				if not found:
					failures.append("지형에 빈 구멍 발생")
				samples += 1
	if not is_equal_approx(grader.corrected_height(Vector3(0,40,-63)),40):
		failures.append("철로 밖 지형 변경")
	var structures := Grader.new()
	structures.configure({"tracks":[{"bridge":true,"tunnel":false,"points":[[-120,5,-18],[120,10,32]]},{"bridge":false,"tunnel":true,"points":[[-120,5,-18],[120,10,32]]}]})
	if not is_equal_approx(structures.corrected_height(Vector3(0,40,7)),40):
		failures.append("교량 또는 터널 지형 변경")
	print(JSON.stringify({"samples":samples,"vertices":vertices,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
