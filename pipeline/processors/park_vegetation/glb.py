"""불투명 정점색으로 전체 기하를 단일 표면 GLB에 기록한다."""
import json
import struct
import math
from .geometry import PALETTE


def export(mesh,path,name):
    blob=bytearray()
    doc={"asset":{"version":"2.0","generator":"Park opaque vertex-color pipeline"},
         "scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":name,"mesh":0}],
         "meshes":[{"primitives":[]}],"materials":[{"name":"park_shared",
         "pbrMetallicRoughness":{"baseColorFactor":[1,1,1,1],"metallicFactor":0,"roughnessFactor":1}}],
         "accessors":[],"bufferViews":[]}
    def accessor(values,fmt,ctype,kind,target,bounds=False):
        blob.extend(b"\0"*(-len(blob)%4)); offset=len(blob)
        for v in values: blob.extend(struct.pack(fmt,*v))
        vi=len(doc["bufferViews"])
        doc["bufferViews"].append({"buffer":0,"byteOffset":offset,"byteLength":len(blob)-offset,"target":target})
        a={"bufferView":vi,"componentType":ctype,"count":len(values),"type":kind}
        if bounds: a.update(min=[min(v[k] for v in values) for k in range(3)],max=[max(v[k] for v in values) for k in range(3)])
        doc["accessors"].append(a)
        return len(doc["accessors"])-1
    vertices=[]; indices=[]; lookup={}
    for face in mesh.faces:
        color=PALETTE[face[4]]
        for p in face[:3]:
            key=(*p,*face[3],*color,1)
            assert all(math.isfinite(x) for x in key)
            if key not in lookup:
                lookup[key]=len(vertices); vertices.append(key)
            indices.append((lookup[key],))
    attributes={"POSITION":accessor([v[:3] for v in vertices],"<3f",5126,"VEC3",34962,True),
                "NORMAL":accessor([v[3:6] for v in vertices],"<3f",5126,"VEC3",34962),
                "COLOR_0":accessor([v[6:] for v in vertices],"<4f",5126,"VEC4",34962)}
    idx=accessor(indices,"<I",5125,"SCALAR",34963)
    doc["meshes"][0]["primitives"]=[{"attributes":attributes,"indices":idx,"material":0,"mode":4}]
    blob.extend(b"\0"*(-len(blob)%4)); doc["buffers"]=[{"byteLength":len(blob)}]
    payload=json.dumps(doc,separators=(",",":")).encode(); payload+=b" "*(-len(payload)%4)
    path.write_bytes(struct.pack("<III",0x46546C67,2,28+len(payload)+len(blob))+
                     struct.pack("<II",len(payload),0x4E4F534A)+payload+struct.pack("<II",len(blob),0x004E4942)+blob)
