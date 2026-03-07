# CardData.gd
# カード1枚分のデータ定義（Resource型）
# なぜResource？→ Godotエディタ上で視覚的に編集でき、.tres/.resファイルとして保存可能
# カードはユニットを召喚するための「設計図」のようなもの
extends Resource
class_name CardData

# === カードの基本情報 ===
@export var card_name: String = "Unknown Card"
@export_multiline var description: String = ""

# === CDとレベル ===
# CD（クールダウン）= 手札に来てから召喚されるまでの待機時間
# 企画書：CDの長さがコスト代替として機能する（強いユニット=CDが長い）
@export var cooldown: float = 3.0
@export var card_level: int = 1  # 通常版=1, アップグレード版=2

# === ユニットの役割（待機時の陣形に影響） ===
enum UnitRole {
	ASSAULT,   # 待機命令を無視して常に敵陣へ突撃（ゴブリン等）
	TANK,      # 待機時、前衛ライン（最前列）で立ち止まる
	FIGHTER,   # 待機時、中衛ライン（タンクの後ろ）で立ち止まる
	SHOOTER    # 待機時、後衛ライン（遠方）で立ち止まる
}

# === 召喚されるユニットのステータス ===
@export_group("Unit Stats")
@export var unit_role: UnitRole = UnitRole.FIGHTER
@export var unit_name: String = "Soldier"
@export var max_hp: float = 100.0
@export var atk: float = 10.0
@export var attack_range: float = 50.0
@export var defense: float = 0.0
@export var speed: float = 80.0
@export var attack_interval: float = 1.0
@export var lifespan: float = 0.0  # 0=無限

@export_group("Knockback")
@export var knockback_chance: float = 0.0
@export var knockback_power: float = 0.0
@export var kb_resistance: float = 0.0

@export_group("Death Effect")
@export var death_effect_type: String = "" # 例: "explosion"
@export var death_effect_value: float = 0.0 # 爆発ダメージ等
@export var death_effect_range: float = 0.0 # 爆発範囲等

# === 妨害カードフラグ ===
# true = このカードは呪いカード（プレイヤーを妨害する）
@export var is_curse: bool = false

# カードからユニット生成用のステータス辞書を作る
# なぜ辞書？→ BattleField.spawn_unit()が辞書でステータスを受け取る設計のため
func get_unit_stats() -> Dictionary:
	return {
		"unit_role": unit_role,
		"unit_name": unit_name,
		"max_hp": max_hp,
		"atk": atk,
		"attack_range": attack_range,
		"defense": defense,
		"speed": speed,
		"attack_interval": attack_interval,
		"knockback_chance": knockback_chance,
		"knockback_power": knockback_power,
		"kb_resistance": kb_resistance,
		"lifespan": lifespan,
		"death_effect_type": death_effect_type,
		"death_effect_value": death_effect_value,
		"death_effect_range": death_effect_range
	}
