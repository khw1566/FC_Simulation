"""이번 수집 원본만 해시 검증 후 압축 보관한다."""
import json
import sys
import zipfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"processors"))
from building_source_store import BuildingSourceStore


class KanmonBuildingSourceCompactor:
    def run(self):
        root = BuildingSourceStore.ROOT
        folder = root/"data/raw/buildings"
        files = [folder/name for name in ["kanmon_straits_buildings_20261003.json","kanmon_gsi_buildings_20261003.json"]]
        archive_path = BuildingSourceStore.ARCHIVE
        archive_path.parent.mkdir(parents=True,exist_ok=True)
        if not all(path.exists() for path in files):
            return
        hashes = {path.name:BuildingSourceStore.digest(path) for path in files}
        temporary = archive_path.with_suffix(".tmp.zip")
        with zipfile.ZipFile(temporary,"w",zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
            for path in files:
                archive.write(path,path.name)
            archive.writestr("source_sha256.json",json.dumps(hashes,indent=2))
        import hashlib
        with zipfile.ZipFile(temporary) as archive:
            for path in files:
                with archive.open(path.name) as stream:
                    assert hashlib.file_digest(stream,"sha256").hexdigest()==hashes[path.name]
        temporary.replace(archive_path)
        before = sum(path.stat().st_size for path in files)
        for path in files:
            assert path.resolve().parent == folder.resolve()
            path.unlink()
        metrics = {"archive":str(archive_path),"original_bytes":before,"archive_bytes":archive_path.stat().st_size,"source_sha256":hashes,"restore_read":"BuildingSourceStore.read / digest가 압축 원본을 직접 읽음"}
        (root/"results/261003_kanmon_building_source_archive.json").write_text(json.dumps(metrics,ensure_ascii=False,indent=2),encoding="utf-8")
        print(json.dumps(metrics,ensure_ascii=False),flush=True)


if __name__=="__main__":
    KanmonBuildingSourceCompactor().run()
