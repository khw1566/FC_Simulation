"""GLB를 보존하며 선박 씬에 작은 항해등 리그를 부착한다."""
import hashlib
import json
import os
from pathlib import Path

def attach(scene, length, beam, deck, kind=""):
    scene = scene.split('\n[node name="NavigationLighting"')[0]
    resource = '[ext_resource type="Script" path="res://scripts/core/asset_marker_lighting.gd" id="2"]'
    scene = scene.replace(resource, '')
    scene = scene.replace('load_steps=2', 'load_steps=3')
    marker = '\n[node name='
    offset = scene.index(marker)
    scene = scene[:offset] + '\n[ext_resource type="Script" path="res://scripts/core/asset_marker_lighting.gd" id="2"]\n' + scene[offset:]
    return scene + f'\n[node name="NavigationLighting" type="Node3D" parent="."]\nscript = ExtResource("2")\nvessel_length = {float(length)}\nvessel_beam = {float(beam)}\nvessel_deck = {float(deck)}\nvessel_kind = "{kind}"\n'

def main():
    root = Path(__file__).resolve().parents[3]
    folder = root / 'godot_project/assets/generated/vessels'
    manifest_path = folder / 'manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    for entry in manifest['assets'].values():
        metadata = entry['metadata']
        scene = root / 'godot_project' / entry['scene_path'].removeprefix('res://')
        kind = scene.stem
        deck = {"container_ship":5.0, "tugboat":2.2, "motor_boat":1.1, "lpg_carrier":4.0, "oil_tanker":5.5, "fishing_boat":1.5}[kind]
        text = attach(scene.read_text(encoding='utf-8'), metadata['length_m'], metadata['beam_m'], deck, kind)
        pending = scene.with_suffix('.lighting.pending')
        pending.write_text(text, encoding='utf-8')
        os.replace(pending, scene)
        entry['scene_sha256'] = hashlib.sha256(scene.read_bytes()).hexdigest()
        metadata['lighting'] = {'marker_count': 4, 'local_light_count': 1, 'energy': 0.2, 'fade_end_m': 100, 'glb_includes_lights': False}
    master_path = folder.parent / 'manifest.json'
    master = json.loads(master_path.read_text(encoding='utf-8'))
    for key, entry in manifest['assets'].items():
        master['assets']['vessel_' + key] = entry
    for path, data in [(manifest_path, manifest), (master_path, master)]:
        pending = path.with_suffix('.lighting.pending')
        pending.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
        os.replace(pending, path)
    print('Vessel lighting scenes: 6; original GLB preserved')

if __name__ == '__main__':
    main()
