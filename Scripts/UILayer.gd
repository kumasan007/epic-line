# UILayer.gd
# 画面下部40%のUI全体を管理するスクリプト
# フェーズ制マナ召喚システムに対応：
# - カードスロット（クリックで召喚）
# - マナ表示
# - 「出撃！」ボタン
# - 士気ゲージ
extends Control

# === 参照 ===
@onready var hand_container: HBoxContainer = $HandContainer
@onready var debug_label: Label = $DebugLabel
@onready var roster_container: HBoxContainer = $RosterContainer

# === 内部状態 ===
var slot_uis: Array[CardUI] = []
var deck_manager: DeckManager = null
var roster_count_labels: Dictionary = {}

# === ウェーブ関連 ===
var wave_manager: WaveManager = null
var wave_info_panel: PanelContainer = null
var wave_info_label: Label = null

# === スペル関連 ===
var spell_manager: SpellManager = null
var spell_buttons: Array[SpellButton] = []
var spell_container: HBoxContainer = null

# === 全軍指揮関連 ===
var battlefield_ref = null
var btn_advance: Button = null
var btn_defend: Button = null

# === サイクルシステムUI ===
var mana_label: Label = null
var cycle_timer_label: Label = null

# === ドラッグ＆ドロップ状態 ===
var dragging_slot_index: int = -1
var dragging_ghost: ColorRect = null

func _ready() -> void:
	print("[UILayer] UIを初期化しました")
	_update_debug_info(0, 0, 0)
	_create_spell_container()
	_create_mana_ui()

func set_battlefield_ref(ref) -> void:
	battlefield_ref = ref
	print("[UILayer] BattleFieldの参照を受け取りました")

func _process(_delta: float) -> void:
	_update_card_cds()
	_update_spell_cds()
	_update_roster_counts()
	_update_wave_info()

# === デッキマネージャーを接続する ===
func connect_deck_manager(dm: DeckManager) -> void:
	deck_manager = dm
	
	dm.mana_changed.connect(_on_mana_changed)
	dm.cycle_timer_updated.connect(_on_cycle_timer_updated)
	dm.hand_drawn.connect(_on_hand_drawn)
	dm.hand_discarded.connect(_on_hand_discarded)
	
	print("[UILayer] DeckManagerとの接続完了（リアルタイム・ウェーブ制）")
	
	if dm.hand.size() > 0:
		_create_card_slots()
	
	_on_mana_changed(dm.current_mana, dm.max_mana)

# === カードスロットUIを作成 ===
func _create_card_slots() -> void:
	if deck_manager == null: return
	_on_hand_discarded()
	
	if hand_container == null: return
	
	for i in range(deck_manager.hand.size()):
		var card = deck_manager.hand[i]
		var card_ui = CardUI.new()
		card_ui.custom_minimum_size = Vector2(120, 180)
		hand_container.add_child(card_ui)
		card_ui.set_card(card)
		slot_uis.append(card_ui)
		
		# ドラッグ＆ドロップ開始用
		card_ui.gui_input.connect(_on_card_slot_gui_input.bind(i))

func _on_hand_drawn() -> void:
	_create_card_slots()

func _on_hand_discarded() -> void:
	if dragging_ghost:
		dragging_ghost.queue_free()
		dragging_ghost = null
	dragging_slot_index = -1
	
	for card_ui in slot_uis:
		if is_instance_valid(card_ui):
			card_ui.queue_free()
	slot_uis.clear()

