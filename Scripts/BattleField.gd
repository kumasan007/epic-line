# BattleField.gd
# 戦場全体を管理するスクリプト
# ユニットの生成・管理、デッキとの連携、敵ウェーブの管理、勝敗判定を担当する
extends Node2D

# --- 戦場の定数（横画面 1280×720） ---
# 上部60%=432px が戦場、下部40%=288px がUI
# ユニットが歩く地面のY座標（地面ラインの上端）
const GROUND_Y: float = 380.0
# 自陣の拠点X座標（ここからユニットが出現する）
const PLAYER_BASE_X: float = 70.0
# 敵陣の拠点X座標（横幅が1280pxあるので広いレーン）
const ENEMY_BASE_X: float = 1210.0

# --- 拠点HP ---
const PLAYER_BASE_HP: float = 500.0
const ENEMY_BASE_HP: float = 500.0

# --- 参照 ---
@onready var units_container: Node2D = $Units
@onready var main_camera: Camera2D = $Camera2D

# --- マネージャー ---
var deck_manager: DeckManager = null
var wave_manager: WaveManager = null
var spell_manager: SpellManager = null

# --- 拠点HP管理 ---
var player_hp: float = 0.0
var player_max_hp_current: float = 0.0
var enemy_hp: float = 0.0
var battle_ended: bool = false
var earned_gold: int = 0

# 配置可能範囲をマップの半分に設定（1280幅なので640を中心とする）
var player_deploy_limit_x: float = 640.0
# 配置可能ゾーンのビジュアル
var deploy_zone_node: Node2D = null

# --- 時間停止 ---
var is_time_stopped: bool = false
var time_stop_overlay: ColorRect = null
var time_stop_label: Label = null

# --- 演出用（ヒットストップ＆画面揺れ） ---
var hit_stop_timer: float = 0.0
var camera_shake_timer: float = 0.0
var camera_shake_intensity: float = 0.0
var original_camera_pos: Vector2 = Vector2.ZERO

# --- 拠点HPバー（画面上部に表示） ---
var player_hp_bar: ColorRect = null
var enemy_hp_bar: ColorRect = null
var player_hp_label: Label = null
var enemy_hp_label: Label = null
var result_label: Label = null

func _ready() -> void:
	print("[BattleField] 戦場を初期化しました")
	
	# 拠点HPの初期化（GameManagerから引き継ぐ）
	if GameManager != null:
		player_hp = float(GameManager.player_current_hp)
		player_max_hp_current = float(GameManager.player_max_hp)
	else:
		player_hp = PLAYER_BASE_HP
		player_max_hp_current = PLAYER_BASE_HP
		
	enemy_hp = ENEMY_BASE_HP
	
	# 拠点HPバーUIの作成
	_create_base_hp_ui()
	
	# 時間停止オーバーレイ作成
	_create_time_stop_ui()
	
	# DeckManagerの作成と初期化
	_setup_deck_manager()
	
	# WaveManagerの作成と初期化
	_setup_wave_manager()
	
	# SpellManagerの作成と初期化
	_setup_spell_manager()
	
	# UILayerとの接続
	_connect_ui_layer()
	

	
	# 配置可能ゾーンの地面ビジュアルを生成
	_setup_deploy_zone_visual()
	
	if main_camera:
		original_camera_pos = main_camera.position
		
	# === 実時間ウェーブ制：最初から時間は進み始める ===
	# 時止めは廃止されました

# === _processで演出処理を回す（ヒットストップ・カメラシェイク） ===
func _process(delta: float) -> void:
		
	# -- カメラシェイク処理 --
	if camera_shake_timer > 0.0 and main_camera != null:
		camera_shake_timer -= delta
		# 強度が徐々に減衰するシェイク
		var dampen = maxf(camera_shake_timer * 1.5, 0.0)
		var offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized() * camera_shake_intensity * dampen
		main_camera.position = original_camera_pos + offset
		if camera_shake_timer <= 0.0:
			main_camera.position = original_camera_pos
			
	# -- ヒットストップ（一瞬だけゲーム速度を遅くする/止める） --
	if hit_stop_timer > 0.0:
		Engine.time_scale = 0.1
		hit_stop_timer -= delta
		if hit_stop_timer <= 0.0:
			Engine.time_scale = 1.0
	

	
	# -- 拠点へのダメージ判定とピンチ演出 --
	_check_base_damage(delta)

# === 拠点ダメージとピンチ演出 ===
var _pinch_flash_timer: float = 0.0

