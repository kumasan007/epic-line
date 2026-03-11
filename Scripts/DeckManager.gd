# DeckManager.gd
# 【リアルタイム・ウェーブ召喚制】
# - 12秒ごとにサイクルが回る（時間停止なし）
# - サイクル開始時にマナが回復する
# - プレイヤーは手札からカードを戦場に配置し、1秒後に実体化する
extends Node
class_name DeckManager

# === シグナル ===
signal hand_drawn()                                       # 手札が新しく引かれた時
signal hand_discarded()                                   # 手札が破棄された時
signal mana_changed(current_mana: int, max_mana: int)     # マナが変化した時
signal cycle_timer_updated(time_left: float, total: float)# サイクルの残り時間が変わった時
signal cycle_started(cycle_number: int)                    # 新しいサイクルが開始した時
signal deck_shuffled()                                    # 山札がシャッフルされた時

# === デッキ状態 ===
var draw_pile: Array[CardData] = []
var discard_pile: Array[CardData] = []
var hand: Array[CardData] = []

var max_hand_size: int = 5      # 毎サイクル引く枚数

# === マナシステム ===
var current_mana: int = 5       # 現在のマナ
var max_mana: int = 5           # マナ上限（=毎サイクルの回復量。持ち越し不可）
var mana_per_cycle: int = 5     # 1サイクルごとのマナリセット値

# === サイクルシステム ===
var cycle_duration: float = 12.0 # 1サイクルの秒数
var cycle_timer: float = 0.0     # 現在の残り時間
var cycle_count: int = 0         # 何サイクル目か（敵の難易度スケーリングに使用）

func _ready() -> void:
	print("[DeckManager] 実時間ウェーブ召喚システムを初期化しました")

func _process(delta: float) -> void:
	# 常に時間が進み続ける
	cycle_timer -= delta
	cycle_timer_updated.emit(maxf(cycle_timer, 0.0), cycle_duration)
	
	if cycle_timer <= 0.0:
		_on_cycle_end()

# === デッキを初期化する ===
func initialize_deck(cards: Array[CardData]) -> void:
	draw_pile.clear()
	discard_pile.clear()
	hand.clear()
	
	for card in cards:
		draw_pile.append(card)
	
	_shuffle_deck()
	
	# 初期マナ
	current_mana = mana_per_cycle
	mana_changed.emit(current_mana, max_mana)
	
	# 最初のサイクルを開始
	_start_new_cycle()
	
	print("[DeckManager] デッキ初期化完了: %d枚" % draw_pile.size())

# === サイクルの終了と一斉スポーン ===
func _on_cycle_end() -> void:
	print("[DeckManager] ⏳ サイクル終了！ マナ回復と手札補充を行います")
	
	# マナリセット（Slay the Spireのように、持ち越し不可。毎サイクル固定値になる）
	current_mana = mana_per_cycle
	mana_changed.emit(current_mana, max_mana)
	
	# 手札を捨てる
	_discard_hand()
	
	# 新しいサイクルを開始
	_start_new_cycle()

# === 新しいサイクルの開始（ドロー） ===
func _start_new_cycle() -> void:
	cycle_count += 1
	cycle_timer = cycle_duration
	_draw_cards(max_hand_size)
	cycle_timer_updated.emit(cycle_timer, cycle_duration)
	# BattleFieldに「新しいサイクルが始まった」ことを通知（敵のゴースト配置用）
	cycle_started.emit(cycle_count)
	print("[DeckManager] サイクル %d 開始！" % cycle_count)

# === 手札を全て捨て札へ送る ===
func _discard_hand() -> void:
	for c in hand:
		discard_pile.append(c)
	hand.clear()
	hand_discarded.emit()

# === カードをドローする ===
func _draw_cards(amount: int) -> void:
	for i in range(amount):
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				# 山札も捨て札も空ならこれ以上引けない
				break
			_shuffle_deck()
			
		var drawn = draw_pile.pop_back()
		hand.append(drawn)
		
	hand_drawn.emit()

# === デッキシャッフル ===
func _shuffle_deck() -> void:
	print("[DeckManager] 山札をシャッフルしました")
	for c in discard_pile:
		draw_pile.append(c)
	discard_pile.clear()
	draw_pile.shuffle()
	deck_shuffled.emit()

# === 手札からカードを使用する（マナ消費と手札からの削除） ===
func try_use_card(hand_index: int) -> bool:
	if hand_index < 0 or hand_index >= hand.size():
		return false
		
	var card = hand[hand_index]
	
	# 呪いチェック
	if card.is_curse:
		return false
		
	# マナチェック
	if current_mana < card.mana_cost:
		print("[DeckManager] マナ不足")
		return false
		
	# マナ消費
	current_mana -= card.mana_cost
	mana_changed.emit(current_mana, max_mana)
	
	# 手札から捨て札へ直接移動
	hand.remove_at(hand_index)
	discard_pile.append(card)
	
	# UI更新のために再通知
	hand_drawn.emit() 
	return true

