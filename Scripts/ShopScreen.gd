extends Control

var container: HBoxContainer
var message_label: Label
var shop_items: Array[Dictionary] = []

func _ready() -> void:
	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = Color(0.15, 0.1, 0.1, 0.95)
	add_child(bg)

	var title = Label.new()
	title.text = "💰 ショップ（商人） 💰\n- ゴールドを使って戦力を増強せよ -"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 50)
	title.size = Vector2(1280, 100)
	add_child(title)

	message_label = Label.new()
	message_label.text = "所持ゴールド: %d" % GameManager.player_gold
	message_label.add_theme_font_size_override("font_size", 28)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.position = Vector2(0, 150)
	message_label.size = Vector2(1280, 50)
	add_child(message_label)

	container = HBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.position = Vector2(0, 250)
	container.size = Vector2(1280, 260)
	container.add_theme_constant_override("separation", 60)
	add_child(container)

	_generate_shop_inventory()

	var next_btn = Button.new()
	next_btn.text = "店を出る"
	next_btn.custom_minimum_size = Vector2(200, 60)
	next_btn.add_theme_font_size_override("font_size", 24)
	next_btn.position = Vector2(540, 600)
	next_btn.pressed.connect(self._on_leave_pressed)
	add_child(next_btn)

func _generate_shop_inventory() -> void:
	# ランダムなカードを3枚販売
	for i in range(3):
		var card = _get_random_card_for_sale()
		var price = randi_range(30, 80)
		_create_buy_button("card", card, price) # Corrected from _button to _create_buy_button
	# 回復アイテム（一律50Gで30%回復）
	var heal_data = {"name": "ポーション(HP30%回復)", "heal_amount": int(GameManager.player_max_hp * 0.3)}
	_create_buy_button("heal", heal_data, 50)
	
	# カード削除サービス（75G）
	var remove_data = {"name": "カード削除サービス"}
	_create_buy_button("remove", remove_data, 75)

func _create_buy_button(type: String, item_data: Variant, price: int) -> void:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var btn = Button.new()
	btn.custom_minimum_size = Vector2(160, 240)

	var item_name = ""
	var desc = ""

	if type == "card":
		var c: CardData = item_data
		item_name = c.card_name
		desc = "HP: %d\nATK: %d\nチャージ: %d" % [c.max_hp, c.atk, c.charge_count]
		var style = StyleBoxFlat.new()
		style.bg_color = c.unit_color if c.unit_color != Color.WHITE else Color(0.3, 0.3, 0.3)
		style.border_width_left = 4; style.border_width_right = 4; style.border_width_top = 4; style.border_width_bottom = 4;
		style.border_color = Color(0.8, 0.8, 0.2)
		style.corner_radius_top_left = 10; style.corner_radius_top_right = 10;
		style.corner_radius_bottom_left = 10; style.corner_radius_bottom_right = 10;
		btn.add_theme_stylebox_override("normal", style)
		var style_hover = style.duplicate()
		style_hover.bg_color = style.bg_color.lightened(0.2)
		btn.add_theme_stylebox_override("hover", style_hover)
	elif type == "heal":
		item_name = item_data["name"]
		desc = "拠点HPを大きく回復します。"
	elif type == "remove":
		item_name = item_data["name"]
		desc = "デッキからカードを\n1枚選んで削除し、\nデッキを圧縮します。"
	else: # Original else block, now for other types
		item_name = item_data["name"]
		desc = "拠点HPを回復します。"

	btn.text = "%s\n\n%s" % [item_name, desc]
	btn.add_theme_font_size_override("font_size", 16)

	var price_lbl = Label.new()
	price_lbl.text = "%d G" % price
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_lbl.add_theme_font_size_override("font_size", 24)
	if GameManager.player_gold >= price:
		price_lbl.add_theme_color_override("font_color", Color(1, 1, 0)) # 買えるなら黄色
	else:
		price_lbl.add_theme_color_override("font_color", Color(1, 0.2, 0.2)) # 買えないなら赤

	btn.pressed.connect(self._on_item_bought.bind(type, item_data, price, vbox, price_lbl))

	vbox.add_child(btn)
	vbox.add_child(price_lbl)
	container.add_child(vbox)

