# WaveManager.gd
# 敵ウェーブの管理を行うクラス
# 時間経過に応じて段階的に敵を出現させ、ステージの難易度カーブを作る
# なぜ別クラス？→ ウェーブのデータ定義と出現ロジックをBattleFieldから分離し、
#   ステージごとに異なるウェーブ構成を簡単に差し替え可能にするため
extends Node
class_name WaveManager

# === シグナル ===
# 敵を1体スポーンさせるリクエスト。BattleFieldがこのシグナルを受け取って実際に生成する
signal spawn_enemy_requested(enemy_stats: Dictionary)
# ウェーブ番号が進んだ時（UI更新用）
signal wave_changed(wave_number: int, total_waves: int)
# 全ウェーブが終了した時（勝利判定用）
signal all_waves_completed()

# === ウェーブデータ構造 ===
# 1つのウェーブ = 「何秒後に」「どの敵を」「何体」出すか
# enemies配列の各要素: { "stats": Dictionary, "count": int, "interval": float }
#   stats: 敵のステータス辞書（BattleField.spawn_unitに渡す形式）
#   count: この種類の敵を何体出すか
#   interval: 1体ずつ出す間隔（秒）
var waves: Array[Dictionary] = []

# === 内部状態 ===
var current_wave_index: int = 0    # 現在のウェーブ番号（0始まり）
var wave_timer: float = 0.0        # ウェーブ内の経過時間
var is_running: bool = false        # ウェーブ進行中フラグ
var is_all_done: bool = false       # 全ウェーブ完了フラグ

# ウェーブ内の敵スポーン管理
var spawn_queue: Array[Dictionary] = []  # スポーン待ちの敵キュー
var spawn_timer: float = 0.0             # スポーン間隔タイマー

func _process(delta: float) -> void:
	if not is_running or is_all_done:
		return
	
	# --- ウェーブ開始判定 ---
	wave_timer += delta
	
	# 現在のウェーブの開始時間に達したらスポーンキューを作成
	if current_wave_index < waves.size():
		var wave: Dictionary = waves[current_wave_index]
		var start_time: float = wave.get("start_time", 0.0)
		
		if wave_timer >= start_time and spawn_queue.is_empty() and not wave.get("_started", false):
			_start_wave(current_wave_index)
	
	# --- スポーンキューの処理 ---
	if not spawn_queue.is_empty():
		spawn_timer += delta
		var next_spawn: Dictionary = spawn_queue[0]
		var interval: float = next_spawn.get("interval", 0.5)
		
		if spawn_timer >= interval:
			spawn_timer = 0.0
			var stats: Dictionary = next_spawn.get("stats", {})
			spawn_enemy_requested.emit(stats)
			
			# このエントリの残りカウントを減らす
			next_spawn["remaining"] -= 1
			if next_spawn["remaining"] <= 0:
				spawn_queue.pop_front()
				
				# スポーンキューが空になったら次のウェーブへ
				if spawn_queue.is_empty():
					current_wave_index += 1
					if current_wave_index >= waves.size():
						is_all_done = true
						all_waves_completed.emit()
						print("[WaveManager] 全ウェーブ完了！")
					else:
						wave_changed.emit(current_wave_index + 1, waves.size())

# === ウェーブデータを設定してスタート ===
func start_waves(wave_data: Array[Dictionary]) -> void:
	waves = wave_data
	current_wave_index = 0
	wave_timer = 0.0
	is_running = true
	is_all_done = false
	spawn_queue.clear()
	
	if waves.size() > 0:
		wave_changed.emit(1, waves.size())
	print("[WaveManager] ウェーブ開始！ 全%dウェーブ" % waves.size())

