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
var enemy_hp: float = 0.0
var battle_ended: bool = false

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
	
	# 拠点HPの初期化
	player_hp = PLAYER_BASE_HP
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
	
	if main_camera:
		original_camera_pos = main_camera.position

# === _processで演出処理を回す（ヒットストップ・カメラシェイク） ===
func _process(delta: float) -> void:
	# -- 時間停止処理 --
	if is_time_stopped:
		return
		
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
		Engine.time_scale = 0.1 # 10%の速度でスローモーション（重い打撃感を出す）
		hit_stop_timer -= delta
		if hit_stop_timer <= 0.0:
			Engine.time_scale = 1.0 # 元の速度に戻す

# === 演出トリガー（ユニット等から手軽に呼べるようにする） ===
func trigger_impact(hit_stop_duration: float = 0.05, shake_intensity: float = 10.0, shake_duration: float = 0.2) -> void:
	# 既存のヒットストップ・シェイクより強い・長い場合のみ上書きする
	if hit_stop_duration > hit_stop_timer:
		hit_stop_timer = hit_stop_duration
	if shake_intensity > camera_shake_intensity:
		camera_shake_intensity = shake_intensity
	if shake_duration > camera_shake_timer:
		camera_shake_timer = shake_duration


# === デッキマネージャーの構築 ===
func _setup_deck_manager() -> void:
	deck_manager = DeckManager.new()
	deck_manager.name = "DeckManager"
	add_child(deck_manager)
	
	# CDが完了したカードからユニットを召喚するシグナルを接続
	deck_manager.card_ready_to_summon.connect(_on_card_summon)
	
	# テスト用の初期デッキを作成
	var initial_deck: Array[CardData] = _create_test_deck()
	deck_manager.initialize_deck(initial_deck)

# === ウェーブマネージャーの構築 ===
func _setup_wave_manager() -> void:
	wave_manager = WaveManager.new()
	wave_manager.name = "WaveManager"
	add_child(wave_manager)
	
	# 敵スポーンリクエストを受け取って実際に生成する
	wave_manager.spawn_enemy_requested.connect(_on_enemy_spawn_requested)
	# ウェーブ番号の変更をUIに通知
	wave_manager.wave_changed.connect(_on_wave_changed)
	# 全ウェーブ完了
	wave_manager.all_waves_completed.connect(_on_all_waves_completed)
	
	# テスト用ウェーブデータでスタート
	var test_waves: Array[Dictionary] = WaveManager.create_test_waves()
	wave_manager.start_waves(test_waves)

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
		if ui_layer.has_method("connect_spell_manager"):
			ui_layer.connect_spell_manager(spell_manager)
		if ui_layer.has_method("set_battlefield_ref"):
			ui_layer.set_battlefield_ref(self)
		print("[BattleField] UILayerとの接続完了")

# === 全軍指揮（現在フィールドにいる味方に命令を出す単発トリガー） ===
func order_all_player_units(advance: bool) -> void:
	if advance:
		print("[BattleField] ⚔ 現在の全軍に突撃命令を発行しました！")
	else:
		print("[BattleField] 🔙 現在の全軍に後退・待機命令を発行しました！")
	
	for child in units_container.get_children():
		if child is BaseUnit and child.team == BaseUnit.Team.PLAYER and child.is_alive:
			if child.has_method("order_command"):
				child.order_command(advance)

