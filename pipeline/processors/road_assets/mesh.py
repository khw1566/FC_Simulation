"""도로 전용 재질과 메시·GLB 작성기."""
import json
import math
import struct
from pathlib import Path
from taehwagang.geometry import StationMesh

PALETTE = {
    "asphalt":(.18,.19,.20), "asphalt_worn":(.25,.26,.26),
    "concrete":(.57,.57,.54), "concrete_worn":(.43,.44,.42),
    "paver_gray":(.48,.49,.48), "paver_sand":(.64,.59,.47),
    "brick_red":(.46,.28,.22), "stone":(.47,.48,.43),
    "stone_dark":(.33,.35,.34), "granite":(.66,.67,.64),
    "wood":(.39,.30,.22), "wood_weathered":(.42,.40,.34),
    "gravel":(.50,.47,.40), "sand":(.68,.61,.45),
    "earth":(.41,.32,.22), "earth_dark":(.28,.26,.20),
    "rubber":(.31,.37,.32), "joint":(.22,.23,.22),
    "white":(.86,.87,.83), "yellow":(.79,.65,.20),
    "steel":(.44,.48,.49), "grass":(.27,.35,.25),
    "tile_light":(.61,.61,.57), "tile_dark":(.37,.38,.36),
}
for name in ("concrete","concrete_worn","paver_gray","paver_sand","brick_red", "stone","stone_dark","granite","wood","wood_weathered","gravel","sand","earth","earth_dark"):
    PALETTE[name+"_light"]=tuple(min(1,c*1.09) for c in PALETTE[name])
    PALETTE[name+"_dark"]=tuple(c*.90 for c in PALETTE[name])


class RoadMesh(StationMesh):
    """기존 기하를 재사용하고 도로 전용 재질만 내보낸다."""

    @staticmethod
    def at(point, offset, y):
        x,z,a = point
        return (x+offset*math.cos(a),y,z-offset*math.sin(a))

    def strip(self, points, left, right, top, material, bottom=None):
        for a,b in zip(points,points[1:]):
            self.quad(self.at(a,left,top),self.at(b,left,top),
                      self.at(b,right,top),self.at(a,right,top),material)
            if bottom is not None:
                self.quad(self.at(a,right,bottom),self.at(b,right,bottom),
                          self.at(b,left,bottom),self.at(a,left,bottom),material)
                for offset in (left,right):
                    quad=[self.at(a,offset,bottom),self.at(b,offset,bottom),
                          self.at(b,offset,top),self.at(a,offset,top)]
                    self.quad(*(quad if offset==left else list(reversed(quad))),material)
        if bottom is not None:
            for point,reverse in ((points[0],False),(points[-1],True)):
                quad=[self.at(point,left,bottom),self.at(point,left,top),
                      self.at(point,right,top),self.at(point,right,bottom)]
                self.quad(*(list(reversed(quad)) if reverse else quad),material)

    def patch(self, point, offset, width, length, y, material):
        x,z,a=point
        delta=(math.sin(a)*length/2,math.cos(a)*length/2)
        start=(x-delta[0],z-delta[1],a); end=(x+delta[0],z+delta[1],a)
        self.strip([start,end],offset-width/2,offset+width/2,y,material)

    def export(self, path, name):
        blob=bytearray()
        doc={"asset":{"version":"2.0","generator":"Kanmon modular road assets"},
             "scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":name,"mesh":0}],
             "meshes":[{"primitives":[]}],"materials":[],"accessors":[],"bufferViews":[]}
        for material,color in PALETTE.items():
            faces=[f for f in self.faces if f[4]==material]
            if not faces: continue
            index=len(doc["materials"])
            doc["materials"].append({"name":material,"pbrMetallicRoughness":{
                "baseColorFactor":[*color,1],"metallicFactor":.2 if material=="steel" else 0,
                "roughnessFactor":.62 if material=="steel" else .95},"doubleSided":False})
            attributes={}
            for semantic,values in (("POSITION",[p for f in faces for p in f[:3]]),
                                    ("NORMAL",[f[3] for f in faces for _ in range(3)])):
                start=len(blob)
                for value in values: blob.extend(struct.pack("<3f",*value))
                doc["bufferViews"].append({"buffer":0,"byteOffset":start,
                    "byteLength":len(blob)-start,"target":34962})
                accessor={"bufferView":len(doc["bufferViews"])-1,"componentType":5126,
                          "count":len(values),"type":"VEC3"}
                if semantic=="POSITION":
                    accessor.update(min=[min(p[k] for p in values) for k in range(3)],
                                    max=[max(p[k] for p in values) for k in range(3)])
                attributes[semantic]=len(doc["accessors"]); doc["accessors"].append(accessor)
            doc["meshes"][0]["primitives"].append({"attributes":attributes,"material":index,"mode":4})
        unknown={f[4] for f in self.faces}-set(PALETTE)
        if unknown: raise ValueError(f"정의되지 않은 재질: {unknown}")
        doc["buffers"]=[{"byteLength":len(blob)}]
        payload=json.dumps(doc,separators=(",",":")).encode(); payload+=b" "*(-len(payload)%4)
        blob+=b"\0"*(-len(blob)%4)
        data=struct.pack("<III",0x46546C67,2,28+len(payload)+len(blob))
        data+=struct.pack("<II",len(payload),0x4E4F534A)+payload
        data+=struct.pack("<II",len(blob),0x004E4942)+blob
        Path(path).write_bytes(data)
