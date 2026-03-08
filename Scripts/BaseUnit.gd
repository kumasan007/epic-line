# BaseUnit.gd
# 全ユニットの基底クラス
# ステータス管理、自動前進、攻撃、死亡処理を担当する
# なぜNode2D？→ 物理エンジンを使わず、シンプルな距離計算で戦闘を処理するため
extends Node2D
class_name BaseUnit

# === シグナル ===
signal unit_died(unit: BaseUnit)     # ユニットが死亡した時
signal reached_base(unit: BaseUnit)  # （未使用：互換性のために残す）
signal attacked_base(unit: BaseUnit, damage: float) # 拠点を攻撃した時

# === チーム定義 ===
# ユニットがどちらの軍に属するか
enum Team { PLAYER, ENEMY }

# === ステータス（企画書§6に対応） ===
@export var unit_name: String = "Unknown"
@export var team: Team = Team.PLAYER
@export var max_hp: float = 100.0         # 最大HP
@export var atk: float = 10.0             # 攻撃力
@export var cooldown: float = 3.0         # 召喚CD（カードシステム用、ユニット自体では使わない）
# ステータス関連
var attack_range: float = 40.0
var defense: float = 0.0
var speed: float = 80.0
var attack_interval: float = 1.0     # 何秒に1回攻撃するか
var attack_windup_time: float = -1.0 # 攻撃モーションのタメ時間
var lifespan: float = 0.0            # >0 なら一定時間で死亡する
var is_ranged: bool = false
var projectile_speed: float = 300.0
var projectile_color: Color = Color.WHITE
var projectile_aoe: float = 0.0 # 着弾後の爆発範囲

# ユニットのロール（BattleFieldからの指示で行動を変える）
var unit_role: int = 0  # CardData.UnitRole.FIGHTER と同じ意味(デフォルト=2)

# ノックバック関連
@export var knockback_chance: float = 0.0   # 吹き飛ばし確率(%)
@export var knockback_power: float = 0.0    # 吹き飛ばし力
@export var knockback_direction: Vector2 = Vector2(1.0, -0.5) # x=水平, y=垂直
@export var kb_resistance: float = 0.0      # ノックバック耐性(%)

# ひるみ（Flinch/Stun）関連
@export var flinch_chance: float = 0.0      # ひるみ確率(%)
@export var flinch_duration: float = 0.0    # ひるみ秒数

# 死亡時効果
@export var death_effect_type: String = "" # 死亡時の特殊効果（例: "explosion"）
var death_effect_value: float = 0.0 # 効果値（爆発ダメージなど）
var death_effect_range: float = 0.0 # 効果範囲
var is_upgraded: bool = false # アップグレード済みフラグ

# --- 演出用変数 ---
# 見た目（ハクスラとしての演出用）
@export var visual_size: float = 30.0        # ユニットのサイズ
@export var unit_color: Color = Color.WHITE  # ユニットの色

# === 内部状態 ===
var current_hp: float = 0.0       # 現在HP
var move_direction: float = 1.0    # 移動方向（1.0=右, -1.0=左）
var current_target: BaseUnit = null # 現在の攻撃対象
var attack_timer: float = 0.0      # 攻撃クールダウンタイマー
var original_attack_interval: float = 1.0
var battle_ended: bool = false
var is_alive: bool = true          # 生存フラグ
var is_ghost: bool = false        # ゴースト（出撃待機）状態フラグ
var lifespan_timer: float = 0.0    # 寿命タイマー
var local_hit_stop_timer: float = 0.0 # 個別ヒットストップ（Stun/硬直）

# 基準となるY座標（バトルフィールド側から渡される地面Y）
var base_y: float = 0.0
# 個体ごとの速度ゆらぎを持たせるための実際の速度
var actual_speed: float = 0.0

# === 全軍指揮の個別状態 ===
# デフォルトはfalse（待機・後退）。突撃命令を受けるとtrueになる。
var is_advancing: bool = false
# BattleFieldへの参照（待機/後退ロジックなどで使用）
var battlefield_ref = null

# === ラリーポイント（指定地点待機） ===
# -1.0 = 未設定（デフォルトのロール別ラインを使う）
# 0以上 = 指定された座標へ移動して待機する
var rally_x: float = -1.0

# === 選択ハイライト ===
var is_selected: bool = false
var highlight_rect: ColorRect = null

# === 拠点到達の境界座標 ===
# BattleFieldから設定される。この座標を超えたら拠点に到達とみなす
var enemy_base_x: float = INF

