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

# --- 時間停止 ---
var is_time_stopped: bool = false
var time_stop_overlay: ColorRect = null
var time_stop_label: Label = null

# --- 演出用（ヒットストップ＆画面揺れ） ---
var hit_stop_timer: float = 0.0
var camera_shake_timer: float = 0.0
var camera_shake_intensity: float = 0.0
var original_camera_pos: Vector2 = Vector2.ZERO

# --- ユニット選択システム ---
var selected_unit_name: String = ""  # 現在選択中のユニット種別名（"" = 未選択）
var rally_flag: ColorRect = null     # ラリーポイントの旗表示用
var unit_rally_points: Dictionary = {} # { "unit_name": float(rally_x) } 新規生成ユニットへ引き継ぐため

# --- 選択中専用の指揮UI ---
var selection_ui_canvas: CanvasLayer = null
var selection_ui_container: HBoxContainer = null

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
	
	if main_camera:
		original_camera_pos = main_camera.position
		
	# --- 選択時専用の指揮UI（矢印ボタン）を作成 ---
	_create_selection_ui()

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

# === ユニット選択＆ラリーポイント設定のクリック処理 ===
func _input(event: InputEvent) -> void:
	if battle_ended:
		return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# UI領域（画面Y座標 >= 420）は無視（スクリーン座標で判定）
		if event.position.y >= 420.0:
			return
			
		# --- 戦場（ワールド）の実際のクリック座標を取得 ---
		var world_pos = get_global_mouse_position()
		var clicked_unit = _find_unit_at(world_pos)
		
		# --- ステップ1: べつの自軍ユニットをクリックした場合は、選択をそちらに切り替える ---
		if clicked_unit != null and clicked_unit.team == BaseUnit.Team.PLAYER and clicked_unit.unit_name != selected_unit_name:
			_select_unit_type(clicked_unit.unit_name)
			return
			
		# --- ステップ2: 既に選択中の同種ユニット自身を再クリックした場合は、選択を解除する ---
		if clicked_unit != null and clicked_unit.team == BaseUnit.Team.PLAYER and clicked_unit.unit_name == selected_unit_name:
			_deselect_all()
			return
			
		# --- ステップ3: 地面をクリックした場合はラリーポイント設定 ---
		if selected_unit_name != "":
			_set_rally_for_selected(world_pos.x)
	
	# 右クリックで選択解除
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_deselect_all()

# === クリック位置の近くにいるユニットを探す ===
func _find_unit_at(pos: Vector2) -> BaseUnit:
	var best: BaseUnit = null
	var best_dist: float = 50.0  # 50px以内がクリック範囲
	for child in units_container.get_children():
		if child is BaseUnit and child.is_alive:
			var dist = child.position.distance_to(pos)
			if dist < best_dist:
				best_dist = dist
				best = child
	return best

# === 指定のユニット種別を全選択 ===
func _select_unit_type(u_name: String) -> void:
	selected_unit_name = u_name
	print("[BattleField] ユニット選択: '%s'" % u_name)
	
	var is_controllable = false
	
	# 同種のユニットを全てハイライト
	for child in units_container.get_children():
		if child is BaseUnit and child.is_alive and child.team == BaseUnit.Team.PLAYER:
			if child.unit_name == u_name:
				child.set_selected(true)
				if child.unit_role != 0: # 突撃兵以外なら操作可能
					is_controllable = true
			else:
				child.set_selected(false)
				
	# 操作可能なユニットなら専用UIを表示
	if selection_ui_container:
		selection_ui_container.visible = is_controllable

# === 選択解除 ===
func _deselect_all() -> void:
	selected_unit_name = ""
	for child in units_container.get_children():
		if child is BaseUnit:
			child.set_selected(false)
	# ラリー旗を消す
	if rally_flag and is_instance_valid(rally_flag):
		rally_flag.queue_free()
		rally_flag = null
	# 専用UIを隠す
	if selection_ui_container:
		selection_ui_container.visible = false

