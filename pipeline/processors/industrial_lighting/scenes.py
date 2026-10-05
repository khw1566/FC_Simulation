"""재사용 발광 메시·실제 광원으로 정적 조명 씬 직렬화."""

COLORS={'warm':(1,.64,.3),'cool':(.55,.77,1),'red':(1,.12,.055)}


def vector(values): return ', '.join(str(round(v,5)) for v in values)


def scene(fixtures,lights):
    resources=[]; nodes=[]; meshes={}
    for tint,color in COLORS.items():
        resources.append(f'''[sub_resource type="StandardMaterial3D" id="Mat_{tint}"]
albedo_color = Color({vector(color)}, 1)
emission_enabled = true
emission = Color({vector(color)}, 1)
emission_energy_multiplier = 2.5
roughness = 0.5
''')
        resources.append(f'''[sub_resource type="ShaderMaterial" id="Halo_{tint}"]
shader = ExtResource("2")
shader_parameter/tint = Color({vector(color)}, 1)
shader_parameter/strength = 0.55
''')
        resources.append(f'''[sub_resource type="QuadMesh" id="HaloMesh_{tint}"]
material = SubResource("Halo_{tint}")
size = Vector2(2.4, 2.4)
''')
    nodes.append('[node name="NightLighting" type="Node3D"]\nscript = ExtResource("1")\n')
    for i,(kind,p,size,tint,angle) in enumerate(fixtures):
        key=(kind,size,tint)
        if key not in meshes:
            resource=f'Fixture{len(meshes)}'; meshes[key]=resource
            shape=(f'[sub_resource type="SphereMesh" id="{resource}"]\nradius = {size[0]/2}\nheight = {size[0]}\nradial_segments = 8\nrings = 4\n'
                   if kind=='sphere' else f'[sub_resource type="BoxMesh" id="{resource}"]\nsize = Vector3({vector(size)})\n')
            resources.append(shape+f'material = SubResource("Mat_{tint}")\n')
        nodes.append(f'''[node name="Fixture{i}" type="MeshInstance3D" parent="."]
position = Vector3({vector(p)})
rotation = Vector3(0, {angle}, 0)
cast_shadow = 0
mesh = SubResource("{meshes[key]}")
''')
        if kind=='sphere':
            nodes.append(f'''[node name="Halo{i}" type="MeshInstance3D" parent="."]
position = Vector3({vector(p)})
cast_shadow = 0
mesh = SubResource("HaloMesh_{tint}")
''')
    for i,item in enumerate(lights):
        spot=item['rotation'] is not None
        nodes.append(f'''[node name="Light{i}" type="{'SpotLight3D' if spot else 'OmniLight3D'}" parent="."]
position = Vector3({vector(item['position'])})
light_color = Color({vector(COLORS[item['tint']])}, 1)
light_energy = {item['energy']}
shadow_enabled = false
distance_fade_enabled = true
distance_fade_begin = 350.0
distance_fade_length = 200.0
'''+(f'rotation = Vector3({vector(item["rotation"])})\nspot_range = {item["range"]}\nspot_angle = 44.0\nspot_attenuation = 0.7\n' if spot
             else f'omni_range = {item["range"]}\nomni_attenuation = 0.8\n'))
    return f'''[gd_scene load_steps={len(resources)+3} format=3]

[ext_resource type="Script" path="res://scripts/industrial_lighting/night_lighting.gd" id="1"]
[ext_resource type="Shader" path="res://shaders/industrial_lamp_halo.gdshader" id="2"]

'''+ '\n'.join(resources)+'\n'+'\n'.join(nodes)
