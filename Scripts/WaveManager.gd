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

# === ウェーブの停止（戦闘終了時など） ===
func stop_waves() -> void:
	is_running = false
	spawn_queue.clear()
	print("[WaveManager] ウェーブを停止しました。")

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

# === UI表示用：次のウェーブの情報を取得 ===
func get_next_wave_info() -> Dictionary:
	if current_wave_index >= waves.size() or is_all_done:
		return {"is_final": true}
		
	var next_wave = waves[current_wave_index]
	var start_time = next_wave.get("start_time", 0.0)
	var time_left = maxf(0.0, start_time - wave_timer)
	
	# スポーン中なら残り0秒として扱う
	if wave_timer >= start_time:
		time_left = 0.0
	
	var enemy_summaries = []
	for e in next_wave.get("enemies", []):
		var u_name = e.get("stats", {}).get("unit_name", "???")
		var count = e.get("count", 1)
		enemy_summaries.append("%s x%d" % [u_name, count])
		
	return {
		"is_final": false,
		"time_left": time_left,
		"wave_num": current_wave_index + 1,
		"total_waves": waves.size(),
		"enemies": enemy_summaries
	}

# === 現在のノードに応じたウェーブデータを生成する ===
static func get_waves_for_current_node() -> Array[Dictionary]:
	var node_type = "battle"
	if GameManager != null and GameManager.map_nodes.size() > GameManager.current_node_index:
		node_type = GameManager.map_nodes[GameManager.current_node_index]
	
	print("[WaveManager] ノードタイプ '%s' 用のウェーブを生成" % node_type)
	
	if node_type == "boss":
		return _create_boss_waves()
	elif node_type == "elite":
		return _create_elite_waves()
	else:
		return _create_normal_waves()

# 以下、遭遇タイプごとのウェーブ定義（プライベート）
static func _get_enemy_dict() -> Dictionary:
	return {
		"goblin": {
			"unit_name": "狂速ゴブリン", "max_hp": 30.0, "atk": 5.0,
			"attack_range": 30.0, "speed": 80.0, "attack_interval": 0.8,
			"visual_size": 20.0, "unit_color": Color(0.2, 0.8, 0.2)
		},
		"skeleton": {
			"unit_name": "骨の歩兵", "max_hp": 350.0, "atk": 12.0,
			"attack_range": 40.0, "speed": 25.0, "attack_interval": 2.0,
			"visual_size": 32.0, "unit_color": Color(0.8, 0.8, 0.85)
		},
		"skeleton_archer": {
			"unit_name": "骨の弓兵", "max_hp": 120.0, "atk": 25.0,
			"attack_range": 280.0, "speed": 20.0, "attack_interval": 3.0,
			"visual_size": 28.0, "unit_color": Color(0.7, 0.7, 0.7),
			"is_ranged": true, "projectile_aoe": 5.0, "projectile_speed": 400.0
		},
		"orc": {
			"unit_name": "暴虐オーク", "max_hp": 1500.0, "atk": 50.0,
			"attack_range": 45.0, "speed": 15.0, "attack_interval": 3.0, "defense": 5.0,
			"knockback_chance": 100.0, "knockback_power": 60.0, "kb_resistance": 50.0,
			"flinch_chance": 30.0, "flinch_duration": 0.5,
			"visual_size": 65.0, "unit_color": Color(0.1, 0.4, 0.1)
		},
		"dark_knight": {
			"unit_name": "死の暴君(ボス)", "max_hp": 5000.0, "atk": 80.0,
			"attack_range": 60.0, "speed": 12.0, "attack_interval": 4.0, "defense": 15.0,
			"knockback_chance": 100.0, "knockback_power": 120.0, "kb_resistance": 100.0,
			"flinch_chance": 80.0, "flinch_duration": 1.0,
			"visual_size": 110.0, "unit_color": Color(0.3, 0.1, 0.5)
		}
	}

static func _create_normal_waves() -> Array[Dictionary]:
	var e = _get_enemy_dict()
	return [
		{ "start_time": 0.0, "enemies": [ {"stats": e.goblin, "count": 5, "interval": 1.5} ] },
		{ "start_time": 15.0, "enemies": [ {"stats": e.skeleton, "count": 10, "interval": 2.0} ] },
		{ "start_time": 35.0, "enemies": [ 
			{"stats": e.skeleton, "count": 8, "interval": 2.0},
			{"stats": e.skeleton_archer, "count": 4, "interval": 3.0} 
		] }
	]

static func _create_elite_waves() -> Array[Dictionary]:
	var e = _get_enemy_dict()
	return [
		{ "start_time": 0.0, "enemies": [ {"stats": e.goblin, "count": 10, "interval": 1.0} ] },
		{ "start_time": 15.0, "enemies": [ 
			{"stats": e.orc, "count": 3, "interval": 5.0},
			{"stats": e.skeleton_archer, "count": 6, "interval": 2.0} 
		] },
		{ "start_time": 40.0, "enemies": [ {"stats": e.skeleton, "count": 20, "interval": 1.5} ] }
	]

static func _create_boss_waves() -> Array[Dictionary]:
	var e = _get_enemy_dict()
	return [
		{ "start_time": 0.0, "enemies": [ 
			{"stats": e.skeleton, "count": 10, "interval": 1.5},
			{"stats": e.skeleton_archer, "count": 5, "interval": 2.5} 
		] },
		{ "start_time": 30.0, "enemies": [ 
			{"stats": e.orc, "count": 4, "interval": 4.0},
			{"stats": e.goblin, "count": 15, "interval": 0.8} 
		] },
		{ "start_time": 60.0, "enemies": [ 
			{"stats": e.dark_knight, "count": 1, "interval": 0.0},
			{"stats": e.skeleton, "count": 10, "interval": 3.0}
		] }
	]
