"""회전·축척한 산업 설비 전체 점유 형상을 검사하는 결정적 배치."""
import math
from shapely.affinity import rotate, scale, translate
from shapely.geometry import box, Point, LineString
from shapely.ops import nearest_points, unary_union


class IndustrialAssetPlacer:
    KINDS = {
        "general_factory":["factory_gable","factory_gable","factory_sawtooth","factory_flat","industrial_chimney","cooling_fan_bank","stack_steel"],
        "petrochemical":["liquid_storage_tank","liquid_storage_tank","liquid_storage_tank","lpg_sphere","process_column","scrubber_tower","cooling_tower","stack_concrete"],
        "shipbuilding":["shipbuilding_hangar","gantry_crane","tower_crane","factory_flat"],
        "logistics":["factory_flat","factory_flat","factory_gable","cooling_fan_bank"]}

    def build(self, parcels, graph, inputs, profile_name, profile, catalog, rng, zone_id, safety):
        placements, occupied, driveways = [], [], []
        limit = int(inputs.config.get("max_assets_per_zone",100))
        for parcel_index,parcel in enumerate(parcels):
            area = 0.0
            attempts = 0
            local_occupied = []
            main_count, auxiliary_count = 0,0
            while attempts<180 and len(placements)<limit and area<parcel.area*profile["asset_coverage"]:
                attempts += 1
                kind = rng.choice(self.KINDS[profile_name])
                auxiliary = profile_name=="general_factory" and not kind.startswith("factory_")
                if auxiliary and (main_count==0 or auxiliary_count>=min(2,main_count)):
                    continue
                spec = catalog[kind]
                factor = rng.uniform(*spec.get("scale_range",[0.85,1.15]))
                yaw = rng.choice([0,90,180,270])
                bounds = spec["footprint_xz_m"]
                center_x = rng.uniform(parcel.bounds[0],parcel.bounds[2])
                center_z = rng.uniform(parcel.bounds[1],parcel.bounds[3])
                shape = translate(rotate(scale(box(*bounds),xfact=factor,yfact=factor,origin=(0,0)),yaw,origin=(0,0)),center_x,center_z)
                padding = shape.buffer(max(4,float(spec.get("placement_padding_m",3))))
                if not parcel.covers(padding) or any(padding.intersects(p) for p in occupied):
                    continue
                heights = [inputs.sample(x,z) for x,z in shape.exterior.coords]
                point = Point(center_x,center_z)
                road_point = nearest_points(point,graph["lines"])[1]
                access = LineString([point,road_point])
                # 부지 밖으로 새 진입로를 내지 않는다. 기존 설비·건물도 가로지르지 않는다.
                corridor = access.buffer(3,cap_style=2)
                if access.length>150 or not safety.covers(corridor):
                    continue
                if any(corridor.intersects(p) for p in occupied):
                    continue
                if any(padding.intersects(d) for d in driveways):
                    continue
                if max(heights)-min(heights)>inputs.config.get("max_foundation_height_m",3.5):
                    continue
                base_y = max(heights)+0.12
                placement = {"id":f"zone_{zone_id}_asset_{len(placements)}","zone_id":zone_id,"parcel_id":parcel_index,
                             "asset_type":kind,"scene_path":spec["scene_path"],"glb_path":spec["scene_path"].replace(".tscn",".glb"),
                             "position":[round(center_x,3),round(base_y,3),round(center_z,3)],"yaw_degrees":-yaw,"scale":round(factor,5),
                             "aabb_min_m":spec["aabb_min_m"],"aabb_max_m":spec["aabb_max_m"],
                             "footprint_xz":[[round(x,3),round(z,3)] for x,z in shape.exterior.coords],
                             "foundation_bottom_y":round(min(heights)-0.75,3),"night_lighting":spec.get("night_lighting",{}),
                             "attachments":spec.get("attachments",[]),"smoke_outlets_m":spec.get("smoke_outlets_m",[]),
                             "driveway_xz":[list(access.coords[0]),list(access.coords[-1])]}
                placements.append(placement)
                if auxiliary:
                    auxiliary_count += 1
                else:
                    main_count += 1
                occupied.append(padding)
                local_occupied.append(padding)
                driveways.append(corridor)
                area += padding.area
        return placements
