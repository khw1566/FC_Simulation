extends RefCounted
class_name RiverBedGrade

const BASE := "res://assets/generated/taehwa_civil/"
const Images = preload("res://scripts/services/map_image_preloader.gd")

## 높이맵 복사본에만 패치를 적용한다. 메시와 기존 지형 충돌 모두 같은 하상을 따른다.
static func apply(image: Image, map_id: String, low: float, high: float, material: ShaderMaterial) -> bool:
    if map_id != "ulsan_metro_80km" or image == null or material == null:
        return false
    if not FileAccess.file_exists(BASE+"bed_patch.json") or not FileAccess.file_exists(BASE+"catalog.json"):
        return false
    var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE+"bed_patch.json"))
    var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE+"catalog.json"))
    if absf(low-float(meta.height_min)) > 0.01 or absf(high-float(meta.height_max)) > 0.01:
        return false
    # 수면과 하상 중 일부만 존재하면 지형에 구멍을 만들지 않고 기존 표현을 유지한다.
    for chunk in catalog.hydro_chunks:
        if not FileAccess.file_exists(str(chunk.scene_path)):
            return false
    var patch := Images.read(BASE+"bed_patch.rf32z")
    var mask := Images.read(BASE+"bed_mask.png")
    var overlay := Images.read(BASE+"overlay_mask.png")
    if patch == null or mask == null or overlay == null:
        return false
    var ratio: float = float(image.get_width()-1)/float(meta.source_resolution[0]-1)
    var rect: Array = meta.pixel_rect
    var destination := Vector2i(roundi(float(rect[0])*ratio),roundi(float(rect[1])*ratio))
    if not is_equal_approx(ratio,1.0):
        var width := maxi(1,roundi(float(rect[2])*ratio))
        var height := maxi(1,roundi(float(rect[3])*ratio))
        patch.resize(width,height,Image.INTERPOLATE_NEAREST)
        mask.resize(width,height,Image.INTERPOLATE_NEAREST)
    image.blit_rect_mask(patch,mask,Rect2i(Vector2i.ZERO,patch.get_size()),destination)
    var world: Array = meta.world_rect
    material.set_shader_parameter("river_overlay_mask",ImageTexture.create_from_image(overlay))
    material.set_shader_parameter("river_overlay_rect",Vector4(world[0],world[1],world[2],world[3]))
    material.set_shader_parameter("has_river_overlay",true)
    return true
