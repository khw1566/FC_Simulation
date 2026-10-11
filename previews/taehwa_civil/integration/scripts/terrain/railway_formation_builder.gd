extends RefCounted
class_name RailwayFormationBuilder

## 낮은 지형 LOD에서도 도상이 뜨지 않도록 측면과 매립 기초를 연결한다.
static func build(points: PackedVector3Array,terrain: Node3D,structure: Dictionary) -> MeshInstance3D:
	if points.size()<2 or bool(structure.get("bridge",false)):
		return null
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1,points.size()):
		var a := points[i-1]
		var b := points[i]
		var side := (b-a).cross(Vector3.UP).normalized()
		if side.length_squared()<0.1:
			continue
		for sign in [-1.0,1.0]:
			var top_a: Vector3 = a+side*sign*1.95+Vector3.DOWN*0.14
			var top_b: Vector3 = b+side*sign*1.95+Vector3.DOWN*0.14
			var foot_a: Vector3 = a+side*sign*5.5
			var foot_b: Vector3 = b+side*sign*5.5
			if bool(structure.get("tunnel",false)):
				foot_a.y = a.y-0.55
				foot_b.y = b.y-0.55
			else:
				foot_a.y = minf(a.y-1.0,terrain.get_terrain_elevation(foot_a.x,foot_a.z)-1.0)
				foot_b.y = minf(b.y-1.0,terrain.get_terrain_elevation(foot_b.x,foot_b.z)-1.0)
			for p in [top_a,top_b,foot_b,top_a,foot_b,foot_a]:
				var normal := (top_b-top_a).cross(foot_b-top_a).normalized()
				if normal.y<0.0:
					normal = -normal
				surface.set_normal(normal)
				surface.add_vertex(p)
	var instance := MeshInstance3D.new()
	instance.name = "RailFormation"
	instance.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.34,0.32,0.28)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = 12000.0
	return instance
