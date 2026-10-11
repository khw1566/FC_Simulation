extends RefCounted
## 공항 기반 지형을 청크 메시 생성 전에 정지한다. 원본 래스터는 수정하지 않는다.
const Layout = preload("res://scripts/terrain/regional_airport_layout.gd")

static func apply(image: Image, catalog: Dictionary, meta: Dictionary, min_y: float, max_y: float) -> void:
	var size: float = meta.world_size_meters
	for spec in catalog.airports:
		if not Layout.in_map(spec, meta):
			continue
		var frame := Layout.frame(spec, meta)
		var inverse := frame.affine_inverse()
		var bounds := Layout.bounds(spec)
		var margin := 120.0
		var low := frame * Vector3(bounds.position.x - margin, 0, bounds.position.y - margin)
		var high := frame * Vector3(bounds.end.x + margin, 0, bounds.end.y + margin)
		var x0 := maxi(0, int((low.x / size + 0.5) * (image.get_width() - 1)))
		var x1 := mini(image.get_width() - 1, int(ceil((high.x / size + 0.5) * (image.get_width() - 1))))
		var z0 := maxi(0, int((low.z / size + 0.5) * (image.get_height() - 1)))
		var z1 := mini(image.get_height() - 1, int(ceil((high.z / size + 0.5) * (image.get_height() - 1))))
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				var p := inverse * Vector3((float(x) / (image.get_width() - 1) - 0.5) * size, 0, (float(z) / (image.get_height() - 1) - 0.5) * size)
				var d := (Vector2(p.x, p.z) - bounds.get_center()).abs() - bounds.size / 2
				var distance := Vector2(maxf(d.x, 0), maxf(d.y, 0)).length()
				var weight := 1.0 - smoothstep(0, margin, distance)
				var target := clampf((float(spec.elevation_m) - 0.3 - min_y) / (max_y - min_y), 0, 1)
				image.set_pixel(x, z, Color(lerpf(image.get_pixel(x, z).r, target, weight), 0, 0))
