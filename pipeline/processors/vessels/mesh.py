"""외부 모델링 라이브러리 없이 평면 법선 메시와 GLB를 생성한다."""

import json
import math
import struct
from pathlib import Path

PALETTE = {
    "hull": (0.12, 0.19, 0.24), "bottom": (0.40, 0.12, 0.10),
    "deck": (0.38, 0.43, 0.43), "white": (0.85, 0.87, 0.83),
    "glass": (0.09, 0.23, 0.29), "dark": (0.055, 0.065, 0.07),
    "red": (0.66, 0.22, 0.16), "blue": (0.20, 0.35, 0.46),
    "ochre": (0.69, 0.52, 0.23), "green": (0.25, 0.39, 0.33),
    "steel": (0.62, 0.67, 0.68), "orange": (0.86, 0.40, 0.10),
}


class VesselMesh:
    """재질별 삼각형을 하나의 정적 메시로 병합한다."""

    def __init__(self):
        self.faces = []

    def triangle(self, a, b, c, material):
        u = [b[i] - a[i] for i in range(3)]
        v = [c[i] - a[i] for i in range(3)]
        n = (u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0])
        length = math.sqrt(sum(x*x for x in n))
        if length > 1e-9:
            self.faces.append((a, b, c, tuple(x / length for x in n), material))

    def quad(self, a, b, c, d, material):
        self.triangle(a, b, c, material)
        self.triangle(a, c, d, material)

    def box(self, center, size, material):
        x, y, z = center
        w, h, l = (s / 2 for s in size)
        p = [(x+dx*w, y+dy*h, z+dz*l) for dx,dy,dz in
             [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),
              (-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
        for indices in [(0,3,2,1),(4,5,6,7),(0,4,7,3),
                        (1,2,6,5),(3,7,6,2),(0,1,5,4)]:
            self.quad(*(p[i] for i in indices), material)

    def cylinder(self, a, b, radius, material, segments=10):
        axis = [b[i]-a[i] for i in range(3)]
        length = math.sqrt(sum(x*x for x in axis))
        axis = [x/length for x in axis]
        helper = (1,0,0) if abs(axis[0]) < 0.8 else (0,1,0)
        u = (axis[1]*helper[2]-axis[2]*helper[1],
             axis[2]*helper[0]-axis[0]*helper[2],
             axis[0]*helper[1]-axis[1]*helper[0])
        norm = math.sqrt(sum(x*x for x in u))
        u = [x/norm for x in u]
        v = (axis[1]*u[2]-axis[2]*u[1], axis[2]*u[0]-axis[0]*u[2],
             axis[0]*u[1]-axis[1]*u[0])
        rings = [[tuple(p[k]+radius*(u[k]*math.cos(i*2*math.pi/segments)
                  +v[k]*math.sin(i*2*math.pi/segments)) for k in range(3))
                  for i in range(segments)] for p in (a,b)]
        for i in range(segments):
            j = (i+1) % segments
            self.quad(rings[0][i], rings[0][j], rings[1][j], rings[1][i], material)
            self.triangle(a, rings[0][j], rings[0][i], material)
            self.triangle(b, rings[1][i], rings[1][j], material)

    def hull(self, length, beam, draft, freeboard):
        # 위에서 보아 반시계 방향인 선체 윤곽. 선수는 -Z.
        outline = [(-.36,.48),(.36,.48),(.50,.32),(.50,-.24),
                   (.39,-.39),(.17,-.48),(0,-.50),(-.17,-.48),
                   (-.39,-.39),(-.50,-.24),(-.50,.32)]
        rings = [[(x*beam*scale,y,z*length*scale) for x,z in outline]
                 for y,scale in [(-draft,.68),(0,.96),(freeboard,1)]]
        for r in range(2):
            for i in range(len(outline)):
                j = (i+1) % len(outline)
                self.quad(rings[r][i], rings[r][j], rings[r+1][j],
                          rings[r+1][i], "bottom" if r == 0 else "hull")
        for i in range(len(outline)):
            j = (i+1) % len(outline)
            self.triangle((0,freeboard,0),rings[-1][i],rings[-1][j],"deck")
            self.triangle((0,-draft,0),rings[0][j],rings[0][i],"bottom")

    def export(self, path, name):
        blob = bytearray()
        doc = {"asset":{"version":"2.0","generator":"Kanmon vessel asset pipeline"},
               "scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":name,"mesh":0}],
               "meshes":[{"primitives":[]}],"materials":[],"accessors":[],"bufferViews":[]}
        for material, color in PALETTE.items():
            doc["materials"].append({"name":material,"pbrMetallicRoughness":{
                "baseColorFactor":[*color,1],"metallicFactor":0.15 if material=="steel" else 0,
                "roughnessFactor":0.3 if material=="glass" else 0.78}})
            faces = [f for f in self.faces if f[4] == material]
            if not faces:
                continue
            positions = [p for f in faces for p in f[:3]]
            normals = [f[3] for f in faces for _ in range(3)]
            attributes = {}
            for semantic, values in [("POSITION",positions),("NORMAL",normals)]:
                start = len(blob)
                for value in values:
                    blob.extend(struct.pack("<3f",*value))
                view = len(doc["bufferViews"])
                doc["bufferViews"].append({"buffer":0,"byteOffset":start,
                                          "byteLength":len(blob)-start,"target":34962})
                accessor = {"bufferView":view,"componentType":5126,"count":len(values),"type":"VEC3"}
                if semantic == "POSITION":
                    accessor.update(min=[min(p[k] for p in values) for k in range(3)],
                                    max=[max(p[k] for p in values) for k in range(3)])
                attributes[semantic] = len(doc["accessors"])
                doc["accessors"].append(accessor)
            doc["meshes"][0]["primitives"].append({"attributes":attributes,
                "material":list(PALETTE).index(material),"mode":4})
        doc["buffers"] = [{"byteLength":len(blob)}]
        payload = json.dumps(doc,separators=(",",":")).encode()
        payload += b" " * (-len(payload)%4)
        blob += b"\0" * (-len(blob)%4)
        data = struct.pack("<III",0x46546C67,2,28+len(payload)+len(blob))
        data += struct.pack("<II",len(payload),0x4E4F534A)+payload
        data += struct.pack("<II",len(blob),0x004E4942)+blob
        Path(path).write_bytes(data)