func _check_base_damage(delta: float) -> void:
	if battle_ended:
		return
		
	var player_base_threat: int = 0
	
	for child in units_container.get_children():
		if not (child is BaseUnit) or not child.is_alive or child.is_ghost:
			continue
			
		if child.team == BaseUnit.Team.ENEMY:
			# 敵が自陣拠点(x=70±20)に到達したらダメージ
			if child.position.x <= PLAYER_BASE_X + 20.0:
				player_hp -= child.atk * delta
				player_base_threat += 1
				trigger_impact(0.0, 2.0, 0.1) # 軽く揺らす
				
		elif child.team == BaseUnit.Team.PLAYER:
			# 味方が敵拠点(x=1210±20)に到達したらダメージ
			if child.position.x >= ENEMY_BASE_X - 20.0:
				enemy_hp -= child.atk * delta
				trigger_impact(0.0, 2.0, 0.1)
				
	_update_base_hp_ui()
	
	# ピンチ演出（自拠点HP20%以下かつ敵が拠点に張り付いてる時）
	var main_node = get_parent()
	if main_node:
		var effect_layer = main_node.get_node_or_null("EffectLayer")
		if effect_layer:
			var pinch_rect = effect_layer.get_node_or_null("PinchFlash")
			if pinch_rect == null:
				pinch_rect = ColorRect.new()
				pinch_rect.name = "PinchFlash"
				pinch_rect.color = Color(1.0, 0.0, 0.0, 0.0)
				pinch_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
				pinch_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
				effect_layer.add_child(pinch_rect)
				
			if player_hp > 0 and player_hp < player_max_hp_current * 0.2:
				_pinch_flash_timer += delta * 2.5
				# 正弦波で赤く点滅（アルファ値 0.1〜0.35）
				pinch_rect.color.a = 0.1 + (sin(_pinch_flash_timer) * 0.5 + 0.5) * 0.25
			else:
				pinch_rect.color.a = 0.0
				
	if player_hp <= 0.0:
		player_hp = 0.0
		_update_base_hp_ui()
		_on_battle_defeat()
	elif enemy_hp <= 0.0:
		enemy_hp = 0.0
		_update_base_hp_ui()
		# TODO: _on_battle_victory() があれば呼ぶ
		if has_method("_on_battle_victory"):
			call("_on_battle_victory")
		else:
			print("VICTORY!!!!")
			battle_ended = true

# === 演出トリガー（ユニット等から手軽に呼べるようにする） ===
func trigger_impact(hit_stop_duration: float = 0.05, shake_intensity: float = 10.0, shake_duration: float = 0.2) -> void:
	# 既存のヒットストップ・シェイクより強い・長い場合のみ上書きする
	if hit_stop_duration > hit_stop_timer:
		hit_stop_timer = hit_stop_duration
	if shake_intensity > camera_shake_intensity:
		camera_shake_intensity = shake_intensity
	if shake_duration > camera_shake_timer:
		camera_shake_timer = shake_duration

# === 死亡ユニットの生存数をカウント ===
func get_alive_count_by_name(u_name: String) -> int:
	var count: int = 0
	for child in units_container.get_children():
		if child is BaseUnit and child.is_alive and child.team == BaseUnit.Team.PLAYER:
			if child.unit_name == u_name:
				count += 1
	return count


# === デッキマネージャーの構築（リアルタイムサイクル制） ===
func _setup_deck_manager() -> void:
	deck_manager = DeckManager.new()
	deck_manager.name = "DeckManager"
	add_child(deck_manager)
	

	# サイクル開始時に敵ゴーストを配置
	deck_manager.cycle_started.connect(_on_cycle_started)
	
	# デッキを初期化（全カードをスロットにセット）
	var initial_deck: Array[CardData] = _create_test_deck()
	deck_manager.initialize_deck(initial_deck)

# === サイクル開始時：敵ゴーストを配置 ===
func _on_cycle_started(cycle_number: int) -> void:
	if battle_ended:
		return
	var enemies_for_cycle: Array[Dictionary] = _get_enemies_for_cycle(cycle_number)
	for enemy_stats in enemies_for_cycle:
		# 敵は常に敵拠点付近（右端）から出現。城砦で足止めされつつ前進する
		var spawn_x = randf_range(ENEMY_BASE_X - 120.0, ENEMY_BASE_X - 20.0)
		var unit = spawn_unit(BaseUnit.Team.ENEMY, spawn_x, enemy_stats, true)
		unit.enemy_base_x = PLAYER_BASE_X
		
		# --- 敵は1.5秒の「ゴースト状態」を経て進軍開始 ---
		get_tree().create_timer(1.5).timeout.connect(func():
			if is_instance_valid(unit) and unit.is_ghost:
				unit.materialize()
				# 敵の実体化エフェクト（赤黒いオーラ）
				var effect = ColorRect.new()
				effect.size = Vector2(unit.visual_size + 15, unit.visual_size + 15)
				effect.color = Color(1.0, 0.2, 0.2, 0.4)
				effect.position = Vector2(-effect.size.x/2, -effect.size.y)
				unit.add_child(effect)
				var tw = unit.create_tween()
				tw.tween_property(effect, "scale", Vector2(1.3, 1.3), 0.3)
				tw.parallel().tween_property(effect, "modulate:a", 0.0, 0.3)
				tw.tween_callback(effect.queue_free)
		)
		
	print("[BattleField] サイクル%d: 敵%d体を出撃警告(1.5秒後に進軍)！" % [cycle_number, enemies_for_cycle.size()])

