"""단색 평면 법선은 유지하고 중복 정점과 미사용 재질을 제거한다."""
import json
import math
import struct


def inspect(path):
    data = path.read_bytes()
    assert struct.unpack_from("<III", data) == (0x46546C67, 2, len(data))
    size, kind = struct.unpack_from("<II", data, 12)
    assert kind == 0x4E4F534A
    doc = json.loads(data[20:20+size])
    count = sum(doc["accessors"][p.get("indices", p["attributes"]["POSITION"])]["count"] // 3
                for m in doc["meshes"] for p in m["primitives"])
    return {"triangles": count, "size_bytes": len(data)}


def export(mesh, path, name, palette):
    blob = bytearray()
    doc = {"asset": {"version": "2.0", "generator": "Custom low-poly indexed mesh"},
           "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": name, "mesh": 0}],
           "meshes": [{"primitives": []}], "materials": [], "accessors": [], "bufferViews": []}
    def accessor(values, fmt, component, kind, target, bounds=False):
        blob.extend(b"\0" * (-len(blob) % 4))
        offset = len(blob)
        for value in values:
            blob.extend(struct.pack(fmt, *value))
        view = len(doc["bufferViews"])
        doc["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": len(blob)-offset, "target": target})
        entry = {"bufferView": view, "componentType": component, "count": len(values), "type": kind}
        if bounds:
            entry.update(min=[min(p[i] for p in values) for i in range(3)], max=[max(p[i] for p in values) for i in range(3)])
        doc["accessors"].append(entry)
        return len(doc["accessors"]) - 1
    for material in dict.fromkeys(f[4] for f in mesh.faces):
        color = palette[material]
        mat = len(doc["materials"])
        doc["materials"].append({"name": material, "pbrMetallicRoughness": {
            "baseColorFactor": [*color, 1], "metallicFactor": 0, "roughnessFactor": 1}})
        lookup, vertices, indices = {}, [], []
        for face in mesh.faces:
            if face[4] != material:
                continue
            for point in face[:3]:
                key = tuple(round(v, 7) for v in (*point, *face[3]))
                assert all(math.isfinite(v) for v in key)
                if key not in lookup:
                    lookup[key] = len(vertices)
                    vertices.append(key)
                indices.append((lookup[key],))
        position = accessor([p[:3] for p in vertices], "<3f", 5126, "VEC3", 34962, True)
        normal = accessor([p[3:] for p in vertices], "<3f", 5126, "VEC3", 34962)
        index = accessor(indices, "<I", 5125, "SCALAR", 34963)
        doc["meshes"][0]["primitives"].append({"attributes": {"POSITION": position, "NORMAL": normal},
                                              "indices": index, "material": mat, "mode": 4})
    blob.extend(b"\0" * (-len(blob) % 4))
    doc["buffers"] = [{"byteLength": len(blob)}]
    payload = json.dumps(doc, separators=(",", ":")).encode()
    payload += b" " * (-len(payload) % 4)
    path.write_bytes(struct.pack("<III", 0x46546C67, 2, 28+len(payload)+len(blob)) +
                     struct.pack("<II", len(payload), 0x4E4F534A) + payload +
                     struct.pack("<II", len(blob), 0x004E4942) + blob)
    assert inspect(path)["triangles"] == len(mesh.faces)
