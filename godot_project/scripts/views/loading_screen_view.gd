extends Control
class_name LoadingScreenView

## 가상현실 렌더링 공간 진입 및 GPU VRAM 전송 시각화 콘솔
## Host RAM -> PCIe DMA -> GPU VRAM 실시간 데이터 파이프라인 및 계측 매트릭스 표출

@onready var loading_title_label: Label = $RootMargin/MainLayout/Header/TitleVBox/LoadingTitleLabel
@onready var map_title_label: Label = $RootMargin/MainLayout/Header/TitleVBox/MapTitleLabel
@onready var map_scale_label: Label = $RootMargin/MainLayout/Header/BadgeContainer/MapScaleBadge/MapScaleLabel
@onready var vram_badge_label: Label = $RootMargin/MainLayout/Header/BadgeContainer/VramBadge/VramBadgeLabel

@onready var preview_texture: TextureRect = $RootMargin/MainLayout/ContentHBox/LeftPanel/PreviewFrame/PreviewTexture
@onready var val_area: Label = $RootMargin/MainLayout/ContentHBox/LeftPanel/SpecsPanel/SpecsMargin/SpecsGrid/ValArea
@onready var val_elev: Label = $RootMargin/MainLayout/ContentHBox/LeftPanel/SpecsPanel/SpecsMargin/SpecsGrid/ValElev
@onready var val_chunks: Label = $RootMargin/MainLayout/ContentHBox/LeftPanel/SpecsPanel/SpecsMargin/SpecsGrid/ValChunks
@onready var val_spawn: Label = $RootMargin/MainLayout/ContentHBox/LeftPanel/SpecsPanel/SpecsMargin/SpecsGrid/ValSpawn

@onready var live_rate_label: Label = $RootMargin/MainLayout/ContentHBox/RightPanel/VramMonitorFrame/VramMargin/VramVBox/PipelineHeaderHBox/LiveRateLabel
@onready var bus_arrow_label: Label = $RootMargin/MainLayout/ContentHBox/RightPanel/VramMonitorFrame/VramMargin/VramVBox/BusDiagramPanel/BusMargin/BusHBox/BusArrowLabel
@onready var vram_allocated_label: Label = $RootMargin/MainLayout/ContentHBox/RightPanel/VramMonitorFrame/VramMargin/VramVBox/TelemetryHBox/VramAllocatedLabel
@onready var texture_vram_label: Label = $RootMargin/MainLayout/ContentHBox/RightPanel/VramMonitorFrame/VramMargin/VramVBox/TelemetryHBox/TextureVramLabel
@onready var buffer_vram_label: Label = $RootMargin/MainLayout/ContentHBox/RightPanel/VramMonitorFrame/VramMargin/VramVBox/TelemetryHBox/BufferVramLabel
@onready var bank_grid: GridContainer = $RootMargin/MainLayout/ContentHBox/RightPanel/VramMonitorFrame/VramMargin/VramVBox/BankGrid

@onready var card_dem_status: Label = $RootMargin/MainLayout/ContentHBox/RightPanel/VramMonitorFrame/VramMargin/VramVBox/AssetCardsVBox/CardDem/Margin/HBox/Status
@onready var card_water_status: Label = $RootMargin/MainLayout/ContentHBox/RightPanel/VramMonitorFrame/VramMargin/VramVBox/AssetCardsVBox/CardWater/Margin/HBox/Status
@onready var card_terrain_status: Label = $RootMargin/MainLayout/ContentHBox/RightPanel/VramMonitorFrame/VramMargin/VramVBox/AssetCardsVBox/CardTerrain/Margin/HBox/Status
@onready var card_urban_status: Label = $RootMargin/MainLayout/ContentHBox/RightPanel/VramMonitorFrame/VramMargin/VramVBox/AssetCardsVBox/CardUrban/Margin/HBox/Status

