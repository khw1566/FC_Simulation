"""API 키를 환경변수 우선, 로컬 키 파일 차선으로 읽는다. 키는 저장소에 기록하지 않는다."""
import json
import os
from pathlib import Path


class ApiKeyResolver:
    def __init__(self, root, env_name, file_field, key_file="data/api_keys.json"):
        self.root = Path(root)
        self.env_name = env_name
        self.file_field = file_field
        self.key_file = self.root / key_file

    def resolve(self):
        value = os.environ.get(self.env_name, "").strip()
        if value:
            return value, f"env:{self.env_name}"
        if self.key_file.exists():
            keys = json.loads(self.key_file.read_text(encoding="utf-8-sig"))
            value = str(keys.get(self.file_field, "")).strip()
            if value:
                return value, f"file:{self.key_file.relative_to(self.root).as_posix()}"
        return "", None