# === 描画用 ===
# 仮のスプライト（色付き四角形）。後でピクセルアートに差し替える
var sprite_rect: ColorRect = null
var hp_bar_bg: ColorRect = null
var hp_bar_fill: ColorRect = null

func _ready() -> void:
	# HPを最大値で初期化
	current_hp = max_hp
	
	# 個体ごとに移動速度を±10%ランダムに揺らして個体差を生む
	actual_speed = speed * randf_range(0.9, 1.1)
	
	# チームに応じて移動方向を設定
	if team == Team.PLAYER:
		move_direction = 1.0
	else:
		move_direction = -1.0
	
	# 仮スプライトの作成（色付き四角形）
	_create_temp_sprite()
	# HPバーの作成
	_create_hp_bar()
	# 選択ハイライト枠の作成
	_create_highlight()

func _process(delta: float) -> void:
	if not is_alive or is_ghost:
		return
	
	# --- 個別ヒットストップ（格ゲーの打撃停止） ---
	# 攻撃が当たった時やダメージを食らった時、一瞬だけ動きとアニメーションを止めて「重たい」感触を出す
	if local_hit_stop_timer > 0.0:
		local_hit_stop_timer -= delta
		return # ヒットストップ中は一切の行動（移動・攻撃タイマー進行）を行わない
	
	# --- 寿命チェック ---
	# 企画書：寿命が尽きるとHPに関わらず退場する
	if lifespan > 0.0:
		lifespan_timer += delta
		if lifespan_timer >= lifespan:
			_on_lifespan_expired()
			return
	
	# --- ターゲット検索 ---
	# 現在の攻撃対象が無効、あるいは射程外なら、より近いターゲットを探す
	var dist_to_target = INF
	if current_target != null and is_instance_valid(current_target) and current_target.is_alive:
		dist_to_target = abs(current_target.position.x - position.x)
	
	if current_target == null or not is_instance_valid(current_target) or not current_target.is_alive or dist_to_target > attack_range:
		var nearest = _find_nearest_enemy()
		if nearest != null:
			current_target = nearest
	
	# --- 行動決定：射程内なら攻撃、射程外なら前進 ---
	if current_target != null and _is_in_range(current_target):
		_do_attack(delta)
	else:
		_do_move(delta)
	
	# --- ユニット同士の押し合い（群れの自然なバラけを演出） ---
	_apply_soft_collision(delta)

# === 移動処理 ===
func _do_move(delta: float) -> void:
	# --- 敵との「すれ違い」防止ロジック ---
	# 足の速いユニットが敵を通り抜けてしまうのを防ぐため、物理的に極めて近い敵がいる場合は強制停止する
	var nearest = _find_nearest_enemy()
	if nearest != null:
		var dist_x = abs(position.x - nearest.position.x)
		if dist_x < 15.0: # 15px以内なら物理的にぶつかっていると判定して立ち止まる
			return
	
	# --- 待機/後退コマンド時の移動制御 ---
	# 自軍ユニットかつ、アサルト(0)以外の場合
	var current_move_dir: float = move_direction
	if team == Team.PLAYER and unit_role != 0:
		if not is_advancing: # 待機・後退状態
			# ラリーポイントが設定されていればそこへ、未設定ならロール別デフォルトラインへ
			var stop_x: float = rally_x if rally_x >= 0.0 else _get_defend_line_x()
			# 許容誤差±5px
			if position.x > stop_x + 5.0:
				# ラインより進みすぎている → 自陣へ逃げ帰る（左へ）
				current_move_dir = -1.0
			elif position.x < stop_x - 5.0:
				# ラインより手前 → 前進する（右へ）
				current_move_dir = 1.0
			else:
				# ライン上にいる → 立ち止まる
				return
	
	# 実際の速度（ゆらぎ込み）×方向で更新
	position.x += actual_speed * current_move_dir * delta
	
	# 移動中のボビング（上下の揺れ）と前のめりアニメーション
	# Time.get_ticks_msec() を使って歩行の躍動感を出す
	var time_sec = Time.get_ticks_msec() / 1000.0
	var bob_speed = actual_speed * 0.15
	var sprite_node = get_node_or_null("SpriteRect")
	if sprite_node:
		sprite_node.rotation_degrees = current_move_dir * 10.0 # 前のめり
		sprite_node.position.y = -visual_size + sin(time_sec * bob_speed) * (visual_size * 0.15) # 上下にポヨンポヨン跳ねる
	
	# --- 拠点到達チェック ---
	# 自軍は右端(敵拠点)に到達、敵軍は左端(自陣)に到達で拠点ダメージ
	if team == Team.PLAYER and position.x >= enemy_base_x:
		position.x = enemy_base_x # これ以上前進しない
		_do_attack_base(delta)
	elif team == Team.ENEMY and position.x <= enemy_base_x:
		position.x = enemy_base_x # これ以上前進しない
		_do_attack_base(delta)

