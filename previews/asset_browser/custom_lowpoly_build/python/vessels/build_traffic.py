"""현재 지도 해수 마스크를 이용한 선박 배치 및 운항 자산 생성."""
import hashlib
import json
import math
from pathlib import Path
from PIL import Image
from navigation_grid import VesselNavigationGrid


class VesselTrafficBuilder:
    ROOT = Path(__file__).resolve().parents[3]

    def run(self):
        settings = json.loads((self.ROOT / "config/vessel_traffic.json").read_text(encoding="utf-8"))
        models = json.loads((self.ROOT / "godot_project/assets/generated/vessels/manifest.json").read_text(encoding="utf-8-sig"))["assets"]
        maps, omitted, validation = {}, [], []
        for map_id in ("ulsan_metro_80km", "kanmon_straits", "kyushu_wide"):
            meta = json.loads((self.ROOT / f"godot_project/assets/maps/{map_id}/map_meta.json").read_text(encoding="utf-8-sig"))
            source = meta["assets"].get("sea_mask", meta["assets"]["watermask"])
            with Image.open(self.ROOT / "godot_project" / source.removeprefix("res://")) as mask:
                nav = VesselNavigationGrid(mask, meta["world_size_meters"])
            bbox, entries, occupied = meta["bbox"], [], []
            for harbor in settings["harbors"]:
                if not (bbox["west"] < harbor["lon"] < bbox["east"] and bbox["south"] < harbor["lat"] < bbox["north"]):
                    continue
                for index, kind in enumerate(harbor["types"]):
                    asset = models[kind]
                    dimensions = asset["metadata"]
                    clearance = math.hypot(dimensions["length_m"]*0.5, dimensions["beam_m"]*0.5) + 15
                    grid = nav.allowed(clearance)
                    seed = nav.project_geo(harbor["lon"] + index*0.0018, harbor["lat"] + index*0.0008, bbox)
                    target = nav.project_geo(harbor["offshore_lon"] + index*0.003, harbor["offshore_lat"]-index*0.0015, bbox)
                    start, finish = nav.nearest(grid, seed), nav.nearest(grid, target)
                    path = nav.path(grid,start,finish) if start and finish else []
                    if len(path) < 2:
                        omitted.append({"map":map_id,"harbor":harbor["id"],"type":kind,"reason":"연결된 안전 해수 영역 없음"})
                        continue
                    points = [nav.world(p) for p in path]
                    length = sum(math.dist(a,b) for a,b in zip(points,points[1:]))
                    if length < 300:
                        omitted.append({"map":map_id,"harbor":harbor["id"],"type":kind,"reason":"운항 구간 300m 미만"})
                        continue
                    clear = all(nav.line_clear(grid,a,b) for a,b in zip(path,path[1:]))
                    if not clear:
                        raise ValueError("항로가 안전 해수 영역을 벗어났습니다")
                    entry = {"id":harbor["id"]+"_"+kind,"harbor":harbor["name_ko"],"type":kind,"scene_path":asset["scene_path"],"glb_path":asset["file_path"],"length_m":dimensions["length_m"],"beam_m":dimensions["beam_m"],"points_xz":points,"speed_mps":settings["speeds_mps"][kind],"initial_phase":0.0 if index == 0 else 0.25+index*0.11,"shore_clearance_radius_m":clearance,"navigation_cell_m":nav.cell,"seed_adjustment_m":math.dist(nav.world(seed),nav.world(start))}
                    entry["mode"] = "sailing"
                    for number in range(int(settings.get("sailing_copies_per_type", 3))):
                        copy = dict(entry)
                        copy["id"] += f"_sailing_{number + 1}"
                        copy["initial_phase"] = (0.15 + index * 0.11 + number / int(settings.get("sailing_copies_per_type", 3))) % 1
                        entries.append(copy)
                    for number in range(int(settings.get("moored_copies_per_type", 2))):
                        dock = self._dock(nav, grid, seed, clearance, occupied, points)
                        if dock is None:
                            omitted.append({"map":map_id,"harbor":harbor["id"],"type":kind,"mode":"moored","reason":"안전 이격 거리와 선체 간격을 만족하는 항포구 주변 해역 없음"})
                            continue
                        position = nav.world(dock)
                        occupied.append((position, clearance))
                        parked = dict(entry)
                        parked.update(id=entry["id"] + f"_moored_{number + 1}", mode="moored", points_xz=[position], speed_mps=0, heading_radians=math.atan2(-(points[1][0]-points[0][0]), -(points[1][1]-points[0][1])))
                        entries.append(parked)
                    validation.append({"map":map_id,"id":entry["id"],"segments":len(path)-1,"length_m":length,"shore_clear":True,"shore_clearance_radius_m":clearance})
            maps[map_id] = {"sea_level":meta["sea_level"],"bbox":bbox,"world_size_meters":meta["world_size_meters"],"mask_source":source,"entries":entries}
            print(map_id, "vessels=", len(entries), flush=True)
        destination = self.ROOT / "godot_project/assets/generated/vessels/traffic.json"
        payload = {"version":2,"settings":{key:value for key,value in settings.items() if key != "harbors"},"maps":maps,"omitted":omitted}
        destination.write_text(json.dumps(payload,ensure_ascii=False,indent=2),encoding="utf-8")
        manifest_path = self.ROOT / "godot_project/assets/generated/manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        manifest.setdefault("assets", {})["vessel_traffic"] = {"file_path":"res://assets/generated/vessels/traffic.json","sha256":hashlib.sha256(destination.read_bytes()).hexdigest(),"bbox":{key:value["bbox"] for key,value in maps.items()},"elevation_min":0,"elevation_max":0,"resolution":"해수 마스크 격자 65m 목표, 지도별 최대 2048격자","type":"vessel_traffic_catalog","vessel_count":sum(len(m["entries"]) for m in maps.values()),"note":settings["note"]}
        manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
        (self.ROOT / "results/261004_VesselNavigationValidation.json").write_text(json.dumps({"routes":validation,"omitted":omitted,"failures":[],"method":"선체 반대각선+15m 이상 해수 격자 침식, 모든 단순화 항로 구간 재검사"},ensure_ascii=False,indent=2),encoding="utf-8")

    def _dock(self, nav, grid, seed, clearance, occupied, route):
        # 조사된 접안 위치가 아닌 항포구 주변의 게임용 정박 위치다.
        for radius in (250, 450, 700, 1000, 1400):
            for angle_index in range(24):
                angle = angle_index * math.tau / 24
                probe = (round(seed[0] + math.cos(angle)*radius/nav.cell), round(seed[1] + math.sin(angle)*radius/nav.cell))
                point = nav.nearest(grid, probe, radius_m=nav.cell*2)
                if point is None:
                    continue
                position = nav.world(point)
                if math.dist(position, nav.world(seed)) > 1600:
                    continue
                corridor_clear = True
                for a, b in zip(route, route[1:]):
                    dx, dy = b[0]-a[0], b[1]-a[1]
                    t = max(0, min(1, ((position[0]-a[0])*dx + (position[1]-a[1])*dy) / max(dx*dx+dy*dy, 0.001)))
                    if math.dist(position, (a[0]+t*dx, a[1]+t*dy)) < clearance*2+25:
                        corridor_clear = False
                        break
                if not corridor_clear:
                    continue
                if all(math.dist(position, other) > clearance + other_radius + 25 for other, other_radius in occupied):
                    return point
        return None


if __name__ == "__main__":
    VesselTrafficBuilder().run()
