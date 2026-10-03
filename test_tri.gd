
extends SceneTree
func _init():
    var pts = PackedVector2Array([Vector2(0,0), Vector2(10,0), Vector2(10,10), Vector2(0,10)])
    var indices = Geometry2D.triangulate_polygon(pts)
    print('Triangles:', indices)
    quit(0)
