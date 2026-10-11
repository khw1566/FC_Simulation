"""생태 구역별 512px 반복(타일러블) 바닥 텍스처를 절차적으로 그린다."""
import numpy as np
from PIL import Image, ImageDraw

SIZE = 512

# 기본색, 보조색, 획 색 목록, 획 형태(blade|leaf|dot), 획 수, 획 길이(px)
STYLES = {
    "lawn": ((70, 118, 46), (98, 148, 60), [(88, 140, 52), (60, 104, 40), (112, 160, 70)], "blade", 9000, 7),
    "silvergrass_ground": ((176, 142, 78), (214, 184, 116), [(236, 214, 156), (204, 166, 92), (160, 124, 64), (190, 176, 140)], "blade", 9000, 16),
    "bamboo_litter": ((78, 62, 40), (110, 88, 54), [(150, 122, 70), (124, 98, 56), (92, 104, 50)], "leaf", 2600, 18),
    "reed_mud": ((92, 104, 58), (124, 126, 74), [(108, 124, 64), (140, 128, 84), (86, 96, 52), (128, 104, 86)], "blade", 8000, 14),
    "woodland_soil": ((62, 52, 38), (88, 74, 50), [(70, 92, 44), (110, 86, 52), (52, 70, 36)], "leaf", 1800, 10),
    "canopy_bamboo": ((52, 86, 36), (84, 124, 52), [(70, 112, 44), (96, 140, 60), (44, 74, 30)], "leaf", 9000, 14),
    "canopy_broadleaf": ((44, 70, 34), (78, 108, 48), [(58, 92, 40), (90, 122, 56), (36, 58, 28)], "dot_leaf", 5000, 16),
    "meadow": ((100, 128, 56), (132, 150, 72), [(120, 148, 64), (90, 120, 50), (228, 220, 180), (214, 190, 70), (150, 120, 170)], "dot", 7000, 6),
}


def tile_noise(rng, cells):
    grid = rng.random((cells, cells))
    coords = np.arange(SIZE) * cells / SIZE
    i0 = np.floor(coords).astype(int) % cells
    i1 = (i0 + 1) % cells
    t = coords - np.floor(coords)
    t = t * t * (3 - 2 * t)
    rows = grid[i0][:, i0] * (1 - t)[None, :] + grid[i0][:, i1] * t[None, :]
    rows_next = grid[i1][:, i0] * (1 - t)[None, :] + grid[i1][:, i1] * t[None, :]
    return rows * (1 - t)[:, None] + rows_next * t[:, None]


def render(name, seed):
    base, alt, strokes, shape, count, length = STYLES[name]
    rng = np.random.default_rng(seed)
    noise = 0.55 * tile_noise(rng, 6) + 0.3 * tile_noise(rng, 24) + 0.15 * tile_noise(rng, 96)
    mix = noise[..., None]
    pixels = np.array(base, dtype=np.float32) * (1 - mix) + np.array(alt, dtype=np.float32) * mix
    image = Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8), "RGB")
    draw = ImageDraw.Draw(image)
    for _ in range(count):
        color = strokes[int(rng.integers(len(strokes)))]
        x, y = rng.uniform(0, SIZE, 2)
        size = length * rng.uniform(0.5, 1.2)
        angle = rng.uniform(0, np.pi) if shape != "blade" else rng.normal(-np.pi / 2, 0.45)
        for ox in (-SIZE, 0, SIZE):
            for oy in (-SIZE, 0, SIZE):
                _stroke(draw, shape, x + ox, y + oy, size, angle, color)
    return image


def _stroke(draw, shape, x, y, size, angle, color):
    if shape == "dot_leaf":
        r = size * 0.45
        draw.ellipse([x - r, y - r * 0.8, x + r, y + r * 0.8], fill=color)
        return
    if shape == "dot":
        if color[0] > 140:
            r = size * 0.25
            draw.ellipse([x - r, y - r, x + r, y + r], fill=color)
        else:
            draw.line([(x, y), (x + np.cos(angle) * size, y + np.sin(angle) * size)], fill=color, width=1)
        return
    dx, dy = np.cos(angle) * size, np.sin(angle) * size
    if shape == "blade":
        draw.line([(x, y), (x + dx, y + dy)], fill=color, width=1)
        return
    nx, ny = -dy * 0.18, dx * 0.18
    draw.polygon([(x, y), (x + dx / 2 + nx, y + dy / 2 + ny), (x + dx, y + dy), (x + dx / 2 - nx, y + dy / 2 - ny)], fill=color)


def render_silvergrass_card(seed):
    """원경 억새 카드 512×256 RGBA: 왼쪽 절반 옆모습(꽃대·숙인 이삭), 오른쪽 절반 위에서 본 이삭 덩이."""
    rng = np.random.default_rng(seed)
    # 투명 영역 RGB를 황금색으로 채워 밉맵·필터링 시 가장자리가 검게 번지지 않게 한다.
    image = Image.new("RGBA", (512, 256), (214, 184, 118, 0))
    draw = ImageDraw.Draw(image)
    stems = [(176, 140, 76, 255), (196, 158, 88, 255), (150, 118, 64, 255)]
    plumes = [(240, 220, 168, 255), (226, 200, 140, 255), (250, 236, 196, 255)]
    for _ in range(46):
        x = rng.uniform(8, 248)
        top = rng.uniform(30, 110)
        lean = rng.uniform(-14, 14)
        draw.line([(x, 255), (x + lean, top)], fill=stems[int(rng.integers(3))], width=2)
        for k in range(4):
            dx = lean * 0.2 + rng.uniform(-10, 10)
            draw.line([(x + lean, top), (x + lean + dx, top + rng.uniform(18, 34))], fill=plumes[int(rng.integers(3))], width=3)
    for _ in range(14):
        x = rng.uniform(10, 246)
        draw.polygon([(x - 4, 255), (x + rng.uniform(-30, 30), rng.uniform(120, 180)), (x + 4, 255)], fill=(150, 130, 70, 255))
    for _ in range(220):
        cx, cy = rng.uniform(262, 506), rng.uniform(6, 250)
        r = rng.uniform(5, 13)
        color = plumes[int(rng.integers(3))] if rng.uniform() < 0.7 else stems[int(rng.integers(3))]
        draw.ellipse([cx - r, cy - r * 0.6, cx + r, cy + r * 0.6], fill=color)
    return image


def render_all(folder, seed):
    folder.mkdir(parents=True, exist_ok=True)
    written = {}
    for index, name in enumerate(STYLES):
        path = folder / f"{name}.png"
        temporary = path.with_name(path.stem + ".partial.png")
        render(name, seed + index).save(temporary)
        temporary.replace(path)
        written[name] = path
    card = folder / "silvergrass_card.png"
    temporary = card.with_name("silvergrass_card.partial.png")
    render_silvergrass_card(seed + 99).save(temporary)
    temporary.replace(card)
    written["silvergrass_card"] = card
    return written
