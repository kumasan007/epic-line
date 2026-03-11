# UILayer.gd
# 画面下部40%のUI全体を管理するスクリプト
# サイクル制リアルタイム召喚に対応：
# - カードスロット（ドラッグ＆ドロップで召喚）
# - マナ表示
# - サイクルタイマー
extends Control

# === 参照 ===
@onready var hand_container: HBoxContainer = $HandContainer

# === 内部状態 ===
var slot_uis: Array[CardUI] = []
var deck_manager: DeckManager = null
var battlefield_ref = null

# === サイクルシステムUI ===
var mana_label: Label = null
var cycle_timer_label: Label = null

# === ドラッグ＆ドロップ状態 ===
var dragging_slot_index: int = -1
var dragging_ghost: ColorRect = null
# 配置可能X上限（城砦占領で広がる。初期は自陣付近のみ）
var player_deploy_limit_x: float = 200.0
# 無効ゾーンのフィードバック用（ゴーストに重ねるロックアイコン）
var drag_invalid_label: Label = null

func _ready() -> void:
	_create_mana_ui()

func set_battlefield_ref(ref) -> void:
	battlefield_ref = ref

func _process(_delta: float) -> void:
	_update_card_cds()

# === デッキマネージャーを接続する ===
func connect_deck_manager(dm: DeckManager) -> void:
	deck_manager = dm
	dm.mana_changed.connect(_on_mana_changed)
	dm.cycle_timer_updated.connect(_on_cycle_timer_updated)
	dm.hand_drawn.connect(_on_hand_drawn)
	dm.hand_discarded.connect(_on_hand_discarded)
	
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
			if slot_index >= deck_manager.hand.size(): return
			var card = deck_manager.hand[slot_index]
			if deck_manager.current_mana >= card.mana_cost:
				dragging_slot_index = slot_index
				dragging_ghost = ColorRect.new()
				
				if card.card_type == CardData.CardType.UNIT:
					# ユニット → 四角いゴースト
					dragging_ghost.size = Vector2(card.visual_size, card.visual_size * 2)
					dragging_ghost.color = card.unit_color
				else:
					# スペル → 照準表示
					var spell_size = maxf(card.spell_range * 0.3, 30.0)
					dragging_ghost.size = Vector2(spell_size, spell_size)
					dragging_ghost.color = card.spell_color
				
				dragging_ghost.modulate.a = 0.5
				dragging_ghost.global_position = event.global_position - dragging_ghost.size / 2
				add_child(dragging_ghost)

# === グローバルドラッグ＆ドロップ処理 ===
func _input(event: InputEvent) -> void:
	if dragging_slot_index >= 0:
		if event is InputEventMouseMotion:
			if dragging_ghost:
				dragging_ghost.global_position = event.position - dragging_ghost.size / 2
				# 戦場エリア（Y<420）に入った時のみゾーン判定。UIエリアは常に有効
				if deck_manager and dragging_slot_index < deck_manager.hand.size():
					var card = deck_manager.hand[dragging_slot_index]
					var in_battle_area = event.position.y < 420.0
					var zone_valid = not in_battle_area or _is_valid_drop_zone(event.position.x, event.position.y, card)
					
					if zone_valid:
						# 有効: カード果色で半透明表示
						dragging_ghost.modulate = Color(1.0, 1.0, 1.0, 0.55)
						if drag_invalid_label:
							drag_invalid_label.visible = false
					else:
						# 無効: グレーアウト＋ロックアイコンオーバーレイ
						dragging_ghost.modulate = Color(0.4, 0.4, 0.4, 0.35)
						if drag_invalid_label == null:
							drag_invalid_label = Label.new()
							drag_invalid_label.text = "🔒"
							drag_invalid_label.add_theme_font_size_override("font_size", 28)
							add_child(drag_invalid_label)
						drag_invalid_label.global_position = event.position + Vector2(-14, -30)
						drag_invalid_label.visible = true
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			var drop_pos = event.global_position
			# 戦場エリア（Y < 420）かつゾーン制限をクリアした場合のみ発動
			if drop_pos.y < 420.0:
				if deck_manager and dragging_slot_index < deck_manager.hand.size():
					var card = deck_manager.hand[dragging_slot_index]
					if _is_valid_drop_zone(drop_pos.x, drop_pos.y, card):
						if battlefield_ref and battlefield_ref.has_method("request_use_card"):
							battlefield_ref.request_use_card(dragging_slot_index, drop_pos.x)
			
			if dragging_ghost:
				dragging_ghost.queue_free()
				dragging_ghost = null
			if drag_invalid_label:
				drag_invalid_label.queue_free()
				drag_invalid_label = null
			dragging_slot_index = -1

func set_deploy_limit(new_limit: float) -> void:
	player_deploy_limit_x = new_limit
	print("[UILayer] 配置可能範囲が %.0fpx に拡大！" % new_limit)

# === 配置ゾーンの有効性チェック ===
# マップ中央(x=640)を境に自陣/敵陣を分割
func _is_valid_drop_zone(x: float, y: float, card: CardData) -> bool:
	if y >= 420.0:
		return false
	# player_deploy_limit_xは城砦占領で動的に拡大する
	var midpoint: float = player_deploy_limit_x
	match card.place_zone:
		CardData.PlaceZone.ALLY_SIDE:
			return x < midpoint  # 自陣+占領済みエリアまで
		CardData.PlaceZone.ENEMY_SIDE:
			return x >= midpoint
		CardData.PlaceZone.ANYWHERE:
			return true
	return true

# === マナUI作成 ===
func _create_mana_ui() -> void:
	mana_label = Label.new()
	mana_label.text = "💎 マナ: 5 / 5"
	mana_label.add_theme_font_size_override("font_size", 22)
	mana_label.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
	mana_label.position = Vector2(480, 435)
	add_child(mana_label)
	
	cycle_timer_label = Label.new()
	cycle_timer_label.text = "⚔ WAVE --"
	cycle_timer_label.add_theme_font_size_override("font_size", 24)
	cycle_timer_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	cycle_timer_label.position = Vector2(800, 440)
	add_child(cycle_timer_label)

	# --- 引き直しボタン（1マナ） ---
	var redraw_btn = Button.new()
	redraw_btn.text = "🔄 引き直し\n(1マナ消費)"
	redraw_btn.position = Vector2(1050, 435)
	redraw_btn.custom_minimum_size = Vector2(120, 50)
	redraw_btn.add_theme_font_size_override("font_size", 14)
	redraw_btn.pressed.connect(func():
		if deck_manager:
			deck_manager.redraw_hand()
	)
	add_child(redraw_btn)

# === マナ変化時 ===
func _on_mana_changed(current: int, max_val: int) -> void:
	if mana_label:
		mana_label.text = "💎 マナ: %d / %d" % [current, max_val]

# === タイマー変化時 ===
func _on_cycle_timer_updated(time_left: float, _total: float) -> void:
	if cycle_timer_label:
		var secs = int(ceil(time_left))
		var c_count = deck_manager.cycle_count if deck_manager else 0
		if c_count > 0:
			cycle_timer_label.text = "⚔ WAVE %d : 残り %d秒" % [c_count, secs]
		else:
			cycle_timer_label.text = "⚔ 残り %d秒" % secs

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
			slot_uis[i].modulate = Color.WHITE
		else:
			slot_uis[i].modulate = Color(0.5, 0.5, 0.5)
		
		slot_uis[i].update_cd_text(0.0, card.mana_cost, 0)
