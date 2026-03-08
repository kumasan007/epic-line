extends Control

# StS方式のツリーマップに見立てたモックアップ画面
# GameManagerが持つ `map_nodes` に従って画面上にノードを描画し、
# プレイヤーが「進行」を選ぶと現在のノードのイベント（Battle等）に入る

var bg: ColorRect
var line_container: Control
var nodes_container: Control

func _ready() -> void:
	_create_ui()
	_draw_map()

func _create_ui() -> void:
	# 背景
	bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = Color(0.15, 0.12, 0.1, 1.0) # 古地図のような色
	add_child(bg)
	
	# タイトル
	var title = Label.new()
	title.text = "- 進行ルート -"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.6))
	title.position = Vector2(0, 40)
	title.size = Vector2(1280, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	
	line_container = Control.new()
	add_child(line_container)
	
	nodes_container = Control.new()
	add_child(nodes_container)
	
	# 下部のステータスバー
	var status_bg = ColorRect.new()
	status_bg.size = Vector2(1280, 60)
	status_bg.position = Vector2(0, 720 - 60)
	status_bg.color = Color(0.1, 0.1, 0.1, 0.8)
	add_child(status_bg)
	
	var status_label = Label.new()
	status_label.text = " HP: %d / %d    GOLD: %d " % [GameManager.player_current_hp, GameManager.player_max_hp, GameManager.player_gold]
	status_label.add_theme_font_size_override("font_size", 24)
	status_label.position = Vector2(20, 720 - 45)
	add_child(status_label)
	
func _draw_map() -> void:
	if GameManager == null or GameManager.map_nodes.size() == 0:
		return
		
	var maps = GameManager.map_nodes
	var current = GameManager.current_node_index
	
	if current >= maps.size():
		var clear_lbl = Label.new()
		clear_lbl.text = "🎉 ゲームクリア！ 🎉\n- DEMO VERSION 終了 -\n\nプレイありがとうございました！\n拠点やユニットをもっと増やして\nより長く遊べるように拡張 予定です。"
		clear_lbl.add_theme_font_size_override("font_size", 40)
		clear_lbl.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
		clear_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		clear_lbl.position = Vector2(0, 200)
		clear_lbl.size = Vector2(1280, 200)
		add_child(clear_lbl)
		
		# タイトルへ戻るボタン
		var back_btn = Button.new()
		back_btn.text = "タイトルへ戻る"
		back_btn.custom_minimum_size = Vector2(300, 80)
		back_btn.add_theme_font_size_override("font_size", 32)
		back_btn.position = Vector2(490, 450)
		back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://Scenes/TitleScreen.tscn"))
		add_child(back_btn)
		return
	
	# 横並びにノードを配置
	# 全体の幅1000として、左右140ずつマージン
	var start_x = 140.0
	var available_w = 1000.0
	var step_x = available_w / max(1, maps.size() - 1)
	
	for i in range(maps.size()):
		var node_type = maps[i]
		var px = start_x + (i * step_x)
		
		# Y座標を少し散らして自然なマップっぽくする（今回はモックなので真っ直ぐ＋少し揺らす程度）
		var py = 360.0 + (sin(i * 1.5) * 60.0)
		
		var node_pos = Vector2(px, py)
		
		# === ノードからノードへの線（現在の位置までは明るく、先は暗く） ===
		if i > 0:
			var prev_px = start_x + ((i-1) * step_x)
			var prev_py = 360.0 + (sin((i-1) * 1.5) * 60.0)
			
			var line = Line2D.new()
			line.add_point(Vector2(prev_px, prev_py))
			line.add_point(node_pos)
			line.width = 4.0
			if i <= current:
				line.default_color = Color(0.8, 0.7, 0.3, 1.0) # 踏破済み
			else:
				line.default_color = Color(0.4, 0.3, 0.2, 0.5) # 未踏破
			line_container.add_child(line)
			
		# === ノードのボタン ===
		var btn = Button.new()
		# アイコン文字でごまかす
		var text = ""
		match node_type:
			"battle": text = "⚔️\nBattle"
			"elite": text = "🔥\nElite"
			"boss": text = "💀\nBOSS"
			"rest": text = "🏕️\nRest"
			"shop": text = "💰\nShop"
			"treasure": text = "🎁\nTreasure"
			"event": text = "❓\nEvent"
			_: text = "?\nNode"
		btn.text = text
		btn.size = Vector2(60, 60)
		btn.position = node_pos - Vector2(30, 30)
		btn.add_theme_font_size_override("font_size", 30)
		
		var style = StyleBoxFlat.new()
		style.corner_radius_top_left = 30
		style.corner_radius_top_right = 30
		style.corner_radius_bottom_left = 30
		style.corner_radius_bottom_right = 30
		
		if i < current:
			# 踏破済み
			style.bg_color = Color(0.3, 0.3, 0.3, 1.0)
			btn.disabled = true
		elif i == current:
			# 現在の挑戦可能ノード
			style.bg_color = Color(0.8, 0.2, 0.2, 1.0) if node_type in ["battle", "elite", "boss"] else Color(0.2, 0.6, 0.2, 1.0)
			# 宝箱やショップなら色を変えるともっといいかも
			if node_type == "treasure": style.bg_color = Color(0.8, 0.6, 0.2, 1.0)
			
			style.border_width_left = 4; style.border_width_right = 4; style.border_width_top = 4; style.border_width_bottom = 4;
			style.border_color = Color(1.0, 1.0, 0.8, 1.0)
			
			# 押した時の処理
			btn.pressed.connect(_on_node_pressed.bind(node_type))
			
			# ここを進めるというテキストを上に表示
			var cur_lbl = Label.new()
			cur_lbl.text = "挑戦する！"
			cur_lbl.add_theme_color_override("font_color", Color(1,1,0))
			cur_lbl.position = btn.position + Vector2(0, -30)
			nodes_container.add_child(cur_lbl)
			
		else:
			# 未踏破
			style.bg_color = Color(0.2, 0.2, 0.2, 1.0)
			btn.disabled = true
			
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("disabled", style)
		
		nodes_container.add_child(btn)

func _on_node_pressed(type: String) -> void:
	print("ノード進行: ", type)
	
	if type == "battle" or type == "elite" or type == "boss":
		# 戦闘なのでBattleFieldへ
		get_tree().change_scene_to_file("res://Scenes/Main.tscn")
	elif type == "rest":
		# 休憩画面へ
		get_tree().change_scene_to_file("res://Scenes/RestScreen.tscn")
	elif type == "shop":
		# お店画面へ
		get_tree().change_scene_to_file("res://Scenes/ShopScreen.tscn")
	elif type == "treasure":
		# 宝箱画面へ（レリック獲得）
		get_tree().change_scene_to_file("res://Scenes/TreasureScreen.tscn")
	elif type == "event":
		# イベントマスのシーンへ
		get_tree().change_scene_to_file("res://Scenes/EventScreen.tscn")
