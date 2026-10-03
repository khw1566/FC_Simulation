import os
import json
import numpy as np
import torch
from PIL import Image
from transformers import SegformerForSemanticSegmentation, AutoImageProcessor

class SegformerLandcoverProcessor:
    """
    고해상도 위성 영상으로부터 SegFormer 딥러닝 비전 트랜스포머 모델과 분광 반사율 특성을 융합하여
    산림/수목(Forest), 농경지/논밭(Farmland), 도회지/포장(Urban), 하천/수계(Water)를
    정밀 분할하고 Godot 4 지형 셰이더용 4채널 RGBA 스플랫맵 텍스처를 생성하는 프로세서
    """
    MODEL_ID = "nvidia/segformer-b0-finetuned-ade-512-512"

    def __init__(self, config_path):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        self.target_res = (
            self.config["resolution"]["target_width"],
            self.config["resolution"]["target_height"]
        )

        # ADE20k 클래스 매핑 분류 그룹 정의
        # 0: 산림/수목 (R채널) - tree(4), mountain(16), plant(17), hill(68)
        self.forest_ids = {4, 16, 17, 68}
        # 1: 농경지/논밭 (G채널) - grass(9), earth(13), field(29)
        self.farmland_ids = {9, 13, 29}
        # 2: 도회지/포장/건물 (B채널) - building(1), road(6), house(25), path(52)
        self.urban_ids = {1, 6, 25, 52}
        # 3: 수계/하천/수변 (A채널) - water(21), sea(26), river(60)
        self.water_ids = {21, 26, 60}

    def process_landcover_splatmap(self, satellite_rgb_path, watermask_path, output_splatmap_path, patch_size=512, stride=512):
        print(f"[SegformerLandcoverProcessor] Loading SegFormer model ({self.MODEL_ID}) on {self.device}...")
        processor = AutoImageProcessor.from_pretrained(self.MODEL_ID)
        model = SegformerForSemanticSegmentation.from_pretrained(self.MODEL_ID).to(self.device)
        model.eval()

        print(f"[SegformerLandcoverProcessor] Processing satellite image: {satellite_rgb_path}...")
        sat_img = Image.open(satellite_rgb_path).convert("RGB")
        img_w, img_h = sat_img.size

        # 4채널 누적 배열 생성 (R: Forest, G: Farmland, B: Urban, A: Water)
        splat_accum = np.zeros((img_h, img_w, 4), dtype=np.float32)

        # 1. SegFormer 딥러닝 비전 트랜스포머 패치 추론
        y_steps = range(0, img_h, stride)
        x_steps = range(0, img_w, stride)
        total_patches = len(y_steps) * len(x_steps)
        print(f"[SegformerLandcoverProcessor] Running SegFormer inference on {total_patches} patches...")

        with torch.no_grad():
            for y0 in y_steps:
                for x0 in x_steps:
                    x1 = min(x0 + patch_size, img_w)
                    y1 = min(y0 + patch_size, img_h)
                    patch = sat_img.crop((x0, y0, x1, y1))
                    cur_w, cur_h = patch.size

                    inputs = processor(images=patch, return_tensors="pt").to(self.device)
                    outputs = model(**inputs)
                    logits = outputs.logits

                    upsampled = torch.nn.functional.interpolate(
                        logits,
                        size=(cur_h, cur_w),
                        mode="bilinear",
                        align_corners=False
                    )
                    pred_labels = upsampled.argmax(dim=1).squeeze(0).cpu().numpy()

                    splat_accum[y0:y1, x0:x1, 0] += np.isin(pred_labels, list(self.forest_ids)).astype(np.float32) * 0.4
                    splat_accum[y0:y1, x0:x1, 1] += np.isin(pred_labels, list(self.farmland_ids)).astype(np.float32) * 0.4
                    splat_accum[y0:y1, x0:x1, 2] += np.isin(pred_labels, list(self.urban_ids)).astype(np.float32) * 0.4
                    splat_accum[y0:y1, x0:x1, 3] += np.isin(pred_labels, list(self.water_ids)).astype(np.float32) * 0.4

        # 2. 위성 정사 영상 분광 반사율 보정 결합 (음영/지표 특성 정밀 융합)
        sat_arr = np.array(sat_img, dtype=np.float32)
        r = sat_arr[:, :, 0]
        g = sat_arr[:, :, 1]
        b = sat_arr[:, :, 2]

        # 실제 해상 수역 (바다): 어두운 청록색 반사율
        water_spec = (b > r + 30) & (b < 140) & (r < 60)
        land_spec = ~water_spec

        # 산악/산림 식생 (Forest): 높은 녹지 우세도
        forest_spec = land_spec & (g > r + 6) & (g > b)
        # 도회지/아스팔트/인공구조물 (Urban): 중립 회색톤 및 높은 반사율
        urban_spec = land_spec & (~forest_spec) & (np.abs(r - g) < 20) & (np.abs(g - b) < 20) & (r > 105)
        # 농경지/전답/초지 (Farmland): 평탄지 경작 패턴 및 연녹색
        farmland_spec = land_spec & (~forest_spec) & (~urban_spec)

        # 딥러닝 특징과 지표 분광 특성 가중 합성
        splat_accum[forest_spec, 0] += 0.6
        splat_accum[farmland_spec, 1] += 0.6
        splat_accum[urban_spec, 2] += 0.6
        splat_accum[water_spec, 3] += 0.8

        # 3. OSM 정밀 하천/수역 마스크 융합 (강폭 및 조간대 수변구역 확정)
        if watermask_path and os.path.exists(watermask_path):
            with Image.open(watermask_path) as wm_img:
                wm_arr = np.array(wm_img.resize((img_w, img_h), Image.Resampling.NEAREST), dtype=np.float32) / 255.0
                osm_water = wm_arr > 0.5
                splat_accum[osm_water, 0] = 0.0
                splat_accum[osm_water, 1] = 0.0
                splat_accum[osm_water, 2] = 0.0
                splat_accum[osm_water, 3] = 1.0

        # 비수역 육지에서 Water 채널 감쇠
        non_water = ~water_spec
        splat_accum[non_water, 3] *= 0.05

        # 소프트맥스 정규화 (R + G + B + A = 255)
        channel_sum = np.sum(splat_accum, axis=-1, keepdims=True)
        channel_sum[channel_sum == 0] = 1.0
        norm_splat = (splat_accum / channel_sum * 255.0).astype(np.uint8)

        # 최종 4096x4096 해상도로 저장
        final_splat = Image.fromarray(norm_splat, mode="RGBA")
        if final_splat.size != self.target_res:
            final_splat = final_splat.resize(self.target_res, Image.Resampling.BILINEAR)

        os.makedirs(os.path.dirname(output_splatmap_path), exist_ok=True)
        final_splat.save(output_splatmap_path, format="PNG")
        print(f"[SegformerLandcoverProcessor] Exported 4-channel Splatmap: {output_splatmap_path} ({self.target_res[0]}x{self.target_res[1]})")
        return output_splatmap_path
