"""한 수종당 3 LOD, 1 표면과 경량 원경 카드 생성."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile
from PIL import Image, ImageDraw

SOURCE = Path(__file__).resolve().parent
ROOT = Path(r'C:\Users\work\Desktop\FC_Simulation')
if SOURCE.parent.name == 'processors':
    ROOT = SOURCE.parents[2]
SPECS = {'broadleaf':(9,6),'slender':(11,3.8),'conifer':(12,5),'shrub':(2.2,2.8)}

def card(kind, path):
    image = Image.new('RGBA',(256,512))
    draw = ImageDraw.Draw(image)
    draw.rectangle((119,180,137,511),fill=(82,59,34,255))
    if kind == 'conifer':
        for tip,bottom,width in [(180,422,126),(95,323,105),(2,225,78)]:
            draw.polygon([(128,tip),(128-width,bottom),(128+width,bottom)],fill=(27,76+tip//14,43,255))
    else:
        boxes = [(3,8,253,355)]
        if kind == 'broadleaf':
            boxes = [(32,5,225,272),(1,116,163,363),(89,100,254,355)]
        elif kind == 'slender':
            boxes = [(11,4,245,369)]
            draw.rectangle((120,300,135,511),fill=(165,161,143,255))
        elif kind == 'shrub':
            boxes = [(2,50,254,484)]
        for i,box in enumerate(boxes):
            draw.ellipse(box,fill=(49+i*5,95+i*6,35+i*3,255))
    image.save(path)

def atomic(path, data):
    pending = path.with_name(path.name+'.trees.pending')
    pending.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    os.replace(pending,path)

def main():
    source_dir = ROOT/'godot_project/scripts/vegetation'
    source_dir.mkdir(parents=True,exist_ok=True)
    for name in ['tree_geometry.gd','tree_batch_factory.gd']:
        shutil.copy2(SOURCE/name,source_dir/name)
    output = ROOT/'godot_project/assets/generated/trees'
    output.mkdir(parents=True,exist_ok=True)
    preview = ROOT/'previews/asset_browser/tree_check'
    preview.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='trees_',dir=preview) as tmp:
        stage=Path(tmp)
        tree_dir=stage/'assets/generated/trees'
        tree_dir.mkdir(parents=True)
        script_dir=stage/'scripts/vegetation'
        script_dir.mkdir(parents=True)
        for name in ['tree_geometry.gd','tree_batch_factory.gd']:
            shutil.copy2(source_dir/name,script_dir/name)
        for name in ['export_trees.gd','capture.gd']:
            shutil.copy2(SOURCE/name,stage/name)
        for kind in SPECS:
            card(kind,tree_dir/(kind+'_card.png'))
        (stage/'project.godot').write_text('config_version=5\n[display]\nwindow/size/viewport_width=1600\nwindow/size/viewport_height=1000\n',encoding='utf-8')
        env=os.environ.copy()
        env['APPDATA']=str(stage/'user_data')
        Path(env['APPDATA']).mkdir()
        for script in ['export_trees.gd','capture.gd']:
            result=subprocess.run([str(ROOT/'tools/godot/Godot_v4.3-stable_win64_console.exe'),'--path',str(stage),'--rendering-method','gl_compatibility','--script','res://'+script,'--quit-after','90'],env=env,capture_output=True,text=True,encoding='utf-8',timeout=40,creationflags=subprocess.CREATE_NO_WINDOW)
            print(result.stdout)
            if result.returncode or 'ERROR' in result.stderr:
                raise RuntimeError(result.stderr)
        for file in tree_dir.iterdir():
            pending=output/(file.name+'.pending')
            shutil.copy2(file,pending)
            os.replace(pending,output/file.name)
        shutil.copy2(stage/'tree_preview.png',output/'tree_preview.png')
    manifest=json.loads((output/'manifest.json').read_text(encoding='utf-8'))
    master_path=output.parent/'manifest.json'
    master=json.loads(master_path.read_text(encoding='utf-8'))
    for key,entry in manifest['assets'].items():
        master.setdefault('assets',{})['tree_'+key]=entry
    atomic(master_path,master)
    catalog={'version':1,'kinds':list(SPECS),'lod_ranges_m':[[0,100],[100,350],[350,3000]],'chunk_size_m':64,'assets':manifest['assets']}
    atomic(output/'catalog.json',catalog)

if __name__ == '__main__':
    main()