# === 拠点攻撃処理 ===
# 敵のユニットではなく、拠点そのものを殴り続けるロジック
func _do_attack_base(delta: float) -> void:
	attack_timer += delta
	if attack_timer >= attack_interval:
		attack_timer = 0.0
		# 攻撃アニメーション（物理的に一瞬引いて戻る）
		position.x -= move_direction * 10.0
		var tween := create_tween()
		tween.tween_property(self, "position:x", position.x + move_direction * 10.0, 0.1).set_trans(Tween.TRANS_QUAD)
		
		# 拠点へダメージを与える
		attacked_base.emit(self, atk)

# === 全軍指揮命令を受け取る ===
func order_command(advance: bool) -> void:
	if unit_role == 0:
		return # アサルト(突撃兵)は命令を無視して常に前進する
	is_advancing = advance

# === ユニット種別のラリーポイントを設定 ===
func set_rally_point(x_pos: float) -> void:
	if unit_role == 0:
		return # 突撃兵は命令無視
	rally_x = x_pos
	# ラリーポイントが設定されたら突撃状態を解除（待機に戻す）
	is_advancing = false

# === 選択ハイライトの切り替え ===
func set_selected(selected: bool) -> void:
	is_selected = selected
	if highlight_rect:
		highlight_rect.visible = selected

# === 選択ハイライト枠の作成 ===
func _create_highlight() -> void:
	highlight_rect = ColorRect.new()
	highlight_rect.name = "Highlight"
	highlight_rect.color = Color(1.0, 1.0, 1.0, 0.3)
	highlight_rect.size = Vector2(visual_size + 8, visual_size + 8)
	highlight_rect.position = Vector2(-(visual_size + 8) / 2.0, -visual_size - 4)
	highlight_rect.visible = false
	highlight_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(highlight_rect)

# === ロールに応じた防衛ラインX座標を取得 ===
func _get_defend_line_x() -> float:
	# 自陣拠点(X=70)からどれくらい進んだ位置に待機するか
	match unit_role:
		1: return 350.0 # TANK: 一番前（前衛の壁）
		2: return 280.0 # FIGHTER: TANKの少し後ろ（近接主力）
		3: return 200.0 # SHOOTER: 自陣拠点に近い後方（遠距離支援）
		_: return 300.0

# === 味方同士のめり込みを防ぐソフトコリジョン ===
# 物理エンジンを使わず、近くの味方から軽く反発力を受けることで群れを散らす
func _apply_soft_collision(delta: float) -> void:
	var units_parent = get_parent()
	if units_parent == null:
		return
	
	var separation_vector := Vector2.ZERO
	var neighbor_count: int = 0
	
	for child in units_parent.get_children():
		if child is BaseUnit and child != self and child.team == team and child.is_alive:
			var diff = position - child.position
			var sqr_dist = diff.length_squared()
			# 半径25px(平方距離 625)以内なら反発を計算
			if sqr_dist < 625.0:
				if sqr_dist < 1.0:
					diff = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
					sqr_dist = 1.0
				# 近いほど反発力が強くなる
				var push_strength = (625.0 - sqr_dist) / 625.0
				separation_vector += diff.normalized() * push_strength * 40.0
				neighbor_count += 1
	
	if neighbor_count > 0:
		# 反発力を位置に適用
		position += separation_vector * delta
		# 大きくY軸がズレすぎないように基準Yから±20の範囲に収める
		if base_y > 0.0:
			position.y = clampf(position.y, base_y - 20.0, base_y + 20.0)