# === サイクル番号に応じた敵の編成を返す ===
func _get_enemies_for_cycle(cycle_number: int) -> Array[Dictionary]:
	var enemies: Array[Dictionary] = []
	
	# ===  敵ロールテンプレート ===
	# プレイヤーと同じく「ロール」を持たせ、戦術的な戦闘を生む
	
	# 雑兵ゴブリン（狂気兵の敵版。安い・速い・脆い）
	var goblin = {
		"unit_name": "ゴブリン", "max_hp": 25.0, "atk": 8.0,
		"attack_range": 28.0, "speed": 75.0, "attack_interval": 0.7,
		"visual_size": 18.0, "unit_color": Color(0.3, 0.7, 0.2)
	}
	# オーク盾（盾兵の敵版。HPが高く壁になるが攻撃は弱い）
	var orc_shield = {
		"unit_name": "オーク盾", "max_hp": 500.0, "atk": 5.0,
		"attack_range": 40.0, "speed": 18.0, "attack_interval": 2.5,
		"knockback_chance": 70.0, "knockback_power": 40.0, "kb_resistance": 60.0,
		"visual_size": 45.0, "unit_color": Color(0.25, 0.45, 0.25)
	}
	# ゴブリン弓兵（弓兵の敵版。後方から射撃）
	var goblin_archer = {
		"unit_name": "ゴブリン弓", "max_hp": 60.0, "atk": 30.0,
		"attack_range": 300.0, "speed": 15.0, "attack_interval": 3.0,
		"flinch_chance": 80.0, "flinch_duration": 0.4,
		"visual_size": 22.0, "unit_color": Color(0.5, 0.7, 0.3),
		"is_ranged": true, "projectile_speed": 400.0, "projectile_aoe": 10.0
	}
	# オーク狂戦士（双剣兵の敵版。連撃型）
	var orc_berserker = {
		"unit_name": "オーク狂戦士", "max_hp": 150.0, "atk": 15.0,
		"attack_range": 35.0, "speed": 40.0, "attack_interval": 0.6,
		"visual_size": 28.0, "unit_color": Color(0.6, 0.2, 0.1)
	}
	# ★ボス：死の暴君（10サイクル目に登場する最終壁）
	var boss = {
		"unit_name": "死の暴君", "max_hp": 3000.0, "atk": 60.0,
		"attack_range": 55.0, "speed": 12.0, "attack_interval": 3.0, "defense": 10.0,
		"knockback_chance": 100.0, "knockback_power": 100.0, "kb_resistance": 90.0,
		"flinch_chance": 60.0, "flinch_duration": 0.8,
		"visual_size": 80.0, "unit_color": Color(0.35, 0.1, 0.45)
	}
	
	# === サイクル別の編成（段階的難易度上昇）===
	# 設計思想: 最初は「数で押す」→中盤「壁+火力の組み合わせ」→終盤「プレイヤーの鏡写し」
	match cycle_number:
		1:
			# サイクル1: 雑兵のみ。チュートリアル的な易しさ
			for i in range(3):
				enemies.append(goblin.duplicate())
		2:
			# サイクル2: 雑兵増加+壁役が初登場。「壁を壊す」経験
			for i in range(4):
				enemies.append(goblin.duplicate())
			enemies.append(orc_shield.duplicate())
		3:
			# サイクル3: 弓兵登場！壁の後ろから射撃し始める
			for i in range(3):
				enemies.append(goblin.duplicate())
			enemies.append(orc_shield.duplicate())
			enemies.append(goblin_archer.duplicate())
		4:
			# サイクル4: 「壁+弓」コンボを体験。プレイヤーも対応を迫られる
			for i in range(2):
				enemies.append(goblin.duplicate())
			for i in range(2):
				enemies.append(orc_shield.duplicate())
			for i in range(2):
				enemies.append(goblin_archer.duplicate())
		5:
			# サイクル5: 狂戦士登場！速い連撃で前線を切り崩す
			for i in range(3):
				enemies.append(goblin.duplicate())
			enemies.append(orc_shield.duplicate())
			enemies.append(goblin_archer.duplicate())
			for i in range(2):
				enemies.append(orc_berserker.duplicate())
		_:
			# サイクル6以降: 全ロールが出現。毎サイクル少しずつ増えていく
			var extra = cycle_number - 5
			for i in range(2 + extra):
				enemies.append(goblin.duplicate())
			for i in range(1 + extra / 2):
				enemies.append(orc_shield.duplicate())
			for i in range(1 + extra / 2):
				enemies.append(goblin_archer.duplicate())
			if cycle_number >= 7:
				for i in range(extra / 2):
					enemies.append(orc_berserker.duplicate())
			# 10サイクル目にボス出現！
			if cycle_number == 10:
				enemies.append(boss.duplicate())
	
	return enemies
# ===================================================
# 配置ゾーン・地面ビジュアル
# ===================================================

# 内部クラス：市松模様を描画するNode2D
# GDScriptではinner classに_draw()を定義して使うことができる
class DeployZoneVisual extends Node2D:
	var zone_width: float = 200.0   # 配置可能な横幅（player_deploy_limit_x - PLAYER_BASE_X）
	var start_x: float = 70.0       # 開始X（自陣拠点）
	var tile_size: float = 30.0     # 市松の1マスサイズ
	var zone_y: float = 380.0       # 地面Y座標
	var zone_height: float = 40.0   # 地面に描く高さ
	
	func _draw() -> void:
		# zone_width ÷ tile_size 列 × zone_height ÷ tile_size 行 の市松模様
		var cols = int(ceil(zone_width / tile_size)) + 1
		var rows = int(ceil(zone_height / tile_size)) + 1
		for row in range(rows):
			for col in range(cols):
				# 市松: (row+col)が偶数→白、奇数→薄グレー
				var color: Color
				if (row + col) % 2 == 0:
					color = Color(1.0, 1.0, 1.0, 0.18)   # 白（薄め）
				else:
					color = Color(0.1, 0.1, 0.1, 0.12)   # 黒（薄め）
				var rx = start_x + col * tile_size
				var ry = zone_y + row * tile_size
				# zone_widthを超えないようクリップ
				var rw = minf(tile_size, start_x + zone_width - rx)
				if rw <= 0:
					continue
				draw_rect(Rect2(rx, ry, rw, tile_size), color)
		
		# ゾーン右端に縦線（ここまで置けるという境界線）
		var edge_x = start_x + zone_width
		draw_line(Vector2(edge_x, zone_y), Vector2(edge_x, zone_y + zone_height),
			Color(1.0, 1.0, 0.5, 0.6), 2.0)

