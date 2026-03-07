# SpellData.gd
# スペル1つ分のデータ定義（Resource型）
# スペルはユニットカードとは別枠で管理される
# 山札に混ぜず、固定スロットにセットしてCDで繰り返し使用する
extends Resource
class_name SpellData

# === スペルの基本情報 ===
@export var spell_name: String = "Unknown Spell"
@export_multiline var description: String = ""

# === CD ===
@export var cooldown: float = 15.0  # 発動後の再使用までのCD（秒）

# === 効果の種類 ===
# スペルの効果タイプを定義。BattleFieldがこれを見て処理を分岐する
enum SpellType {
	DAMAGE_AOE,    # 範囲ダメージ（タップした地点を中心に）
	HEAL_ALL,      # 全味方ユニットを回復
	BUFF_ATK,      # 全味方ユニットのATKを一定時間上昇
	SLOW_ENEMIES,  # 全敵ユニットの移動速度を一定時間低下
}

@export var spell_type: SpellType = SpellType.DAMAGE_AOE

# === 効果の数値 ===
@export var effect_value: float = 50.0  # ダメージ量/回復量/バフ量
@export var effect_range: float = 150.0 # 範囲（AoEの半径、ピクセル）
@export var effect_duration: float = 5.0 # 持続時間（バフ/デバフ用、秒）