# === カードスロットでのドラッグ開始処理 ===
func _on_card_slot_gui_input(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if deck_manager == null: return
			var card = deck_manager.hand[slot_index]
			if deck_manager.current_mana >= card.mana_cost:
				dragging_slot_index = slot_index
				dragging_ghost = ColorRect.new()
				dragging_ghost.size = Vector2(card.visual_size, card.visual_size * 2)
				dragging_ghost.color = card.unit_color
				dragging_ghost.modulate.a = 0.5
				dragging_ghost.global_position = event.global_position - dragging_ghost.size / 2
				add_child(dragging_ghost)

# === グローバルドラッグ＆ドロップ処理 ===
func _input(event: InputEvent) -> void:
	if dragging_slot_index >= 0:
		if event is InputEventMouseMotion:
			if dragging_ghost:
				dragging_ghost.global_position = event.position - dragging_ghost.size / 2
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			var drop_pos = event.global_position
			if drop_pos.y < 420.0:  # 戦場エリアなら
				if battlefield_ref and battlefield_ref.has_method("request_use_card"):
					battlefield_ref.request_use_card(dragging_slot_index, drop_pos.x)
			
			if dragging_ghost:
				dragging_ghost.queue_free()
				dragging_ghost = null
			dragging_slot_index = -1

# === マナUI作成 ===
func _create_mana_ui() -> void:
	# マナ表示ラベル
	mana_label = Label.new()
	mana_label.text = "💎 マナ: 5 / 20"
	mana_label.add_theme_font_size_override("font_size", 22)
	mana_label.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
	mana_label.position = Vector2(480, 435)
	add_child(mana_label)

	
	# サイクルタイマー表示
	cycle_timer_label = Label.new()
	cycle_timer_label.text = "⏳ 次の増援波まで: --秒"
	cycle_timer_label.add_theme_font_size_override("font_size", 24)
	cycle_timer_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	cycle_timer_label.position = Vector2(800, 440)
	add_child(cycle_timer_label)

# === マナ変化時 ===
func _on_mana_changed(current: int, max_val: int) -> void:
	if mana_label:
		mana_label.text = "💎 マナ: %d / %d" % [current, max_val]

# === タイマー変化時 ===
func _on_cycle_timer_updated(time_left: float, _total: float) -> void:
	if cycle_timer_label:
		cycle_timer_label.text = "⏳ 次の増援波まで: %.1f秒" % time_left



# === ロスターUIの作成 ===
func _create_roster_ui(deck: Array[CardData]) -> void:
	if roster_container == null:
		return
	roster_count_labels.clear()
	var unique_units = {}
	for card in deck:
		if not unique_units.has(card.unit_name):
			unique_units[card.unit_name] = card
			
	for u_name in unique_units.keys():
		var card: CardData = unique_units[u_name]
		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 2)
		
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(50, 50)
		btn.text = u_name.left(2)
		btn.add_theme_font_size_override("font_size", 18)
		btn.pressed.connect(_on_roster_button_pressed.bind(u_name))
		
		var style = StyleBoxFlat.new()
		style.bg_color = card.unit_color
		style.set_corner_radius_all(8)
		btn.add_theme_stylebox_override("normal", style)
		
		var count_label = Label.new()
		count_label.text = "x0"
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_label.add_theme_font_size_override("font_size", 12)
		
		vbox.add_child(btn)
		vbox.add_child(count_label)
		
		roster_container.add_child(vbox)
		roster_count_labels[u_name] = count_label

func _on_roster_button_pressed(u_name: String) -> void:
	if battlefield_ref and battlefield_ref.has_method("select_unit_type_by_name"):
		battlefield_ref.select_unit_type_by_name(u_name)

func _update_roster_counts() -> void:
	if battlefield_ref == null:
		return
	for u_name in roster_count_labels.keys():
		if battlefield_ref.has_method("count_alive_units_by_name"):
			var count = battlefield_ref.count_alive_units_by_name(u_name)
			roster_count_labels[u_name].text = "x%d" % count

# === スペル関連 ===
func connect_spell_manager(sm: SpellManager) -> void:
	spell_manager = sm
	if spell_container and sm.spell_slots.size() > 0:
		for i in range(sm.spell_slots.size()):
			if i < spell_buttons.size():
				spell_buttons[i].set_spell(sm.spell_slots[i])

# === ウェーブマネージャーを接続する ===
func connect_wave_manager(wm: WaveManager) -> void:
	wave_manager = wm
	_create_wave_info_ui()
	print("[UILayer] WaveManagerとの接続完了")

func _create_wave_info_ui() -> void:
	wave_info_panel = PanelContainer.new()
	wave_info_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	wave_info_panel.anchor_left = 0.75
	wave_info_panel.anchor_top = 0.05
	wave_info_panel.anchor_right = 0.98
	wave_info_panel.anchor_bottom = 0.15
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.2, 0.7)
	style.set_corner_radius_all(8)
	wave_info_panel.add_theme_stylebox_override("panel", style)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	wave_info_panel.add_child(margin)
	
	wave_info_label = Label.new()
	wave_info_label.text = "ウェーブ情報"
	wave_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wave_info_label.add_theme_font_size_override("font_size", 14)
	margin.add_child(wave_info_label)
	
	add_child(wave_info_panel)

func _update_wave_info() -> void:
	if wave_manager == null or wave_info_label == null:
		return
		
	var info = wave_manager.get_next_wave_info()
	if info.get("is_final", false):
		wave_info_label.text = "全ウェーブ完了！"
		return
	
	var text = "Wave %d/%d\n" % [info.get("wave_num", 1), info.get("total_waves", 1)]
	var time_left = info.get("time_left", 0.0)
	if time_left > 0.0:
		text += "次のウェーブまで: %.0f秒\n" % time_left
	else:
		text += "進行中！\n"
	
	var enemies = info.get("enemies", [])
	for e in enemies:
		text += "  " + str(e) + "\n"
	
	wave_info_label.text = text

