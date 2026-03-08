# Projectile.gd
# 弓兵や魔法使いなどが放つ、遠距離攻撃用の「弾」
# 発射されてからターゲットに向かって移動し、着弾時（または敵に触れた時）にダメージとエフェクトを発生させる。
extends Node2D
class_name Projectile

# === プロパティ ===
var team: int = 0 # BaseUnit.Team (0= PLAYER, 1= ENEMY)
var damage: float = 0.0
var speed: float = 300.0
var target_pos: Vector2 = Vector2.ZERO
var knockback_chance: float = 0.0
var knockback_power: float = 0.0
var knockback_direction: Vector2 = Vector2(1.0, -0.5)
var flinch_chance: float = 0.0
var flinch_duration: float = 0.0
var source_unit = null     # 誰が撃ったか（生存確認や能力参照用）
var visual_size: float = 8.0
var projectile_color: Color = Color.WHITE
var aoe_range: float = 15.0 # 着弾時の爆発（ダメージ）範囲

var move_direction: float = 1.0 # 1.0=右、-1.0=左

func _ready() -> void:
	# 弾の見た目を作成
	var rect = ColorRect.new()
	rect.size = Vector2(visual_size * 2, visual_size) # 矢なので横長
	rect.position = Vector2(-visual_size, -visual_size / 2)
	rect.color = projectile_color
	add_child(rect)

func _process(delta: float) -> void:
	# 目標位置に向かって真っ直ぐ飛ぶ（X軸移動中心だが、Y軸も少し動く）
	var current_dist = position.distance_to(target_pos)
	var move_amount = speed * delta
	
	if current_dist <= move_amount:
		# 着弾した
		position = target_pos
		_explode_and_destroy()
		return
	
	# 移動方向
	var dir = (target_pos - position).normalized()
	position += dir * move_amount
	
	# 弾の向きを合わせる
	rotation = dir.angle()

# === 着弾処理（ダメージとエフェクト） ===
func _explode_and_destroy() -> void:
	var battle_field = get_node_or_null("../../")
	if battle_field == null:
		queue_free()
		return
		
	var hit_count: int = 0
	var units_parent = get_parent() # 通常はBattleField/Unitsにアタッチされる想定
	if units_parent != null:
		# AoE判定で敵を探す
		for enemy in units_parent.get_children():
			# Projectile自体もあるかもしれないのでBaseUnitかチェック
			if enemy is BaseUnit and enemy.team != team and enemy.is_alive:
				var dist = position.distance_to(enemy.position)
				if dist <= aoe_range:
					# ダメージ計算用に、仮のsourceを作る（ノックバック情報等を引き継ぐため）
					var fake_source = BaseUnit.new()
					fake_source.knockback_chance = knockback_chance
					fake_source.knockback_power = knockback_power
					fake_source.knockback_direction = knockback_direction
					fake_source.flinch_chance = flinch_chance
					fake_source.flinch_duration = flinch_duration
					fake_source.move_direction = move_direction
					
					enemy.take_damage(damage, fake_source, false) # 魔法の大きなヒットストップではなく通常のヒットストップ
					hit_count += 1
					fake_source.queue_free()
					
	# 攻撃が当たったら、個別ヒットストップの代わりにゲーム全体を「超極薄」で揺らしてヒット感を出す
	if hit_count > 0 and battle_field.has_method("trigger_impact"):
		battle_field.trigger_impact(0.01, 3.0, 0.1) # ごく僅かに画面を揺らす
		
	# 着弾エフェクト（小さな火花）
	var spark = ColorRect.new()
	spark.color = projectile_color
	spark.size = Vector2(visual_size * 1.5, visual_size * 1.5)
	spark.position = position - spark.size / 2
	battle_field.add_child(spark)
	
	var tween = spark.create_tween().set_parallel(true)
	tween.tween_property(spark, "scale", Vector2(2.0, 2.0), 0.1)
	tween.tween_property(spark, "modulate:a", 0.0, 0.1)
	tween.chain().tween_callback(spark.queue_free)
	
	queue_free()