# === 選択中のユニットにラリーポイントを設定 ===
func _set_rally_for_selected(x_pos: float) -> void:
	var is_controllable: bool = false
	
	# 新規生成ユニット用にラリーポイントを記憶
	unit_rally_points[selected_unit_name] = x_pos
	
	for child in units_container.get_children():
		if child is BaseUnit and child.is_alive and child.team == BaseUnit.Team.PLAYER:
			if child.unit_name == selected_unit_name:
				# 突撃兵(ASSAULT)は命令無視なのでラリーも無視
				if child.unit_role != 0:
					child.set_rally_point(x_pos)
					is_controllable = true
	
	if is_controllable:
		print("[BattleField] '%s' のラリーポイントを X=%.0f に設定" % [selected_unit_name, x_pos])
		# ラリー旗の表示
		_show_rally_flag(x_pos)
	else:
		print("[BattleField] '%s' は命令を受け付けません" % selected_unit_name)
	
	# 指示を出した後はハイライトを解除する
	_deselect_all()

# === ラリー旗の表示 ===
func _show_rally_flag(x_pos: float) -> void:
	if rally_flag and is_instance_valid(rally_flag):
		rally_flag.queue_free()
	
	rally_flag = ColorRect.new()
	rally_flag.color = Color(0.2, 1.0, 0.2, 0.6)
	rally_flag.size = Vector2(4, 30)
	rally_flag.position = Vector2(x_pos - 2, GROUND_Y - 30)
	add_child(rally_flag)
	
	# 3秒後に自動で消える
	var tween = rally_flag.create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(rally_flag, "modulate:a", 0.0, 1.0)
	tween.tween_callback(rally_flag.queue_free)

# === 外部からユニット種別を選択する（ロスターUIから呼ばれる） ===
func select_unit_type_by_name(u_name: String) -> void:
	if selected_unit_name == u_name:
		_deselect_all() # 既に選択中なら解除（トグル動作）
	else:
		_select_unit_type(u_name)

# === 死亡ユニットの生存数をカウント ===
func get_alive_count_by_name(u_name: String) -> int:
	var count: int = 0
	for child in units_container.get_children():
		if child is BaseUnit and child.is_alive and child.team == BaseUnit.Team.PLAYER:
			if child.unit_name == u_name:
				count += 1
	return count


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
	
	# ウェーブデータの登録と開始
	if wave_manager:
		wave_manager.start_waves(WaveManager.get_waves_for_current_node())
	
	# --- ゲーム状態（HP等）の初期化 ---

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
		if ui_layer.has_method("connect_wave_manager"):
			ui_layer.connect_wave_manager(wave_manager)
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

# === CDが完了したカードからユニットを召喚する ===
func _on_card_summon(card: CardData, _hand_index: int) -> void:
	if battle_ended:
		return
		
	if card.is_curse:
		print("[BattleField] 呪いカード '%s' が発動！ 拠点にダメージ！" % card.card_name)
		player_hp = maxf(player_hp - card.atk, 0.0)
		_update_base_hp_ui()
		trigger_impact(0.01, 10.0, 0.3) # 呪いダメージで画面が少し揺れる
		
		var lbl = Label.new()
		lbl.text = "呪いダメージ! -%d" % int(card.atk)
		lbl.add_theme_font_size_override("font_size", 32)
		lbl.add_theme_color_override("font_color", Color(0.8, 0.1, 0.4))
		lbl.position = Vector2(PLAYER_BASE_X + 20, GROUND_Y - 100)
		add_child(lbl)
		var t = create_tween().set_parallel(true)
		t.tween_property(lbl, "position:y", lbl.position.y - 50.0, 1.0)
		t.tween_property(lbl, "modulate:a", 0.0, 1.0)
		t.chain().tween_callback(lbl.queue_free)
		
		# 呪いはユニットを出さない
		if player_hp <= 0.0:
			_on_battle_defeat()
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
	if stats.has("is_upgraded"): unit.is_upgraded = stats["is_upgraded"]
	
	# Y座標にランダムな微小オフセットを加えて「団子化」を緩和
	var y_offset: float = randf_range(-15.0, 15.0)
	unit.position = Vector2(spawn_x, GROUND_Y + y_offset)
	unit.base_y = GROUND_Y + y_offset # ソフトコリジョン用の基準Y
	
	# 戦場のUnitsノードに子として追加
	units_container.add_child(unit)
	
	# --- アーティファクトの効果適用 ---
	if GameManager != null:
		if team == BaseUnit.Team.PLAYER and "mask_of_swiftness" in GameManager.player_relics:
			unit.speed *= 1.2 # 味方全員の移動速度+20%
	
	# --- 新規生成ユニットへの「ラリーポイント」と「選択状態」の引き継ぎ ---
	if team == BaseUnit.Team.PLAYER:
		if unit_rally_points.has(unit.unit_name):
			unit.set_rally_point(unit_rally_points[unit.unit_name])
		if unit.unit_name == selected_unit_name:
			unit.set_selected(true)
	
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
			# DeckManagerの枚数を取得
			var deck_size: int = deck_manager.draw_pile.size() if deck_manager else 0
			var discard_size: int = deck_manager.discard_pile.size() if deck_manager else 0
			ui_root._update_debug_info(deck_size, discard_size, wave_num)

