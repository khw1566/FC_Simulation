"""Godot 4.3 비암호화 PCK의 파일별 MD5 검사와 정렬 오프셋 복구."""

import hashlib
import struct
from pathlib import Path


class PckIntegrity:
    def __init__(self, path):
        self.path = Path(path)

    @staticmethod
    def legacy_pad(position, alignment=32):
        signed = (position + 2**31) % 2**32 - 2**31
        remainder = signed % alignment if signed >= 0 else -(abs(signed) % alignment)
        return alignment - remainder if remainder > 0 else 0

    def repair_legacy_alignment(self):
        """물리 기록 순서로 전 파일 해시를 확인한 후에만 위치 색인을 복구한다."""
        entries = []
        with self.path.open('rb') as stream:
            header = stream.read(100)
            magic, version, major, minor, patch, flags, base = struct.unpack('<6IQ', header[:32])
            if (magic, version, major, minor, flags) != (0x43504447, 2, 4, 3, 0):
                raise ValueError('지원하지 않는 PCK 헤더')
            count = struct.unpack('<I', header[96:100])[0]
            for _ in range(count):
                length = struct.unpack('<I', stream.read(4))[0]
                name = stream.read(length).rstrip(b'\0').decode('utf-8')
                index_position = stream.tell()
                offset, size = struct.unpack('<QQ', stream.read(16))
                digest = stream.read(16)
                entry_flags = struct.unpack('<I', stream.read(4))[0]
                if entry_flags:
                    raise ValueError('암호화 파일은 지원하지 않습니다.')
                entries.append((name, index_position, offset, size, digest))
            position = base
            corrections = []
            for number, (name, index_position, offset, size, digest) in enumerate(entries, 1):
                stream.seek(position)
                hasher = hashlib.md5()
                remaining = size
                while remaining:
                    data = stream.read(min(remaining, 1024 * 1024))
                    if not data:
                        raise ValueError(f'파일 데이터 부족: {name}')
                    hasher.update(data)
                    remaining -= len(data)
                if hasher.digest() != digest:
                    raise ValueError(f'내용 해시 불일치로 복구 중단: {name}')
                correct_offset = position - base
                if offset != correct_offset:
                    corrections.append((index_position, correct_offset))
                position += size
                position += self.legacy_pad(position)
                if number % 10000 == 0:
                    print(f'PCK 내용 해시 확인: {number}/{count}', flush=True)
            if position != self.path.stat().st_size:
                raise ValueError('PCK 물리 파일 크기 불일치')
        with self.path.open('r+b') as stream:
            for index_position, offset in corrections:
                stream.seek(index_position)
                stream.write(struct.pack('<Q', offset))
        return {'verified_files': count, 'corrected_offsets': len(corrections),
                'bytes': self.path.stat().st_size, 'content_check': 'all_md5_passed'}