@onready var progress_bar: ProgressBar = $RootMargin/MainLayout/BottomContent/ProgressBar
@onready var status_label: Label = $RootMargin/MainLayout/BottomContent/StatusHBox/StatusLabel
@onready var percent_label: Label = $RootMargin/MainLayout/BottomContent/StatusHBox/PercentLabel
@onready var tip_label: Label = $RootMargin/MainLayout/Footer/TipLabel

const BANK_COUNT: int = 16
var _bank_panels: Array[PanelContainer] = []
var _bank_labels: Array[Label] = []

var _target_progress: float = 0.0
var _display_progress: float = 0.0
var _is_fading_out: bool = false
var _bus_anim_timer: float = 0.0
var _tip_timer: float = 0.0
var _current_tip_index: int = 0

const FLIGHT_TIPS: Array[String] = [
	"Tip: 10,000m 이상 고고도 비행 시 소형 건물이 자동 생략되어 지형과 비행체에 렌더링 성능이 집중됩니다.",
	"Tip: 15,000m 고도에서는 대기 수증기 밀도가 감소하여 최대 75km까지 원경이 선명하게 조망됩니다.",
	"Tip: [C] 키로 지형 충돌 감지를 On/Off할 수 있으며, [G] 키로 중력 시뮬레이션을 토글할 수 있습니다.",
	"Tip: [1]~[4] 키로 비행 기어를 변속할 수 있으며, 4단 기어에서는 최고 마하 10 초음속 순항이 가능합니다.",
	"Tip: [M] 키를 누르면 위성 지표 피복 모드와 절차적 등고선 심플 모드를 실시간으로 전환할 수 있습니다."
]

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	_init_vram_bank_grid()
	_update_vram_telemetry(0.0)

func _process(delta: float) -> void:
	# 1. 프로그레스 바 부드러운 전진 보간 (Lerp)
	if _display_progress < _target_progress:
		_display_progress = move_toward(_display_progress, _target_progress, delta * 85.0)
		if progress_bar:
			progress_bar.value = _display_progress
		if percent_label:
			percent_label.text = "%d%%" % [int(_display_progress)]
		_update_vram_telemetry(_display_progress)

	# 2. PCIe 버스 데이터 스트림 전송 애니메이션
	_bus_anim_timer += delta
	if bus_arrow_label:
		if _display_progress >= 100.0 or _is_fading_out:
			bus_arrow_label.text = "지도 준비 완료"
			if live_rate_label:
				live_rate_label.text = "준비 완료"
		else:
			var step: int = int(_bus_anim_timer * 6.0) % 4
			var arrows: String = "===>"
			match step:
				0: arrows = "==[ > ]==> 지도 준비 ===>"
				1: arrows = "==[ >> ]==> 지도 준비 ===>"
				2: arrows = "==[ >>> ]==> 지도 준비 ===>"
				3: arrows = "==[ >>>> ]==> 지도 준비 ===>"
			bus_arrow_label.text = arrows
			if live_rate_label:
				var elapsed: float = _bus_anim_timer
				live_rate_label.text = "경과 %.1f초" % elapsed

	# 3. 비행 조종 및 시뮬레이션 팁 순환 (3.5초 주기)
	_tip_timer += delta
	if _tip_timer >= 3.5:
		_tip_timer = 0.0
		_current_tip_index = (_current_tip_index + 1) % FLIGHT_TIPS.size()
		if tip_label:
			tip_label.text = FLIGHT_TIPS[_current_tip_index]

func _init_vram_bank_grid() -> void:
	if not bank_grid:
		return
	_bank_panels.clear()
	_bank_labels.clear()

	for i in range(BANK_COUNT):
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(36, 26)
		p.add_theme_stylebox_override("panel", _create_bank_style(false))

		var lbl := Label.new()
		lbl.text = "B%02d" % [i]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(0.4, 0.45, 0.5, 1.0))

		p.add_child(lbl)
		bank_grid.add_child(p)

		_bank_panels.append(p)
		_bank_labels.append(lbl)

