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
SPECS = {'bamboo_single':(9,3.0),'bamboo_clump':(9,4.5),'bamboo_grove':(9,9.0)}

def card(kind, path):
    import math
    image = Image.new('RGBA',(512,512))
    draw = ImageDraw.Draw(image)
    width = SPECS[kind][1]
    xs = [0] if kind == 'bamboo_single' else [-0.6,0.55,-0.25,0.65] if kind == 'bamboo_clump' else [-2.8,0.2,2.7,-2.5,0,2.6,-2.7,0.3,2.9]
    for j, x in enumerate(xs):
        height = 9 * (1 - (j%4)*0.055)
        px = int((x / width + 0.5) * 512)
        scale = 512 / width
        top = int(512 * (1-height/9))
        stem_width = max(2,int(0.13*scale))
        draw.line([(px,511),(px,top)],fill=(83,110,32,255),width=stem_width)
        for fraction in [0.24,0.45,0.66]:
            y = int(512 * (1 - height * fraction / 9))
            draw.line([(px-stem_width//2,y),(px+stem_width//2,y)],fill=(55,79,21,255),width=2)
        for i in range(4):
            y = int(512 * (1-height*(0.48+i*0.11)/9))
            angle = j*1.71+i*2.4
            end_x = px + int(math.cos(angle)*1.0*scale)
            end_y = y-int(0.3*512/9)
            draw.line([(px,y),(end_x,end_y)],fill=(60,96,25,255),width=2)
            for sign in [-1,1]:
                leaf_x = end_x + int(sign*0.55*scale)
                leaf_y = end_y - 10
                mid_x = (px+leaf_x)//2
                mid_y = (y+leaf_y)//2
                leaf_width = max(3,int(0.20*512/9))
                draw.polygon([(px,y),(mid_x,mid_y-leaf_width),(leaf_x,leaf_y),(mid_x,mid_y+leaf_width)],fill=(40,88+i*3,24,255))
    image.save(path)


def atomic(path, data):
    pending = path.with_name(path.name+'.trees.pending')
    pending.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    os.replace(pending,path)

def main():
    source_dir = ROOT/'godot_project/scripts/vegetation'
    source_dir.mkdir(parents=True,exist_ok=True)
    for name in ['bamboo_geometry.gd','bamboo_batch_factory.gd']:
        shutil.copy2(SOURCE/name,source_dir/name)
    output = ROOT/'godot_project/assets/generated/bamboo'
    output.mkdir(parents=True,exist_ok=True)
    preview = ROOT/'previews/asset_browser/bamboo_check'
    preview.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='bamboo_',dir=preview) as tmp:
        stage=Path(tmp)
        tree_dir=stage/'assets/generated/bamboo'
        tree_dir.mkdir(parents=True)
        script_dir=stage/'scripts/vegetation'
        script_dir.mkdir(parents=True)
        for name in ['bamboo_geometry.gd','bamboo_batch_factory.gd']:
            shutil.copy2(source_dir/name,script_dir/name)
        shutil.copy2(ROOT/'godot_project/scripts/vegetation/tree_geometry.gd',script_dir/'tree_geometry.gd')
        for name in ['export_bamboo.gd','capture.gd']:
            shutil.copy2(SOURCE/name,stage/name)
        for kind in SPECS:
            card(kind,tree_dir/(kind+'_card.png'))
        (stage/'project.godot').write_text('config_version=5\n[display]\nwindow/size/viewport_width=1600\nwindow/size/viewport_height=1000\n',encoding='utf-8')
        env=os.environ.copy()
        env['APPDATA']=str(stage/'user_data')
        Path(env['APPDATA']).mkdir()
        for script in ['export_bamboo.gd','capture.gd']:
            result=subprocess.run([str(ROOT/'tools/godot/Godot_v4.3-stable_win64_console.exe'),'--path',str(stage),'--rendering-method','gl_compatibility','--script','res://'+script,'--quit-after','90'],env=env,capture_output=True,text=True,encoding='utf-8',timeout=40,creationflags=subprocess.CREATE_NO_WINDOW)
            print(result.stdout)
            if result.returncode or 'ERROR' in result.stderr:
                raise RuntimeError(result.stderr)
        for file in tree_dir.iterdir():
            pending=output/(file.name+'.pending')
            shutil.copy2(file,pending)
            os.replace(pending,output/file.name)
        shutil.copy2(stage/'bamboo_preview.png',output/'bamboo_preview.png')
    manifest=json.loads((output/'manifest.json').read_text(encoding='utf-8'))
    master_path=output.parent/'manifest.json'
    master=json.loads(master_path.read_text(encoding='utf-8'))
    for key,entry in manifest['assets'].items():
        master.setdefault('assets',{})['bamboo_'+key]=entry
    atomic(master_path,master)
    catalog={'version':1,'kinds':list(SPECS),'lod_ranges_m':[[0,70],[70,250],[250,2200]],'chunk_size_m':64,'assets':manifest['assets']}
    atomic(output/'catalog.json',catalog)

if __name__ == '__main__':
    main()
