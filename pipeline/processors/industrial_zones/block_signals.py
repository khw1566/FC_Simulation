"""블록 안의 기존 건물 형태와 이름에서 용도 단서를 뽑는다.

- 원형에 가까운 중대형 건물은 저장 탱크로 본다.
- 초대형 동과 조선·중공업 이름은 조선소 단서로 본다.
- 이름 키워드로 정유·화학, 물류, 발전 단서를 센다.
"""
import math

KEYWORDS = {
    "petro": ("정유", "석유", "화학", "에너지", "가스", "유류", "탱크", "플랜트", "케미칼", "오일", "oil"),
    "ship": ("조선", "중공업", "선박", "도크", "선각", "해양"),
    "logistics": ("물류", "창고", "터미널", "하역", "부두", "보세"),
    "power": ("발전", "변전", "전력", "열병합"),
}


class IndustrialBlockSignals:
    ROUND_MIN_AREA_M2 = 150.0
    ROUND_CIRCULARITY = 0.82

    def __init__(self, inputs):
        from shapely.strtree import STRtree
        self.info = inputs.building_info
        self.tree = STRtree([b["polygon"] for b in self.info]) if self.info else None

    def measure(self, block):
        result = {"count": 0, "round_count": 0, "round_area": 0.0, "area": 0.0, "max_area": 0.0}
        result.update({key: 0 for key in KEYWORDS})
        if self.tree is None:
            return result
        for index in self.tree.query(block):
            building = self.info[int(index)]
            polygon = building["polygon"]
            if not block.contains(polygon.representative_point()):
                continue
            area = polygon.area
            result["count"] += 1
            result["area"] += area
            result["max_area"] = max(result["max_area"], area)
            perimeter = polygon.exterior.length
            if area >= self.ROUND_MIN_AREA_M2 and perimeter > 0 and 4 * math.pi * area / perimeter ** 2 >= self.ROUND_CIRCULARITY:
                result["round_count"] += 1
                result["round_area"] += area
            name = building["name"].lower()
            for key, words in KEYWORDS.items():
                if any(word in name for word in words):
                    result[key] += 1
        return result

    @staticmethod
    def merge(signals):
        total = {}
        for signal in signals:
            for key, value in signal.items():
                total[key] = total.get(key, 0) + value
        return total