func _setup_deploy_zone_visual() -> void:
	deploy_zone_node = DeployZoneVisual.new()
	deploy_zone_node.start_x = PLAYER_BASE_X
	deploy_zone_node.zone_width = player_deploy_limit_x - PLAYER_BASE_X
	deploy_zone_node.zone_y = GROUND_Y
	deploy_zone_node.zone_height = 42.0
	deploy_zone_node.tile_size = 28.0
	# units_containerより下のz_indexで描画（ユニットの後ろ）
	deploy_zone_node.z_index = -1
	add_child(deploy_zone_node)

func _refresh_deploy_zone_visual() -> void:
	if deploy_zone_node == null or not is_instance_valid(deploy_zone_node):
		return
	deploy_zone_node.zone_width = player_deploy_limit_x - PLAYER_BASE_X
	deploy_zone_node.queue_redraw()  # 再描画をリクエスト

# === ウェーブマネージャーの構築（サイクル制では未使用だが、UI表示用に残す） ===
func _setup_wave_manager() -> void:
	wave_manager = WaveManager.new()
	wave_manager.name = "WaveManager"
	add_child(wave_manager)
	
	# サイクル制ではタイマーベースのスポーンはしない（_on_cycle_startedが担当）
	# wave_changedだけUI表示用に接続
	wave_manager.wave_changed.connect(_on_wave_changed)
	wave_manager.all_waves_completed.connect(_on_all_waves_completed)

# === スペルマネージャーの構築 ===
func _setup_spell_manager() -> void:
	spell_manager = SpellManager.new()
	spell_manager.name = "SpellManager"
	add_child(spell_manager)
	
	# シグナル接続
	spell_manager.spell_cast_requested.connect(_on_spell_cast)
	spell_manager.time_stop_started.connect(_on_time_stop_started)
	spell_manager.time_stop_ended.connect(_on_time_stop_ended)
	
	# テスト用スペルを作成してセット
	var fireball := SpellData.new()
	fireball.spell_name = "火球"
	fireball.spell_type = SpellData.SpellType.DAMAGE_AOE
	fireball.cooldown = 12.0
	fireball.effect_value = 30.0 # 強すぎたので60→30に下方修正
	fireball.effect_range = 100.0 # 少しだけ爆撃範囲も縮小
	spell_manager.set_spell(0, fireball)
	
	var heal := SpellData.new()
	heal.spell_name = "回復"
	heal.spell_type = SpellData.SpellType.HEAL_ALL
	heal.cooldown = 20.0
	heal.effect_value = 40.0
	spell_manager.set_spell(1, heal)

func _connect_ui_layer() -> void:
	call_deferred("_deferred_connect_ui")

func _deferred_connect_ui() -> void:
	var main_node = get_parent()
	if main_node == null:
		return
	var ui_layer = main_node.get_node_or_null("UILayer/UIRoot")
	if ui_layer and ui_layer is Control:
		if ui_layer.has_method("connect_deck_manager"):
			ui_layer.connect_deck_manager(deck_manager)
		if ui_layer.has_method("set_battlefield_ref"):
			ui_layer.set_battlefield_ref(self)
		print("[BattleField] UILayerとの接続完了")


# === デッキを取得（GameManagerがあればそこから、無ければテスト用を生成） ===
func _create_test_deck() -> Array[CardData]:
	if GameManager != null and GameManager.player_deck.size() > 0:
		print("[BattleField] GameManagerからデッキを取得します。")
		var deck: Array[CardData] = []
		# 元の配列を壊さないようにディープコピー（参照コピー）で渡す
		for c in GameManager.player_deck:
			deck.append(c)
		return deck
		return deck
		
	# GameManagerから取得できなかった場合の最低限のフォールバック
	var deck: Array[CardData] = []
	var c := CardData.new()
	c.card_name = "新兵"
	c.unit_role = CardData.UnitRole.FIGHTER
	c.cooldown = 2.0
	c.unit_name = "新兵"
	c.max_hp = 50.0
	c.atk = 8.0
	c.attack_range = 35.0
	c.speed = 80.0
	c.attack_interval = 0.8
	c.visual_size = 25.0
	c.unit_color = Color(0.4, 0.6, 0.8)
	deck.append(c)
	
	print("[BattleField] フォールバック用デッキを作成しました。")
	return deck

# === UILayerから要求されたカードの発動・予約 ===
func request_use_card(hand_index: int, target_pos_x: float) -> void:
	if battle_ended:
		return
	if deck_manager == null:
		return
	
	if hand_index < 0 or hand_index >= deck_manager.hand.size():
		return
	
	var card: CardData = deck_manager.hand[hand_index]
	
	if deck_manager.try_use_card(hand_index):
		if card.is_curse:
			return
		
		# カード種別に応じた処理を分岐
		match card.card_type:
			CardData.CardType.UNIT:
				var count = card.summon_count
				print("[BattleField] ユニット '%s' ×%d を位置 %.0f に配置！(1秒後に実体化)" % [card.card_name, count, target_pos_x])
				for i in range(count):
					var offset_x = 0.0
					if count > 1:
						offset_x = (i - (count - 1) / 2.0) * 25.0  # 中心から±25pxずつ散開
					var spawn_x = clampf(target_pos_x + offset_x, PLAYER_BASE_X, 640.0)
					var unit = spawn_unit(BaseUnit.Team.PLAYER, spawn_x, card.get_unit_stats(), true)
					unit.enemy_base_x = ENEMY_BASE_X
					
					# --- 1秒間の待機後に実体化 ---
					# ゴーストとして配置し、1秒後に materialize() を呼ぶ
					get_tree().create_timer(1.0).timeout.connect(func():
						if is_instance_valid(unit) and unit.is_ghost:
							unit.materialize()
							# ちょっとしたエフェクト
							var effect = ColorRect.new()
							effect.size = Vector2(unit.visual_size + 10, unit.visual_size + 10)
							effect.color = Color(0.8, 1.0, 1.0, 0.4)
							effect.position = Vector2(-effect.size.x/2, -effect.size.y)
							unit.add_child(effect)
							var tw = unit.create_tween()
							tw.tween_property(effect, "scale", Vector2(1.5, 1.5), 0.3)
							tw.parallel().tween_property(effect, "modulate:a", 0.0, 0.3)
							tw.tween_callback(effect.queue_free)
					)
			
			CardData.CardType.SPELL_INSTANT:
				# 即時スペル → ドロップした瞬間に効果発動！
				print("[BattleField] ⚡ スペル '%s' を即時発動！" % card.card_name)
				_execute_spell(card, target_pos_x)
			
			CardData.CardType.SPELL_CYCLE:
				# 遅延スペル → 1秒後に発動
				print("[BattleField] 🕐 スペル '%s' を1秒後に発動" % card.card_name)
				get_tree().create_timer(1.0).timeout.connect(func():
					_execute_spell(card, target_pos_x)
				)

