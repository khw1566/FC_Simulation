"""전국 파일을 내려받지 않고 캐시된 HTTP Range로 필요한 바이트만 읽는다."""
import json
import time
import urllib.request
from pathlib import Path


class PMTilesRangeSource:
    CHUNK = 1024 * 1024

    def __init__(self, url, cache, max_requests=300):
        self.url = url
        self.cache = Path(cache)
        self.cache.mkdir(parents=True, exist_ok=True)
        self.max_requests = max_requests
        self.calls = 0
        self.bytes = 0
        self.memory = {}

    def __call__(self, offset, length):
        pieces = []
        end = offset + length
        for chunk_id in range(offset // self.CHUNK, (end - 1) // self.CHUNK + 1):
            start = chunk_id * self.CHUNK
            path = self.cache / f"{start}.bin"
            if chunk_id not in self.memory:
                if not path.exists():
                    if self.calls >= self.max_requests:
                        raise RuntimeError("실행당 HTTP 호출 예산 초과. 캐시는 보존되며 재실행 가능")
                    request = urllib.request.Request(self.url, headers={
                        "Range": f"bytes={start}-{start + self.CHUNK - 1}",
                        "User-Agent": "KanmonTerrainBuildingCollector/1.0"})
                    for attempt in range(3):
                        self.calls += 1
                        try:
                            with urllib.request.urlopen(request, timeout=40) as response:
                                content_range = response.headers.get("Content-Range", "")
                                if response.status != 206 or not content_range.startswith(f"bytes {start}-"):
                                    raise RuntimeError("서버가 요청 범위와 다른 응답을 반환함")
                                data = response.read(self.CHUNK + 1)
                                if len(data) > self.CHUNK:
                                    raise RuntimeError("부분 다운로드 크기 초과")
                            self.bytes += len(data)
                            path.write_bytes(data)
                            time.sleep(0.5)
                            break
                        except Exception:
                            if attempt == 2:
                                raise
                            time.sleep(2 ** (attempt + 1))
                self.memory[chunk_id] = path.read_bytes()
            data = self.memory[chunk_id]
            pieces.append(data[max(0, offset-start):min(len(data), end-start)])
        return b"".join(pieces)

    def save_metrics(self, path):
        Path(path).write_text(json.dumps({"source": self.url, "http_requests": self.calls,
            "download_bytes": self.bytes, "cache_chunks": len(list(self.cache.glob("*.bin"))),
            "range_chunk_bytes": self.CHUNK, "max_requests_per_run": self.max_requests}, indent=2), encoding="utf-8")
