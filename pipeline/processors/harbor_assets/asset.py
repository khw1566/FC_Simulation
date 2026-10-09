"""모델 기하와 지형 기준·접속점·간단한 충돌을 함께 기록한다."""
import math
from .mesh import HarborMesh


class HarborAsset:
    def __init__(self,key,label,category,anchor="deck_surface"):
        self.key,self.label,self.category=key,label,category
        self.mesh=HarborMesh(); self.ports=[]; self.collisions=[]; self.extra={}
        self.anchor=anchor
        self.marker("GroundOrigin",(0,0,0),"terrain_anchor")

    def marker(self,name,position,profile="attachment",direction=(0,0,-1),width=None):
        port={"name":name,"position_m":list(position),"outward_direction":list(direction),
              "rotation_y_rad":math.atan2(-direction[0],-direction[2]),"profile":profile}
        if width is not None: port["width_m"]=width
        self.ports.append(port)
        return port

    def ends(self,length,width,profile="quay_walk"):
        self.marker("Start",(0,0,-length/2),profile,(0,0,-1),width)
        self.marker("End",(0,0,length/2),profile,(0,0,1),width)

    def box_collision(self,center,size):
        self.collisions.append({"type":"box","center_m":list(center),"size_m":list(size)})

    def convex_collision(self,points):
        self.collisions.append({"type":"convex","points_m":[list(p) for p in points]})

    def metadata(self):
        points=[p for f in self.mesh.faces for p in f[:3]]
        lo=[min(p[i] for p in points) for i in range(3)]; hi=[max(p[i] for p in points) for i in range(3)]
        return {"label_ko":self.label,"category":self.category,"units":"meters","anchor":self.anchor,
                "detail_profile":"harbor_low_poly_flat_v1","material_style":"flat_color","external_textures":False,
                "indexed_geometry":True,"triangles":len(self.mesh.faces),"triangle_count_method":"gltf_primitive_indices",
                "aabb_min_m":lo,"aabb_max_m":hi,"footprint_xz_m":[lo[0],lo[2],hi[0],hi[2]],
                "bbox":None,"elevation_min":lo[1],"elevation_max":hi[1],"resolution":None,
                "ports":self.ports,"collision_shapes":self.collisions,"grid_m":6,"sea_side_local_axis":"+X",
                "placement_status":"asset_only","surveyed":False,"georeferenced":False,**self.extra}