func _get_random_card_for_sale() -> CardData:
	var r = randi() % 5
	var c = CardData.new()
	if r == 0:
		c.card_name = "傭兵の盾"
		c.unit_role = CardData.UnitRole.TANK
		c.max_hp = 350.0; c.atk = 8.0; c.defense = 6.0; c.cooldown = 4.0; c.charge_count = 2
		c.visual_size = 45.0; c.unit_color = Color(0.5, 0.5, 0.6)
	elif r == 1:
		c.card_name = "毒矢の射手"
		c.unit_role = CardData.UnitRole.SHOOTER
		c.max_hp = 40.0; c.atk = 25.0; c.is_ranged = true; c.cooldown = 3.5; c.charge_count = 3
		c.visual_size = 25.0; c.unit_color = Color(0.6, 0.9, 0.3)
	elif r == 2:
		c.card_name = "特攻野郎"
		c.unit_role = CardData.UnitRole.ASSAULT
		c.max_hp = 10.0; c.atk = 45.0; c.speed = 180.0; c.cooldown = 2.0; c.charge_count = 5
		c.visual_size = 20.0; c.unit_color = Color(0.9, 0.4, 0.1)
	elif r == 3:
		c.card_name = "ベテラン剣士"
		c.unit_role = CardData.UnitRole.FIGHTER
		c.max_hp = 150.0; c.atk = 20.0; c.speed = 70.0; c.cooldown = 2.0; c.charge_count = 4
		c.visual_size = 35.0; c.unit_color = Color(0.2, 0.6, 0.8)
	else:
		c.card_name = "重装爆弾兵"
		c.unit_role = CardData.UnitRole.ASSAULT
		c.max_hp = 200.0; c.atk = 5.0; c.speed = 40.0; c.cooldown = 8.0; c.charge_count = 1
		c.lifespan = 10.0; c.knockback_chance = 100.0; c.knockback_power = 250.0
		c.knockback_direction = Vector2(0.5, -2.0) # 上に大きく吹き飛ぶ大爆発！
		c.flinch_chance = 100.0; c.flinch_duration = 1.0 # 相手は高く打ち上げられて長めのひるみ
		c.death_effect_type = "explosion"; c.death_effect_value = 300.0; c.death_effect_range = 250.0
		c.visual_size = 40.0; c.unit_color = Color(1.0, 0.3, 0.0)
	return c

func _on_item_bought(type: String, item_data: Variant, price: int, item_ui: VBoxContainer, price_lbl: Label) -> void:
	if GameManager.player_gold >= price:
		GameManager.player_gold -= price
		# 効果適用
		if type == "card":
			GameManager.player_deck.append(item_data)
			_show_popup("%s を購入しました！" % item_data.card_name)
			# 買ったアイテムは非表示にする
			item_ui.visible = false
		elif type == "heal":
			var heal_amount = item_data["heal_amount"]
			GameManager.player_current_hp = mini(GameManager.player_current_hp + heal_amount, GameManager.player_max_hp)
			_show_popup("HPが %d 回復しました！" % heal_amount)
			# 買ったアイテムは非表示にする
			item_ui.visible = false
		elif type == "remove":
			_show_card_removal_ui()
			return # removeの時は直後の表示更新等を行わず専用UIに任せる
			
		# 表示更新
		message_label.text = "所持ゴールド: %d" % GameManager.player_gold
		# 他のアイテムの文字色更新
		for child in container.get_children():
			if child is VBoxContainer and child.visible:
				var lbl = child.get_child(1) # price_lblは2番目の子要素
				var current_price_text = lbl.text.replace(" G", "") # Remove " G" before converting
				var current_price = int(current_price_text)
				if GameManager.player_gold < current_price:
					lbl.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
				else:
					lbl.add_theme_color_override("font_color", Color(1, 1, 0)) # Changed from Color.RED to yellow for buyable
	else:
		_show_popup("ゴールドが足りません！", Color.RED)

func _show_popup(text: String, color: Color = Color.WHITE) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", color)
	lbl.position = Vector2(500, 300)
	add_child(lbl)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(lbl, "position:y", 250.0, 1.0).set_ease(Tween.EASE_OUT)
	tween.tween_property(lbl, "modulate:a", 0.0, 1.0).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(lbl.queue_free)
	
# --- カード削除用UI ---
var deck_scroll: ScrollContainer = null

func _show_card_removal_ui() -> void:
	container.visible = false
	message_label.text = "削除するカードを選んでください（キャンセル不可）"
	
	if deck_scroll != null:
		deck_scroll.queue_free()
		
	deck_scroll = ScrollContainer.new()
	deck_scroll.size = Vector2(1000, 300)
	deck_scroll.position = Vector2(140, 250)
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
		var style = StyleBoxFlat.new()
		style.bg_color = card.unit_color if card.unit_color != Color.WHITE else Color(0.3, 0.3, 0.3)
		style.set_corner_radius_all(8)
		style.border_width_left = 3; style.border_width_right = 3; style.border_width_top = 3; style.border_width_bottom = 3;
		style.border_color = Color(1.0, 0.3, 0.3) # 削除は赤枠
		btn.add_theme_stylebox_override("normal", style)
		
		var hover_style = style.duplicate()
		hover_style.bg_color = Color(0.8, 0.2, 0.2)
		btn.add_theme_stylebox_override("hover", hover_style)
		
		btn.pressed.connect(self._on_card_removed.bind(card))
		grid.add_child(btn)

func _on_card_removed(card: CardData) -> void:
	GameManager.player_deck.erase(card)
	
	deck_scroll.visible = false
	_show_popup("%s をデッキから削除しました。" % card.card_name, Color.RED)
	
	# ここからUIの再構築（戻る）は複雑なので、買った後は終了扱い（そのまま進むボタンだけ表示）にする
	message_label.text = "所持ゴールド: %d (デッキ圧縮完了)" % GameManager.player_gold
	container.visible = false

func _on_leave_pressed() -> void:
	GameManager.current_node_index += 1
	get_tree().change_scene_to_file("res://Scenes/MapScreen.tscn")