# === スペルカードの効果を実行する ===
func _execute_spell(card: CardData, target_x: float) -> void:
	match card.spell_effect:
		"damage_aoe":
			# 指定位置周辺の敵にAoEダメージ
			var hit_count: int = 0
			for child in units_container.get_children():
				if child is BaseUnit and child.is_alive and child.team == BaseUnit.Team.ENEMY:
					if not child.is_ghost:  # ゴースト（まだ実体化していない敵）には当たらない
						var dist = abs(child.position.x - target_x)
						if dist <= card.spell_range:
							child.take_damage(card.spell_value, null, true)
							hit_count += 1
			print("[BattleField] 🔥 '%s' が%d体にヒット！" % [card.card_name, hit_count])
			# 爆発エフェクト
			_spawn_spell_effect(target_x, card.spell_color, card.spell_range)
		
		"heal_all":
			# 味方全体を回復
			var heal_count: int = 0
			for child in units_container.get_children():
				if child is BaseUnit and child.is_alive and child.team == BaseUnit.Team.PLAYER:
					if not child.is_ghost:
						child.current_hp = minf(child.current_hp + card.spell_value, child.max_hp)
						child._update_hp_bar()
						heal_count += 1
			print("[BattleField] 💚 '%s' で%d体を回復！" % [card.card_name, heal_count])
			# 回復エフェクト（画面全体にうっすら緑）
			_spawn_spell_effect(640.0, card.spell_color, 1280.0)  # 画面全体
	
		_:
			print("[BattleField] ⚠ 未知のスペル効果: '%s'" % card.spell_effect)

# === スペルの視覚エフェクト ===
func _spawn_spell_effect(x_pos: float, color: Color, radius: float) -> void:
	var effect = ColorRect.new()
	effect.color = Color(color.r, color.g, color.b, 0.4)
	effect.size = Vector2(radius * 2, 200)
	effect.position = Vector2(x_pos - radius, GROUND_Y - 150)
	add_child(effect)
	
	# フェードアウトして消える
	var tween = effect.create_tween()
	tween.tween_property(effect, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_OUT)
	tween.tween_callback(effect.queue_free)

# === 旧WaveManager用（サイクル制では未使用。_on_cycle_startedに移行済み） ===
func _on_enemy_spawn_requested(enemy_stats: Dictionary) -> void:
	if battle_ended:
		return
	var unit = spawn_unit(BaseUnit.Team.ENEMY, ENEMY_BASE_X, enemy_stats, true)
	unit.enemy_base_x = PLAYER_BASE_X

# === ユニットを戦場に生成する汎用関数 ===
func spawn_unit(team: BaseUnit.Team, spawn_x: float, stats: Dictionary = {}, is_ghost: bool = false) -> BaseUnit:
	var unit := BaseUnit.new()
	unit.team = team

	
	# ステータスの上書き
	if stats.has("unit_role"): unit.unit_role = stats["unit_role"]
	if stats.has("unit_name"): unit.unit_name = stats["unit_name"]
	if stats.has("max_hp"): unit.max_hp = stats["max_hp"]
	if stats.has("atk"): unit.atk = stats["atk"]
	if stats.has("attack_range"): unit.attack_range = stats["attack_range"]
	if stats.has("defense"): unit.defense = stats["defense"]
	if stats.has("speed"): unit.speed = stats["speed"]
	if stats.has("attack_interval"): unit.attack_interval = stats["attack_interval"]
	if stats.has("attack_windup_time"): unit.attack_windup_time = stats["attack_windup_time"]
	if stats.has("knockback_chance"): unit.knockback_chance = stats["knockback_chance"]
	if stats.has("knockback_power"): unit.knockback_power = stats["knockback_power"]
	if stats.has("knockback_direction"): unit.knockback_direction = stats["knockback_direction"]
	if stats.has("kb_resistance"): unit.kb_resistance = stats["kb_resistance"]
	if stats.has("flinch_chance"): unit.flinch_chance = stats["flinch_chance"]
	if stats.has("flinch_duration"): unit.flinch_duration = stats["flinch_duration"]
	if stats.has("lifespan"): unit.lifespan = stats["lifespan"]
	if stats.has("death_effect_type"): unit.death_effect_type = stats["death_effect_type"]
	if stats.has("death_effect_value"): unit.death_effect_value = stats["death_effect_value"]
	if stats.has("death_effect_range"): unit.death_effect_range = stats["death_effect_range"]
	if stats.has("visual_size"): unit.visual_size = stats["visual_size"]
	if stats.has("unit_color"): unit.unit_color = stats["unit_color"]
	if stats.has("is_ranged"): unit.is_ranged = stats["is_ranged"]
	if stats.has("projectile_speed"): unit.projectile_speed = stats["projectile_speed"]
	if stats.has("projectile_color"): unit.projectile_color = stats["projectile_color"]
	if stats.has("projectile_aoe"): unit.projectile_aoe = stats["projectile_aoe"]
	if stats.has("is_flying"): unit.is_flying = stats["is_flying"]
	if stats.has("is_upgraded"): unit.is_upgraded = stats["is_upgraded"]
	
	# Y座標にランダムな微小オフセットを加えて「団子化」を緩和
	var y_offset: float = randf_range(-15.0, 15.0)
	# 飛行ユニットは地面より上に浮く
	var fly_offset: float = -100.0 if unit.is_flying else 0.0
	unit.position = Vector2(spawn_x, GROUND_Y + y_offset + fly_offset)
	unit.base_y = GROUND_Y + y_offset + fly_offset
	
	# 戦場のUnitsノードに子として追加
	units_container.add_child(unit)
	
	# ゴースト配置ならゴーストとしてセットアップ
	if is_ghost:
		unit.setup_as_ghost()
		
	# --- アーティファクトの効果適用 ---
	if GameManager != null:
		if team == BaseUnit.Team.PLAYER and "mask_of_swiftness" in GameManager.player_relics:
			unit.speed *= 1.2 # 味方全員の移動速度+20%
	
	# シグナルを接続
	unit.unit_died.connect(_on_unit_died)
	unit.attacked_base.connect(_on_unit_attacked_base)
	
	return unit