# === 攻撃処理（前方範囲薙ぎ払い） ===
func _do_attack(delta: float) -> void:
	# 攻撃準備（振りかぶり）の演出
	var windup = attack_windup_time
	if windup < 0.0:
		windup = minf(0.6, attack_interval * 0.4) # デフォルト値（自動設定）
		
	var is_winding_up = (attack_interval - attack_timer) < windup
	var sprite_node = get_node_or_null("SpriteRect")
	if sprite_node:
		if is_winding_up:
			# 攻撃が近づくと、逆方向に大きく傾いて「タメ」を作る
			var wind_tilt = -move_direction * 25.0
			sprite_node.rotation_degrees = lerp(sprite_node.rotation_degrees, wind_tilt, delta * 5.0)
		else:
			# それ以外は基本姿勢へ戻ろうとする（ひるみ中でなければ）
			if local_hit_stop_timer <= 0.0:
				sprite_node.rotation_degrees = lerp(sprite_node.rotation_degrees, 0.0, delta * 10.0)

	attack_timer += delta
	# 攻撃間隔ごとにダメージを与える
	if attack_timer >= attack_interval:
		attack_timer = 0.0
		
		# 攻撃アニメーション（タメからドスーンと前に踏み込む）
		var original_x = position.x
		var original_rot = 0.0
		if sprite_node:
			original_rot = sprite_node.rotation_degrees
			
		var tween := create_tween()
		# 重もっくるしく前方に踏み込む（0.15秒で大きく前進）
		var lunge_dist = visual_size * 0.8
		tween.tween_property(self, "position:x", position.x + move_direction * lunge_dist, 0.15).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		# ゆっくり元の位置に戻る
		tween.tween_property(self, "position:x", original_x, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		
		if sprite_node:
			# 振り下ろすように前にガクンと傾く
			sprite_node.rotation_degrees = move_direction * 45.0
			var rot_tween = create_tween()
			rot_tween.tween_property(sprite_node, "rotation_degrees", 0.0, 0.4).set_trans(Tween.TRANS_BOUNCE)
		
		if is_ranged:
			# 遠距離攻撃の場合
			_spawn_projectile()
		else:
			# 近接攻撃の場合
			_spawn_slash_effect()
			
			var hit_count: int = 0
			var units_parent = get_parent()
			if units_parent != null:
				for enemy in units_parent.get_children():
					if enemy is BaseUnit and enemy != self and enemy.team != team and enemy.is_alive:
						if _is_in_range(enemy):
							enemy.take_damage(atk, self)
							hit_count += 1
			
			if hit_count > 0:
				# 激しい攻撃は自分にも少しヒットストップ（重みの演出）
				local_hit_stop_timer = 0.1

# === 遠距離用の弾(Projectile)をスポーン ===
func _spawn_projectile() -> void:
	if current_target == null or not is_instance_valid(current_target):
		return # 対象がいなければ撃てない
		
	var battle_field = get_node_or_null("../../")
	if battle_field == null:
		return
		
	# 弾のシーン（スクリプト）を読み込んでインスタンス化
	var proj_script = load("res://Scripts/Projectile.gd")
	if proj_script == null:
		return
		
	var proj = proj_script.new()
	proj.team = team
	proj.damage = atk
	proj.speed = projectile_speed
	proj.knockback_chance = knockback_chance
	proj.knockback_power = knockback_power
	proj.knockback_direction = knockback_direction
	proj.flinch_chance = flinch_chance
	proj.flinch_duration = flinch_duration
	proj.source_unit = self
	proj.visual_size = 8.0
	# 弓兵の色と同じか、設定された色
	proj.projectile_color = projectile_color if projectile_color != Color.WHITE else unit_color
	proj.aoe_range = projectile_aoe
	proj.move_direction = move_direction
	
	# 少し高めから発射
	proj.position = position + Vector2(move_direction * visual_size * 0.5, -visual_size * 0.8)
	# 足元を狙う
	var tgt_pos = current_target.position + Vector2(0, -5.0) 
	
	# ランダムなバラけ（弓のブレ）を少しだけ追加
	tgt_pos.x += randf_range(-15.0, 15.0)
	tgt_pos.y += randf_range(-5.0, 5.0)
	
	proj.target_pos = tgt_pos
	
	# 戦場に追加（Unitsノード）
	var units_parent = get_parent()
	if units_parent != null:
		units_parent.add_child(proj)
	else:
		battle_field.add_child(proj)

# === ダメージ受理 ===
func take_damage(damage: float, source_unit = null, is_spell: bool = false) -> void:
	if not is_alive or is_ghost:
		return
	
	# 被弾時の個別ヒットストップ（食らい硬直）
	# スペルのような大ダメージなら長く、通常攻撃なら一瞬動きを止める
	if is_spell:
		local_hit_stop_timer = 0.15
	else:
		local_hit_stop_timer = 0.05
	
	# 防御力でダメージ軽減（最低1ダメージは入る）
	var actual_damage: float = maxf(damage - defense, 1.0)
	current_hp -= actual_damage
	_update_hp_bar()
	
	# ダメージポップアップの表示
	_spawn_damage_text(actual_damage, is_spell)
	
	# ヒットスパーク（打撃火花）の発生
	_spawn_hit_spark(is_spell)
	
	# ダメージを受けた視覚フィードバック（点滅）
	_flash_damage()
	
	# HP0以下で死亡
	if current_hp <= 0.0:
		_die()
		return
		
	# ノックバックの判定（生きていて、攻撃元にノックバック率がある場合）
	if source_unit != null and source_unit.knockback_chance > 0.0:
		if randf() * 100.0 <= source_unit.knockback_chance:
			_apply_knockback(source_unit.knockback_power, source_unit.move_direction, source_unit.get("knockback_direction"))
	
	# ひるみの判定
	if source_unit != null and source_unit.get("flinch_chance") != null and source_unit.flinch_chance > 0.0:
		if randf() * 100.0 <= source_unit.flinch_chance:
			_apply_flinch(source_unit.flinch_duration)

# === ひるみ処理（スタン） ===
func _apply_flinch(duration: float) -> void:
	# 既存のヒットストップタイマーを上書き・延長する
	if local_hit_stop_timer < duration:
		local_hit_stop_timer = duration
	
	# 少しだけ後ろにそけぞる演出
	var sprite_node = get_node_or_null("SpriteRect")
	if sprite_node:
		var original_rot = 0.0 # デフォルトの角度
		sprite_node.rotation_degrees = -move_direction * 15.0
		var rot_tween = create_tween()
		rot_tween.tween_property(sprite_node, "rotation_degrees", original_rot, duration)

# === 吹き飛ばし処理（ノックバック） ===
func _apply_knockback(power: float, attacker_direction: float, direction_vec = null) -> void:
	if direction_vec == null:
		direction_vec = Vector2(1.0, -0.5)
		
	var actual_power = power * maxf(1.0 - kb_resistance / 100.0, 0.0)
	if actual_power <= 0.0:
		return
	
	if local_hit_stop_timer < 0.4:
		local_hit_stop_timer = 0.4
	
	# 重いほどY軸（打ち上げ）を強調する
	var knockback_offset = Vector2(attacker_direction * direction_vec.x * actual_power, direction_vec.y * actual_power)
	var target_x = position.x + knockback_offset.x
	var original_y = position.y
	var jump_height = abs(knockback_offset.y) * 1.5 # 打ち上げを1.5倍に強調！（ドーパミン！）
	
	# 滞空時間は打ち上げ高さに比例して長くなる（落下物理演算っぽい挙動）
	var air_time_up = minf(0.3 + (jump_height / 500.0), 0.6)
	var air_time_down = minf(0.2 + (jump_height / 400.0), 0.5)
	
	# XとYをそれぞれの時間で動かす
	var tween = create_tween().set_parallel(true)
	var total_time = air_time_up + air_time_down
	tween.tween_property(self, "position:x", target_x, total_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", original_y - jump_height, air_time_up).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	var fall_tween = create_tween()
	fall_tween.tween_interval(air_time_up)
	fall_tween.tween_property(self, "position:y", original_y, air_time_down).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# 空中でグルグル回転しながら落ちるアニメーション！
	var sprite_node = get_node_or_null("SpriteRect")
	if sprite_node:
		var spins = 1
		if jump_height > 100.0: spins = 2
		if jump_height > 200.0: spins = 3
		
		# 後ろ向きに回転
		var spin_angle = -attacker_direction * 360.0 * spins
		var rot_tween = create_tween()
		sprite_node.rotation_degrees = 0
		rot_tween.tween_property(sprite_node, "rotation_degrees", spin_angle, total_time).set_trans(Tween.TRANS_LINEAR)
		# 着地時に0度に戻る
		rot_tween.chain().tween_property(sprite_node, "rotation_degrees", 0.0, 0.1)

# === 死亡処理 ===
func _die() -> void:
	if not is_alive: return # 既に死んでいればスキップ
	is_alive = false
	
	# --- 死亡時効果の発動 ---
	if death_effect_type == "explosion":
		_trigger_death_explosion()
		
	# 砕け散るエフェクト（ゴア/破片）
	_spawn_death_particles()
		
	# シグナルを発火して、戦場管理に通知
	unit_died.emit(self)
	# シーンから削除（後でエフェクト追加時にはここにアニメーションを入れる）
	queue_free()

# === 死亡時のパーティクル（破片）演出 ===
func _spawn_death_particles() -> void:
	var battle_field = get_node_or_null("../../") # BattleFieldへの参照（または自身を保持するコンテナ）
	if battle_field == null:
		return
		
	var particle_count = randi_range(4, 7)
	# 少し大きめのボスなら破片も増やす
	if max_hp >= 200.0:
		particle_count += 5
		
	for i in range(particle_count):
		var part = ColorRect.new()
		# チームに応じた破片の色（敵は赤、味方は青っぽい色、など）
		if team == Team.ENEMY:
			part.color = Color(randf_range(0.6, 1.0), randf_range(0.0, 0.2), randf_range(0.0, 0.2), 1.0) # 血のような赤
		else:
			part.color = Color(randf_range(0.2, 0.4), randf_range(0.4, 0.8), randf_range(0.8, 1.0), 1.0) # 青み
			
		var size_f = randf_range(4.0, 10.0)
		part.size = Vector2(size_f, size_f)
		part.position = position - Vector2(size_f/2, size_f/2)
		battle_field.add_child(part)
		
		# 放射状にバラ撒く
		var angle = randf_range(PI, PI*2) # 上方向に散らす
		var force = randf_range(30.0, 100.0)
		var target_x = part.position.x + cos(angle) * force
		var target_y = part.position.y + sin(angle) * force + 50.0 # 少し落ちる
		
		var tween = part.create_tween().set_parallel(true)
		tween.tween_property(part, "position:x", target_x, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(part, "position:y", target_y, 0.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(part, "modulate:a", 0.0, 0.4).set_ease(Tween.EASE_IN)
		
		var t_end = part.create_tween()
		t_end.tween_interval(0.4)
		t_end.tween_callback(part.queue_free)

# === ダメージポップアップの生成 ===
func _spawn_damage_text(val: float, is_critical: bool) -> void:
	var battle_field = get_node_or_null("../../")
	if battle_field == null:
		return
		
	var lbl = Label.new()
	lbl.text = str(int(val))
	lbl.position = position - Vector2(10, 40)
	
	if is_critical:
		lbl.add_theme_font_size_override("font_size", 24)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2)) # スペル/クリティカルは大きく黄色
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 2)
	else:
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.add_theme_color_override("font_outline_color", Color(0.2, 0.0, 0.0))
		lbl.add_theme_constant_override("outline_size", 1)
		
	battle_field.add_child(lbl)
	
	# 上へフワッと浮いて消えるアニメーション
	var rand_x = randf_range(-15.0, 15.0)
	var tween = lbl.create_tween().set_parallel(true)
	tween.tween_property(lbl, "position:y", lbl.position.y - 30.0, 0.5).set_ease(Tween.EASE_OUT)
	tween.tween_property(lbl, "position:x", lbl.position.x + rand_x, 0.5).set_ease(Tween.EASE_OUT)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN).set_delay(0.1)
	
	var end_tween = lbl.create_tween()
	end_tween.tween_interval(0.6)
	end_tween.tween_callback(lbl.queue_free)

