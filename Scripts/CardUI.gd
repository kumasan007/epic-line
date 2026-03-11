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
var charge_label: Label = null  # チャージ数表示
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
	# 重要: 子要素がマウスイベントを吸収しないようにする
	# これがないとカードの中央部分しかドラッグ判定がなくなる
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vbox)
	
	# カード名ラベル（上部）
	name_label = Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)
	
	# ステータス簡易表示
	stats_label = Label.new()
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_label.add_theme_font_size_override("font_size", 10)
	stats_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(stats_label)
	
	# スペーサー
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer)
	
	# CD残り表示ラベル（中央に大きく）
	cd_label = Label.new()
	cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd_label.add_theme_font_size_override("font_size", 22)
	cd_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	cd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(cd_label)
	
	# スペーサー
	var spacer2 := Control.new()
	spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer2)
	
	# チャージ数表示（下部）
	charge_label = Label.new()
	charge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	charge_label.add_theme_font_size_override("font_size", 11)
	charge_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	charge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(charge_label)
	
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
	
	# カード種別に応じてスタイルを変更
	var style = normal_style.duplicate()
	if data.card_type != CardData.CardType.UNIT:
		# スペルカードは枠の色をspell_colorに変える
		style.border_color = data.spell_color
		style.bg_color = Color(data.spell_color.r * 0.2, data.spell_color.g * 0.2, data.spell_color.b * 0.2, 0.9)
		style.set_border_width_all(3)
	add_theme_stylebox_override("panel", style)
	
	# カード情報を表示
	if name_label:
		if data.card_type == CardData.CardType.UNIT:
			name_label.text = data.card_name
		elif data.card_type == CardData.CardType.SPELL_INSTANT:
			name_label.text = "⚡" + data.card_name  # 即時スペルには稲妻マーク
		else:
			name_label.text = "🕐" + data.card_name  # 遅延スペルには時計マーク
		
		if data.is_curse:
			name_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		elif data.card_type != CardData.CardType.UNIT:
			name_label.add_theme_color_override("font_color", data.spell_color)
		else:
			name_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	
	if stats_label:
		if data.card_type == CardData.CardType.UNIT:
			stats_label.text = "ATK:%d HP:%d" % [int(data.atk), int(data.max_hp)]
		else:
			# スペルの場合は効果の説明を簡潔に表示
			stats_label.text = data.description
		stats_label.visible = true
	
	if cd_label:
		cd_label.visible = true
	if cd_overlay:
		cd_overlay.visible = true
	if charge_label:
		# 召喚数が2以上なら表示（1体は表示不要）
		if data.card_type == CardData.CardType.UNIT and data.summon_count > 1:
			charge_label.text = "×%d" % data.summon_count
			charge_label.visible = true
		else:
			charge_label.visible = false

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
	if charge_label:
		charge_label.text = ""
		charge_label.visible = false
	if cd_overlay:
		cd_overlay.visible = false

# === カード状態表示を更新 ===
func update_cd_text(cd_remaining: float, mana_cost: int, _charge_remaining: int) -> void:
	if is_empty:
		return
	
	if cd_label:
		# マナコストを表示
		cd_label.text = "💎 %d" % mana_cost
		cd_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
		cd_label.add_theme_font_size_override("font_size", 22)
	
	# CDオーバーレイは使わない（リアルタイムサイクル制ではCD無し）
	if cd_overlay:
		cd_overlay.visible = false



