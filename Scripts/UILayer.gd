# UILayer.gd
# 画面下部40%のUI全体を管理するスクリプト
# 手札カード（スロット制）、スペルボタン、CDゲージの更新、デッキ情報の表示を担当する
extends Control

# === 参照 ===
@onready var hand_container: HBoxContainer = $HandContainer
@onready var debug_label: Label = $DebugLabel

# === 内部状態 ===
var slot_uis: Array[CardUI] = []
var deck_manager: DeckManager = null

# === スペル関連 ===
var spell_manager: SpellManager = null
var spell_buttons: Array[SpellButton] = []
var spell_container: HBoxContainer = null

# === 全軍指揮関連 ===
var battlefield_ref = null
var btn_advance: Button = null
var btn_defend: Button = null

func _ready() -> void:
	print("[UILayer] UIを初期化しました")
	_update_debug_info(0, 0, 0)
	# UI要素の作成
	_create_spell_container()
	_create_command_button()

func _process(_delta: float) -> void:
	_update_card_cds()
	_update_spell_cds()

# === デッキマネージャーを接続する ===
func connect_deck_manager(dm: DeckManager) -> void:
	deck_manager = dm
	dm.hand_initialized.connect(_on_hand_initialized)
	dm.slot_updated.connect(_on_slot_updated)
	dm.deck_counts_changed.connect(_on_deck_counts_changed)
	print("[UILayer] DeckManagerとの接続完了")
	
	# 既にデッキが初期化済みの場合
	if dm.hand_size > 0:
		_on_hand_initialized(dm.hand_size)
		for i in range(dm.hand_size):
			var card = dm.get_card_at(i)
			if card != null:
				_on_slot_updated(i, card)

# === スペルマネージャーを接続する ===
func connect_spell_manager(sm: SpellManager) -> void:
	spell_manager = sm
	print("[UILayer] SpellManagerとの接続完了")
	
	# 既にセット済みのスペルをボタンに反映
	for i in range(sm.slot_count):
		if i < spell_buttons.size() and sm.spell_slots[i] != null:
			spell_buttons[i].set_spell(sm.spell_slots[i])

# === BattleFieldの参照をセットする ===
func set_battlefield_ref(bf) -> void:
	battlefield_ref = bf

# === 手札スロットの初期化（起動時1回だけ） ===
func _on_hand_initialized(hand_size: int) -> void:
	_clear_all_slots()
	for i in range(hand_size):
		var card_ui := CardUI.new()
		card_ui.slot_index = i
		hand_container.add_child(card_ui)
		slot_uis.append(card_ui)
	print("[UILayer] %d個のカードスロットを作成" % hand_size)

# === 特定スロットのカードが更新された時 ===
func _on_slot_updated(slot_index: int, card: CardData) -> void:
	if slot_index < 0 or slot_index >= slot_uis.size():
		return
	var card_ui: CardUI = slot_uis[slot_index]
	if not is_instance_valid(card_ui):
		return
	if card != null:
		card_ui.set_card(card)
	else:
		card_ui.clear_card()

# === スロットUIを全てクリア ===
func _clear_all_slots() -> void:
	for card_ui in slot_uis:
		if is_instance_valid(card_ui):
			card_ui.queue_free()
	slot_uis.clear()

# === 毎フレームCDゲージを更新 ===
func _update_card_cds() -> void:
	if deck_manager == null:
		return
	for i in range(slot_uis.size()):
		if is_instance_valid(slot_uis[i]) and not slot_uis[i].is_empty:
			var progress: float = deck_manager.get_cd_progress(i)
			var remaining: float = deck_manager.get_cd_remaining(i)
			slot_uis[i].update_cd(progress, remaining)