# === ユニットが敵拠点に攻撃した場合 ===
func _on_unit_attacked_base(unit: BaseUnit, damage: float) -> void:
	if battle_ended:
		return
	
	if unit.team == BaseUnit.Team.PLAYER:
		# 自軍ユニットが敵拠点にダメージ
		enemy_hp = maxf(enemy_hp - damage, 0.0)
		_update_base_hp_ui()
		if enemy_hp <= 0.0:
			_on_battle_victory()
		# 敵拠点への通常攻撃では画面は揺らさない（多段ヒットでずっと揺れ続けてしまうため）
	else:
		# 敵ユニットが自陣にダメージ
		if GameManager != null and "heavy_plating" in GameManager.player_relics:
			damage *= 0.8 # 拠点ダメージ20%軽減
		player_hp = maxf(player_hp - damage, 0.0)
		_update_base_hp_ui()
		trigger_impact(0.0, 5.0, 0.2) # 拠点が叩かれたら揺らす
		if player_hp <= 0.0:
			_on_battle_defeat()
		else:
			# 自陣が殴られた時だけ「ヒットストップ（スロー）なし」で軽く揺らす
			trigger_impact(0.0, 5.0, 0.2)

# === ユニット死亡時のコールバック ===
func _on_unit_died(unit: BaseUnit) -> void:
	var team_name: String = "自軍" if unit.team == BaseUnit.Team.PLAYER else "敵軍"
	
	if unit.team == BaseUnit.Team.ENEMY:
		# 敵が死んだ際の処理（ゴールド獲得）
		var drop: int = 5
		if "ボス" in unit.unit_name:
			drop = 150
			trigger_impact(0.0, 20.0, 0.8) # ボス撃破時は大揺れ
		elif "オーク" in unit.unit_name:
			drop = 30
			trigger_impact(0.0, 8.0, 0.3)
		elif "弓兵" in unit.unit_name:
			drop = 10
			
		earned_gold += drop
		# （旧システムの士気によるCD短縮ボーナスはリアルタイム制移行により廃止）
		# 画面にゴールドポップアップを出す
		var lbl = Label.new()
		lbl.text = "+%d G" % drop
		lbl.position = unit.position - Vector2(10, 50)
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2)) # ゴールド色
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 2)
		add_child(lbl)
		
		# 上にフワッと浮いて消える
		var tween = lbl.create_tween().set_parallel(true)
		tween.tween_property(lbl, "position:y", lbl.position.y - 40.0, 0.6).set_ease(Tween.EASE_OUT)
		tween.tween_property(lbl, "modulate:a", 0.0, 0.6).set_ease(Tween.EASE_IN).set_delay(0.2)
		
		var end_tween = lbl.create_tween()
		end_tween.tween_interval(0.8)
		end_tween.tween_callback(lbl.queue_free)

# === ウェーブ番号更新 ===
func _on_wave_changed(wave_num: int, total: int) -> void:
	print("[BattleField] ウェーブ %d / %d" % [wave_num, total])

	# UILayerのデバッグ表示を更新
	var main_node = get_parent()
	if main_node:
		var ui_root = main_node.get_node_or_null("UILayer/UIRoot")
		if ui_root and ui_root.has_method("_update_debug_info"):
			# 山札と捨て札の数をUIに渡す
			var deck_size: int = deck_manager.draw_pile.size() if deck_manager else 0
			var discard_size: int = deck_manager.discard_pile.size() if deck_manager else 0
			ui_root._update_debug_info(deck_size, discard_size, wave_num)

# === 全ウェーブ完了 ===
func _on_all_waves_completed() -> void:
	print("[BattleField] 全ウェーブ完了！ 残った敵を倒せば勝利！")

