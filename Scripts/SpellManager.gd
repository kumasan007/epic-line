# SpellManager.gd
# スペルスロットの管理を行うクラス
# スペルは山札の概念がなく、固定スロットにセットしてCDで繰り返し使用する
# スペル発動時に「時間停止」が発生する
extends Node
class_name SpellManager

# === シグナル ===
# スペルの発動がリクエストされた時。BattleFieldが時間停止と効果処理を行う
signal spell_cast_requested(spell: SpellData, slot_index: int, target_pos: Vector2)
# スロットのCD状態が変わった時（UI更新用）
signal spell_slot_updated(slot_index: int, spell: SpellData, cd_remaining: float)
# 時間停止の開始/終了
signal time_stop_started()
signal time_stop_ended()

# === スペルスロット ===
const MAX_SLOTS: int = 3  # 最大スペルスロット数
var spell_slots: Array = []  # Array of SpellData or null
var cd_timers: Array[float] = []  # 各スロットのCD残り時間
var slot_count: int = 2  # 現在の有効スロット数（レリック等で変動）

# === 時間停止状態 ===
var is_time_stopped: bool = false
# 時間停止中に発動待ちのスペル（タップ位置指定が必要な場合に使う）
var pending_spell: SpellData = null
var pending_slot: int = -1

func _ready() -> void:
	# スロットの初期化
	for i in range(MAX_SLOTS):
		spell_slots.append(null)
		cd_timers.append(0.0)
	print("[SpellManager] スペルマネージャー初期化完了（有効スロット: %d）" % slot_count)

func _process(delta: float) -> void:
	# 時間停止中はCDを進めない
	if is_time_stopped:
		return
	
	# 各スロットのCDを更新
	for i in range(slot_count):
		if spell_slots[i] != null and cd_timers[i] > 0.0:
			cd_timers[i] = maxf(cd_timers[i] - delta, 0.0)

# === スペルをスロットにセットする ===
func set_spell(slot_index: int, spell: SpellData) -> void:
	if slot_index < 0 or slot_index >= slot_count:
		return
	spell_slots[slot_index] = spell
	cd_timers[slot_index] = 0.0  # セット時はCD0（すぐ使える）
	print("[SpellManager] スロット%d にスペル '%s' をセット" % [slot_index, spell.spell_name])

# === スペル発動（プレイヤーがスペルボタンをタップした時） ===
func try_cast_spell(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= slot_count:
		return false
	
	var spell: SpellData = spell_slots[slot_index]
	if spell == null:
		print("[SpellManager] スロット%d にスペルがありません" % slot_index)
		return false
	
	# CDが残っていたら発動不可
	if cd_timers[slot_index] > 0.0:
		print("[SpellManager] CD中: 残り %.1f秒" % cd_timers[slot_index])
		return false
	
	# --- 時間停止を開始 ---
	is_time_stopped = true
	pending_spell = spell
	pending_slot = slot_index
	time_stop_started.emit()
	print("[SpellManager] ⏸ 時間停止！ スペル '%s' の効果を適用中..." % spell.spell_name)
	
	return true

# === スペル効果を確定して発動する ===
# 時間停止中にプレイヤーが対象を選択した後、または即時効果の場合に呼ぶ
func confirm_spell(target_position: Vector2 = Vector2.ZERO) -> void:
	if pending_spell == null:
		return
	
	# 発動シグナルを送る（BattleFieldが効果を処理する。位置データ付き）
	spell_cast_requested.emit(pending_spell, pending_slot, target_position)
	
	# CDを開始
	cd_timers[pending_slot] = pending_spell.cooldown
	
	print("[SpellManager] ▶ スペル '%s' 発動！ CD開始: %.1f秒" % [pending_spell.spell_name, pending_spell.cooldown])
	
	# 時間停止を解除
	pending_spell = null
	pending_slot = -1
	is_time_stopped = false
	time_stop_ended.emit()

# === 時間停止をキャンセルする（スペルを使わずに再開） ===
func cancel_time_stop() -> void:
	if not is_time_stopped:
		return
	print("[SpellManager] 時間停止キャンセル")
	pending_spell = null
	pending_slot = -1
	is_time_stopped = false
	time_stop_ended.emit()

# === ユーティリティ ===
func get_cd_progress(slot_index: int) -> float:
	if slot_index < 0 or slot_index >= slot_count:
		return 0.0
	var spell = spell_slots[slot_index]
	if spell == null or spell.cooldown <= 0.0:
		return 0.0
	return clampf(cd_timers[slot_index] / spell.cooldown, 0.0, 1.0)

func get_cd_remaining(slot_index: int) -> float:
	if slot_index < 0 or slot_index >= slot_count:
		return 0.0
	return maxf(cd_timers[slot_index], 0.0)

func is_spell_ready(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= slot_count:
		return false
	return spell_slots[slot_index] != null and cd_timers[slot_index] <= 0.0