# === 死亡時の爆発（自爆）処理 ===
func _trigger_death_explosion() -> void:
	var hit_count: int = 0
	var units_parent = get_parent()
	if units_parent != null:
		# 自分の全周囲の「敵」に対してダメージとノックバック(100%)を与える
		for enemy in units_parent.get_children():
			if enemy is BaseUnit and enemy != self and enemy.team != team and enemy.is_alive:
				var dist = position.distance_to(enemy.position)
				if dist <= death_effect_range:
					# 爆発の中心点(自分)から敵への方向ベクトルを算出
					# 今回はX軸のレーン移動のみなので、敵が自分の右にいれば1.0, 左にいれば-1.0
					var push_dir: float = 1.0 if enemy.position.x > position.x else -1.0
					
					# ノックバック元の偽装オブジェクト（爆発の衝撃）
					var fake_explosion_source = BaseUnit.new()
					fake_explosion_source.knockback_chance = 100.0
					fake_explosion_source.knockback_power = knockback_power # 自分のノックバック力を使う
					fake_explosion_source.knockback_direction = get("knockback_direction") if get("knockback_direction") else Vector2(1.0, -1.0)
					fake_explosion_source.flinch_chance = get("flinch_chance") if get("flinch_chance") else 100.0
					fake_explosion_source.flinch_duration = get("flinch_duration") if get("flinch_duration") else 1.0
					fake_explosion_source.move_direction = push_dir
					
					enemy.take_damage(death_effect_value, fake_explosion_source, false)
					fake_explosion_source.queue_free()
					hit_count += 1
	
	# ド派手な表示を少しする
	print("💥 %s が爆発！ 周囲の%d体の敵を吹き飛ばした！" % [unit_name, hit_count])

