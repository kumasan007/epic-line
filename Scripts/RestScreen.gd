extends Control

# ====== 休憩地点（焚き火） ======
# プレイヤーは「回復」か「特訓（カード強化）」のどちらか1つだけを選べる

var title_label: Label
var container: HBoxContainer
var message_label: Label
var is_chosen: bool = false
var deck_scroll: ScrollContainer = null

func _ready() -> void:
	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = Color(0.2, 0.1, 0.1, 0.95)
	add_child(bg)
	
	title_label = Label.new()
	title_label.text = "⛺ 休息地 ⛺\n- キャンプで一息つき、次の戦いに備えよ -"
	title_label.add_theme_font_size_override("font_size", 32)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.position = Vector2(0, 100)
	title_label.size = Vector2(1280, 100)
	add_child(title_label)
	
	message_label = Label.new()
	message_label.text = "現在のHP: %d / %d\nどちらか1つの行動を選んでください。" % [GameManager.player_current_hp, GameManager.player_max_hp]
	message_label.add_theme_font_size_override("font_size", 24)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.position = Vector2(0, 200)
	message_label.size = Vector2(1280, 80)
	add_child(message_label)
	
	container = HBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.position = Vector2(0, 320)
	container.size = Vector2(1280, 200)
	container.add_theme_constant_override("separation", 100)
	add_child(container)
	
	_create_choices()

func _create_choices() -> void:
	# 休息（回復）ボタン
	var heal_btn = Button.new()
	heal_btn.custom_minimum_size = Vector2(250, 150)
	var heal_amount = int(GameManager.player_max_hp * 0.3)
	heal_btn.text = "💤 休息\n\nHPを %d 回復する" % heal_amount
	heal_btn.add_theme_font_size_override("font_size", 20)
	
	var heal_style = StyleBoxFlat.new()
	heal_style.bg_color = Color(0.2, 0.6, 0.3, 1.0)
	heal_style.set_corner_radius_all(15)
	heal_btn.add_theme_stylebox_override("normal", heal_style)
	heal_btn.pressed.connect(self._on_heal_pressed.bind(heal_amount))
	container.add_child(heal_btn)
	
	# 特訓（強化）ボタン
	var train_btn = Button.new()
	train_btn.custom_minimum_size = Vector2(250, 150)
	train_btn.text = "⚔ 特訓\n\nデッキのカードを1枚\nベースアップ強化する"
	train_btn.add_theme_font_size_override("font_size", 20)
	
	var train_style = StyleBoxFlat.new()
	train_style.bg_color = Color(0.8, 0.3, 0.2, 1.0)
	train_style.set_corner_radius_all(15)
	train_btn.add_theme_stylebox_override("normal", train_style)
	train_btn.pressed.connect(self._on_train_request_pressed)
	container.add_child(train_btn)

func _on_heal_pressed(amount: int) -> void:
	if is_chosen: return
	is_chosen = true
	
	GameManager.player_current_hp = mini(GameManager.player_current_hp + amount, GameManager.player_max_hp)
	_show_result("休息し、HPが回復した...", true)

func _on_train_request_pressed() -> void:
	if is_chosen: return
	
	# ボタングループを消して、手持ちデッキ一覧を表示する
	container.visible = false
	message_label.text = "強化するカードを選んでください。"
	_show_upgrade_deck()

func _show_upgrade_deck() -> void:
	if deck_scroll != null:
		deck_scroll.queue_free()
		
	deck_scroll = ScrollContainer.new()
	deck_scroll.size = Vector2(1000, 300)
	deck_scroll.position = Vector2(140, 300)
	add_child(deck_scroll)
	
	var grid = HBoxContainer.new()
	grid.add_theme_constant_override("separation", 20)
	deck_scroll.add_child(grid)
	
	for card in GameManager.player_deck:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(140, 200)
		btn.text = "%s\nHP: %d\nATK: %d\nCD: %.1f\n%s" % [
			card.card_name, card.max_hp, card.atk, card.cooldown,
			"(強化済)" if card.get("is_upgraded") else ""
		]
		
		# すでに強化済みなら押せない
		if card.get("is_upgraded"):
			btn.disabled = true
			
		var style = StyleBoxFlat.new()
		style.bg_color = card.unit_color if card.unit_color != Color.WHITE else Color(0.3, 0.3, 0.3)
		style.set_corner_radius_all(8)
		style.border_width_left = 3; style.border_width_right = 3; style.border_width_top = 3; style.border_width_bottom = 3;
		style.border_color = Color(0.8, 0.8, 0.8)
		btn.add_theme_stylebox_override("normal", style)
		
		btn.pressed.connect(self._on_card_upgrade_pressed.bind(card))
		grid.add_child(btn)

func _on_card_upgrade_pressed(card: CardData) -> void:
	if is_chosen: return
	is_chosen = true
	
	# カードのプロパティを強化（簡易的）
	card.max_hp = ceil(card.max_hp * 1.3)
	card.atk = ceil(card.atk * 1.3)
	card.cooldown = maxf(0.5, card.cooldown * 0.9)
	card.set("is_upgraded", true) # スクリプトで動的属性を追加
	card.card_name = "%s+" % card.card_name
	
	if deck_scroll:
		deck_scroll.visible = false
		
	_show_result("%s を強化した！" % card.card_name, false)

func _show_result(msg: String, _is_heal: bool) -> void:
	container.visible = false
	message_label.text = msg
	message_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.0))
	
	var next_btn = Button.new()
	next_btn.text = "先へ進む"
	next_btn.custom_minimum_size = Vector2(250, 80)
	next_btn.add_theme_font_size_override("font_size", 28)
	next_btn.position = Vector2(515, 550)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.4, 0.8)
	style.set_corner_radius_all(10)
	next_btn.add_theme_stylebox_override("normal", style)
	
	next_btn.pressed.connect(self._on_next_pressed)
	add_child(next_btn)

func _on_next_pressed() -> void:
	GameManager.current_node_index += 1
	get_tree().change_scene_to_file("res://Scenes/MapScreen.tscn")
