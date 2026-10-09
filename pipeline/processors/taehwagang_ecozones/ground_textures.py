"""생태 구역별 512px 반복(타일러블) 바닥 텍스처를 절차적으로 그린다."""
import numpy as np
from PIL import Image, ImageDraw

SIZE = 512

# 기본색, 보조색, 획 색 목록, 획 형태(blade|leaf|dot), 획 수, 획 길이(px)
STYLES = {
    "lawn": ((70, 118, 46), (98, 148, 60), [(88, 140, 52), (60, 104, 40), (112, 160, 70)], "blade", 9000, 7),
    "silvergrass_ground": ((150, 134, 88), (186, 168, 116), [(206, 190, 140), (160, 140, 90), (120, 110, 70)], "blade", 6500, 16),
    "bamboo_litter": ((78, 62, 40), (110, 88, 54), [(150, 122, 70), (124, 98, 56), (92, 104, 50)], "leaf", 2600, 18),
    "reed_mud": ((86, 80, 64), (108, 100, 78), [(96, 110, 62), (124, 118, 80), (70, 66, 52)], "blade", 3200, 12),
    "woodland_soil": ((62, 52, 38), (88, 74, 50), [(70, 92, 44), (110, 86, 52), (52, 70, 36)], "leaf", 1800, 10),
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


def render_all(folder, seed):
    folder.mkdir(parents=True, exist_ok=True)
    written = {}
    for index, name in enumerate(STYLES):
        path = folder / f"{name}.png"
        temporary = path.with_name(path.stem + ".partial.png")
        render(name, seed + index).save(temporary)
        temporary.replace(path)
        written[name] = path
    return written
