# CardUI.gd
# 手札の1スロットを表示するUIコンポーネント
# CDの進行をオーバーレイで表示し、カードの中身は差し替え可能
extends PanelContainer
class_name CardUI

# このスロットに入っているCardData（nullなら空スロット）
var card_data: CardData = null
# スロットのインデックス
var slot_index: int = -1
# 空スロット状態かどうか
var is_empty: bool = true

# === UI要素 ===
var name_label: Label = null
var cd_label: Label = null
var stats_label: Label = null
var cd_overlay: ColorRect = null

# === スタイル参照 ===
var normal_style: StyleBoxFlat = null
var empty_style: StyleBoxFlat = null

func _ready() -> void:
	custom_minimum_size = Vector2(120, 180)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# --- 通常スタイル（カードあり） ---
	normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.15, 0.13, 0.22, 1.0)
	normal_style.border_color = Color(0.45, 0.38, 0.6, 1.0)
	normal_style.set_border_width_all(2)
	normal_style.set_corner_radius_all(8)
	normal_style.set_content_margin_all(6)
	
	# --- 空スロットスタイル ---
	empty_style = StyleBoxFlat.new()
	empty_style.bg_color = Color(0.08, 0.07, 0.1, 0.4)
	empty_style.border_color = Color(0.2, 0.2, 0.25, 0.5)
	empty_style.set_border_width_all(1)
	empty_style.set_corner_radius_all(8)
	empty_style.set_content_margin_all(6)
	
	# --- レイアウト構築 ---
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)
	
	# カード名ラベル（上部）
	name_label = Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	vbox.add_child(name_label)
	
	# ステータス簡易表示
	stats_label = Label.new()
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_label.add_theme_font_size_override("font_size", 10)
	stats_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	vbox.add_child(stats_label)
	
	# スペーサー
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	
	# CD残り表示ラベル（中央に大きく）
	cd_label = Label.new()
	cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd_label.add_theme_font_size_override("font_size", 22)
	cd_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	vbox.add_child(cd_label)
	
	# スペーサー
	var spacer2 := Control.new()
	spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer2)
	
	# CDオーバーレイ（上から縮んでいく半透明の矩形）
	cd_overlay = ColorRect.new()
	cd_overlay.color = Color(0.0, 0.0, 0.0, 0.5)
	cd_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cd_overlay)
	
	# 初期状態は空スロット
	_show_empty()

# === カードデータをセットする（スロットにカードが入った時） ===
func set_card(data: CardData) -> void:
	card_data = data
	is_empty = false
	
	# スタイルを切り替え
	add_theme_stylebox_override("panel", normal_style)
	
	# カード情報を表示
	if name_label:
		name_label.text = data.card_name
		# 呪いカードは赤色で表示
		if data.is_curse:
			name_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		else:
			name_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	
	if stats_label:
		# ATKとHP情報を簡易表示
		stats_label.text = "ATK:%d HP:%d" % [int(data.atk), int(data.max_hp)]
		stats_label.visible = true
	
	if cd_label:
		cd_label.visible = true
	if cd_overlay:
		cd_overlay.visible = true

# === スロットを空にする ===
func clear_card() -> void:
	card_data = null
	is_empty = true
	_show_empty()

# === 空スロット表示 ===
func _show_empty() -> void:
	add_theme_stylebox_override("panel", empty_style)
	if name_label:
		name_label.text = ""
	if stats_label:
		stats_label.text = ""
		stats_label.visible = false
	if cd_label:
		cd_label.text = ""
		cd_label.visible = false
	if cd_overlay:
		cd_overlay.visible = false

# === CD進行状況を更新 ===
# progress: 0.0=CD完了, 1.0=CDフル残り
func update_cd(progress: float, remaining: float) -> void:
	if is_empty:
		return
	
	if cd_label:
		if remaining <= 0.1:
			cd_label.text = "GO!"
			cd_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
		else:
			cd_label.text = "%.1f" % remaining
			cd_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	
	# CDオーバーレイの高さ = progress に比例
	if cd_overlay:
		var card_height: float = size.y
		cd_overlay.size = Vector2(size.x, card_height * progress)
		cd_overlay.position = Vector2(0, 0)
