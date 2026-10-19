"""검증된 비암호화 PCK의 일부 파일을 교체하여 별도 패키지를 만든다."""
import hashlib
import struct
from pathlib import Path


class PckRevision:
    @staticmethod
    def create(source, destination, replacements):
        source, destination = Path(source), Path(destination)
        entries = {}
        with source.open('rb') as original:
            header = bytearray(original.read(100))
            magic, version, _, _, _, flags, base = struct.unpack('<6IQ', header[:32])
            if (magic, version, flags) != (0x43504447, 2, 0):
                raise ValueError('지원하지 않는 PCK')
            for _ in range(struct.unpack_from('<I', header, 96)[0]):
                length = struct.unpack('<I', original.read(4))[0]
                name = original.read(length).rstrip(b'\0').decode('utf-8')
                offset, size = struct.unpack('<QQ', original.read(16))
                digest = original.read(16)
                if struct.unpack('<I', original.read(4))[0]:
                    raise ValueError('암호화 파일은 지원하지 않습니다.')
                entries[name] = (offset + base, size, digest, None)
            for name, path in replacements.items():
                data = Path(path).read_bytes()
                entries[name] = (0, len(data), hashlib.md5(data).digest(), data)
            names = {name: name.encode('utf-8') for name in sorted(entries)}
            data_base = 100 + sum(40 + len(name) for name in names.values())
            struct.pack_into('<Q', header, 24, data_base)
            struct.pack_into('<I', header, 96, len(names))
            with destination.open('xb') as output:
                output.write(header)
                relative = 0
                for name, encoded in names.items():
                    _, size, digest, _ = entries[name]
                    output.write(struct.pack('<I', len(encoded)) + encoded)
                    output.write(struct.pack('<QQ', relative, size) + digest + struct.pack('<I', 0))
                    relative += size
                for name in names:
                    offset, size, digest, data = entries[name]
                    if data is not None:
                        output.write(data)
                        continue
                    original.seek(offset)
                    hasher = hashlib.md5()
                    remaining = size
                    while remaining:
                        block = original.read(min(remaining, 1024 * 1024))
                        if not block:
                            raise ValueError(f'PCK 데이터 부족: {name}')
                        hasher.update(block)
                        output.write(block)
                        remaining -= len(block)
                    if hasher.digest() != digest:
                        raise ValueError(f'PCK 내용 손상: {name}')
        return {'verified_files': len(entries), 'replaced_files': sorted(replacements),
                'bytes': destination.stat().st_size}
