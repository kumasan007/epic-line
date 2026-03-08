extends Control

# 戦闘終了後に、3枚のカードから1枚を選んでデッキに追加する画面

var container: HBoxContainer
var bg: ColorRect

func _ready() -> void:
	bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = Color(0.1, 0.1, 0.15, 0.95)
	add_child(bg)
	
	var title = Label.new()
	title.text = "★ 勝利報酬 ★\n- デッキに追加するカードを選んでください -"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 100)
	title.size = Vector2(1280, 100)
	add_child(title)
	
	container = HBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.position = Vector2(0, 300)
	container.size = Vector2(1280, 200)
	container.add_theme_constant_override("separation", 100)
	add_child(container)
	
	_generate_rewards()
	
func _generate_rewards() -> void:
	# ランダムに3枚のカード候補を生成する（モックアップ用）
	for i in range(3):
		var card = _get_random_card()
		var btn = Button.new()
		# UIカードの見栄え（SpellButton.gdの使い回しでも良いが、シンプルにテキストボタンでいく）
		btn.custom_minimum_size = Vector2(160, 240)
		btn.text = card.card_name + "\nHP: " + str(card.max_hp) + "\nATK: " + str(card.atk)
		btn.text += "\nチャージ: " + str(card.charge_count)
		if card.is_ranged:
			btn.text += "\n[遠距離]"
		if card.knockback_chance > 0:
			btn.text += "\n[吹飛有]"
			
		btn.add_theme_font_size_override("font_size", 20)
		
		# 色付け（ボタンのスタイルボックスを作成）
		var style = StyleBoxFlat.new()
		style.bg_color = card.unit_color if card.unit_color != Color.WHITE else Color(0.3, 0.3, 0.3)
		style.border_width_left = 4; style.border_width_right = 4; style.border_width_top = 4; style.border_width_bottom = 4;
		style.border_color = Color(0.8, 0.8, 0.8)
		style.corner_radius_top_left = 10; style.corner_radius_top_right = 10;
		style.corner_radius_bottom_left = 10; style.corner_radius_bottom_right = 10;
		btn.add_theme_stylebox_override("normal", style)
		
		# ホバー時（少し明るく）
		var style_hover = style.duplicate()
		style_hover.bg_color = style.bg_color.lightened(0.2)
		btn.add_theme_stylebox_override("hover", style_hover)
		
		btn.pressed.connect(self._on_card_selected.bind(card))
		container.add_child(btn)

func _get_random_card() -> CardData:
	# ランダムなカードデータをひとつ生成（種類はテキトーに3つから選ぶ）
	var r = randi() % 5
	var c = CardData.new()
	if r == 0:
		c.card_name = "追加の盾兵"
		c.unit_role = CardData.UnitRole.TANK
		c.max_hp = 250.0; c.atk = 5.0; c.defense = 4.0; c.cooldown = 5.0
		c.charge_count = 2
		c.kb_resistance = 50.0 # ノックバックしにくい
		c.flinch_chance = 10.0; c.flinch_duration = 0.5 # 盾で殴って少しひるませる
		c.visual_size = 40.0; c.unit_color = Color(0.4, 0.5, 0.6)
	elif r == 1:
		c.card_name = "追加の弓兵"
		c.unit_role = CardData.UnitRole.SHOOTER
		c.max_hp = 50.0; c.atk = 20.0; c.is_ranged = true; c.cooldown = 4.0
		c.charge_count = 3
		c.visual_size = 25.0; c.unit_color = Color(0.8, 0.6, 0.3)
	elif r == 2:
		c.card_name = "突撃兵"
		c.unit_role = CardData.UnitRole.ASSAULT
		c.max_hp = 1.0; c.atk = 30.0; c.speed = 200.0; c.cooldown = 1.5
		c.charge_count = 6
		c.visual_size = 20.0; c.unit_color = Color(0.9, 0.2, 0.3)
	elif r == 3:
		c.card_name = "重戦士"
		c.unit_role = CardData.UnitRole.FIGHTER
		c.max_hp = 120.0; c.atk = 15.0; c.speed = 40.0; c.cooldown = 3.0
		c.charge_count = 3
		c.knockback_chance = 30.0; c.knockback_power = 60.0
		c.knockback_direction = Vector2(1.5, -1.0) # 大きく上に打ち上げる！
		c.flinch_chance = 40.0; c.flinch_duration = 0.8 # 重い一撃で長めにひるむ
		c.visual_size = 35.0; c.unit_color = Color(0.8, 0.4, 0.2)
	else:
		c.card_name = "精鋭剣士"
		c.unit_role = CardData.UnitRole.FIGHTER
		c.max_hp = 120.0; c.atk = 15.0; c.speed = 80.0; c.cooldown = 2.5
		c.charge_count = 4
		c.knockback_chance = 10.0; c.knockback_power = 20.0
		c.visual_size = 30.0; c.unit_color = Color(0.3, 0.7, 0.9)
	return c

func _on_card_selected(card: CardData) -> void:
	print("報酬選択: ", card.card_name)
	# デッキに追加
	GameManager.player_deck.append(card)
	
	# マップ画面へ遷移
	get_tree().change_scene_to_file("res://Scenes/MapScreen.tscn")
