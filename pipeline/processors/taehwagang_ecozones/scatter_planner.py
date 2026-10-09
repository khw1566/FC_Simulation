"""구역 라벨 위에 정사각·육각 규칙 격자를 깔아 식생 인스턴스 변환을 만든다."""
import numpy as np


class ScatterPlanner:
    FIELDS = ["x", "y", "z", "yaw_deg", "scale"]

    def __init__(self, raster, heights, seed):
        self.raster = raster
        self.heights = heights
        self.seed = int(seed)

    def plan(self, rule, index, labels, zone_id, edge_distance):
        rows, cols = np.nonzero(labels == zone_id)
        if rows.size == 0:
            return self._layer(rule, np.zeros((0, 5), dtype=np.float32))
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
        jitter = float(rule.get("jitter_m", 0.0))
        xs = xs + rng.uniform(-jitter, jitter, xs.size)
        zs = zs + rng.uniform(-jitter, jitter, zs.size)
        step = float(rule.get("yaw_step_deg", 0))
        yaw = rng.integers(0, int(360 / step), xs.size) * step if step > 0 else rng.uniform(0, 360, xs.size)
        scale = rng.uniform(rule["scale"][0], rule["scale"][1], xs.size)
        ys = self._height(xs, zs)
        data = np.stack([xs, ys, zs, yaw, scale], axis=1).astype(np.float32)
        return self._layer(rule, data)

    def _lattice(self, rule, index, x0, x1, z0, z1):
        spacing = float(rule["spacing_m"])
        offset = (index * 0.37 % 1.0) * spacing
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
