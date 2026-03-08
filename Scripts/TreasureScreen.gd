extends Control

var title_label: Label
var container: HBoxContainer
var message_label: Label
var is_chosen: bool = false

var available_relics = [
	{
		"id": "mask_of_swiftness",
		"name": "迅速の仮面",
		"desc": "味方全員の移動速度が常に +20% される。",
		"icon": "🎭",
		"color": Color(0.2, 0.8, 0.5)
	},
	{
		"id": "heavy_plating",
		"name": "重厚な装甲",
		"desc": "自陣の拠点が受けるダメージを常に 20% 軽減する。",
		"icon": "🛡️",
		"color": Color(0.6, 0.6, 0.7)
	},
	{
		"id": "golden_idol",
		"name": "黄金の像",
		"desc": "初期ゴールドを +100 獲得し、今後の敵からの獲得ゴールドが少し増える(予定)。",
		"icon": "🗿",
		"color": Color(1.0, 0.8, 0.1)
	}
]

func _ready() -> void:
	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = Color(0.1, 0.1, 0.2, 0.95)
	add_child(bg)
	
	title_label = Label.new()
	title_label.text = "✨ 宝箱部屋 ✨\n- 古代のアーティファクトを発見した！ -"
	title_label.add_theme_font_size_override("font_size", 32)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.position = Vector2(0, 100)
	title_label.size = Vector2(1280, 100)
	add_child(title_label)
	
	message_label = Label.new()
	message_label.text = "1つだけレリック（アーティファクト）を入手できます。"
	message_label.add_theme_font_size_override("font_size", 24)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.position = Vector2(0, 200)
	message_label.size = Vector2(1280, 50)
	add_child(message_label)
	
	container = HBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.position = Vector2(0, 300)
	container.size = Vector2(1280, 240)
	container.add_theme_constant_override("separation", 50)
	add_child(container)
	
	_generate_relic_choices()

func _generate_relic_choices() -> void:
	# シャッフルして3つ選ぶ（現在は3つしかないのでそのまま）
	var choices = available_relics.duplicate()
	choices.shuffle()
	
	# 重複対策: 既に持っているものは除外したいが、今回はデモなのでそのまま
	for i in range(min(3, choices.size())):
		var relic = choices[i]
		_create_relic_button(relic)

func _create_relic_button(relic: Dictionary) -> void:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(250, 240)
	
	var is_owned = GameManager.player_relics.has(relic["id"])
	var status = "\n(所持済み)" if is_owned else ""
	
	btn.text = "%s\n\n%s\n\n%s%s" % [relic["icon"], relic["name"], relic["desc"], status]
	btn.add_theme_font_size_override("font_size", 16)
	
	var style = StyleBoxFlat.new()
	style.bg_color = relic["color"].darkened(0.5)
	style.border_width_left = 4; style.border_width_right = 4; style.border_width_top = 4; style.border_width_bottom = 4;
	style.border_color = relic["color"]
	style.set_corner_radius_all(15)
	
	if is_owned:
		style.bg_color = Color(0.2, 0.2, 0.2)
		style.border_color = Color(0.4, 0.4, 0.4)
		btn.disabled = true
	
	btn.add_theme_stylebox_override("normal", style)
	
	var hover_style = style.duplicate()
	hover_style.bg_color = relic["color"].darkened(0.2)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("disabled", style)
	
	btn.pressed.connect(self._on_relic_chosen.bind(relic))
	container.add_child(btn)

func _on_relic_chosen(relic: Dictionary) -> void:
	if is_chosen: return
	is_chosen = true
	
	# 取得処理
	GameManager.player_relics.append(relic["id"])
	if relic["id"] == "golden_idol":
		GameManager.player_gold += 100
		
	# 演出
	container.visible = false
	message_label.text = "【%s】 を入手した！" % relic["name"]
	message_label.add_theme_color_override("font_color", relic["color"])
	
	var next_btn = Button.new()
	next_btn.text = "先へ進む"
	next_btn.custom_minimum_size = Vector2(250, 80)
	next_btn.add_theme_font_size_override("font_size", 28)
	next_btn.position = Vector2(515, 450)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.4, 0.8)
	style.set_corner_radius_all(10)
	next_btn.add_theme_stylebox_override("normal", style)
	
	next_btn.pressed.connect(self._on_next_pressed)
	add_child(next_btn)

func _on_next_pressed() -> void:
	# GameManager内で適切に制御されているため、退出時は常にインクリメントしてMapに戻る
	GameManager.current_node_index += 1
	get_tree().change_scene_to_file("res://Scenes/MapScreen.tscn")
