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
@export var cooldown: float = 3.0      # CD（召喚後の再使用までの待機時間）
@export var mana_cost: int = 3          # 召喚時に消費するマナ
@export var card_level: int = 1         # 通常版=1, アップグレード版=2

# === チャージ数（生産上限） ===
# このカードが手札にある間に何体までユニットを生産できるか。
# チャージを使い切ると捨て札へ送られ、次のカードが引かれる。
# 0 = 無制限（消耗しない）
@export var charge_count: int = 3

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
@export var defense: float = 0.0
@export var speed: float = 80.0
@export var lifespan: float = 0.0  # 0=無限

@export_group("Attack Properties")
@export var attack_range: float = 40.0
@export var is_ranged: bool = false
@export var projectile_speed: float = 300.0  # 遠距離の場合の弾速
@export var projectile_color: Color = Color.WHITE
@export var projectile_aoe: float = 0.0 # 0なら単体攻撃、0より大きければ着弾点から指定半径の範囲ダメージ
@export var attack_interval: float = 1.0     # 攻撃間隔(秒)
@export var attack_windup_time: float = -1.0 # 攻撃モーションのタメ時間（-1の場合は自動設定）

@export_group("Knockback")
@export var knockback_chance: float = 0.0
@export var knockback_power: float = 0.0
@export var knockback_direction: Vector2 = Vector2(1.0, -0.5) # x=水平, y=垂直
@export var kb_resistance: float = 0.0

@export_group("Flinch (Stun)")
@export var flinch_chance: float = 0.0      # 攻撃ヒット時に相手をひるませる(スタン)確率(%)
@export var flinch_duration: float = 0.0    # ひるませる秒数

@export_group("Death Effect")
@export var death_effect_type: String = "" # 例: "explosion"
@export var death_effect_value: float = 0.0 # 爆発ダメージ等
@export var death_effect_range: float = 0.0 # 爆発範囲等

@export_group("Visuals")
@export var visual_size: float = 30.0
@export var unit_color: Color = Color.WHITE

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
		"attack_windup_time": attack_windup_time,
		"knockback_chance": knockback_chance,
		"knockback_power": knockback_power,
		"knockback_direction": knockback_direction,
		"kb_resistance": kb_resistance,
		"flinch_chance": flinch_chance,
		"flinch_duration": flinch_duration,
		"lifespan": lifespan,
		"is_ranged": is_ranged,
		"projectile_speed": projectile_speed,
		"projectile_color": projectile_color,
		"projectile_aoe": projectile_aoe,
		"death_effect_type": death_effect_type,
		"death_effect_value": death_effect_value,
		"death_effect_range": death_effect_range,
		"visual_size": visual_size,
		"unit_color": unit_color,
		"is_upgraded": get("is_upgraded") if get("is_upgraded") != null else false
	}
