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
@export var attack_range: float = 50.0    # 射程距離（ピクセル）
@export var defense: float = 0.0          # 防御力
@export var speed: float = 80.0           # 移動速度（px/秒）
@export var cooldown: float = 3.0         # 召喚CD（カードシステム用、ユニット自体では使わない）
@export var lifespan: float = 0.0         # 寿命（秒）。0=無限
@export var attack_interval: float = 1.0  # 攻撃間隔（秒）

# ユニットのロール（BattleFieldからの指示で行動を変える）
var unit_role: int = 0  # CardData.UnitRole.FIGHTER と同じ意味(デフォルト=2)

# ノックバック関連
@export var knockback_chance: float = 0.0   # 吹き飛ばし確率(%)
@export var knockback_power: float = 0.0    # 吹き飛ばし力
@export var kb_resistance: float = 0.0      # ノックバック耐性(%)

# 死亡時効果
@export var death_effect_type: String = ""  # 例: "explosion"
@export var death_effect_value: float = 0.0 # 爆発ダメージ等
@export var death_effect_range: float = 0.0 # 爆発範囲等

# === 内部状態 ===
var current_hp: float = 0.0       # 現在HP
var is_alive: bool = true          # 生存フラグ
var current_target: BaseUnit = null # 現在の攻撃対象
var attack_timer: float = 0.0      # 攻撃クールダウンタイマー
var lifespan_timer: float = 0.0    # 寿命タイマー
var move_direction: float = 1.0    # 移動方向（1.0=右, -1.0=左）
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

func _process(delta: float) -> void:
	if not is_alive:
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
	# 現在の攻撃対象が無効なら、新しいターゲットを探す
	if current_target == null or not is_instance_valid(current_target) or not current_target.is_alive:
		current_target = _find_nearest_enemy()
	
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
			var stop_x: float = _get_defend_line_x()
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
	attack_timer += delta
	# 攻撃間隔ごとにダメージを与える
	if attack_timer >= attack_interval:
		attack_timer = 0.0
		
		# 攻撃アニメーション（物理的に一瞬前に出て戻る）
		var original_x = position.x
		var tween := create_tween()
		tween.tween_property(self, "position:x", position.x + move_direction * 15.0, 0.05).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(self, "position:x", original_x, 0.1).set_trans(Tween.TRANS_QUAD)
		
		# ---- 範囲内の全ての敵にダメージ（ハクスラ感・Epic War感のコア） ----
		var hit_count: int = 0
		var units_parent = get_parent()
		if units_parent != null:
			for enemy in units_parent.get_children():
				if enemy is BaseUnit and enemy != self and enemy.team != team and enemy.is_alive:
					if _is_in_range(enemy):
						enemy.take_damage(atk, self) # 攻撃元を渡してノックバック判定させる
						hit_count += 1
		
		# 攻撃を1体以上に当てた場合、自分自身も一瞬だけ動きを止めて「手応え」を出す
		if hit_count > 0:
			local_hit_stop_timer = 0.05 # 自身も少しだけヒットストップ
		
		# デバッグ用（ヒット数が多ければ「ドカッ！」と入った感じになる）
		# if hit_count > 1:
		# 	print("%s の範囲攻撃！ %d体の敵に ヒット！" % [unit_name, hit_count])

# === ダメージ受理 ===
func take_damage(damage: float, source_unit = null, is_spell: bool = false) -> void:
	if not is_alive:
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
	
	# ダメージを受けた視覚フィードバック（点滅）
	_flash_damage()
	
	# HP0以下で死亡
	if current_hp <= 0.0:
		_die()
		return
		
	# ノックバックの判定（生きていて、攻撃元にノックバック率がある場合）
	if source_unit != null and source_unit.knockback_chance > 0.0:
		if randf() * 100.0 <= source_unit.knockback_chance:
			_apply_knockback(source_unit.knockback_power, source_unit.move_direction)

# === 吹き飛ばし処理（ノックバック） ===
func _apply_knockback(power: float, attacker_direction: float) -> void:
	# 耐性で飛ぶ距離を減衰
	var actual_distance = power * maxf(1.0 - kb_resistance / 100.0, 0.0)
	if actual_distance <= 0.0:
		return
	
	# 相手の攻撃方向（attacker_direction）へ飛ぶ
	var target_x = position.x + (attacker_direction * actual_distance)
	var original_y = position.y
	var jump_height = 20.0 # 吹き飛ぶときの浮く高さ
	
	# XYを並行して動かし、放物線を描くように弾き飛ばされる
	var tween = create_tween().set_parallel(true)
	tween.tween_property(self, "position:x", target_x, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", original_y - jump_height, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	var fall_tween = create_tween()
	fall_tween.tween_interval(0.12)
	fall_tween.tween_property(self, "position:y", original_y, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# ※注意: ノックバック中は一時的に操作不能（スタン）にする処理は
	# 現在の「強制X移動」と被るため、一旦は「見た目上強引に吹っ飛ぶ」仕様とする

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
					fake_explosion_source.move_direction = push_dir
					
					enemy.take_damage(death_effect_value, fake_explosion_source)
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

# === 仮スプライトの作成 ===
# なぜColorRect？→ まだアートが無いので、色付き四角形でユニットを表現する
func _create_temp_sprite() -> void:
	sprite_rect = ColorRect.new()
	sprite_rect.size = Vector2(24, 32)
	# 中心を基準にするためオフセット
	sprite_rect.position = Vector2(-12, -32)
	
	# チームに応じた色分け
	if team == Team.PLAYER:
		sprite_rect.color = Color(0.3, 0.6, 1.0)   # 青（自軍）
	else:
		sprite_rect.color = Color(1.0, 0.3, 0.3)   # 赤（敵軍）
	
	add_child(sprite_rect)

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
