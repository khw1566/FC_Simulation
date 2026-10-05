"""프리뷰 전용 이미지로 터널 두 형식의 비교 시트를 작성한다."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


def make_sheet():
    folder = Path(__file__).resolve().parent / "images"
    canvas = Image.new("RGB", (1600, 1160), (17, 17, 17))
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype("C:/Windows/Fonts/malgun.ttf", 28)
    small = ImageFont.truetype("C:/Windows/Fonts/malgun.ttf", 19)
    draw.text((30, 20), "고속철도용 / 동해선용 범용 터널", font=font, fill="white")
    draw.text((30, 64), "실제 Godot 렌더 / 각 칸 독립 축척 / 내부 구조 확인용 씬 포함", font=small, fill=(165, 165, 165))
    for i, (key, label, detail) in enumerate([
        ("hsr_tunnel_entry", "고속철도용 입구", "확폭 갱구 / 넓은 복선 단면 / 슬래브 궤도"),
        ("donghae_tunnel_entry", "동해선용 입구", "콘크리트 갱구 / 복선 단면 / 자갈 궤도"),
        ("hsr_tunnel_inspection", "고속철도용 내부 구조", "연결 세트 64 m / 보행로 · 배수로 · 가선 · 조명"),
        ("donghae_tunnel_inspection", "동해선용 내부 구조", "연결 세트 52 m / 내부 모듈 반복 연결 가능"),
    ]):
        x, y = 20 + (i % 2) * 790, 110 + (i // 2) * 515
        draw.rounded_rectangle((x, y, x + 760, y + 495), radius=12, outline=(65, 65, 65))
        image = Image.open(folder / (key + ".png")).convert("RGB")
        image.thumbnail((740, 395))
        canvas.paste(image, (x + (760 - image.width) // 2, y + 8))
        draw.text((x + 20, y + 410), label, font=font, fill="white")
        draw.text((x + 20, y + 452), detail, font=small, fill=(165, 165, 165))
    canvas.save(folder / "railway_tunnels_preview.png")


if __name__ == "__main__":
    make_sheet()