# === 選択時専用UIの作成 ===
func _create_selection_ui() -> void:
	selection_ui_canvas = CanvasLayer.new()
	selection_ui_canvas.layer = 5 # UILayer(10)より下、戦場より上
	add_child(selection_ui_canvas)
	
	selection_ui_container = HBoxContainer.new()
	# 画面上部の中央付近に配置
	selection_ui_container.set_anchors_preset(Control.PRESET_TOP_WIDE)
	selection_ui_container.position = Vector2(0, 20)
	selection_ui_container.alignment = BoxContainer.ALIGNMENT_CENTER
	selection_ui_container.add_theme_constant_override("separation", 100)
	selection_ui_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_ui_canvas.add_child(selection_ui_container)
	
	# 後退ボタン
	var btn_back = Button.new()
	btn_back.text = "◀ 後退"
	btn_back.custom_minimum_size = Vector2(160, 60)
	btn_back.add_theme_font_size_override("font_size", 28)
	btn_back.pressed.connect(_on_selection_back_pressed)
	var style_back = StyleBoxFlat.new()
	style_back.bg_color = Color(0.2, 0.4, 0.8, 0.9)
	style_back.set_corner_radius_all(8)
	btn_back.add_theme_stylebox_override("normal", style_back)
	btn_back.add_theme_stylebox_override("hover", style_back.duplicate())
	selection_ui_container.add_child(btn_back)
	
	# 突撃ボタン
	var btn_fwd = Button.new()
	btn_fwd.text = "突撃 ▶"
	btn_fwd.custom_minimum_size = Vector2(160, 60)
	btn_fwd.add_theme_font_size_override("font_size", 28)
	btn_fwd.pressed.connect(_on_selection_fwd_pressed)
	var style_fwd = StyleBoxFlat.new()
	style_fwd.bg_color = Color(0.8, 0.3, 0.2, 0.9)
	style_fwd.set_corner_radius_all(8)
	btn_fwd.add_theme_stylebox_override("normal", style_fwd)
	btn_fwd.add_theme_stylebox_override("hover", style_fwd.duplicate())
	selection_ui_container.add_child(btn_fwd)
	
	selection_ui_container.visible = false

# === 選択時UIのボタン処理 ===
func _on_selection_back_pressed() -> void:
	if selected_unit_name != "":
		# 自陣拠点の少し前まで一気に下げる
		_set_rally_for_selected(PLAYER_BASE_X + 60.0)

func _on_selection_fwd_pressed() -> void:
	if selected_unit_name != "":
		# 敵陣拠点の奥深くまで進ませる（実質的な突撃）
		_set_rally_for_selected(ENEMY_BASE_X - 10.0)

# === 全ウェーブ完了 ===
func _on_all_waves_completed() -> void:
	print("[BattleField] 全ウェーブ完了！ 残った敵を倒せば勝利！")

# === 勝利処理 ===
func _on_battle_victory() -> void:
	if battle_ended:
		return
	battle_ended = true
	wave_manager.stop_waves()
	print("🏆============================🏆")
	print("        VICTORY!! 敵陣撃破！")
	print("🏆============================🏆")
	
	if GameManager != null:
		print("獲得ゴールド: %d" % earned_gold)
		GameManager.player_gold += earned_gold
		GameManager.player_current_hp = int(player_hp)
		GameManager.on_battle_won()

# === 敗北処理 ===
func _on_battle_defeat() -> void:
	if battle_ended:
		return
	battle_ended = true
	wave_manager.stop_waves()
	print("💀============================💀")
	print("        DEFEAT... 自陣陥落...")
	print("💀============================💀")
	
	if GameManager != null:
		GameManager.on_battle_lost()

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
