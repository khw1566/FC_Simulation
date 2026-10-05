"""도로 사이의 배치 가능한 필지와 진입 가능한 빈 공간 분할."""
from shapely.geometry import box


class IndustrialParcelBuilder:
    def build(self, safe, graph):
        remaining = safe.difference(graph["footprint"])
        result = []
        xs,zs = graph["grid_x"],graph["grid_z"]
        bounds = safe.bounds
        xs = [bounds[0]]+xs+[bounds[2]]
        zs = [bounds[1]]+zs+[bounds[3]]
        for z0,z1 in zip(zs,zs[1:]):
            for x0,x1 in zip(xs,xs[1:]):
                clipped = remaining.intersection(box(x0,z0,x1,z1)).buffer(-3)
                pieces = [clipped] if clipped.geom_type=="Polygon" else getattr(clipped,"geoms",[])
                for piece in pieces:
                    if piece.geom_type=="Polygon" and piece.area>=1000 and piece.distance(graph["lines"])<15:
                        result.append(piece)
        return result