# === 勝利処理 ===
func _on_battle_victory() -> void:
	if battle_ended:
		return
	battle_ended = true
	wave_manager.stop_waves()
	print("🏆 VICTORY!! 敵陣撃破！")
	
	if GameManager != null:
		print("獲得ゴールド: %d" % earned_gold)
		GameManager.player_gold += earned_gold
		GameManager.player_current_hp = int(player_hp)
	
	_show_result_screen("VICTORY!!", Color(0.2, 0.8, 0.2), "獲得ゴールド: %d G" % earned_gold)


# === 敗北処理 ===
func _on_battle_defeat() -> void:
	if battle_ended:
		return
	battle_ended = true
	wave_manager.stop_waves()
	print("💀 DEFEAT... 自陣陥落...")
	
	_show_result_screen("DEFEAT...", Color(0.9, 0.2, 0.2), "自陣が破壊されました")

# === 勝敗結果画面の表示（動的生成） ===
func _show_result_screen(title: String, color: Color, subtext: String) -> void:
	var canvas = CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)
	
	# 半透明の黒背景
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.75)
	canvas.add_child(bg)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	canvas.add_child(vbox)
	
	var title_label = Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 64)
	title_label.add_theme_color_override("font_color", color)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)
	
	var sub_label = Label.new()
	sub_label.text = subtext
	sub_label.add_theme_font_size_override("font_size", 24)
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub_label)
	
	var btn_container = MarginContainer.new()
	btn_container.add_theme_constant_override("margin_top", 30)
	vbox.add_child(btn_container)
	
	var restart_btn = Button.new()
	restart_btn.text = "もう一度プレイ"
	restart_btn.custom_minimum_size = Vector2(240, 60)
	restart_btn.add_theme_font_size_override("font_size", 24)
	# シーンの再読み込みでループを回す
	restart_btn.pressed.connect(func(): get_tree().reload_current_scene())
	btn_container.add_child(restart_btn)
	
	# アニメーションでポップアップ
	vbox.scale = Vector2.ZERO
	vbox.pivot_offset = Vector2(200, 100) # おおよその中心
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(vbox, "scale", Vector2.ONE, 0.5)

# === 拠点HPバーUIの作成 ===
func _create_base_hp_ui() -> void:
	# 自陣HPバー（左上）
	player_hp_bar = ColorRect.new()
	player_hp_bar.position = Vector2(10, 10)
	player_hp_bar.size = Vector2(200, 16)
	player_hp_bar.color = Color(0.2, 0.5, 0.9, 0.9)
	add_child(player_hp_bar)
	
	var player_bg := ColorRect.new()
	player_bg.position = Vector2(10, 10)
	player_bg.size = Vector2(200, 16)
	player_bg.color = Color(0.1, 0.1, 0.1, 0.6)
	player_bg.z_index = -1
	add_child(player_bg)
	
	player_hp_label = Label.new()
	player_hp_label.position = Vector2(10, 28)
	player_hp_label.add_theme_font_size_override("font_size", 12)
	player_hp_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	player_hp_label.text = "自陣 HP: %d / %d" % [int(player_hp), int(player_max_hp_current)]
	add_child(player_hp_label)
	
	# 敵陣HPバー（右上）
	enemy_hp_bar = ColorRect.new()
	enemy_hp_bar.position = Vector2(1070, 10)
	enemy_hp_bar.size = Vector2(200, 16)
	enemy_hp_bar.color = Color(0.9, 0.2, 0.2, 0.9)
	add_child(enemy_hp_bar)
	
	var enemy_bg := ColorRect.new()
	enemy_bg.position = Vector2(1070, 10)
	enemy_bg.size = Vector2(200, 16)
	enemy_bg.color = Color(0.1, 0.1, 0.1, 0.6)
	enemy_bg.z_index = -1
	add_child(enemy_bg)
	
	enemy_hp_label = Label.new()
	enemy_hp_label.position = Vector2(1070, 28)
	enemy_hp_label.add_theme_font_size_override("font_size", 12)
	enemy_hp_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.7))
	enemy_hp_label.text = "敵陣 HP: %d / %d" % [int(enemy_hp), int(ENEMY_BASE_HP)]
	add_child(enemy_hp_label)

# === 拠点HPバーの表示更新 ===
func _update_base_hp_ui() -> void:
	if player_hp_bar:
		player_hp_bar.size.x = 200.0 * (player_hp / player_max_hp_current)
	if player_hp_label:
		player_hp_label.text = "自陣 HP: %d / %d" % [int(player_hp), int(player_max_hp_current)]
	if enemy_hp_bar:
		enemy_hp_bar.size.x = 200.0 * (enemy_hp / ENEMY_BASE_HP)
	if enemy_hp_label:
		enemy_hp_label.text = "敵陣 HP: %d / %d" % [int(enemy_hp), int(ENEMY_BASE_HP)]

# === 勝敗結果の表示 ===
func _show_result(text: String, color: Color) -> void:
	result_label = Label.new()
	result_label.text = text
	result_label.add_theme_font_size_override("font_size", 48)
	result_label.add_theme_color_override("font_color", color)
	result_label.position = Vector2(400, 180)
	result_label.z_index = 100
	add_child(result_label)

# ==========================================
# === 時間停止 & スペルシステム ===
# ==========================================

# === 時間停止の開始 ===
func _on_time_stop_started() -> void:
	is_time_stopped = true
	print("[BattleField] ⏸ 時間停止！")
	
	# 全ユニットの_processを停止する
	# なぜset_process？→ ユニットの前進・攻撃が全て_processで動いているため
	for child in units_container.get_children():
		if child is BaseUnit:
			child.set_process(false)
	
	# ウェーブマネージャーも停止
	wave_manager.set_process(false)
	# デッキのCD進行も停止
	deck_manager.set_process(false)
	
	# 時間停止オーバーレイを表示
	if time_stop_overlay:
		time_stop_overlay.visible = true
	if time_stop_label:
		time_stop_label.visible = true

