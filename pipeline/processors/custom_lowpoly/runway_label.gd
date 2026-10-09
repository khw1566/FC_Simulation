extends RefCounted
## 입체 글자를 평면 선분으로 바꾸되 활주로 번호와 L/R 구분을 유지한다.
const SEGMENTS = {"0": "abcedf", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc",
	"5": "afgcd", "6": "afgecd", "7": "abc", "8": "abcdefg", "9": "abfgcd",
	"L": "fed", "R": "abfge", "C": "afed"}
const LINES = {"a": [Vector2(-2, 5), Vector2(2, 5)], "g": [Vector2(-2, 0), Vector2(2, 0)],
	"d": [Vector2(-2, -5), Vector2(2, -5)], "f": [Vector2(-2.5, 4.5), Vector2(-2.5, 0.5)],
	"e": [Vector2(-2.5, -0.5), Vector2(-2.5, -4.5)], "b": [Vector2(2.5, 4.5), Vector2(2.5, 0.5)],
	"c": [Vector2(2.5, -0.5), Vector2(2.5, -4.5)]}

static func append(surface: SurfaceTool, value: String, pose: Transform3D) -> void:
	for index in value.length():
		var offset := Vector2((index - (value.length() - 1) * 0.5) * 7.0, 0)
		for segment in str(SEGMENTS.get(value[index], "")):
			var pair: Array = LINES[segment]
			strip(surface, pair[0] + offset, pair[1] + offset, pose)
		if value[index] == "R":
			strip(surface, offset, offset + Vector2(2.5, -5), pose)

static func strip(surface: SurfaceTool, a: Vector2, b: Vector2, pose: Transform3D) -> void:
	var side := (b - a).normalized().orthogonal() * 0.45
	var points := [a - side, a + side, b + side, b - side]
	for index in [0, 1, 2, 0, 2, 3]:
		var point: Vector2 = points[index]
		surface.set_normal((pose.basis * Vector3.BACK).normalized())
		surface.add_vertex(pose * Vector3(point.x, point.y, 0))