# === 寿命切れ処理 ===
func _on_lifespan_expired() -> void:
	# 寿命を迎えた際も破壊と同じ扱い（爆発効果などを発動）として_dieを処理させる
	_die()

# === 最も近い敵を探す ===
func _find_nearest_enemy() -> BaseUnit:
	# 親の"Units"ノードから全ユニットを取得
	var units_parent = get_parent()
	if units_parent == null:
		return null
	
	var nearest: BaseUnit = null
	var nearest_dist: float = INF
	
	for child in units_parent.get_children():
		if child is BaseUnit and child != self and child.is_alive:
			# 自分と違うチームのユニットだけを対象にする
			if child.team != team:
				var dist: float = abs(child.position.x - position.x)
				if dist < nearest_dist:
					nearest_dist = dist
					nearest = child
	
	return nearest

# === 射程内かどうか判定 ===
func _is_in_range(target: BaseUnit) -> bool:
	return abs(target.position.x - position.x) <= attack_range

# === 仮スプライト作成 ===
func _create_temp_sprite() -> void:
	var rect = ColorRect.new()
	rect.name = "SpriteRect"
	rect.size = Vector2(visual_size, visual_size)
	# 足元（中央下）を原点として配置
	rect.position = Vector2(-visual_size/2.0, -visual_size) 
	rect.pivot_offset = Vector2(visual_size/2.0, visual_size) # 回転の軸も足元に
	
	if unit_color != Color.WHITE:
		rect.color = unit_color
	else:
		if team == Team.PLAYER:
			rect.color = Color(0.3, 0.6, 1.0) # デフォルト青
		else:
			rect.color = Color(1.0, 0.3, 0.3) # デフォルト赤
			
	add_child(rect)
	
	# 強化済みならオーラを付ける
	if is_upgraded:
		var aura = ColorRect.new()
		aura.name = "UpgradeAura"
		aura.size = Vector2(visual_size + 4, visual_size + 4)
		aura.position = Vector2(-visual_size/2.0 - 2, -visual_size - 2)
		aura.pivot_offset = Vector2(visual_size/2.0 + 2, visual_size + 2)
		aura.color = Color(1.0, 0.9, 0.2, 0.3) # 黄色の半透明
		aura.z_index = -1
		add_child(aura)
		
		# オーラのアニメーション（フワフワ）
		var tween = create_tween().set_loops()
		tween.tween_property(aura, "scale", Vector2(1.1, 1.1), 0.5)
		tween.tween_property(aura, "scale", Vector2(1.0, 1.0), 0.5)

