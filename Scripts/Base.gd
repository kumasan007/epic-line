# Base.gd
# 拠点（自陣/敵陣）のHP管理を行うクラス
# ユニットが敵拠点に到達するとダメージを与え、HPが0で勝利/敗北となる
# なぜ拠点をノードにする？→ HPバー表示や被ダメージ演出を後から追加しやすくするため
extends Node2D
class_name Base

# === シグナル ===
signal base_destroyed(base: Base)
signal hp_changed(current: float, max_val: float)

# === 設定 ===
@export var team: BaseUnit.Team = BaseUnit.Team.PLAYER
@export var max_hp: float = 1000.0
@export var base_x: float = 0.0  # この拠点のX座標

# === 内部状態 ===
var current_hp: float = 0.0
var is_destroyed: bool = false

# === 描画用 ===
var hp_bar_bg: ColorRect = null
var hp_bar_fill: ColorRect = null
var hp_label: Label = null

func _ready() -> void:
	current_hp = max_hp
	_create_hp_bar()

# === 拠点にダメージを与える ===
func take_damage(damage: float) -> void:
	if is_destroyed:
		return
	current_hp = maxf(current_hp - damage, 0.0)
	hp_changed.emit(current_hp, max_hp)
	_update_hp_bar()
	
	if current_hp <= 0.0:
		is_destroyed = true
		base_destroyed.emit(self)

# === HPバーのUI作成 ===
func _create_hp_bar() -> void:
	# 背景（灰色）
	hp_bar_bg = ColorRect.new()
	hp_bar_bg.size = Vector2(46, 8)
	hp_bar_bg.position = Vector2(-23, -60)
	hp_bar_bg.color = Color(0.2, 0.2, 0.2, 0.8)
	add_child(hp_bar_bg)
	
	# 塗り（チーム色）
	hp_bar_fill = ColorRect.new()
	hp_bar_fill.size = Vector2(44, 6)
	hp_bar_fill.position = Vector2(-22, -59)
	if team == BaseUnit.Team.PLAYER:
		hp_bar_fill.color = Color(0.2, 0.6, 1.0)
	else:
		hp_bar_fill.color = Color(1.0, 0.25, 0.25)
	add_child(hp_bar_fill)
	
	# HPテキスト
	hp_label = Label.new()
	hp_label.position = Vector2(-30, -80)
	hp_label.add_theme_font_size_override("font_size", 12)
	hp_label.add_theme_color_override("font_color", Color.WHITE)
	hp_label.text = "%d" % int(current_hp)
	add_child(hp_label)

# === HPバーの表示を更新 ===
func _update_hp_bar() -> void:
	if hp_bar_fill:
		var ratio: float = current_hp / max_hp
		hp_bar_fill.size.x = 44.0 * ratio
	if hp_label:
		hp_label.text = "%d" % int(current_hp)
