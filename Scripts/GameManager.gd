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
    
    # ============================================================
    # 設計思想: 「高いやつ出せば勝ち」を絶対に許さないバランス
    # - どのユニットも単体では致命的な弱点がある
    # - 「壁＋火力」「数＋足止め」のコンボで初めて強くなる
    # - 5マナの使い方に複数の正解がある
    # ============================================================
    
    # --- 盾兵（壁）× 2 ---
    # 役割: 前衛に立つ壁。HPは高いが攻撃力はほぼゼロ。
    # 弱点: 一人では敵を倒せない。火力ユニットが後ろにいないと意味がない。
    # コンボ: 盾兵(2) + 弓兵(2) + 狂気兵(1) = 鉄壁の布陣
    for i in range(2):
        var c := CardData.new()
        c.card_name = "盾兵"
        c.description = "HP高・攻撃力ゼロ。壁役。弓兵を守れ"
        c.unit_role = CardData.UnitRole.TANK
        c.mana_cost = 2         # 安い壁。パーツとして使う
        c.summon_count = 1      # 単体で壁を張る
        c.unit_name = "盾兵"
        c.max_hp = 600.0        # 硬いが無敵ではない（ゴブリン3体で約30秒で倒れる）
        c.atk = 3.0             # 攻撃力ほぼゼロ！壁でしかない
        c.attack_range = 40.0
        c.defense = 5.0
        c.speed = 18.0          # 遅い
        c.attack_interval = 3.0
        c.attack_windup_time = 1.0
        c.knockback_chance = 80.0
        c.knockback_power = 50.0
        c.kb_resistance = 70.0  # 吹き飛ばされにくい
        
        c.visual_size = 50.0
        c.unit_color = Color(0.4, 0.45, 0.55)
        
        player_deck.append(c)
    
    # --- 双剣兵（近接DPS）× 3 ---
    # 役割: タンクの後ろから連撃。DPSの要。
    # 弱点: HPが低い。壁がないと前に出され即死する。
    # コンボ: 盾兵(2) + 双剣兵(2) = 壁の後ろで暴れるDPSコンボ（計4マナ）
    for i in range(3):
        var c := CardData.new()
        c.card_name = "双剣兵"
        c.description = "連撃が強力。壁が無いと即溶け"
        c.unit_role = CardData.UnitRole.FIGHTER
        c.mana_cost = 2
        c.summon_count = 2      # 2体ペアで召喚！連撃コンビ
        c.unit_name = "双剣兵"
        c.max_hp = 120.0        # 紙。盾がなければすぐ死ぬ
        c.atk = 12.0            # 手数で稼ぐ
        c.attack_range = 35.0
        c.speed = 45.0
        c.attack_interval = 0.5 # 超連撃（0.5秒ごとに斬る＝DPS24）
        c.attack_windup_time = 0.15
        c.kb_resistance = 0.0   # 吹き飛ばされまくる
        
        c.visual_size = 25.0
        c.unit_color = Color(0.2, 0.8, 1.0)
        
        player_deck.append(c)
    
    # --- 弓兵（遠距離火力）× 2 ---
    # 役割: 後衛から高火力狙撃。ひるみ付きで敵を足止め。
    # 弱点: HPが紙。近づかれたら一瞬で死ぬ。壁が必須。
    # コンボ: 盾兵(2) + 弓兵(2) = 鉄板の「壁＋砲台」。残り1マナで狂気兵追加。
    for i in range(2):
        var c := CardData.new()
        c.card_name = "弓兵"
        c.description = "高火力狙撃。近づかれたら即死"
        c.unit_role = CardData.UnitRole.SHOOTER
        c.mana_cost = 2
        c.summon_count = 1      # 単体狙撃手
        c.unit_name = "弓兵"
        c.max_hp = 80.0         # ガラスキャノン。近づかれたら終わり
        c.atk = 45.0            # 一撃が痛い
        c.attack_range = 350.0
        c.speed = 15.0
        c.attack_interval = 3.5
        c.attack_windup_time = 1.5
        c.flinch_chance = 100.0; c.flinch_duration = 0.6
        c.knockback_chance = 40.0
        c.knockback_power = 30.0
        
        c.visual_size = 28.0
        c.unit_color = Color(0.8, 0.5, 0.2)
        c.is_ranged = true
        c.projectile_speed = 500.0
        c.projectile_aoe = 20.0
        
        player_deck.append(c)
    
    # --- 狂気兵（使い捨ての囮）× 3 ---
    # 役割: 1マナで出せる消耗品。数で敵の攻撃を分散させたり、時間稼ぎに。
    # 弱点: 一撃で死ぬ。
    # コンボ: 狂気兵(1)×5 = 肉壁ラッシュ。弓兵が後ろにいれば時間稼ぎとして機能。
    for i in range(3):
        var c := CardData.new()
        c.card_name = "狂気兵"
        c.description = "1マナ使い捨て。囮や数の暴力に"
        c.unit_role = CardData.UnitRole.ASSAULT
        c.mana_cost = 1
        c.summon_count = 3      # 1マナで3体！コスパ最強の群れ
        c.unit_name = "狂気兵"
        c.max_hp = 1.0          # 何が当たっても即死
        c.atk = 15.0
        c.attack_range = 30.0
        c.speed = 85.0
        c.attack_interval = 0.6
        c.attack_windup_time = 0.1
        
        c.visual_size = 20.0
        c.unit_color = Color(0.9, 0.1, 0.3)
        
        player_deck.append(c)
    
    # --- 爆弾兵（一発逆転）× 1 ---
    # 役割: 死亡時に大爆発。密集した敵を一掃する切り札。
    # 弱点: 3マナと高コスト。道中で死ぬと無駄死に。護衛が必要。
    # コンボ: 爆弾兵(3) + 狂気兵(1)×2 = 爆弾を敵陣に送り届けるプラン
    var bomb := CardData.new()
    bomb.card_name = "爆弾兵"
    bomb.description = "死亡時に大爆発！護衛とセットで"
    bomb.unit_role = CardData.UnitRole.ASSAULT
    bomb.mana_cost = 3
    bomb.summon_count = 1       # 単体の大玉
    bomb.unit_name = "爆弾兵"
    bomb.max_hp = 100.0         # 脆い。護衛が必要
    bomb.atk = 1.0
    bomb.attack_range = 10.0
    bomb.speed = 55.0
    bomb.attack_windup_time = 0.0
    bomb.lifespan = 10.0
    bomb.knockback_chance = 100.0
    bomb.knockback_power = 120.0
    bomb.knockback_direction = Vector2(0.5, -2.0)
    bomb.flinch_chance = 100.0; bomb.flinch_duration = 1.0
    bomb.death_effect_type = "explosion"
    bomb.death_effect_value = 200.0
    bomb.death_effect_range = 130.0
    
    bomb.visual_size = 28.0
    bomb.unit_color = Color(1.0, 0.5, 0.1)
    
    player_deck.append(bomb)
    
    # --- 鷹騎兵（飛行ユニット）× 1 ---
    # 役割: 空を飛び、地上近接ユニットを無視して敵の弓兵や後衛を狩る。
    # 弱点: HPが低い。敵の弓兵に撃ち落とされる。
    # コンボ: 盾兵(2)で前線を持たせつつ、鷹騎兵(2)が後方の弓兵を排除
    var hawk := CardData.new()
    hawk.card_name = "鷹騎兵"
    hawk.description = "飛行。地上近接の攻撃を無視"
    hawk.unit_role = CardData.UnitRole.FIGHTER
    hawk.mana_cost = 2
    hawk.summon_count = 1
    hawk.unit_name = "鷹騎兵"
    hawk.max_hp = 90.0          # 弓で落ちる脆さ
    hawk.atk = 20.0             # そこそこの攻撃力
    hawk.attack_range = 35.0
    hawk.speed = 65.0           # 高速移動
    hawk.attack_interval = 1.2
    hawk.attack_windup_time = 0.3
    hawk.is_flying = true       # ★飛行！地上近接から攻撃されない
    
    hawk.visual_size = 22.0
    hawk.unit_color = Color(0.9, 0.85, 0.4)  # 金色
    
    player_deck.append(hawk)
    
    # --- 騎兵（突破役）× 1 ---
    # 役割: 高速で敵陣に突っ込み、強力なノックバックで前線を押し上げる
    var cav := CardData.new()
    cav.card_name = "騎兵"
    cav.description = "高速移動と強力なノックバック"
    cav.unit_role = CardData.UnitRole.FIGHTER
    cav.mana_cost = 3
    cav.summon_count = 1
    cav.unit_name = "騎兵"
    cav.max_hp = 120.0
    cav.atk = 18.0
    cav.attack_range = 35.0
    cav.speed = 100.0  # かなり速い
    cav.attack_interval = 1.0
    cav.attack_windup_time = 0.2
    cav.knockback_chance = 80.0
    cav.knockback_power = 90.0
    cav.knockback_direction = Vector2(1.0, -1.0)
    cav.visual_size = 35.0
    cav.unit_color = Color(0.8, 0.4, 0.2)
    player_deck.append(cav)

    # --- 魔術師（範囲攻撃）× 1 ---
    # 役割: 攻撃間隔は遅いが、着弾地点の周囲にダメージを与える。集団戦に強い
    var mage := CardData.new()
    mage.card_name = "魔術師"
    mage.description = "着弾時に爆発する範囲魔法"
    mage.unit_role = CardData.UnitRole.SHOOTER
    mage.mana_cost = 2
    mage.summon_count = 1
    mage.unit_name = "魔術師"
    mage.max_hp = 40.0
    mage.atk = 25.0
    mage.attack_range = 250.0
    mage.speed = 40.0
    mage.attack_interval = 2.0
    mage.attack_windup_time = 0.4
    mage.is_ranged = true
    mage.projectile_speed = 300.0
    mage.projectile_aoe = 60.0  # 半径60の範囲ダメージ
    mage.visual_size = 25.0
    mage.unit_color = Color(0.5, 0.1, 0.8)
    player_deck.append(mage)

    # --- 暗殺者（一点突破）× 1 ---
    # 役割: 非常に脆いが、とてつもない火力と攻撃速度で厄介な敵を即座に葬る
    var assassin := CardData.new()
    assassin.card_name = "暗殺者"
    assassin.description = "超火力・超紙装甲の近接特化"
    assassin.unit_role = CardData.UnitRole.ASSAULT
    assassin.mana_cost = 2
    assassin.summon_count = 1
    assassin.unit_name = "暗殺者"
    assassin.max_hp = 30.0  # 弓1〜2発で沈む
    assassin.atk = 40.0
    assassin.attack_range = 30.0
    assassin.speed = 120.0
    assassin.attack_interval = 0.4  # 高速連撃
    assassin.attack_windup_time = 0.1
    assassin.visual_size = 20.0
    assassin.unit_color = Color(0.2, 0.2, 0.2)
    player_deck.append(assassin)
    
    # --- 火球（即時スペル） × 2 ---
    # 特徴：指定位置周辺の敵にAoEダメージ。前線が崩壊しそうな時の緊急手段。
    for i in range(2):
        var fireball := CardData.new()
        fireball.card_name = "火球"
        fireball.card_type = CardData.CardType.SPELL_INSTANT
        fireball.place_zone = CardData.PlaceZone.ANYWHERE  # スペルはどこでも撃てる
        fireball.mana_cost = 2
        fireball.description = "指定地点の敵に30ダメージ (範囲100)"
        fireball.spell_effect = "damage_aoe"
        fireball.spell_value = 30.0
        fireball.spell_range = 100.0
        fireball.spell_color = Color(1.0, 0.4, 0.1)  # 炎のオレンジ
        fireball.visual_size = 0.0  # ユニットではないので0
        fireball.unit_color = Color(1.0, 0.4, 0.1)
        player_deck.append(fireball)
    
    # --- 回復（即時スペル） × 2 ---
    # 特徴：味方全体のHPを回復。タンクを延命して次の援軍到着まで持たせる。
    for i in range(2):
        var heal := CardData.new()
        heal.card_name = "回復の祈り"
        heal.card_type = CardData.CardType.SPELL_INSTANT
        heal.place_zone = CardData.PlaceZone.ANYWHERE  # 回復はどこでもOK
        heal.mana_cost = 1
        heal.description = "味方全体のHPを40回復"
        heal.spell_effect = "heal_all"
        heal.spell_value = 40.0
        heal.spell_range = 0.0  # 全体効果なので範囲不要
        heal.spell_color = Color(0.3, 1.0, 0.5)  # 回復の緑
        heal.visual_size = 0.0
        heal.unit_color = Color(0.3, 1.0, 0.5)
        player_deck.append(heal)

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
