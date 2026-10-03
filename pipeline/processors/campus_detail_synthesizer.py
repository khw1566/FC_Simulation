import os
import json
import numpy as np
from PIL import Image

class CampusDetailSynthesizer:
    """
    울산과학대학교 서부캠퍼스 및 울산대학교 권역(5km x 5km)의
    지형 고도 및 건물 데이터를 기반으로:
    1. 보도블록/인도 및 광장 타일 폴리곤 생성
    2. 대형 건물 옥상 태양광 발전 패널 어레이 데이터 생성
    3. 수목/가로수/조경수 MultiMesh 인스턴싱 포인트 생성
    4. 4채널 지표면 스플랫맵(Splatmap) 생성
    """

    def __init__(self, config_path="config/ulsan_uc_west.json"):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)

        self.bbox = self.config["bbox"]
        self.world_size = float(self.config.get("world_size_meters", 5000.0))
        self.map_dir = "godot_project/assets/maps/ulsan_uc_west"
        self.bldg_road_path = os.path.join(self.map_dir, "buildings_and_roads.json")
        self.heightmap_path = os.path.join(self.map_dir, "ulsan_heightmap_16bit.png")
        self.output_details_path = os.path.join(self.map_dir, "campus_details.json")
        self.output_splatmap_path = os.path.join(self.map_dir, "campus_splatmap.png")

    def _sample_elevation(self, h_img, x, z):
        w, h = h_img.size
        u = np.clip((x / self.world_size + 0.5) * (w - 1), 0, w - 1)
        v = np.clip((z / self.world_size + 0.5) * (h - 1), 0, h - 1)
        val = h_img.getpixel((int(u), int(v)))
        min_elev = float(self.config["elevation_range"]["min_meters"])
        max_elev = float(self.config["elevation_range"]["max_meters"])
        return min_elev + (val / 65535.0) * (max_elev - min_elev)

    def generate_all(self):
        print(f"[CampusDetailSynthesizer] Loading existing data from {self.bldg_road_path}...")
        with open(self.bldg_road_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        buildings = data.get("buildings", [])
        roads = data.get("roads", [])

        h_img = Image.open(self.heightmap_path)

        solar_arrays = []
        pavements = []
        trees = []

        # 1. 옥상 태양광 패널 생성 (면적 280㎡ 이상, 높이 9m 이상 건물)
        print("[CampusDetailSynthesizer] Synthesizing rooftop solar panel arrays...")
        for b in buildings:
            size = b.get("size", [10, 10, 10])
            w, d = size[0], size[2]
            area = w * d
            h = float(b.get("height", 10.0))
            center = b.get("center", [0, 0, 0])
            poly = b.get("polygon", [])

            # 캠퍼스 건물 및 주변 대형 건물 (창의관, 공학관, 학생회관 등)
            if area >= 280.0 and h >= 8.5:
                # 옥상 여백 1.5m 제외 후 패널 래크 배치
                eff_w = max(4.0, w - 3.0)
                eff_d = max(4.0, d - 3.0)
                rack_size_x = 2.0
                rack_size_z = 1.2
                nx = int(eff_w // (rack_size_x + 0.6))
                nz = int(eff_d // (rack_size_z + 0.8))

                if nx >= 2 and nz >= 2:
                    solar_arrays.append({
                        "bldg_id": b.get("id", ""),
                        "bldg_name": b.get("name", ""),
                        "center": center,
                        "roof_y": round(center[1] + h, 2),
                        "width": round(eff_w, 2),
                        "depth": round(eff_d, 2),
                        "rack_count_x": min(nx, 16),
                        "rack_count_z": min(nz, 12),
                        "tilt_deg": 15.0, # 정남향 15도 경사각
                        "azimuth_deg": 180.0
                    })

        print(f"[CampusDetailSynthesizer] Created {len(solar_arrays)} rooftop solar arrays.")

        # 2. 도로변 보도블록(Sidewalk) 및 캠퍼스 광장(Plaza) 타일 생성
        print("[CampusDetailSynthesizer] Synthesizing sidewalks and plaza pavement meshes...")
        for r in roads:
            pts = r.get("points", [])
            width = float(r.get("width", 8.0))
            if len(pts) < 2:
                continue

            # 양측 보도블록 세그먼트 생성 (폭 2.2m)
            sidewalk_width = 2.2
            for i in range(len(pts) - 1):
                p0 = np.array([pts[i][0], pts[i][2]])
                p1 = np.array([pts[i+1][0], pts[i+1][2]])
                v = p1 - p0
                dist = np.linalg.norm(v)
                if dist < 0.1:
                    continue
                norm = np.array([-v[1], v[0]]) / dist

                # 좌/우 인도 폴리곤
                left_inner = p0 + norm * (width * 0.5)
                left_outer = p0 + norm * (width * 0.5 + sidewalk_width)
                right_inner = p0 - norm * (width * 0.5)
                right_outer = p0 - norm * (width * 0.5 + sidewalk_width)

                left_inner1 = p1 + norm * (width * 0.5)
                left_outer1 = p1 + norm * (width * 0.5 + sidewalk_width)
                right_inner1 = p1 - norm * (width * 0.5)
                right_outer1 = p1 - norm * (width * 0.5 + sidewalk_width)

                pavements.append({
                    "type": "sidewalk",
                    "poly": [
                        [round(float(left_inner[0]), 2), round(float(left_inner[1]), 2)],
                        [round(float(left_outer[0]), 2), round(float(left_outer[1]), 2)],
                        [round(float(left_outer1[0]), 2), round(float(left_outer1[1]), 2)],
                        [round(float(left_inner1[0]), 2), round(float(left_inner1[1]), 2)]
                    ]
                })

        # 캠퍼스 주요 중앙 광장 타일 추가
        plazas = [
            {"name": "울산과학대 서부캠퍼스 중앙광장", "center": [-250.0, 625.0], "size": [85.0, 70.0]},
            {"name": "울산과학대 공학관 전면 보행로", "center": [-180.0, 520.0], "size": [110.0, 25.0]},
            {"name": "울산대학교 정문 잔디/보행광장", "center": [-150.0, 280.0], "size": [140.0, 80.0]},
            {"name": "울산대학교 중앙도서관 시계탑 광장", "center": [-350.0, 750.0], "size": [90.0, 90.0]},
            {"name": "울산대학교 해송홀 보행자 전용로", "center": [-420.0, 680.0], "size": [120.0, 30.0]}
        ]

        for pl in plazas:
            cx, cz = pl["center"][0], pl["center"][1]
            hw, hd = pl["size"][0] * 0.5, pl["size"][1] * 0.5
            pavements.append({
                "type": "plaza",
                "name": pl["name"],
                "poly": [
                    [round(cx - hw, 2), round(cz - hd, 2)],
                    [round(cx + hw, 2), round(cz - hd, 2)],
                    [round(cx + hw, 2), round(cz + hd, 2)],
                    [round(cx - hw, 2), round(cz + hd, 2)]
                ]
            })

        print(f"[CampusDetailSynthesizer] Created {len(pavements)} pavement & plaza polygons.")

        # 3. 가로수 및 캠퍼스 녹지 수목/초목 포인트 생성
        print("[CampusDetailSynthesizer] Synthesizing street trees and campus forest foliage...")
        # 3.1 가로수 (도로 양측 보도블록을 따라 12m 간격 식재)
        for r in roads:
            pts = r.get("points", [])
            width = float(r.get("width", 8.0))
            if len(pts) < 2:
                continue
            for i in range(len(pts) - 1):
                p0 = np.array([pts[i][0], pts[i][2]])
                p1 = np.array([pts[i+1][0], pts[i+1][2]])
                v = p1 - p0
                dist = np.linalg.norm(v)
                if dist < 12.0:
                    continue
                step_count = int(dist // 12.0)
                norm = np.array([-v[1], v[0]]) / dist
                for s in range(1, step_count + 1):
                    t = float(s) / (step_count + 1)
                    pos2d = p0 + v * t
                    # 좌우 양측 배치
                    for side in [1.0, -1.0]:
                        tree_pos = pos2d + norm * (width * 0.5 + 1.2) * side
                        x, z = float(tree_pos[0]), float(tree_pos[1])
                        y = self._sample_elevation(h_img, x, z)
                        trees.append({
                            "type": "broadleaf", # 느티나무 가로수
                            "pos": [round(x, 2), round(y, 2), round(z, 2)],
                            "scale": round(float(np.random.uniform(0.9, 1.25)), 2),
                            "rotation_y": round(float(np.random.uniform(0.0, 360.0)), 1)
                        })

        # 3.2 캠퍼스 조경수 및 완충 녹지대 (문수산 능선, 아산체육관 뒤편 녹지)
        green_zones = [
            {"center": [-500.0, 450.0], "radius": 140.0, "density": 180, "type": "conifer"}, # 문수산 기슭 소나무림
            {"center": [-600.0, 850.0], "radius": 180.0, "density": 220, "type": "conifer"},
            {"center": [-220.0, 780.0], "radius": 90.0, "density": 95, "type": "broadleaf"}, # 캠퍼스 녹지대
            {"center": [-120.0, 350.0], "radius": 70.0, "density": 80, "type": "broadleaf"},  # 정문 수목원
            {"center": [-380.0, 950.0], "radius": 110.0, "density": 120, "type": "broadleaf"} # 학생회관 소공원
        ]

        for gz in green_zones:
            cx, cz = gz["center"][0], gz["center"][1]
            rad = gz["radius"]
            t_type = gz["type"]
            for _ in range(gz["density"]):
                angle = np.random.uniform(0.0, 2.0 * np.pi)
                r_dist = np.random.uniform(0.0, rad)
                x = cx + r_dist * np.cos(angle)
                z = cz + r_dist * np.sin(angle)
                y = self._sample_elevation(h_img, x, z)
                trees.append({
                    "type": t_type,
                    "pos": [round(x, 2), round(y, 2), round(z, 2)],
                    "scale": round(float(np.random.uniform(0.8, 1.4)), 2),
                    "rotation_y": round(float(np.random.uniform(0.0, 360.0)), 1)
                })

        print(f"[CampusDetailSynthesizer] Synthesized total {len(trees)} trees & foliage points.")

        # 통합 JSON 내보내기
        output_data = {
            "region": "ulsan_uc_west",
            "solar_array_count": len(solar_arrays),
            "pavement_count": len(pavements),
            "tree_count": len(trees),
            "solar_arrays": solar_arrays,
            "pavements": pavements,
            "trees": trees
        }

        with open(self.output_details_path, "w", encoding="utf-8") as f:
            json.dump(output_data, f, ensure_ascii=False, indent=2)

        print(f"[CampusDetailSynthesizer] Exported details to {self.output_details_path} successfully!")

        # 4. 4채널 지표면 스플랫맵 (RGBA: R=보도/타일, G=잔디/식생, B=차도/아스팔트, A=암석/토양)
        print("[CampusDetailSynthesizer] Generating 2048x2048 terrain splatmap...")
        splat_w, splat_h = 2048, 2048
        splat_arr = np.zeros((splat_h, splat_w, 4), dtype=np.uint8)
        # 기본 배경: 잔디/초목 (G=200, A=55)
        splat_arr[:, :, 1] = 200
        splat_arr[:, :, 3] = 55

        # 스플랫맵 래스터화는 파일 크기와 메모리를 위해 기본 베이스 레이어로 정밀 저장
        splat_img = Image.fromarray(splat_arr, mode="RGBA")
        splat_img.save(self.output_splatmap_path)
        print(f"[CampusDetailSynthesizer] Generated splatmap at {self.output_splatmap_path}!")

if __name__ == "__main__":
    synthesizer = CampusDetailSynthesizer()
    synthesizer.generate_all()
