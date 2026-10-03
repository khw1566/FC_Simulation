"""OSM 수계 형상 분류 및 관계 외곽/내곽 연결."""
class HydroGeometry:
    @staticmethod
    def contains(point, ring):
        inside = False
        x, y = point
        previous = ring[-1]
        for current in ring:
            if (current[1] > y) != (previous[1] > y):
                if x < (previous[0]-current[0])*(y-current[1])/(previous[1]-current[1])+current[0]:
                    inside = not inside
            previous = current
        return inside

    @staticmethod
    def coordinates(geometry):
        return [[p["lon"], p["lat"]] for p in geometry if "lon" in p and "lat" in p]

    @staticmethod
    def rings(parts):
        pending = [p[:] for p in parts if len(p) > 1]
        closed = []
        while pending:
            chain = pending.pop()
            while chain[0] != chain[-1]:
                found = False
                for i, part in enumerate(pending):
                    if chain[-1] == part[0]:
                        chain.extend(part[1:])
                    elif chain[-1] == part[-1]:
                        chain.extend(part[-2::-1])
                    elif chain[0] == part[-1]:
                        chain = part[:-1] + chain
                    elif chain[0] == part[0]:
                        chain = part[:0:-1] + chain
                    else:
                        continue
                    pending.pop(i)
                    found = True
                    break
                if not found:
                    raise ValueError("열린 수역 관계 경계: 불완전한 다각형은 적용하지 않습니다")
            closed.append(chain)
        return closed

    def classify(self, data):
        groups = {"coastline": [], "river": [], "lake": []}
        for e in data["elements"]:
            tags = e.get("tags", {})
            if e["type"] == "node":
                continue
            if tags.get("natural") == "coastline":
                kind = "coastline"
            elif tags.get("water") in ("river", "stream", "canal") or "waterway" in tags:
                kind = "river"
            else:
                kind = "lake"
            outer, inner = [], []
            if e["type"] == "relation":
                for role, dest in (("outer", outer), ("inner", inner)):
                    parts = [self.coordinates(m.get("geometry", [])) for m in e.get("members", []) if m.get("type") == "way" and m.get("role", "outer") == role]
                    dest.extend(self.rings(parts))
            else:
                coords = self.coordinates(e.get("geometry", []))
                if len(coords) < 2:
                    continue
                outer = [coords]
            is_area = kind != "coastline" and (e["type"] == "relation" or tags.get("natural") == "water" or tags.get("waterway") == "riverbank" or tags.get("landuse") == "reservoir")
            if is_area:
                geometry = {"type": "MultiPolygon", "coordinates": [[r] for r in outer]}
                for hole in inner:
                    for polygon in geometry["coordinates"]:
                        if self.contains(hole[0], polygon[0]):
                            polygon.append(hole)
                            break
            else:
                geometry = {"type": "MultiLineString", "coordinates": outer}
            groups[kind].append({"type": "Feature", "properties": {"osm_id": e["id"], "osm_type": e["type"], "tags": tags, "inner_rings": inner}, "geometry": geometry})
        return groups