# === 斬撃エフェクトの生成 ===
func _spawn_slash_effect() -> void:
	var battle_field = get_node_or_null("../../")
	if battle_field == null: return
	
	var slash = ColorRect.new()
	slash.color = Color(1.0, 1.0, 0.8, 0.8) if team == Team.PLAYER else Color(1.0, 0.4, 0.4, 0.8)
	slash.size = Vector2(attack_range * 0.8, visual_size * 0.2)
	slash.position = position + Vector2(move_direction * visual_size * 0.5, -visual_size * 0.5)
	if move_direction < 0:
		slash.position.x -= slash.size.x # 左向きの場合は位置調整
		
	# 角度を少しランダムにつけて「斬りつけた」感を出す
	slash.pivot_offset = slash.size / 2.0
	slash.rotation_degrees = randf_range(-30, 30)
	
	battle_field.add_child(slash)
	
	# シュパッ！と伸びて消える
	var tween = slash.create_tween().set_parallel(true)
	tween.tween_property(slash, "scale:x", 1.5, 0.1).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(slash, "scale:y", 0.1, 0.1).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(slash, "modulate:a", 0.0, 0.1)
	
	var end_tween = slash.create_tween()
	end_tween.tween_interval(0.15)
	end_tween.tween_callback(slash.queue_free)