# === スペルボタン用コンテナの作成 ===
func _create_spell_container() -> void:
	spell_container = HBoxContainer.new()
	spell_container.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	spell_container.anchor_left = 0.72
	spell_container.anchor_top = 0.62
	spell_container.anchor_right = 0.98
	spell_container.anchor_bottom = 0.92
	spell_container.alignment = BoxContainer.ALIGNMENT_END
	spell_container.add_theme_constant_override("separation", 8)
	add_child(spell_container)
	
	# スペルボタンを最大3枠分作成
	for i in range(SpellManager.MAX_SLOTS):
		var btn := SpellButton.new()
		btn.slot_index = i
		btn.spell_drag_started.connect(_on_spell_drag_started)
		btn.spell_drag_canceled.connect(_on_spell_drag_canceled)
		spell_container.add_child(btn)
		spell_buttons.append(btn)

# === スペルのドラッグ処理 ===

func _on_spell_drag_started(slot_index: int) -> void:
	if spell_manager == null:
		return
	# ドラッグ開始時にスペル発動試行（時間停止などが走る）
	spell_manager.try_cast_spell(slot_index)

func _on_spell_drag_canceled(slot_index: int) -> void:
	if spell_manager == null:
		return
	# ドロップせずにキャンセルした場合、時間停止を解除しておく
	spell_manager.cancel_time_stop()

# === 戦場領域へのドラッグ＆ドロップ（GUI標準機能） ===
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if typeof(data) == TYPE_DICTIONARY and data.has("type") and data["type"] == "spell":
		# UIRootは画面全体(1280x720)を覆う。Yが432以下なら戦場とみなす（どこでも落とせるように広めに取る）
		return true
	return false

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if typeof(data) == TYPE_DICTIONARY and data.has("type") and data["type"] == "spell":
		if spell_manager:
			# ドロップした位置を対象座標としてスペルを確定する
			spell_manager.confirm_spell(at_position)

# === 毎フレーム、スペルCDを更新 ===
func _update_spell_cds() -> void:
	if spell_manager == null:
		return
	for i in range(spell_buttons.size()):
		if i < spell_manager.slot_count and is_instance_valid(spell_buttons[i]):
			var progress: float = spell_manager.get_cd_progress(i)
			var remaining: float = spell_manager.get_cd_remaining(i)
			spell_buttons[i].update_cd(progress, remaining)

# === デッキ/捨て札の枚数変更時 ===
func _on_deck_counts_changed(deck_size: int, discard_size: int) -> void:
	_update_debug_info(deck_size, discard_size, 0)

# === デバッグ用のステータス表示を更新する ===
func _update_debug_info(deck_count: int, discard_count: int, wave_num: int) -> void:
	if debug_label == null:
		return
	debug_label.text = "デッキ: %d | 捨て札: %d | ウェーブ: %d" % [deck_count, discard_count, wave_num]

# === 全軍指揮ボタンの作成（独立2ボタン、単発トリガー） ===
func _create_command_button() -> void:
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(25, 530)
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)
	
	# --- 突撃ボタン ---
	btn_advance = Button.new()
	btn_advance.custom_minimum_size = Vector2(160, 70)
	btn_advance.text = "⚔ 突撃"
	btn_advance.add_theme_font_size_override("font_size", 22)
	btn_advance.pressed.connect(_on_advance_pressed)
	vbox.add_child(btn_advance)
	
	var style_adv := StyleBoxFlat.new()
	style_adv.bg_color = Color(0.7, 0.15, 0.15, 1.0)
	style_adv.set_corner_radius_all(12)
	style_adv.set_border_width_all(4)
	style_adv.border_color = Color(1.0, 0.5, 0.5, 1.0)
	btn_advance.add_theme_stylebox_override("normal", style_adv)
	btn_advance.add_theme_stylebox_override("hover", style_adv)
	
	# --- 待機/後退ボタン ---
	btn_defend = Button.new()
	btn_defend.custom_minimum_size = Vector2(160, 70)
	btn_defend.text = "🔙 待機・後退"
	btn_defend.add_theme_font_size_override("font_size", 22)
	btn_defend.pressed.connect(_on_defend_pressed)
	vbox.add_child(btn_defend)
	
	var style_def := StyleBoxFlat.new()
	style_def.bg_color = Color(0.15, 0.3, 0.7, 1.0)
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