# === 指定ウェーブのスポーンキューを作成 ===
func _start_wave(index: int) -> void:
	var wave: Dictionary = waves[index]
	wave["_started"] = true  # 二重起動防止フラグ
	
	var enemies: Array = wave.get("enemies", [])
	for enemy_entry in enemies:
		# キューに追加（remaining = count のコピー）
		spawn_queue.append({
			"stats": enemy_entry.get("stats", {}),
			"remaining": enemy_entry.get("count", 1),
			"interval": enemy_entry.get("interval", 0.8),
		})
	
	print("[WaveManager] ウェーブ %d 開始！ 敵グループ数: %d" % [index + 1, enemies.size()])

# === テスト用のウェーブデータを生成する ===
# なぜ静的関数？→ BattleFieldから呼び出して使うユーティリティ
static func create_test_waves() -> Array[Dictionary]:
	# 敵のステータス定義（使い回し用）
	var goblin: Dictionary = {
		# 特徴：速い！すぐ死ぬ！手数がスゲェ！
		"unit_name": "狂速ゴブリン", "max_hp": 8.0, "atk": 5.0,
		"attack_range": 30.0, "speed": 160.0, "attack_interval": 0.4
	}
	var skeleton: Dictionary = {
		# 特徴：普通の兵士。少しタフ。
		"unit_name": "骨の歩兵", "max_hp": 150.0, "atk": 12.0,
		"attack_range": 40.0, "speed": 50.0, "attack_interval": 1.5
	}
	var skeleton_archer: Dictionary = {
		# 特徴：遠くから撃ってくるが、もろい。
		"unit_name": "骨の弓兵", "max_hp": 40.0, "atk": 25.0,
		"attack_range": 220.0, "speed": 35.0, "attack_interval": 2.5
	}
	var orc: Dictionary = {
		# 特徴：超絶硬い＆遅い。一撃がドスーン！と重い。
		"unit_name": "暴虐オーク", "max_hp": 600.0, "atk": 50.0,
		"attack_range": 45.0, "speed": 25.0, "attack_interval": 3.0, "defense": 5.0,
		"knockback_chance": 100.0, "knockback_power": 60.0, "kb_resistance": 50.0
	}
	var dark_knight: Dictionary = {
		# 特徴：全部盛りのボス
		"unit_name": "死の暴君(ボス)", "max_hp": 1500.0, "atk": 80.0,
		"attack_range": 50.0, "speed": 30.0, "attack_interval": 4.0, "defense": 15.0,
		"knockback_chance": 100.0, "knockback_power": 120.0, "kb_resistance": 100.0
	}
	
	var waves: Array[Dictionary] = [
		# ウェーブ1（0秒〜）: ゴブリン15体。最初の小手調べの大群
		{
			"start_time": 0.0,
			"enemies": [
				{"stats": goblin, "count": 15, "interval": 0.4}
			]
		},
		# ウェーブ2（8秒〜）: スケルトン20体。盾兵がいないと少し辛い
		{
			"start_time": 8.0,
			"enemies": [
				{"stats": skeleton, "count": 20, "interval": 0.5}
			]
		},
		# ウェーブ3（18秒〜）: 混成部隊。骨15体+遠距離10体。
		{
			"start_time": 18.0,
			"enemies": [
				{"stats": skeleton, "count": 15, "interval": 0.4},
				{"stats": skeleton_archer, "count": 10, "interval": 0.6}
			]
		},
		# ウェーブ4（30秒〜）: 怒涛のゴブリンラッシュ 60体 + 超巨大オーク5体。範囲攻撃スペルが無いと死ぬ
		{
			"start_time": 30.0,
			"enemies": [
				{"stats": orc, "count": 5, "interval": 1.5},
				{"stats": goblin, "count": 60, "interval": 0.15}
			]
		},
		# ウェーブ5（45秒〜）: ボス級。ダークナイト + 護衛の群れ
		{
			"start_time": 45.0,
			"enemies": [
				{"stats": skeleton, "count": 25, "interval": 0.3},
				{"stats": skeleton_archer, "count": 15, "interval": 0.5},
				{"stats": dark_knight, "count": 1, "interval": 0.0}
			]
		},
	]
	
	return waves