func _create_bank_style(is_active: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	if is_active:
		s.bg_color = Color(0.85, 0.9, 0.95, 1.0)
		s.border_color = Color(1.0, 1.0, 1.0, 1.0)
	else:
		s.bg_color = Color(0.08, 0.09, 0.1, 1.0)
		s.border_color = Color(0.18, 0.2, 0.22, 1.0)
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	return s

func _update_vram_telemetry(prog: float) -> void:
	var total_mb := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var texture_mb := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
	var buffer_mb := Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0
	if vram_allocated_label:
		vram_allocated_label.text = "그래픽 메모리: %.1f MB" % total_mb if total_mb > 0 else "그래픽 메모리: 계측 미지원"
	if texture_vram_label:
		texture_vram_label.text = "텍스처: %.1f MB" % texture_mb
	if buffer_vram_label:
		buffer_vram_label.text = "형상 자료: %.1f MB" % buffer_mb
	for card in [card_dem_status, card_water_status, card_terrain_status]:
		if card:
			card.text = "준비 완료" if prog >= 55 else "준비 중"
	if card_urban_status:
		card_urban_status.text = "주변 구역 준비 완료" if prog >= 100 else "차례로 불러오는 중"
func setup_view(map_name: String, preview_tex: Texture2D, lang_dict: Dictionary, map_model: Object = null) -> void:
	if map_title_label:
		map_title_label.text = map_name
	if loading_title_label:
		loading_title_label.text = lang_dict.get("loading_title", "가상 현실 공간 데이터 로딩 중")
	if tip_label and FLIGHT_TIPS.size() > 0:
		tip_label.text = FLIGHT_TIPS[0]
	if status_label:
		status_label.text = lang_dict.get("loading_status_init", "환경 및 지형 시스템 초기화...")
	if preview_texture and preview_tex:
		preview_texture.texture = preview_tex

	# 맵 모델 제원 상세 표출
	if map_model:
		var w_size: float = float(map_model.get("world_size_meters")) if "world_size_meters" in map_model else 28000.0
		var min_h: float = float(map_model.get("min_elevation")) if "min_elevation" in map_model else -50.0
		var max_h: float = float(map_model.get("max_elevation")) if "max_elevation" in map_model else 750.0
		var spawn_pos: Vector3 = map_model.get("spawn_position") if "spawn_position" in map_model else Vector3(0, 350, 0)

		var km: float = w_size / 1000.0
		if map_scale_label:
			map_scale_label.text = "%.0fKM x %.0fKM" % [km, km]
		if val_area:
			val_area.text = "%.0fm x %.0fm (%.0f ㎢)" % [w_size, w_size, km * km]
		if val_elev:
			val_elev.text = "%.1fm ~ %.1fm (고도차 %.0fm)" % [min_h, max_h, max_h - min_h]
		if val_chunks:
			var chunks_cnt: int = 64 if km >= 40.0 else 16
			val_chunks.text = "%dx%d (%d 청크 타일)" % [8 if km >= 40.0 else 4, 8 if km >= 40.0 else 4, chunks_cnt]
		if val_spawn:
			val_spawn.text = "X: %.0fm, Y: %.0fm, Z: %.0fm" % [spawn_pos.x, spawn_pos.y, spawn_pos.z]

	_target_progress = 5.0
	_display_progress = 0.0
	if progress_bar:
		progress_bar.value = 0.0
	if percent_label:
		percent_label.text = "0%"

func set_progress(percentage: float, status_text: String) -> void:
	_target_progress = clamp(percentage, 0.0, 100.0)
	if status_label and not status_text.is_empty():
		status_label.text = status_text

func fade_out_and_finish(callable_on_finish: Callable) -> void:
	_is_fading_out = true
	_target_progress = 100.0
	_display_progress = 100.0
	if progress_bar:
		progress_bar.value = 100.0
	if percent_label:
		percent_label.text = "100%"
	_update_vram_telemetry(100.0)

	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		if callable_on_finish.is_valid():
			callable_on_finish.call()
		queue_free()
	)