# === テスト用の初期デッキを作成 ===
func _create_test_deck() -> Array[CardData]:
	var deck: Array[CardData] = []
	
	# --- 巨盾兵（スーパータンク） × 1 ---
	# 特徴：絶望的に足が遅く、攻撃も信じられないほど遅いが、HPが異常に高く、一撃のノックバックが強烈。
	for i in range(1):
		var c := CardData.new()
		c.card_name = "巨盾兵"
		c.unit_role = CardData.UnitRole.TANK # 前衛の壁
		c.cooldown = 4.0
		c.unit_name = "巨盾兵"
		c.max_hp = 800.0        # 超絶硬い
		c.atk = 40.0           # 一撃は重い
		c.attack_range = 45.0
		c.defense = 10.0
		c.speed = 20.0         # めちゃくちゃ遅い
		c.attack_interval = 3.5 # 攻撃がスゲェ遅い（ドスーン！という感じ）
		c.knockback_chance = 100.0 # 攻撃したら絶対吹き飛ばす
		c.knockback_power = 90.0
		c.kb_resistance = 80.0 # ほとんど吹き飛ばされない
		deck.append(c)
		
	# --- 双剣兵（ラッシュアタッカー） × 2 ---
	# 特徴：HPは紙で射程も短いが、移動速度が速く、攻撃速度が異常（シュバッ！と連続で斬る）。
	for i in range(2):
		var c := CardData.new()
		c.card_name = "双剣兵"
		c.unit_role = CardData.UnitRole.FIGHTER # 中衛（前衛の後ろからラッシュ）
		c.cooldown = 2.5
		c.unit_name = "双剣兵"
		c.max_hp = 80.0         # スグ死ぬ
		c.atk = 8.0            # 一発は軽い
		c.attack_range = 35.0
		c.speed = 100.0        # かなり速い
		c.attack_interval = 0.3 # 狂った連撃スピード
		c.kb_resistance = 0.0
		deck.append(c)
	
	# --- 長弓兵（スナイパー） × 2 ---
	# 特徴：超後方から、遅いが一門の大砲のように重い一撃を放つ。
	for i in range(2):
		var c := CardData.new()
		c.card_name = "長弓兵"
		c.unit_role = CardData.UnitRole.SHOOTER # ずっと後ろ
		c.cooldown = 3.5
		c.unit_name = "長弓兵"
		c.max_hp = 50.0
		c.atk = 60.0           # 一撃の威力が鬼
		c.attack_range = 350.0 # 画面全体の半分くらい射程がある
		c.speed = 40.0         # 遅い
		c.attack_interval = 4.0 # 矢を撃つまでがスゲェ遅い
		c.knockback_chance = 50.0
		c.knockback_power = 40.0
		deck.append(c)
	
	# --- 狂ゴブリン（鉄砲玉） × 2 ---
	# 特徴：命令無視で爆速アタックするが、一発でも殴られたら死ぬ。
	for i in range(2):
		var c := CardData.new()
		c.card_name = "狂気兵"
		c.unit_role = CardData.UnitRole.ASSAULT # 命令無視の鉄砲玉
		c.cooldown = 2.0
		c.unit_name = "狂気兵"
		c.max_hp = 1.0          # 触れられたら即死
		c.atk = 20.0
		c.attack_range = 30.0
		c.speed = 180.0        # 爆速！
		c.attack_interval = 0.5
		deck.append(c)
	
	# --- 爆弾兵 × 1 ---
	# 特徴：今まで通りだが、寿命が極端に短いかわりに爆発特化。
	var bomb := CardData.new()
	bomb.card_name = "爆弾兵"
	bomb.unit_role = CardData.UnitRole.ASSAULT # 自爆特攻
	bomb.cooldown = 5.0
	bomb.unit_name = "爆弾兵"
	bomb.max_hp = 50.0
	bomb.atk = 1.0
	bomb.attack_range = 10.0
	bomb.speed = 140.0
	bomb.lifespan = 4.0        # 4秒で勝手に起爆
	bomb.knockback_chance = 100.0
	bomb.knockback_power = 120.0 # 爆発ですげー飛ぶ
	bomb.death_effect_type = "explosion" # 死亡時に爆発
	bomb.death_effect_value = 150.0      # 爆発の特大ダメージ
	bomb.death_effect_range = 150.0      # 広範囲
	deck.append(bomb)
	
	print("[BattleField] テストデッキ作成完了: %d枚" % deck.size())
	return deck

# === CDが完了したカードからユニットを召喚する ===
func _on_card_summon(card: CardData, _hand_index: int) -> void:
	if battle_ended:
		return
	print("[BattleField] カード '%s' のCD完了 → ユニット召喚！" % card.card_name)
	var unit = spawn_unit(BaseUnit.Team.PLAYER, PLAYER_BASE_X, card.get_unit_stats())
	# 自軍ユニットの拠点到達先 = 敵陣
	unit.enemy_base_x = ENEMY_BASE_X

# === 敵スポーンリクエスト（ウェーブマネージャーから） ===
func _on_enemy_spawn_requested(enemy_stats: Dictionary) -> void:
	if battle_ended:
		return
	var unit = spawn_unit(BaseUnit.Team.ENEMY, ENEMY_BASE_X, enemy_stats)
	# 敵ユニットの拠点到達先 = 自陣
	unit.enemy_base_x = PLAYER_BASE_X

