"""선박 크기를 고려한 해수 영역 탐색 및 경로 단순화."""
import heapq
import math
import numpy as np
from PIL import ImageFilter, ImageOps


class VesselNavigationGrid:
    def __init__(self, image, world_size):
        self.size = min(2048, max(512, int(math.ceil(world_size / 65))))
        self.cell = world_size / self.size
        resized = image.convert("L").resize((self.size, self.size), resample=1)
        self.image = resized.point(lambda p: 255 if p >= 254 else 0)
        self.world_size = world_size
        self.cache = {}

    def allowed(self, radius):
        pixels = max(1, math.ceil(radius / self.cell) + 1)
        if pixels not in self.cache:
            padded = ImageOps.expand(self.image, border=pixels, fill=0)
            filtered = padded.filter(ImageFilter.MinFilter(pixels * 2 + 1))
            self.cache[pixels] = np.asarray(filtered.crop((pixels, pixels, pixels + self.size, pixels + self.size))) == 255
        return self.cache[pixels]

    def nearest(self, grid, point, radius_m=2200):
        x, y = point
        radius = math.ceil(radius_m / self.cell)
        x0, y0 = max(0, x-radius), max(0, y-radius)
        x1, y1 = min(self.size, x+radius+1), min(self.size, y+radius+1)
        ys, xs = np.nonzero(grid[y0:y1, x0:x1])
        if not len(xs):
            return None
        distances = (xs+x0-x)**2 + (ys+y0-y)**2
        index = int(np.argmin(distances))
        return int(xs[index]+x0), int(ys[index]+y0)

    def path(self, grid, start, finish):
        queue = [(0.0, start)]
        cost, parent = {start: 0.0}, {}
        visited = set()
        while queue and len(visited) < 300000:
            _, current = heapq.heappop(queue)
            if current in visited:
                continue
            visited.add(current)
            if current == finish:
                result = [finish]
                while result[-1] != start:
                    result.append(parent[result[-1]])
                return self.simplify(grid, list(reversed(result)))
            x, y = current
            for dx, dy in ((1,0),(-1,0),(0,1),(0,-1),(1,1),(1,-1),(-1,1),(-1,-1)):
                nx, ny = x+dx, y+dy
                if not (0 <= nx < self.size and 0 <= ny < self.size) or not grid[ny,nx]:
                    continue
                if dx and dy and (not grid[y,nx] or not grid[ny,x]):
                    continue
                candidate = cost[current] + math.hypot(dx,dy)
                neighbor = (nx,ny)
                if candidate < cost.get(neighbor, math.inf):
                    cost[neighbor], parent[neighbor] = candidate, current
                    heuristic = math.hypot(finish[0]-nx, finish[1]-ny)
                    heapq.heappush(queue, (candidate+heuristic, neighbor))
        return []

    def line_clear(self, grid, a, b):
        steps = max(abs(a[0]-b[0]), abs(a[1]-b[1])) * 3 + 1
        for index in range(steps+1):
            t = index / steps
            x, y = round(a[0]+(b[0]-a[0])*t), round(a[1]+(b[1]-a[1])*t)
            if not (0 <= x < self.size and 0 <= y < self.size) or not grid[y,x]:
                return False
        return True

    def simplify(self, grid, path):
        result, first = [path[0]], 0
        while first < len(path)-1:
            last = min(len(path)-1, first+64)
            while last > first+1 and not self.line_clear(grid, path[first], path[last]):
                last -= 1
            result.append(path[last])
            first = last
        return result

    def project_geo(self, lon, lat, bbox):
        x = (lon-bbox["west"])/(bbox["east"]-bbox["west"])
        y = (bbox["north"]-lat)/(bbox["north"]-bbox["south"])
        return round(x*(self.size-1)), round(y*(self.size-1))

    def world(self, point):
        return [(point[0]/(self.size-1)-0.5)*self.world_size, (point[1]/(self.size-1)-0.5)*self.world_size]
