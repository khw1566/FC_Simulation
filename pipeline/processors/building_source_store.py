"""원본 JSON과 해시 검증된 압축 원본에 동일한 읽기 인터페이스를 제공한다."""
import hashlib
import json
import zipfile
from pathlib import Path


class BuildingSourceStore:
    ROOT = Path(__file__).resolve().parents[2]
    ARCHIVE = ROOT / "data/archives/kanmon_building_sources_20261003.zip"

    @classmethod
    def read(cls, path):
        path = Path(path)
        if path.exists():
            return json.loads(path.read_text(encoding="utf-8-sig"))
        with zipfile.ZipFile(cls.ARCHIVE) as archive:
            return json.loads(archive.read(path.name).decode("utf-8-sig"))

    @classmethod
    def digest(cls, path):
        path = Path(path)
        if path.exists():
            with path.open("rb") as stream:
                return hashlib.file_digest(stream,"sha256").hexdigest()
        with zipfile.ZipFile(cls.ARCHIVE) as archive, archive.open(path.name) as stream:
            return hashlib.file_digest(stream,"sha256").hexdigest()
