"""텍스처 파일 없이 연기·증기 GPU 파티클 프리셋을 작성."""

PRESETS={'smoke_gray':(.55,.57,.59,.28),'steam_white':(.92,.94,.96,.22),
         'smoke_dark':(.22,.24,.26,.35)}


def scene(key):
    r,g,b,alpha=PRESETS[key]
    return f'''[gd_scene load_steps=10 format=3]

[ext_resource type="Script" path="res://scripts/industrial_plant/plume_controller.gd" id="1"]
[ext_resource type="Shader" path="res://shaders/industrial_plant_plume.gdshader" id="2"]

[sub_resource type="Gradient" id="Fade"]
offsets = PackedFloat32Array(0, 0.04, 0.6, 1)
colors = PackedColorArray({r}, {g}, {b}, 0, {r}, {g}, {b}, {alpha}, {r}, {g}, {b}, {alpha*.65}, {r}, {g}, {b}, 0)

[sub_resource type="GradientTexture1D" id="Ramp"]
gradient = SubResource("Fade")

[sub_resource type="Curve" id="Expansion"]
max_value = 7.0
_data = [Vector2(0, 0.8), 0.0, 0.0, 0, 0, Vector2(1, 6), 0.0, 0.0, 0, 0]
point_count = 2

[sub_resource type="CurveTexture" id="Scale"]
curve = SubResource("Expansion")

[sub_resource type="ParticleProcessMaterial" id="Process"]
resource_local_to_scene = true
emission_shape = 1
emission_sphere_radius = 0.6
direction = Vector3(0, 1, 0)
spread = 9.0
gravity = Vector3(0.36, 0.35, 0)
initial_velocity_min = 3.0
initial_velocity_max = 5.0
scale_min = 1.2
scale_max = 2.0
scale_curve = SubResource("Scale")
color_ramp = SubResource("Ramp")

[sub_resource type="ShaderMaterial" id="SoftPlume"]
shader = ExtResource("2")

[sub_resource type="QuadMesh" id="Puff"]
material = SubResource("SoftPlume")
size = Vector2(3, 3)

[node name="{key}" type="GPUParticles3D"]
script = ExtResource("1")
amount = 96
lifetime = 12.0
randomness = 0.25
local_coords = false
cast_shadow = 0
draw_order = 3
visibility_aabb = AABB(-80, -8, -80, 160, 120, 160)
process_material = SubResource("Process")
draw_pass_1 = SubResource("Puff")
'''
