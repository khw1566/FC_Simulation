"""기존 도로 진입점에 연결되는 공단 내부 직교 도로 그래프."""
import math
from shapely.geometry import Point, LineString
from shapely.ops import nearest_points, unary_union


class IndustrialRoadGraph:
    def build(self, zone, safe, inputs, profile, rng):
        width = float(profile["local_road_width_m"])
        spacing = rng.uniform(*profile["block_size_m"])
        lower_x,lower_z,upper_x,upper_z = zone.bounds
        inset = max(40,width)
        xs = self.axis(lower_x+inset,upper_x-inset,spacing)
        zs = self.axis(lower_z+inset,upper_z-inset,spacing)
        nodes, edges, adjacency = {}, [], {}
        for iz,z in enumerate(zs):
            for ix,x in enumerate(xs):
                if safe.covers(Point(x,z).buffer(width/2+2)):
                    nodes[(ix,iz)] = (x,z)
                    adjacency[(ix,iz)] = []
        for key,point in nodes.items():
            for neighbor in ((key[0]+1,key[1]),(key[0],key[1]+1)):
                if neighbor not in nodes:
                    continue
                line = LineString([point,nodes[neighbor]])
                if self.safe_line(line,safe,inputs,width):
                    edges.append((key,neighbor,line))
                    adjacency[key].append(neighbor)
                    adjacency[neighbor].append(key)
        components,remaining = [],set(nodes)
        while remaining:
            start = min(remaining)
            component,stack = set(),[start]
            while stack:
                key = stack.pop()
                if key in component:
                    continue
                component.add(key)
                stack.extend(adjacency[key])
            remaining.difference_update(component)
            if len(component)>2:
                components.append(component)
        choices = []
        for component in components:
            for key in sorted(component):
                point = Point(nodes[key])
                for index in inputs.road_tree.query(point.buffer(450)):
                    source = inputs.roads[int(index)]
                    join = nearest_points(point,source["line"])[1]
                    connector = LineString([point,join])
                    if connector.length<5 or connector.length>450:
                        continue
                    if self.safe_line(connector,safe,inputs,width):
                        choices.append((-len(component),connector.length,key,component,connector,source,join))
        if not choices:
            return None
        _,_,entry,component,connector,source,join = min(choices,key=lambda p:(p[0],p[1],p[2]))
        lines = [line for a,b,line in edges if a in component and b in component]
        lines.append(connector)
        existing = [inputs.roads[int(i)]["line"].buffer(inputs.roads[int(i)]["width"]/2) for i in inputs.road_tree.query(zone)]
        existing_geometry = unary_union(existing)
        records, footprints = [], []
        main_width = float(profile["main_road_width_m"])
        primary = max(lines,key=lambda line:line.length)
        for number,line in enumerate(lines):
            road_width = main_width if line==primary and self.safe_line(line,safe,inputs,main_width) else width
            clipped = line.difference(existing_geometry)
            parts = [clipped] if clipped.geom_type=="LineString" else list(getattr(clipped,"geoms",[]))
            for part in parts:
                if part.geom_type!="LineString" or part.length<2:
                    continue
                records.append({"id":f"internal_{number}_{len(records)}","width_m":road_width,
                                "points_xz":[list(p) for p in part.coords]})
                footprints.append(part.buffer(road_width/2+6,cap_style=2,join_style=2))
        return {"roads":records,"footprint":unary_union(footprints),"lines":unary_union(lines),
                "connection":{"existing_road_id":source["id"],"point_xz":[join.x,join.y],"entry_node_xz":list(nodes[entry])},
                "grid_x":xs,"grid_z":zs,"spacing_m":spacing,"connected_nodes":len(component),"component_count":1}

    @staticmethod
    def axis(start,finish,spacing):
        count = max(2,int((finish-start)/spacing)+1)
        return [start+(finish-start)*i/(count-1) for i in range(count)]

    @staticmethod
    def safe_line(line,safe,inputs,width):
        if not safe.covers(line.buffer(width/2+2,cap_style=2)):
            return False
        count = max(2,math.ceil(line.length/10))
        last = None
        for i in range(count+1):
            point = line.interpolate(i/count,normalized=True)
            height = inputs.sample(point.x,point.y)
            if last is not None and abs(height-last)/(line.length/count)>inputs.config.get("max_road_grade",0.08):
                return False
            last = height
        return True