# === ユニットを戦場に生成する汎用関数 ===
func spawn_unit(team: BaseUnit.Team, spawn_x: float, stats: Dictionary = {}) -> BaseUnit:
	var unit := BaseUnit.new()
	unit.team = team
	unit.battlefield_ref = self # BattleFieldの参照を持たせる（コマンド確認用）
	
	# ステータスの上書き
	if stats.has("unit_role"): unit.unit_role = stats["unit_role"]
	if stats.has("unit_name"): unit.unit_name = stats["unit_name"]
	if stats.has("max_hp"): unit.max_hp = stats["max_hp"]
	if stats.has("atk"): unit.atk = stats["atk"]
	if stats.has("attack_range"): unit.attack_range = stats["attack_range"]
	if stats.has("defense"): unit.defense = stats["defense"]
	if stats.has("speed"): unit.speed = stats["speed"]
	if stats.has("attack_interval"): unit.attack_interval = stats["attack_interval"]
	if stats.has("knockback_chance"): unit.knockback_chance = stats["knockback_chance"]
	if stats.has("knockback_power"): unit.knockback_power = stats["knockback_power"]
	if stats.has("kb_resistance"): unit.kb_resistance = stats["kb_resistance"]
	if stats.has("lifespan"): unit.lifespan = stats["lifespan"]
	if stats.has("death_effect_type"): unit.death_effect_type = stats["death_effect_type"]
	if stats.has("death_effect_value"): unit.death_effect_value = stats["death_effect_value"]
	if stats.has("death_effect_range"): unit.death_effect_range = stats["death_effect_range"]
	
	# Y座標にランダムな微小オフセットを加えて「団子化」を緩和
	var y_offset: float = randf_range(-15.0, 15.0)
	unit.position = Vector2(spawn_x, GROUND_Y + y_offset)
	unit.base_y = GROUND_Y + y_offset # ソフトコリジョン用の基準Y
	
	# 戦場のUnitsノードに子として追加
	units_container.add_child(unit)
	
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
		player_hp = maxf(player_hp - damage, 0.0)
		_update_base_hp_ui()
		if player_hp <= 0.0:
			_on_battle_defeat()
		else:
			# 自陣が殴られた時だけ「ヒットストップ（スロー）なし」で軽く揺らす
			trigger_impact(0.0, 5.0, 0.2)

# === ユニット死亡時のコールバック ===
func _on_unit_died(unit: BaseUnit) -> void:
	var team_name: String = "自軍" if unit.team == BaseUnit.Team.PLAYER else "敵軍"
	print("[BattleField] %s(%s) が撃破！" % [unit.unit_name, team_name])

# === ウェーブ番号更新 ===
func _on_wave_changed(wave_num: int, total: int) -> void:
	print("[BattleField] ウェーブ %d / %d" % [wave_num, total])
	# UILayerのデバッグ表示を更新
	var main_node = get_parent()
	if main_node:
		var ui_root = main_node.get_node_or_null("UILayer/UIRoot")
		if ui_root and ui_root.has_method("_update_debug_info"):
			# DeckManagerの枚数を取得
			var deck_size: int = deck_manager.draw_pile.size() if deck_manager else 0
			var discard_size: int = deck_manager.discard_pile.size() if deck_manager else 0
			ui_root._update_debug_info(deck_size, discard_size, wave_num)

# === 全ウェーブ完了 ===
func _on_all_waves_completed() -> void:
	print("[BattleField] 全ウェーブ完了！ 残った敵を倒せば勝利！")

# === 勝利処理 ===
func _on_battle_victory() -> void:
	battle_ended = true
	print("★★★ 勝利！ ★★★")
	_show_result("⚔ VICTORY! ⚔", Color(0.3, 0.9, 0.3))

# === 敗北処理 ===
func _on_battle_defeat() -> void:
	battle_ended = true
	print("✖✖✖ 敗北 ✖✖✖")
	_show_result("💀 DEFEAT 💀", Color(0.9, 0.2, 0.2))

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
	player_hp_label.text = "自陣 HP: %d / %d" % [int(player_hp), int(PLAYER_BASE_HP)]
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
		player_hp_bar.size.x = 200.0 * (player_hp / PLAYER_BASE_HP)
	if player_hp_label:
		player_hp_label.text = "自陣 HP: %d / %d" % [int(player_hp), int(PLAYER_BASE_HP)]
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