# === 時間停止の終了 ===
func _on_time_stop_ended() -> void:
	is_time_stopped = false
	print("[BattleField] ▶ 時間再開！")
	
	# 全ユニットの_processを再開
	for child in units_container.get_children():
		if child is BaseUnit:
			child.set_process(true)
	
	# マネージャーも再開
	wave_manager.set_process(true)
	deck_manager.set_process(true)
	
	# オーバーレイを非表示
	if time_stop_overlay:
		time_stop_overlay.visible = false
	if time_stop_label:
		time_stop_label.visible = false

# === スペル効果の処理 ===
func _on_spell_cast(spell: SpellData, _slot_index: int, target_pos: Vector2) -> void:
	print("[BattleField] スペル '%s' 発動！ 位置: " % spell.spell_name, target_pos)
	
	match spell.spell_type:
		SpellData.SpellType.DAMAGE_AOE:
			_spell_damage_aoe(spell, target_pos)
		SpellData.SpellType.HEAL_ALL:
			_spell_heal_all(spell)
		SpellData.SpellType.BUFF_ATK:
			_spell_buff_atk(spell)
		SpellData.SpellType.SLOW_ENEMIES:
			_spell_slow_enemies(spell)

# === AoEダメージ（ドラッグ＆ドロップで指定した位置を爆撃） ===
func _spell_damage_aoe(spell: SpellData, target_pos: Vector2) -> void:
	# 指定位置（target_pos）から一定範囲（effect_range）の敵にのみダメージ
	# （横スクロールなのでX軸の距離を重視しつつ、円形に判定）
	var hit_count: int = 0
	for child in units_container.get_children():
		if child is BaseUnit and child.team == BaseUnit.Team.ENEMY and child.is_alive:
			# ドロップ位置と敵ユニットの距離を計算
			var dist = target_pos.distance_to(child.position)
			if dist <= spell.effect_range:
				child.take_damage(spell.effect_value, null, true) # スペル属性でダメージを渡す（ヒットストップ等は後述変更）
				hit_count += 1
				
	# スペル着弾時：画面全体の揺れと「ごく僅かな」ヒットストップ（メインは個別のヒットストップに任せる）
	trigger_impact(0.04, 20.0, 0.25)
	print("[BattleField] 🔥 (X:%.0f, Y:%.0f)に火球爆撃！ %d体の敵に%.0fダメージ！" % [target_pos.x, target_pos.y, hit_count, spell.effect_value])

# === 全味方回復 ===
func _spell_heal_all(spell: SpellData) -> void:
	var heal_count: int = 0
	for child in units_container.get_children():
		if child is BaseUnit and child.team == BaseUnit.Team.PLAYER and child.is_alive:
			child.current_hp = minf(child.current_hp + spell.effect_value, child.max_hp)
			child._update_hp_bar()
			heal_count += 1
	print("[BattleField] 💚 %d体の味方を%.0f回復！" % [heal_count, spell.effect_value])

# === ATKバフ（一定時間全味方のATKを加算） ===
func _spell_buff_atk(spell: SpellData) -> void:
	for child in units_container.get_children():
		if child is BaseUnit and child.team == BaseUnit.Team.PLAYER and child.is_alive:
			child.atk += spell.effect_value
			# 一定時間後にバフを解除するタイマー
			var timer := get_tree().create_timer(spell.effect_duration)
			var unit_ref = child
			var buff_amount = spell.effect_value
			timer.timeout.connect(func():
				if is_instance_valid(unit_ref) and unit_ref.is_alive:
					unit_ref.atk -= buff_amount
			)
	print("[BattleField] ⚔ 全味方のATK+%.0f（%.1f秒間）" % [spell.effect_value, spell.effect_duration])

# === 敵スロウ（一定時間全敵の移動速度を半減） ===
func _spell_slow_enemies(spell: SpellData) -> void:
	for child in units_container.get_children():
		if child is BaseUnit and child.team == BaseUnit.Team.ENEMY and child.is_alive:
			var original_speed: float = child.speed
			child.speed *= 0.5
			var timer := get_tree().create_timer(spell.effect_duration)
			var unit_ref = child
			timer.timeout.connect(func():
				if is_instance_valid(unit_ref) and unit_ref.is_alive:
					unit_ref.speed = original_speed
			)
	print("[BattleField] 🧊 全敵の速度50%%減（%.1f秒間）" % spell.effect_duration)

# === 時間停止オーバーレイUIの作成 ===
func _create_time_stop_ui() -> void:
	# 半透明の青いオーバーレイ（戦場全体に被せる）
	time_stop_overlay = ColorRect.new()
	time_stop_overlay.position = Vector2(0, 0)
	time_stop_overlay.size = Vector2(1280, 432)
	time_stop_overlay.color = Color(0.1, 0.15, 0.35, 0.3)
	time_stop_overlay.z_index = 50
	time_stop_overlay.visible = false
	time_stop_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(time_stop_overlay)
	
	# 「TIME STOP」テキスト
	time_stop_label = Label.new()
	time_stop_label.text = "⏸ TIME STOP"
	time_stop_label.add_theme_font_size_override("font_size", 28)
	time_stop_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0, 0.8))
	time_stop_label.position = Vector2(530, 50)
	time_stop_label.z_index = 51
	time_stop_label.visible = false
	add_child(time_stop_label)
