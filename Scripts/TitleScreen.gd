extends Control

func _ready() -> void:
    var bg = ColorRect.new()
    bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    bg.color = Color(0.05, 0.05, 0.08, 1.0)
    add_child(bg)
    
    var title = Label.new()
    title.text = "EPIC LINE\n- TACTICS -"
    title.add_theme_font_size_override("font_size", 80)
    title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.2))
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.position = Vector2(0, 150)
    title.size = Vector2(1280, 200)
    add_child(title)
    
    var start_btn = Button.new()
    start_btn.text = "ゲーム開始"
    start_btn.add_theme_font_size_override("font_size", 40)
    start_btn.position = Vector2(540, 450)
    start_btn.size = Vector2(200, 80)
    start_btn.pressed.connect(self._on_start_pressed)
    add_child(start_btn)
    
func _on_start_pressed() -> void:
    if GameManager != null:
        GameManager.init_new_run()
    get_tree().change_scene_to_file("res://Scenes/MapScreen.tscn")
