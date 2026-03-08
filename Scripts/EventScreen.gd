extends Control

var title_label: Label
var message_label: Label
var container: VBoxContainer
var is_chosen: bool = false

func _ready() -> void:
	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.05, 0.1, 1.0) # 暗い背景
	add_child(bg)
	
	title_label = Label.new()
	title_label.text = "🦇 謎の祭壇 🦇"
	title_label.add_theme_font_size_override("font_size", 36)
	title_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.8))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.position = Vector2(0, 100)
	title_label.size = Vector2(1280, 50)
	add_child(title_label)
	
	message_label = Label.new()
	message_label.text = "薄暗い森の奥で、不気味な光を放つ祭壇を見つけた。\n「力を望むか？」と耳元で恐ろしい声が囁く..."
	message_label.add_theme_font_size_override("font_size", 24)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.position = Vector2(0, 200)
	message_label.size = Vector2(1280, 100)
	add_child(message_label)
	
	container = VBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.position = Vector2(0, 350)
	container.size = Vector2(1280, 300)
	container.add_theme_constant_override("separation", 30)
	add_child(container)
	
	_create_choice_button("【祈る】 強力なアーティファクトを得るが、デッキに『呪い（厄災）』が混入する", self._on_pray_chosen)
	_create_choice_button("【立ち去る】 何もせずこの場を離れる", self._on_leave_chosen)

func _create_choice_button(text_str: String, callback: Callable) -> void:
	var btn = Button.new()
	btn.text = text_str
	btn.custom_minimum_size = Vector2(800, 80)
	btn.add_theme_font_size_override("font_size", 24)
	
	# HBoxに入れて中央揃えにするためのコンテナ
	var h_box = HBoxContainer.new()
	h_box.alignment = BoxContainer.ALIGNMENT_CENTER
	h_box.add_child(btn)
	container.add_child(h_box)
	
	btn.pressed.connect(callback)

func _on_pray_chosen() -> void:
	if is_chosen: return
	is_chosen = true
	
	# ランダムなレリックを付与
	if GameManager != null:
		var relics = ["mask_of_swiftness", "heavy_plating", "golden_idol"]
		var relic = relics[randi() % relics.size()]
		GameManager.player_relics.append(relic)
		
		# 呪いカードをデッキに追加
		var curse = CardData.new()
		curse.card_name = "呪い（厄災）"
		curse.is_curse = true
		curse.cooldown = 2.0
		curse.charge_count = 1
		curse.atk = 50.0 # 拠点へのダメージ
		
		# 見た目のため（呼ばれないが）設定
		curse.unit_name = "呪い" 
		curse.unit_color = Color(0.4, 0.0, 0.6)
		curse.visual_size = 20.0
		GameManager.player_deck.append(curse)
	
	message_label.text = "あなたは祈りを捧げ、力を手に入れた...\nしかし、得体の知れない『呪い』も憑りついてしまった！"
	message_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2))
	
	_show_next_button()

func _on_leave_chosen() -> void:
	if is_chosen: return
	is_chosen = true
	
	message_label.text = "関わるべきではないと判断し、足早にその場を離れた..."
	message_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	
	_show_next_button()

func _show_next_button() -> void:
	container.visible = false
	
	var next_btn = Button.new()
	next_btn.text = "先へ進む"
	next_btn.custom_minimum_size = Vector2(300, 80)
	next_btn.add_theme_font_size_override("font_size", 32)
	next_btn.position = Vector2(490, 450)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.3, 0.6)
	style.set_corner_radius_all(10)
	next_btn.add_theme_stylebox_override("normal", style)
	
	next_btn.pressed.connect(self._on_next_pressed)
	add_child(next_btn)

func _on_next_pressed() -> void:
	if GameManager != null:
		GameManager.current_node_index += 1
	get_tree().change_scene_to_file("res://Scenes/MapScreen.tscn")
