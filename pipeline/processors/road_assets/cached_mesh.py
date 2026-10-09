"""기존 도로 GLB를 읽기 전용 프리뷰 메시로 변환."""
import json
import struct
from road_assets.mesh import RoadMesh


def read(path):
    data=path.read_bytes()
    magic,version,size=struct.unpack_from("<III",data)
    if (magic,version,size)!=(0x46546C67,2,len(data)): raise ValueError("GLB 헤더 오류")
    json_size,chunk_type=struct.unpack_from("<II",data,12)
    if chunk_type!=0x4E4F534A: raise ValueError("GLB JSON 누락")
    doc=json.loads(data[20:20+json_size]); binary=28+json_size; mesh=RoadMesh()
    def accessor(index):
        entry=doc["accessors"][index]; view=doc["bufferViews"][entry["bufferView"]]
        if entry["componentType"]!=5126 or entry["type"]!="VEC3": raise ValueError("프리뷰 메시 형식 불일치")
        start=binary+view.get("byteOffset",0)+entry.get("byteOffset",0)
        stride=view.get("byteStride",12)
        return [struct.unpack_from("<3f",data,start+i*stride) for i in range(entry["count"])]
    for primitive in doc["meshes"][0]["primitives"]:
        if "indices" in primitive: raise ValueError("프리뷰 입력은 도로 생성 GLB만 지원한다")
        points=accessor(primitive["attributes"]["POSITION"])
        normals=accessor(primitive["attributes"]["NORMAL"])
        material=doc["materials"][primitive["material"]]["name"]
        for i in range(0,len(points),3): mesh.faces.append((*points[i:i+3],normals[i],material))
    return mesh
