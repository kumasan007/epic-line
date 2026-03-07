# SpellButton.gd
# スペルスロット1つ分のUIボタン
# プレイヤーがタップしてスペルを発動する
extends Button
class_name SpellButton

# スロットのインデックス
var slot_index: int = -1
# このスロットにセットされたスペル
var spell_data: SpellData = null
# CDオーバーレイ
var cd_overlay: ColorRect = null

# === シグナル ===
signal spell_drag_started(slot_index: int)
signal spell_drag_canceled(slot_index: int)

func _ready() -> void:
	# ボタンのサイズと見た目
	custom_minimum_size = Vector2(80, 80)
	
	# スタイル設定（角丸の暗いボタン）
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.18, 0.12, 0.28, 1.0)
	normal.border_color = Color(0.5, 0.3, 0.7, 1.0)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(12)
	add_theme_stylebox_override("normal", normal)
	
	# ホバー時のスタイル
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.25, 0.18, 0.38, 1.0)
	hover.border_color = Color(0.7, 0.5, 0.9, 1.0)
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(12)
	add_theme_stylebox_override("hover", hover)
	
	# 押下時のスタイル
	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.3, 0.2, 0.45, 1.0)
	pressed_style.border_color = Color(0.8, 0.6, 1.0, 1.0)
	pressed_style.set_border_width_all(3)
	pressed_style.set_corner_radius_all(12)
	add_theme_stylebox_override("pressed", pressed_style)
	
	# 無効時のスタイル（CD中）
	var disabled_style := StyleBoxFlat.new()
	disabled_style.bg_color = Color(0.1, 0.08, 0.12, 0.7)
	disabled_style.border_color = Color(0.2, 0.15, 0.25, 0.5)
	disabled_style.set_border_width_all(1)
	disabled_style.set_corner_radius_all(12)
	add_theme_stylebox_override("disabled", disabled_style)
	
	# テキスト設定
	add_theme_font_size_override("font_size", 11)
	add_theme_color_override("font_color", Color(0.85, 0.75, 1.0))
	add_theme_color_override("font_disabled_color", Color(0.4, 0.35, 0.45))
	
	# CDオーバーレイ
	cd_overlay = ColorRect.new()
	cd_overlay.color = Color(0.0, 0.0, 0.0, 0.5)
	cd_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cd_overlay.visible = false
	add_child(cd_overlay)
	
	# ボタン自体の押下シグナルは使わない（ドラッグで発動するため）
	
	# 初期状態（空スロット）
	text = "空"
	disabled = true

# === ドラッグ＆ドロップの開始 ===
func _get_drag_data(at_position: Vector2) -> Variant:
	if disabled or spell_data == null:
		return null
	
	# スペル発動開始をUILayerに通知（これで時間が止まる）
	spell_drag_started.emit(slot_index)
	
	# マウスに追従するプレビューを作成（赤色の半透明な円＝効果範囲）
	var preview := Control.new()
	var preview_bg := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.2, 0.2, 0.4)
	style.set_corner_radius_all(100) # 円形にする
	preview_bg.add_theme_stylebox_override("panel", style)
	
	# 火球など効果範囲があるものはその大きさにする。無いものは固定サイズ
	var r: float = spell_data.effect_range if spell_data.effect_range > 0 else 80.0
	preview_bg.size = Vector2(r * 2, r * 2)
	preview_bg.position = -preview_bg.size / 2.0
	
	preview.add_child(preview_bg)
	set_drag_preview(preview)
	
	return {"type": "spell", "slot_index": slot_index, "spell_data": spell_data}

# === ドラッグが終了した時（成功/キャンセル問わず呼ばれる） ===
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		if not get_viewport().gui_is_drag_successful():
			# ドロップされずにキャンセルされた場合、時間停止を解除する
			spell_drag_canceled.emit(slot_index)

# === スペルをセット ===
func set_spell(spell: SpellData) -> void:
	spell_data = spell
	text = spell.spell_name
	disabled = false

# === CD進行状況を更新 ===
func update_cd(progress: float, remaining: float) -> void:
	if spell_data == null:
		return
	
	if remaining <= 0.0:
		# CD完了 → 使用可能
		disabled = false
		if cd_overlay:
			cd_overlay.visible = false
		text = spell_data.spell_name
	else:
		# CD中 → 使用不可
		disabled = true
		text = "%s\n%.0f" % [spell_data.spell_name, remaining]
		if cd_overlay:
			cd_overlay.visible = true
			cd_overlay.size = Vector2(size.x, size.y * progress)
			cd_overlay.position = Vector2(0, 0)

# (ボタン単体のクリックイベントは削除しました)
