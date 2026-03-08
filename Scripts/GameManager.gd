extends Node

# ゲーム全体の進行状況（Deck、Gold、HPなど）を管理するSingleton (Autoload)

var player_deck: Array[CardData] = []
var player_gold: int = 100
var player_max_hp: int = 2000
var player_current_hp: int = 2000
var current_floor: int = 1

# 追加：レリック（アーティファクト）システム
# 要素は文字列 ("mask_of_swiftness", "golden_idol" など)
var player_relics: Array[String] = []

# ローグライク風のマップデータ（仮）
# Node形式： "battle", "elite", "rest", "shop", "boss"
var map_nodes: Array[String] = []
var current_node_index: int = 0

func _ready() -> void:
    # 完全に空の状態なら（オートロード等のテスト用）適当に初期化
    if map_nodes.size() == 0:
        init_new_run()

func init_new_run() -> void:
    player_gold = 100
    player_max_hp = 2000
    player_current_hp = 2000
    current_floor = 1
    player_relics.clear()
    
    _generate_initial_deck()
    _generate_map()

func _generate_initial_deck() -> void:
    player_deck.clear()
    
    # --- 巨盾兵（スーパータンク） × 1 ---
    # 特徴：絶望的に足が遅く、攻撃も信じられないほど遅いが、HPが異常に高く、一撃のノックバックが強烈。
    for i in range(1):
        var c := CardData.new()
        c.card_name = "巨盾兵"
        c.unit_role = CardData.UnitRole.TANK # 前衛の壁
        c.cooldown = 10.0    # 生産が超遅い（重量ユニット）
        c.charge_count = 2   # 2体しか出せないが、その分硬い
        c.unit_name = "巨盾兵"
        c.max_hp = 3000.0       # 超絶硬い (壁)
        c.atk = 40.0           # 一撃は重い
        c.attack_range = 45.0
        c.defense = 10.0
        c.speed = 12.0         # めちゃくちゃ遅い、ジリジリ進む
        c.attack_interval = 4.0 # 攻撃がスゲェ遅い（ドスーン！という感じ）
        c.attack_windup_time = 1.5 # 1.5秒かけて大きく振りかぶる！（超重厚）
        c.knockback_chance = 100.0 # 攻撃したら絶対吹き飛ばす
        c.knockback_power = 90.0
        c.kb_resistance = 80.0 # ほとんど吹き飛ばされない
        c.flinch_chance = 50.0; c.flinch_duration = 0.5
        
        # 見た目のハクスラ感（巨大・重装甲色）
        c.visual_size = 65.0 # 他の倍以上デカい
        c.unit_color = Color(0.4, 0.45, 0.5) # スレートグレー
        
        player_deck.append(c)
        
    # --- 双剣兵（ラッシュアタッカー） × 2 ---
    # 特徴：HPは紙で射程も短いが、移動速度が速く、攻撃速度が異常（シュバッ！と連続で斬る）。
    for i in range(2):
        var c := CardData.new()
        c.card_name = "双剣兵"
        c.unit_role = CardData.UnitRole.FIGHTER # 中衛（前衛の後ろからラッシュ）
        c.cooldown = 4.0
        c.charge_count = 5   # 軽量ユニットなのでチャージ多め
        c.unit_name = "双剣兵"
        c.max_hp = 180.0        # スグ死ぬが前よりは耐える
        c.atk = 8.0            # 一発は軽い
        c.attack_range = 35.0
        c.speed = 40.0         # 歩兵の中では速い方だが、全体的には遅く
        c.attack_interval = 0.5 # 狂った連撃スピード
        c.attack_windup_time = 0.2 # スパッと斬るためタメは少ない
        c.kb_resistance = 0.0
        
        c.visual_size = 25.0
        c.unit_color = Color(0.2, 0.8, 1.0) # 水色（スピード感）
        
        player_deck.append(c)
    
    # --- 長弓兵（スナイパー） × 2 ---
    # 特徴：超後方から、遅いが一門の大砲のように重い一撃を放つ。
    for i in range(2):
        var c := CardData.new()
        c.card_name = "長弓兵"
        c.unit_role = CardData.UnitRole.SHOOTER # ずっと後ろ
        c.cooldown = 8.0     # 生産が遅い（強力な遠距離）
        c.charge_count = 3   # 3体まで
        c.unit_name = "長弓兵"
        c.max_hp = 150.0
        c.atk = 60.0           # 一撃の威力が鬼
        c.attack_range = 350.0 # 画面全体の半分くらい射程がある
        c.speed = 20.0         # 遅い
        c.attack_interval = 4.0 # 矢を撃つまでがスゲェ遅い
        c.attack_windup_time = 2.0 # 弦を2秒間ギチギチと引き絞る！
        c.knockback_chance = 50.0
        c.knockback_power = 40.0
        c.flinch_chance = 100.0; c.flinch_duration = 0.8 # 長弓は確実に重いひるみを与える
        
        c.visual_size = 30.0
        c.unit_color = Color(0.8, 0.5, 0.2) # 茶色よりのオレンジ
        c.is_ranged = true
        c.projectile_speed = 600.0
        c.projectile_aoe = 35.0 # 着弾するとそこそこ広い範囲が爆発する
        
        player_deck.append(c)
    
    # --- 狂気兵（鉄砲玉） × 2 ---
    # 特徴：速めのアタッカーだが、一発もらっただけで死ぬ。Epic War風に速度は落とした。
    for i in range(2):
        var c := CardData.new()
        c.card_name = "狂気兵"
        c.unit_role = CardData.UnitRole.ASSAULT
        c.cooldown = 3.0     # 生産にも少し時間がかかるように
        c.charge_count = 8   
        c.unit_name = "狂気兵"
        c.max_hp = 1.0          # 触れられたら即死
        c.atk = 20.0
        c.attack_range = 30.0
        c.speed = 90.0        # EpicWarテンポなら90でも十分疾走感がある（元180は速すぎた）
        c.attack_interval = 0.5
        c.attack_windup_time = 0.1 # タメなしで飛び掛かる
        
        c.visual_size = 22.0
        c.unit_color = Color(0.9, 0.1, 0.3)
        
        player_deck.append(c)
    
    # --- 爆弾兵 × 1 ---
    # 特徴：今まで通りだが、寿命が極端に短いかわりに爆発特化。
    var bomb := CardData.new()
    bomb.card_name = "爆弾兵"
    bomb.unit_role = CardData.UnitRole.ASSAULT # 自爆特攻
    bomb.cooldown = 12.0     # 重めのCD
    bomb.charge_count = 1    # たった1体だが特大爆発を持つ
    bomb.unit_name = "爆弾兵"
    bomb.max_hp = 150.0
    bomb.atk = 1.0
    bomb.attack_range = 10.0
    bomb.speed = 70.0
    bomb.attack_windup_time = 0.0 # 爆発にタメは無い
    bomb.lifespan = 8.0        # 勝手に起爆するまでの時間
    bomb.knockback_chance = 100.0
    bomb.knockback_power = 150.0 # 爆発ですげー飛ぶ
    bomb.knockback_direction = Vector2(0.5, -2.0)
    bomb.flinch_chance = 100.0; bomb.flinch_duration = 1.0
    bomb.death_effect_type = "explosion" # 死亡時に爆発
    bomb.death_effect_value = 250.0      # 爆発の特大ダメージ
    bomb.death_effect_range = 150.0      # 広範囲
    
    bomb.visual_size = 30.0
    bomb.unit_color = Color(1.0, 0.6, 0.2) # 爆発しそうなオレンジ
    
    player_deck.append(bomb)

func _generate_map() -> void:
    # 簡単な一本道マップを生成（途中にイベントマスを追加）
    map_nodes = [
        "battle", "event", "treasure", "battle", "elite", "rest", "shop", "boss"
    ]
    current_node_index = 0

# 戦闘勝利時の処理
func on_battle_won() -> void:
    var won_node = map_nodes[current_node_index]
    
    if won_node == "elite" or won_node == "boss":
        # エリート・ボス撃破時はレリック獲得へ（ここではインクリメントせず、Treasureの退出時に進める）
        get_tree().change_scene_to_file("res://Scenes/TreasureScreen.tscn")
    else:
        # 通常戦闘はカード報酬へ（ここでインクリメントして報酬画面へ）
        current_node_index += 1
        get_tree().change_scene_to_file("res://Scenes/RewardScreen.tscn")

# 戦闘敗北時の処理
func on_battle_lost() -> void:
    # タイトル画面（未作成の場合はモック画面）に戻すかゲームオーバ画面へ
    player_current_hp = player_max_hp # 仮回復
    _generate_initial_deck() # デッキも初期化
    _generate_map()
    get_tree().change_scene_to_file("res://Scenes/TitleScreen.tscn")
