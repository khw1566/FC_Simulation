from pathlib import Path
import json
entry={'class_name':'RailwayFormationBuilder','path':'godot_project/scripts/terrain/railway_formation_builder.gd','responsibility':'철도 절성토 도상의 측면 및 매립 기초 메시 생성'}
for name in ['module_index.json','godot_project/module_index.json']:
 p=Path(name);d=json.loads(p.read_text(encoding='utf-8-sig'));m=d['domains']['terrain']['modules']
 if not any(item.get('path')==entry['path'] for item in m):m.append(entry)
 p.write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
