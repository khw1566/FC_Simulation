"""도로 좌표 변환, 직사각형 선분 클리핑, 원본 폭 해석."""
import math
import re

WIDTHS = {"motorway":22, "motorway_link":12, "trunk":18, "trunk_link":10,
          "primary":15, "primary_link":9, "secondary":12, "secondary_link":8,
          "tertiary":9, "tertiary_link":7, "unclassified":4.5, "residential":5.5,
          "living_street":4.5, "service":3.5, "pedestrian":2.4, "footway":1.6,
          "path":1.25, "steps":1.8, "cycleway":2, "track":2.6, "bridleway":1.6,
          "road":4, "busway":7, "raceway":6, "escape":6}
EXCLUDED = {"construction", "proposed", "abandoned", "razed", "platform", "elevator", "corridor", "bus_stop", "rest_area", "services"}


def width(tags):
    raw = str(tags.get("width", "")).strip().lower()
    if re.fullmatch(r"\d+(?:[.,]\d+)?\s*(?:m|meters|meter)?", raw):
        value = float(re.match(r"[\d.,]+", raw).group().replace(",", "."))
        if .6 <= value <= 80:
            return value, "osm_width"
    kind = tags.get("highway", "road")
    if kind not in {"footway", "path", "steps", "pedestrian", "cycleway", "track", "bridleway"}:
        try:
            lanes = float(tags.get("lanes", ""))
            if 1 <= lanes <= 12:
                return max(WIDTHS.get(kind, 4), lanes*3.2+1), "osm_lanes_estimate"
        except (TypeError, ValueError):
            pass
    if kind == "track":
        return {"grade1":3.5, "grade2":3, "grade3":2.6, "grade4":2.2, "grade5":1.8}.get(tags.get("tracktype"), 2.6), "type_estimate"
    return WIDTHS.get(kind, 4), "type_estimate"


def enabled(tags, name):
    return str(tags.get(name, "no")).lower() not in {"", "no", "false", "0"}


def project(p, config):
    b, size = config["bbox"], config["world_size_meters"]
    return [(float(p["lon"])-b["west"])/(b["east"]-b["west"])*size-size/2,
            0.0, (b["north"]-float(p["lat"] ))/(b["north"]-b["south"])*size-size/2]


def clip_segment(a, b, half):
    lo, hi = 0.0, 1.0
    dx, dz = b[0]-a[0], b[2]-a[2]
    for p, q in [(-dx,a[0]+half),(dx,half-a[0]),(-dz,a[2]+half),(dz,half-a[2])]:
        if abs(p) < 1e-12:
            if q < 0:
                return None
            continue
        t = q/p
        if p < 0:
            lo = max(lo, t)
        else:
            hi = min(hi, t)
        if lo > hi:
            return None
    return ([a[0]+lo*dx, 0.0, a[2]+lo*dz], [a[0]+hi*dx, 0.0, a[2]+hi*dz])


def clip_line(points, half):
    result, current = [], []
    for a, b in zip(points, points[1:]):
        pair = clip_segment(a,b,half)
        if pair is None or math.hypot(pair[1][0]-pair[0][0],pair[1][2]-pair[0][2]) < .005:
            if len(current) > 1:
                result.append(current)
            current = []
            continue
        p, q = [[round(v, 2) for v in pt] for pt in pair]
        if current and current[-1] != p:
            if len(current) > 1:
                result.append(current)
            current = []
        if not current:
            current.append(p)
        if q != current[-1]:
            current.append(q)
    if len(current) > 1:
        result.append(current)
    return result


def convert(way, config):
    tags = way.get("tags", {})
    kind = tags.get("highway", "")
    if kind in EXCLUDED or tags.get("indoor") == "yes":
        return [], "non_surface_or_not_operational"
    if kind not in WIDTHS:
        return [], "unsupported_highway:"+kind
    raw = way.get("geometry", [])
    if len(raw) != len(way.get("nodes", [])):
        return [], "invalid_geometry"
    if len(raw) < 2:
        return [], "degenerate_way"
    points = [project(p, config) for p in raw]
    if not all(math.isfinite(v) for p in points for v in p):
        return [], "invalid_geometry"
    sections = clip_line(points, config["world_size_meters"]/2)
    if not sections:
        return [], "outside_or_zero_length"
    w, basis = width(tags)
    attrs = {key:tags[key] for key in ("surface","tracktype","smoothness","access","foot","bicycle","incline","oneway","junction","lanes") if key in tags}
    attrs.update(osm_id=way["id"], osm_version=way.get("version"),
                 osm_timestamp=way.get("timestamp"), type=kind, width=round(w,2), width_basis=basis,
                 name=tags.get("name:ko",tags.get("name",tags.get("ref",kind))),
                 layer=tags.get("layer","0"), bridge=enabled(tags,"bridge"),
                 tunnel=enabled(tags,"tunnel"), structure_tags_verified=True,
                 projected_source=True, source="OpenStreetMap", source_tags=tags)
    return [{**attrs,"id":f"osm_way_{way['id']}_{i}","points":section} for i,section in enumerate(sections)], None
