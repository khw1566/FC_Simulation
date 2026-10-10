"""구역 라벨 위에 격자(정사각·육각) 또는 블루 노이즈 배치를 깔아 식생 인스턴스 변환을 만든다.

숲은 lattice="blue"(회전된 층화 지터 격자: 줄무늬 없는 최소 간격 배치)와 저주파 밀도 변화,
가장자리 솎아내기, kinds 가중치에 따른 수종·형태 혼합을 쓴다.
"""
import numpy as np


class ScatterPlanner:
    FIELDS = ["x", "y", "z", "yaw_deg", "scale"]

    def __init__(self, raster, heights, seed):
        self.raster = raster
        self.heights = heights
        self.seed = int(seed)
        self.obstacle_distance = None

    def set_obstacles(self, obstacle_distance):
        """차도·건물·수면까지의 거리(m). 개체 반경(clearance_m)보다 가까우면 놓지 않는다."""
        self.obstacle_distance = obstacle_distance

    def plan(self, rule, index, labels, zone_id, edge_distance):
        rows, cols = np.nonzero(labels == zone_id)
        if rows.size == 0:
            return [self._layer(dict(rule, kind=k), np.zeros((0, 5), dtype=np.float32)) for k in rule.get("kinds", [rule.get("kind")])]
        half = self.raster.world_size_m / 2.0
        cell = self.raster.cell_m
        x0, x1 = cols.min() * cell - half, cols.max() * cell - half
        z0, z1 = rows.min() * cell - half, rows.max() * cell - half
        xs, zs = self._lattice(rule, index, x0, x1, z0, z1)
        u, v = self.raster.world_to_pixel(xs, zs)
        ui = np.clip(np.rint(u).astype(int), 0, self.raster.size - 1)
        vi = np.clip(np.rint(v).astype(int), 0, self.raster.size - 1)
        keep = labels[vi, ui] == zone_id
        edge = edge_distance[vi, ui]
        if "min_edge_m" in rule:
            keep &= edge >= float(rule["min_edge_m"])
        if "max_edge_m" in rule:
            keep &= edge < float(rule["max_edge_m"])
        xs, zs = xs[keep], zs[keep]
        rng = np.random.default_rng(self.seed + index * 7919)
        thin = self._thinning(rule, xs, zs, edge[keep], rng)
        xs, zs = xs[thin], zs[thin]
        jitter = float(rule.get("jitter_m", 0.0))
        xs = xs + rng.uniform(-jitter, jitter, xs.size)
        zs = zs + rng.uniform(-jitter, jitter, zs.size)
        # 흔들린 최종 위치에서 구역 소속과 장애물 여유 거리를 다시 확인한다.
        u, v = self.raster.world_to_pixel(xs, zs)
        ui = np.clip(np.rint(u).astype(int), 0, self.raster.size - 1)
        vi = np.clip(np.rint(v).astype(int), 0, self.raster.size - 1)
        keep = labels[vi, ui] == zone_id
        if self.obstacle_distance is not None:
            keep &= self.obstacle_distance[vi, ui] >= float(rule.get("clearance_m", 1.5))
        xs, zs = xs[keep], zs[keep]
        step = float(rule.get("yaw_step_deg", 0))
        yaw = rng.integers(0, int(360 / step), xs.size) * step if step > 0 else rng.uniform(0, 360, xs.size)
        scale = rng.uniform(rule["scale"][0], rule["scale"][1], xs.size)
        ys = self._height(xs, zs)
        data = np.stack([xs, ys, zs, yaw, scale], axis=1).astype(np.float32)
        if "kinds" not in rule:
            return [self._layer(rule, data)]
        # 수종·형태 혼합: 가중치대로 개체마다 형태를 고르고 형태별 레이어로 나눈다.
        kinds = list(rule["kinds"])
        weights = np.array([float(rule["kinds"][k]) for k in kinds])
        pick = rng.choice(len(kinds), size=data.shape[0], p=weights / weights.sum())
        return [self._layer(dict(rule, kind=kind), data[pick == i]) for i, kind in enumerate(kinds)]

    def _thinning(self, rule, xs, zs, edge, rng):
        """저주파 밀도 변화(density_noise 0~1)와 가장자리 솎아내기(edge_thin_m)로 남길 개체를 고른다."""
        keep_prob = np.ones(xs.size)
        amount = float(rule.get("density_noise", 0.0))
        if amount > 0.0:
            phase = rng.uniform(0, 2 * np.pi, 4)
            noise = (np.sin(xs * 0.021 + phase[0]) * np.sin(zs * 0.017 + phase[1]) * 0.6
                     + np.sin((xs - zs) * 0.009 + phase[2]) * 0.4)
            keep_prob *= 1.0 - amount * (0.5 + 0.5 * noise)
        edge_thin = float(rule.get("edge_thin_m", 0.0))
        if edge_thin > 0.0:
            keep_prob *= np.clip(edge / edge_thin, 0.35, 1.0)
        return rng.uniform(0, 1, xs.size) < keep_prob

    def _lattice(self, rule, index, x0, x1, z0, z1):
        spacing = float(rule["spacing_m"])
        offset = (index * 0.37 % 1.0) * spacing
        if rule.get("lattice") == "blue":
            return self._blue(spacing, index, x0, x1, z0, z1)
        if rule.get("lattice") == "hex":
            row_step = spacing * np.sqrt(3) / 2
            zs_line = np.arange(z0 + offset, z1 + row_step, row_step)
            grids = []
            for row, z in enumerate(zs_line):
                shift = spacing / 2 if row % 2 else 0.0
                line = np.arange(x0 + offset + shift, x1 + spacing, spacing)
                grids.append(np.stack([line, np.full(line.size, z)], axis=1))
            points = np.concatenate(grids) if grids else np.zeros((0, 2))
            return points[:, 0], points[:, 1]
        gx, gz = np.meshgrid(np.arange(x0 + offset, x1 + spacing, spacing), np.arange(z0 + offset, z1 + spacing, spacing))
        return gx.ravel(), gz.ravel()

    def _blue(self, spacing, index, x0, x1, z0, z1):
        """회전된 격자 칸마다 한 점을 칸 안에서 무작위로 둔다(층화 지터). 이웃 칸 점끼리 최소 약 0.1칸 떨어진다."""
        rng = np.random.default_rng(self.seed * 3 + index)
        angle = rng.uniform(0, np.pi / 2)
        cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
        radius = np.hypot(x1 - x0, z1 - z0) / 2 + spacing
        steps = np.arange(-radius, radius, spacing)
        gx, gz = np.meshgrid(steps, steps)
        gx = gx.ravel() + rng.uniform(0.05, 0.95, gx.size) * spacing
        gz = gz.ravel() + rng.uniform(0.05, 0.95, gz.size) * spacing
        c, s = np.cos(angle), np.sin(angle)
        xs, zs = cx + gx * c - gz * s, cz + gx * s + gz * c
        inside = (xs >= x0) & (xs <= x1) & (zs >= z0) & (zs <= z1)
        return xs[inside], zs[inside]

    def _height(self, xs, zs):
        size = self.heights.shape[0]
        u = (xs / self.raster.world_size_m + 0.5) * (size - 1)
        v = (zs / self.raster.world_size_m + 0.5) * (size - 1)
        u0 = np.clip(np.floor(u).astype(int), 0, size - 2)
        v0 = np.clip(np.floor(v).astype(int), 0, size - 2)
        fu, fv = np.clip(u - u0, 0, 1), np.clip(v - v0, 0, 1)
        h = self.heights
        top = h[v0, u0] * (1 - fu) + h[v0, u0 + 1] * fu
        bottom = h[v0 + 1, u0] * (1 - fu) + h[v0 + 1, u0 + 1] * fu
        return top * (1 - fv) + bottom * fv

    def _layer(self, rule, data):
        rounded = np.round(data.astype(np.float64), 2)
        return {
            "zone": rule["zone"],
            "family": rule["family"],
            "kind": rule["kind"],
            "lattice": rule.get("lattice", "square"),
            "spacing_m": rule["spacing_m"],
            "count": int(data.shape[0]),
            "fields": self.FIELDS,
            "data": rounded.ravel().tolist(),
        }