# === ヒットスパーク（火花演出）の生成 ===
func _spawn_hit_spark(is_spell: bool) -> void:
	var battle_field = get_node_or_null("../../")
	if battle_field == null: return
	
	# メインの火花
	var spark = ColorRect.new()
	if is_spell:
		spark.color = Color(1.0, 0.6, 0.2) # スペルは大きくオレンジ
		spark.size = Vector2(visual_size * 0.8, visual_size * 0.8)
	else:
		spark.color = Color(1.0, 0.9, 0.5) # 通常攻撃は黄色っぽい白
		spark.size = Vector2(visual_size * 0.5, visual_size * 0.5)
		
	spark.pivot_offset = spark.size / 2.0
	
	# バラけるようにランダム配置
	var offset_x = randf_range(-visual_size * 0.4, visual_size * 0.4)
	var offset_y = randf_range(-visual_size * 0.8, -visual_size * 0.2)
	spark.position = position + Vector2(offset_x, offset_y) - spark.size / 2.0
	spark.rotation_degrees = randf_range(0, 360)
	
	battle_field.add_child(spark)
	
	# パッと広がってシュッと消える
	var tween = spark.create_tween().set_parallel(true)
	tween.tween_property(spark, "scale", Vector2(1.8, 1.8), 0.1).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(spark, "modulate:a", 0.0, 0.15).set_ease(Tween.EASE_IN)
	
	var end_tween = spark.create_tween()
	end_tween.tween_interval(0.15)
	end_tween.tween_callback(spark.queue_free)

# === HPバーの作成 ===
func _create_hp_bar() -> void:
	# 背景（暗い灰色）
	hp_bar_bg = ColorRect.new()
	hp_bar_bg.size = Vector2(24, 3)
	hp_bar_bg.position = Vector2(-12, -36)
	hp_bar_bg.color = Color(0.15, 0.15, 0.15, 0.8)
	add_child(hp_bar_bg)
	
	# 塗り（緑→HP減少で赤に変化）
	hp_bar_fill = ColorRect.new()
	hp_bar_fill.size = Vector2(22, 2)
	hp_bar_fill.position = Vector2(-11, -35.5)
	hp_bar_fill.color = Color(0.3, 0.9, 0.3)
	add_child(hp_bar_fill)

# === HPバーの更新 ===
func _update_hp_bar() -> void:
	if hp_bar_fill == null:
		return
	var ratio: float = clampf(current_hp / max_hp, 0.0, 1.0)
	hp_bar_fill.size.x = 22.0 * ratio
	# HP残量に応じて色を変化（緑→黄→赤）
	if ratio > 0.5:
		hp_bar_fill.color = Color(0.3, 0.9, 0.3)
	elif ratio > 0.25:
		hp_bar_fill.color = Color(0.9, 0.8, 0.2)
	else:
		hp_bar_fill.color = Color(0.9, 0.2, 0.2)

# === ダメージ時の点滅演出 ===
func _flash_damage() -> void:
	if sprite_rect == null:
		return
	# 白く光らせて元に戻す簡易アニメーション
	var original_color: Color = sprite_rect.color
	sprite_rect.color = Color.WHITE
	# 0.1秒後に元の色に戻すタイマー
	var timer := get_tree().create_timer(0.1)
	timer.timeout.connect(func():
		if is_instance_valid(sprite_rect):
			sprite_rect.color = original_color
	)

# === ゴースト状態（出撃待機中）の設定 ===
# ゴースト状態のユニットは半透明で表示され、一切行動しない（_processでreturn）
# サイクル終了時にmaterialize()が呼ばれると、完全な状態で戦闘に参加する
func setup_as_ghost() -> void:
	is_ghost = true
	modulate.a = 0.35  # 半透明にして「まだ本物じゃない」ことを示す
	# HPバーを一時的に非表示に
	if hp_bar_bg:
		hp_bar_bg.visible = false
	if hp_bar_fill:
		hp_bar_fill.visible = false

# === ゴーストから実体化する ===
# サイクル終了時に呼ばれ、ユニットが完全に戦闘可能になる
func materialize() -> void:
	is_ghost = false
	modulate.a = 1.0  # 完全に不透明に
	# HPバーを再表示
	if hp_bar_bg:
		hp_bar_bg.visible = true
	if hp_bar_fill:
		hp_bar_fill.visible = true
	# 実体化した時は常に前進状態にする（全軍突撃ボタンを廃止したため）
	is_advancing = true
