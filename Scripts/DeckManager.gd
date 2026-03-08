# DeckManager.gd
# デッキ全体の管理を行うクラス
# 【チャージ式繰り返し生産方式】
# 手札にあるカードは、CDごとに繰り返しユニットを自動生成する。
# 各カードにはチャージ数（生産上限）があり、使い切ると捨て札→次のカードをドロー。
# 山札が尽きたら捨て札をシャッフルして山札に戻す（StS仕様）。
extends Node
class_name DeckManager

# === シグナル ===
# 特定スロットのカードが更新された時（UIの該当スロットだけ更新すればよい）
signal slot_updated(slot_index: int, card: CardData)
# カードのCDが完了してユニット召喚可能になった時
signal card_ready_to_summon(card: CardData, slot_index: int)
# デッキ/捨て札の枚数が変わった時（UI更新用）
signal deck_counts_changed(deck_size: int, discard_size: int)
# 手札の全スロットが初期化された時（起動時）
signal hand_initialized(hand_size: int)
# チャージ数が変化した時（UI更新用）
signal charge_changed(slot_index: int, remaining: int, max_charge: int)

# === デッキの各パイル ===
var original_deck: Array[CardData] = []  # 戦闘開始時の全カード（ロスター用等）
var draw_pile: Array[CardData] = []      # 山札（ここからドローする）
var discard_pile: Array[CardData] = []   # 捨て札（使用済みカード）

# === 手札スロット管理 ===
# 固定長配列。null = そのスロットが空（カードが入っていない）
var hand_slots: Array = []   # Array of CardData or null
# 各スロットのCDタイマー（hand_slotsと同じインデックス）
var cd_timers: Array[float] = []
# 各スロットの残りチャージ数（チャージ式の核心）
var charge_remaining: Array[int] = []

# === 設定 ===
var hand_size: int = 5  # 手札のスロット数

func _ready() -> void:
	print("[DeckManager] デッキマネージャーを初期化しました")

func _process(delta: float) -> void:
	_update_cooldowns(delta)

# === デッキを初期化する ===
func initialize_deck(cards: Array[CardData], num_slots: int = 5) -> void:
	original_deck = cards.duplicate()
	draw_pile = cards.duplicate()
	discard_pile.clear()
	hand_size = num_slots
	
	# 手札スロットを初期化（全てnull=空）
	hand_slots.clear()
	cd_timers.clear()
	charge_remaining.clear()
	for i in range(hand_size):
		hand_slots.append(null)
		cd_timers.append(0.0)
		charge_remaining.append(0)
	
	# 山札をシャッフル
	draw_pile.shuffle()
	
	# UIに「スロット数が決まったよ」と通知
	hand_initialized.emit(hand_size)
	
	# 全スロットにカードを配る
	for i in range(hand_size):
		_draw_card_to_slot(i)
	
	_emit_counts()
	print("[DeckManager] デッキ初期化完了: 山札=%d, スロット数=%d" % [draw_pile.size(), hand_size])

# === 指定スロットにカードを1枚ドローする ===
func _draw_card_to_slot(slot_index: int) -> void:
	# 山札が空なら、捨て札をシャッフルして山札にする（StS仕様）
	if draw_pile.is_empty():
		_reshuffle_discard_to_draw()
	
	# それでも空ならドロー不可
	if draw_pile.is_empty():
		print("[DeckManager] ドロー不可：カードが残っていません")
		return
	
	# 山札の一番上から1枚取って、指定スロットに配置
	var card: CardData = draw_pile.pop_back()
	hand_slots[slot_index] = card
	# CDタイマーをカードのcooldown値で開始
	cd_timers[slot_index] = card.cooldown
	# チャージ数をセット（0=無制限のため、0のままにする）
	charge_remaining[slot_index] = card.charge_count
	
	# UIに通知
	slot_updated.emit(slot_index, card)
	charge_changed.emit(slot_index, charge_remaining[slot_index], card.charge_count)
	_emit_counts()

# === 捨て札をシャッフルして山札にする（StS仕様） ===
func _reshuffle_discard_to_draw() -> void:
	if discard_pile.is_empty():
		return
	print("[DeckManager] 捨て札→山札にリシャッフル（%d枚）" % discard_pile.size())
	draw_pile = discard_pile.duplicate()
	discard_pile.clear()
	draw_pile.shuffle()
	_emit_counts()

# === CDを毎フレーム更新する（チャージ式の核心ロジック） ===
func _update_cooldowns(delta: float) -> void:
	for i in range(hand_size):
		# スロットが空ならスキップ
		if hand_slots[i] == null:
			continue
		
		cd_timers[i] -= delta
		
		# CD完了！→ ユニットを1体召喚
		if cd_timers[i] <= 0.0:
			var card: CardData = hand_slots[i]
			
			if card.is_curse:
				# 呪いカード → 召喚せず、チャージも減らさず即座に捨て札
				print("[DeckManager] 呪いカード '%s' が発動！" % card.card_name)
				_exhaust_slot(i)
				continue
			
			# 通常カード → 召喚シグナルを発火
			card_ready_to_summon.emit(card, i)
			
			# チャージを1消費（0=無制限の場合は減らさない）
			if card.charge_count > 0:
				charge_remaining[i] -= 1
				charge_changed.emit(i, charge_remaining[i], card.charge_count)
				
				# チャージが0になったらこのカードを捨て札に送り、次のカードを引く
				if charge_remaining[i] <= 0:
					print("[DeckManager] '%s' のチャージが切れました → 捨て札へ" % card.card_name)
					_exhaust_slot(i)
					continue
			
			# まだチャージが残っている → CDをリセットして次の生産サイクルへ
			cd_timers[i] = card.cooldown

# === スロットのカードを消耗して次を引く ===
func _exhaust_slot(slot_index: int) -> void:
	var card = hand_slots[slot_index]
	if card != null:
		discard_pile.append(card)
	hand_slots[slot_index] = null
	_draw_card_to_slot(slot_index)

# === デッキ枚数変更通知 ===
func _emit_counts() -> void:
	deck_counts_changed.emit(draw_pile.size(), discard_pile.size())

# === 外部から現在のCDを取得するユーティリティ ===
func get_cd_progress(slot_index: int) -> float:
	# 0.0 = CD完了、1.0 = CDフル残り
	if slot_index < 0 or slot_index >= hand_size:
		return 0.0
	var card = hand_slots[slot_index]
	if card == null or card.cooldown <= 0.0:
		return 0.0
	return clampf(cd_timers[slot_index] / card.cooldown, 0.0, 1.0)

func get_cd_remaining(slot_index: int) -> float:
	if slot_index < 0 or slot_index >= hand_size:
		return 0.0
	return maxf(cd_timers[slot_index], 0.0)

func get_card_at(slot_index: int) -> CardData:
	if slot_index < 0 or slot_index >= hand_size:
		return null
	return hand_slots[slot_index]

func get_charge_remaining(slot_index: int) -> int:
	if slot_index < 0 or slot_index >= hand_size:
		return 0
	return charge_remaining[slot_index]
