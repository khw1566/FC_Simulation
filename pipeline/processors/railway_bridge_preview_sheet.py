"""실제 Godot 렌더 이미지를 철도 교량 종류별 비교 시트로 배치한다."""

from PIL import Image, ImageChops, ImageDraw, ImageFont


def create_preview_sheet(folder):
    canvas = Image.new("RGB", (1600, 1520), (17, 17, 17))
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype("C:/Windows/Fonts/malgun.ttf", 27)
    small = ImageFont.truetype("C:/Windows/Fonts/malgun.ttf", 19)
    draw.text((35, 20), "철도 교량 5종 + 안양교–울산역 연결 세트", font=font, fill="white")
    draw.text((35, 62), "실제 Godot 렌더 / 칸마다 독립 축척 / 단위 m", font=small, fill=(160, 160, 160))
    models = [
        ("rail_box_girder", "복선 콘크리트 박스거더교", "32 m"),
        ("rail_plate_girder", "단선 강판거더교", "24 m"),
        ("rail_through_truss", "복선 강재 트러스교", "72 m"),
        ("rail_deck_arch", "복선 상로 아치교", "120 m"),
        ("rail_multi_viaduct", "복선 다경간 고가교", "160 m"),
        ("anyang_main_bridge", "안양교 병렬 아치 본체", "231.8 m / 상세 부재 근사"),
        ("ulsan_anyang_connected_set", "북측 접근부 → 안양교 → 울산역 방향 접근부 → 역 연결부", "연속 조립 길이 834.8 m / 접근부 배치는 제작 가정"),
    ]
    for index, (key, label, dimensions) in enumerate(models):
        if index < 6:
            x, y = 25 + (index % 2) * 790, 105 + (index // 2) * 345
            width, height = 760, 325
        else:
            x, y, width, height = 25, 1160, 1550, 330
        draw.rounded_rectangle((x, y, x + width, y + height), radius=10,
                               outline=(70, 70, 70), fill=(17, 17, 17))
        source = Image.open(folder / (key + "_preview.png")).convert("RGB")
        background = Image.new("RGB", source.size, source.getpixel((0, 0)))
        bounds = ImageChops.difference(source, background).getbbox()
        if bounds:
            source = source.crop((max(0, bounds[0] - 25), max(0, bounds[1] - 20),
                                  min(source.width, bounds[2] + 25), min(source.height, bounds[3] + 20)))
        source.thumbnail((width - 45, height - 100))
        canvas.paste(source, (x + (width - source.width) // 2, y + 15 + (height - 110 - source.height) // 2))
        draw.text((x + 20, y + height - 78), label, font=font if index < 6 else small, fill="white")
        draw.text((x + 20, y + height - 40), dimensions, font=small, fill=(170, 170, 170))
    canvas.save(folder / "railway_bridge_assets_preview.png")
