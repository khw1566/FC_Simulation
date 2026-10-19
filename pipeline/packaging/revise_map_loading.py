"""기존 패키지를 보존하며 지도 캐시 검사 수정본을 별도 생성한다."""
import json
import shutil
from .build_windows import ROOT, WindowsPackageBuilder
from .pck_revision import PckRevision


def revise():
    previous = 'FC_Simulation_20261012_windows_x64'
    builder = WindowsPackageBuilder(previous + '_v2')
    builder.project = ROOT / 'build_artifacts/work' / previous / 'project'
    builder.output.mkdir(exist_ok=True, parents=True)
    paths = ['scripts/terrain/cache_source_validator.gd',
             'scripts/terrain/vector_data_stream.gd',
             'scripts/terrain/railway_terrain_void.gd',
             'scripts/terrain/module_index.json',
             'scripts/terrain/terrain_chunk.gd',
             'scripts/terrain/terrain_chunk_mesher.gd',
             'scripts/terrain/road_formation_field.gd',
             'scripts/terrain/road_earthwork_detail.gd',
             'scripts/models/render_quality_profile.gd']
    replacements = {}
    for relative in paths:
        path = ROOT / 'godot_project' / relative
        shutil.copy2(path, builder.project / relative)
        replacements['res://' + relative] = path
    report = PckRevision.create(
        ROOT / 'build_artifacts/releases' / previous / 'FC_Simulation.pck',
        builder.output / 'FC_Simulation.pck', replacements)
    (builder.work / 'pck_revision.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report), flush=True)


if __name__ == '__main__':
    revise()
