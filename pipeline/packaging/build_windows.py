"""원본 임포트 캐시를 변경하지 않는 Windows 휴대용 패키지 생성."""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import zipfile
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class WindowsPackageBuilder:
    def __init__(self, version):
        self.version = version
        self.work = ROOT / 'build_artifacts/work' / version
        self.project = self.work / 'project'
        self.output = ROOT / 'build_artifacts/releases' / version
        self.engine = ROOT / 'tools/godot/Godot_v4.3-stable_win64.exe'
        self.environment = dict(os.environ)
        for key, name in [('APPDATA', 'roaming'), ('LOCALAPPDATA', 'local')]:
            path = self.work / name
            path.mkdir(parents=True, exist_ok=True)
            self.environment[key] = str(path)

    def run_engine(self, arguments, name):
        log = self.work / name
        with log.open('w', encoding='utf-8') as stream:
            result = subprocess.run([str(self.engine), '--headless', '--path',
                                     str(self.project), *arguments],
                                    env=self.environment, stdout=stream,
                                    stderr=subprocess.STDOUT, timeout=1800)
        text = log.read_text(encoding='utf-8', errors='replace')
        errors = [line for line in text.splitlines()
                  if 'SCRIPT ERROR:' in line or 'Parse Error:' in line]
        if result.returncode or errors:
            raise RuntimeError(f'빌드 실패: {log}; ' + '\n'.join(errors[:8]))

    def build(self):
        if not self.engine.exists():
            raise FileNotFoundError(self.engine)
        if self.project.exists() or self.output.exists():
            raise RuntimeError('기존 빌드 경로를 보존합니다. 다른 --version을 지정하세요.')
        self.output.mkdir(parents=True)
        shutil.copytree(ROOT / 'godot_project', self.project,
                        ignore=shutil.ignore_patterns('.godot', '*.tmp', '*.log', 'export_presets.cfg'))
        # 지도는 Image/문자열로 직접 읽는다. 원본 데이터와 이력은 임포트 스캔에서 제외한다.
        (self.project / 'assets/maps/.gdignore').write_text('', encoding='utf-8')
        print('격리 프로젝트 복사 완료. 임포트 시작.', flush=True)
        self.run_engine(['--editor', '--import'], 'import.log')
        files = []
        for path in self.project.rglob('*'):
            if not path.is_file():
                continue
            relative = path.relative_to(self.project).as_posix()
            if relative.startswith('.godot/') and not (
                    relative.startswith('.godot/imported/') or
                    relative in ('.godot/global_script_class_cache.cfg', '.godot/uid_cache.bin')):
                continue
            files.append(relative)
        listing = self.work / 'pack_files.json'
        listing.write_text(json.dumps(sorted(files)), encoding='utf-8')
        pck = self.output / 'FC_Simulation.pck'
        self.run_engine(['--script', str(ROOT / 'pipeline/packaging/pack_project.gd'),
                         '--', str(listing), str(pck)], 'pack.log')
        if not pck.exists() or pck.stat().st_size == 0:
            raise RuntimeError('PCK 산출물이 없습니다.')
        shutil.copy2(self.engine, self.output / 'FC_Simulation.exe')
        launcher = '@echo off\r\ncd /d "%~dp0"\r\nstart "" "FC_Simulation.exe" --main-pack "FC_Simulation.pck"\r\n'
        (self.output / '실행.bat').write_bytes(launcher.encode('ascii'))
        (self.output / 'README.md').write_text(
            '# FC Simulation Windows 패키지\n'
            '전체 폴더를 함께 보관하고 `실행.bat` 또는 `FC_Simulation.exe`를 실행하세요.\n\n'
            '- Godot 4.3 엔진을 포함하므로 별도 엔진 설치가 필요 없습니다.\n'
            '- 기본 그래픽은 Forward Plus입니다. 호환 모드는 실행 명령에 '
            '`--rendering-method gl_compatibility`를 추가하세요.\n'
            '- 원본 이미지·GLB·JSON과 임포트 결과를 함께 PCK에 넣어 런타임 직접 읽기를 보존했습니다.\n'
            '- 지도 선택 메뉴까지만 경량 확인했으며 전체 지도 로딩과 장시간 실행은 미검증입니다.\n',
            encoding='utf-8')
        # 지도 선택 메뉴에서 종료한다. 전체 지도는 로딩하지 않는다.
        with (self.work / 'startup.log').open('w', encoding='utf-8') as stream:
            result = subprocess.run([str(self.output / 'FC_Simulation.exe'), '--headless',
                '--main-pack', str(pck), '--quit-after', '3'], cwd=self.output,
                env=self.environment, stdout=stream, stderr=subprocess.STDOUT, timeout=90)
        startup = (self.work / 'startup.log').read_text(encoding='utf-8', errors='replace')
        if result.returncode or 'SCRIPT ERROR:' in startup or 'ERROR:' in startup:
            raise RuntimeError('패키지 시작 확인 실패: ' + str(self.work / 'startup.log'))
        manifest = {'version': self.version, 'created': datetime.now().isoformat(),
                    'engine': 'Godot 4.3 stable Windows x86_64',
                    'packaged_files': len(files), 'startup_menu_check': 'passed',
                    'full_map_check': 'not_run', 'files': {}}
        for path in self.output.iterdir():
            if path.is_file():
                digest = hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()
                manifest['files'][path.name] = {'bytes': path.stat().st_size, 'sha256': digest}
        (self.output / 'package_manifest.json').write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
        archive = self.output.with_suffix('.zip')
        print('패키지 메뉴 시작 확인 완료. ZIP 생성 시작.', flush=True)
        with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED,
                             compresslevel=1, allowZip64=True) as zipped:
            for path in self.output.iterdir():
                if path.is_file():
                    zipped.write(path, self.output.name + '/' + path.name)
        report = {'folder': str(self.output), 'archive': str(archive),
                  'archive_bytes': archive.stat().st_size,
                  'archive_sha256': hashlib.file_digest(archive.open('rb'), 'sha256').hexdigest(),
                  'packaged_files': len(files), 'startup_menu_check': 'passed'}
        (ROOT / 'results' / '261005_WindowsPackaging.json').write_text(
            json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
        print(json.dumps(report, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', default='FC_Simulation_20261005_windows_x64')
    WindowsPackageBuilder(parser.parse_args().version).build()
