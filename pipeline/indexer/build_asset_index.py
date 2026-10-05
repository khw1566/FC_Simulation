"""전체 에셋 색인과 분류별 지침용 요약을 수동 갱신."""

import json
import os
import sys
from collections import Counter,defaultdict
from datetime import datetime,timezone
from pathlib import Path
from asset_inventory import collect,CATEGORIES

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'pipeline/processors'))
from simple_maps.publish import atomic


def main():
    output=ROOT/'godot_project/assets/asset_index.json'
    lock=output.with_suffix('.lock')
    descriptor=os.open(lock,os.O_CREAT|os.O_EXCL|os.O_WRONLY)
    try:
        previous=json.loads(output.read_text(encoding='utf-8')) if output.exists() else {}
        files,pending=collect(ROOT,previous)
        groups=defaultdict(list)
        for item in files: groups[item['category']].append(item)
        counts={key:dict(Counter(item['role'] for item in items)) for key,items in sorted(groups.items())}
        atomic(output,{'version':1,'updated_utc':datetime.now(timezone.utc).isoformat(),
                       'scope':['godot_project/assets','godot_project/shaders'],
                       'excluded':['.import','.godot','index outputs','temporary files'],
                       'categories':counts,'pending':pending,'files':files})
        lines=['# 전체 에셋 인덱스','수동 갱신 결과. 상세 경로·SHA256·원본 매니페스트 메타데이터는 `asset_index.json`을 참조한다.',
               '',f'총 {len(files):,}개 파일. 쓰기 중 보류 {len(pending)}개. 지도 리비전은 보존된 자료이며 활성 여부를 추정하지 않는다.','',
               '| 분류 | 파일 수 | 구성 |','|---|---:|---|']
        for key,items in sorted(groups.items()):
            roles=', '.join(f'{role} {count}' for role,count in counts[key].items())
            lines.append(f'| {CATEGORIES.get(key,"기타")} ({key}) | {len(items):,} | {roles} |')
        lines+=['','## 모델 및 씬 목록','같은 이름의 GLB와 씬은 같은 에셋의 표현 파일이며 별도 모델 종류로 중복 계산하지 않는다.','']
        for key,items in sorted(groups.items()):
            models=[item for item in items if item['role'] in ('모델','씬')]
            if not models: continue
            lines+=['### '+CATEGORIES.get(key,key)]
            for item in models:
                lines.append('- '+(item['label_ko']+' — ' if item['label_ko'] else '')+'`'+item['path']+'`')
        if pending: lines+=['','## 다음 갱신에서 재조사할 파일']+['- `'+p+'`' for p in pending]
        report=output.with_name('ASSET_INDEX.md')
        temp=report.with_name(report.name+f'.{os.getpid()}.tmp')
        temp.write_text('\n'.join(lines)+'\n',encoding='utf-8'); os.replace(temp,report)
        for index in (ROOT/'module_index.json',ROOT/'godot_project/module_index.json'):
            before=index.read_bytes(); doc=json.loads(before)
            section=next(k for k in doc if k!='metadata' and isinstance(doc[k],dict))
            doc[section]['asset_inventory']={'description':'전체 에셋 수동 분류와 색인',
                'modules':[{'path':'pipeline/indexer/'+name,'responsibility':description} for name,description in
                           [('asset_inventory.py','안정된 에셋 조사·분류'),('build_asset_index.py','수동 색인 갱신')]]}
            if index.read_bytes()!=before: raise RuntimeError('모듈 인덱스 동시 변경: 재실행 필요')
            atomic(index,doc)
        print(json.dumps({'files':len(files),'categories':counts,'pending':len(pending)},ensure_ascii=False))
    finally:
        os.close(descriptor); lock.unlink()


if __name__=='__main__': main()
