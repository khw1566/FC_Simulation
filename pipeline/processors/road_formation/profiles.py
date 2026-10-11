"""도로 중심 고도를 기준으로 횡단 방향이 수평인 노반 선분을 만든다."""
import math

import numpy as np


def sample(image, x, z, size):
    h, w = image.shape
    px = np.clip((np.asarray(x) / size + .5) * (w-1), 0, w-1)
    pz = np.clip((np.asarray(z) / size + .5) * (h-1), 0, h-1)
    ix, iz = px.astype(int), pz.astype(int)
    jx, jz = np.minimum(ix+1, w-1), np.minimum(iz+1, h-1)
    dx, dz = px-ix, pz-iz
    dx, dz = dx*dx*(3-2*dx), dz*dz*(3-2*dz)
    return (image[iz, ix]*(1-dx)+image[iz, jx]*dx)*(1-dz)+(image[jz, ix]*(1-dx)+image[jz, jx]*dx)*dz


def enabled(value):
    return value.lower() in ("yes", "true", "1", "viaduct", "building_passage") if isinstance(value, str) else bool(value)


def profiles(roads, heights, water, size):
    rows, counts = [], {}
    for road in roads:
        reason = "bridge" if enabled(road.get("bridge")) else "tunnel" if enabled(road.get("tunnel")) else "steps" if road.get("type")=="steps" else "surface"
        points = road.get("points", [])
        if len(points)<2:
            reason = "degenerate"
        counts[reason] = counts.get(reason, 0)+1
        if reason != "surface":
            continue
        width = max(1.0, min(40.0, float(road.get("width", 8))))
        shoulder = min(12.0, max(4.0, width*.5))
        for a, b in zip(points, points[1:]):
            distance = math.hypot(b[0]-a[0], b[2]-a[2])
            if distance<.01:
                continue
            steps = max(1, math.ceil(distance/24))
            t = np.linspace(0, 1, steps+1)
            xs, zs = a[0]+(b[0]-a[0])*t, a[2]+(b[2]-a[2])*t
            ys = sample(heights, xs, zs, size)
            wet = sample(water, (xs[:-1]+xs[1:])*.5, (zs[:-1]+zs[1:])*.5, size)
            for i in range(steps):
                if wet[i] >= .65:
                    counts["water_segments_skipped"] = counts.get("water_segments_skipped", 0)+1
                    continue
                rows.append([xs[i], zs[i], ys[i], xs[i+1], zs[i+1], ys[i+1], width*.5, shoulder, len(rows)])
    return np.asarray(rows, dtype="<f4"), counts