# === カードスロットの更新（毎フレーム実行） ===
func _update_card_cds() -> void:
	if deck_manager == null:
		return
	for i in range(slot_uis.size()):
		if not is_instance_valid(slot_uis[i]):
			continue
		if i >= deck_manager.hand.size():
			continue
			
		var card = deck_manager.hand[i]
		if deck_manager.current_mana >= card.mana_cost:
			slot_uis[i].modulate = Color.WHITE  # 召喚可能
		else:
			slot_uis[i].modulate = Color(0.5, 0.5, 0.5)  # マナ不足で召喚不可
		
		# リアルタイム制ではCDとチャージがないため、0を渡してマナだけ表示させる
		slot_uis[i].update_cd_text(0.0, card.mana_cost, 1)

# === スペルの生成 ===
func _create_spell_container() -> void:
	spell_container = HBoxContainer.new()
	spell_container.position = Vector2(1050, 440)
	spell_container.add_theme_constant_override("separation", 10)
	add_child(spell_container)
	
	for i in range(2):
		var btn = SpellButton.new()
		btn.slot_index = i
		btn.spell_drag_started.connect(_on_spell_drag_started)
		btn.spell_drag_canceled.connect(_on_spell_drag_canceled)
		spell_container.add_child(btn)
		spell_buttons.append(btn)

# === スペルのドラッグ処理 ===
func _on_spell_drag_started(slot_index: int) -> void:
	if spell_manager == null:
		return
	spell_manager.try_cast_spell(slot_index)

func _on_spell_drag_canceled(_slot_index: int) -> void:
	if spell_manager == null:
		return
	if spell_manager.has_method("cancel_time_stop"):
		spell_manager.cancel_time_stop()

func _update_spell_cds() -> void:
	if spell_manager == null:
		return
	for i in range(spell_buttons.size()):
		if i < spell_manager.spell_slots.size():
			var progress: float = spell_manager.get_cd_progress(i)
			var remaining: float = spell_manager.get_cd_remaining(i)
			spell_buttons[i].update_cd(progress, remaining)

# === デバッグ情報更新 ===
func _update_debug_info(deck_count: int, discard_count: int, wave_num: int) -> void:
	if debug_label == null:
		return
	debug_label.text = "ウェーブ: %d" % [wave_num]

# === 全軍指揮ボタンの作成 ===
func _create_command_button() -> void:
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(25, 530)
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)
	
	# --- 突撃ボタン ---
	btn_advance = Button.new()
	btn_advance.text = "⚔ 全軍突撃"
	btn_advance.custom_minimum_size = Vector2(120, 50)
	btn_advance.add_theme_font_size_override("font_size", 18)
	btn_advance.pressed.connect(_on_advance_pressed)
	vbox.add_child(btn_advance)
	
	var style_adv = StyleBoxFlat.new()
	style_adv.bg_color = Color(0.7, 0.2, 0.2, 0.9)
	style_adv.set_corner_radius_all(12)
	style_adv.set_border_width_all(4)
	style_adv.border_color = Color(1.0, 0.5, 0.3, 1.0)
	btn_advance.add_theme_stylebox_override("normal", style_adv)
	btn_advance.add_theme_stylebox_override("hover", style_adv)
	
	# --- 防衛ボタン ---
	btn_defend = Button.new()
	btn_defend.text = "🛡 全軍後退"
	btn_defend.custom_minimum_size = Vector2(120, 50)
	btn_defend.add_theme_font_size_override("font_size", 18)
	btn_defend.pressed.connect(_on_defend_pressed)
	vbox.add_child(btn_defend)
	
	var style_def = StyleBoxFlat.new()
	style_def.bg_color = Color(0.2, 0.3, 0.6, 0.9)
	style_def.set_corner_radius_all(12)
	style_def.set_border_width_all(4)
	style_def.border_color = Color(0.5, 0.7, 1.0, 1.0)
	btn_defend.add_theme_stylebox_override("normal", style_def)
	btn_defend.add_theme_stylebox_override("hover", style_def)

func _on_advance_pressed() -> void:
	if battlefield_ref != null and battlefield_ref.has_method("order_all_player_units"):
		battlefield_ref.order_all_player_units(true)

func _on_defend_pressed() -> void:
	if battlefield_ref != null and battlefield_ref.has_method("order_all_player_units"):
		battlefield_ref.order_all_player_units(false)
