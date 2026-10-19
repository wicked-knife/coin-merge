class_name NormalGame
extends RefCounted
## 普通模式规则。数组始终按槽底→顶部排列；视图不参与规则计算。

const CAPACITY := 10
const CELL_COUNT := 12
const SAVE_PATH := "user://normal_game.json"
const SAVE_VERSION := 1
enum CellState { NORMAL, LOCKED, UNLOCKABLE, REWARD, USING_AD, LOCK_AD }

# 保留捕获配置的行顺序，权重按总和抽样（第一组总和为 125）。
const COUNT_TABLES := [
	[[4, 60], [3, 20], [2, 20], [5, 25]],
	[[6, 25], [5, 30], [4, 35], [2, 10]],
	[[6, 45], [5, 35], [4, 10], [2, 10]],
	[[6, 30], [5, 35], [4, 25], [3, 5], [2, 5]],
	[[6, 30], [5, 35], [4, 20], [3, 10], [2, 5]],
]
const GROUP_TABLES := [
	[["11111", 50], ["11222", 30], ["11122", 20]],
	[["111111", 30], ["111122", 40], ["112222", 20], ["112211", 10]],
	[["111111", 10], ["111222", 20], ["112233", 40], ["112211", 20], ["112333", 10]],
	[["111111", 5], ["111222", 20], ["112233", 30], ["122333", 25], ["112211", 10], ["122211", 10]],
	[["111122", 5], ["112233", 20], ["122233", 25], ["122333", 15], ["112311", 20], ["123311", 15]],
]

var cells: Array = []
var normal_order: Array = []
var level := 1
var unlock_count := 5
var highest_level := 1
var shuffle_left := 3
var guide_step := 0
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()
	new_game()


static func coin(value: int, hidden: bool = false) -> Dictionary:
	return {"level": value, "hidden": hidden}


func base_level() -> int:
	return 6 * (level - 1) + 1


func stage() -> int:
	var extra := unlock_count - 5
	if extra >= 7:
		return 4
	if extra >= 5:
		return 3
	if extra >= 3:
		return 2
	return 1 if extra >= 1 else 0


func targets() -> Array:
	var base := base_level()
	return [base + 4, base + 5, base + 6, base + 8, base + 9]


func new_game() -> void:
	level = 1
	unlock_count = 5
	highest_level = 1
	shuffle_left = 3
	guide_step = 0
	_empty_board()
	for index in range(5):
		cells[index].state = CellState.NORMAL
		normal_order.append(index)
	for index in [0, 2]:
		for count in range(5):
			cells[index].coins.append(coin(1))


func _empty_board() -> void:
	cells.clear()
	normal_order.clear()
	for index in range(CELL_COUNT):
		cells.append({"state": CellState.LOCKED, "coins": []})


func restart() -> void:
	guide_step = -1
	shuffle_left = 3
	_init_random_board()


func _init_random_board() -> void:
	_empty_board()
	var open_count := 5 + mini(3, floori(level / 2.0))
	for index in range(open_count):
		cells[index].state = CellState.NORMAL
		normal_order.append(index)
	if level >= 2:
		cells[open_count].state = CellState.UNLOCKABLE
	for index in range(open_count, unlock_count):
		cells[index].state = CellState.UNLOCKABLE
	var positions: Array = [0, 1, 2, 3, 4]
	_shuffle(positions)
	var base := base_level()
	for offset in range(2):
		var stack: Array = cells[positions[offset]].coins
		for count in range(rng.randi_range(2, 5)):
			stack.append(coin(base + offset))
	var candidates: Array = [base, base + 1, base + 2, base + 3]
	for offset in range(2, 5):
		if candidates.size() < 2:
			candidates = [base, base + 1, base + 2, base + 3]
		var bottom: int = candidates.pop_at(rng.randi_range(0, candidates.size() - 1))
		var top: int = candidates.pop_at(rng.randi_range(0, candidates.size() - 1))
		# 发布版初始化丢失 hidden 标记，故初盘全部可见。
		cells[positions[offset]].coins = [coin(bottom), coin(top), coin(top), coin(top)]
	_enable_reward_cell()


func _shuffle(values: Array) -> void:
	for index in range(values.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var temporary = values[index]
		values[index] = values[other]
		values[other] = temporary


func is_playable(index: int) -> bool:
	return index >= 0 and index < cells.size() and cells[index].state in [CellState.NORMAL, CellState.USING_AD]


func selected_count(index: int) -> int:
	if not is_playable(index) or cells[index].coins.is_empty():
		return 0
	var stack: Array = cells[index].coins
	var top_level: int = stack.back().level
	var count := 1
	for offset in range(stack.size() - 2, -1, -1):
		if stack[offset].hidden or stack[offset].level != top_level:
			break
		count += 1
	return count


func move(source: int, target: int) -> Dictionary:
	var count := selected_count(source)
	if count == 0 or source == target or not is_playable(target):
		return {}
	var from: Array = cells[source].coins
	var to: Array = cells[target].coins
	if to.size() >= CAPACITY or (not to.is_empty() and to.back().level != from.back().level):
		return {}
	count = mini(count, CAPACITY - to.size())
	var source_start := from.size() - count
	var target_start := to.size()
	var moved := from.slice(source_start)
	from.resize(source_start)
	to.append_array(moved)
	var revealed: Array = []
	for offset in range(from.size() - 1, -1, -1):
		if not from[offset].hidden:
			break
		from[offset].hidden = false
		revealed.append(offset)
	return {"source": source, "target": target, "count": count, "source_start": source_start,
		"target_start": target_start, "coins": moved, "revealed": revealed}


func can_merge(index: int) -> bool:
	if not is_playable(index):
		return false
	var stack: Array = cells[index].coins
	if stack.size() != CAPACITY:
		return false
	var value: int = stack[0].level
	for item: Dictionary in stack:
		if item.hidden or item.level != value:
			return false
	return true


func mergeable_cells() -> Array:
	return normal_order.filter(func(index: int) -> bool: return can_merge(index))


func merge_ready() -> Array:
	var merged: Array = []
	for index: int in mergeable_cells():
		var value: int = cells[index].coins[0].level + 1
		cells[index].coins = [coin(value), coin(value)]
		merged.append({"index": index, "level": value})
	return merged


func maximum_level() -> int:
	var result := base_level()
	for cell: Dictionary in cells:
		for item: Dictionary in cell.coins:
			result = maxi(result, item.level)
	return result


func check_upgrade(new_level: int) -> Dictionary:
	highest_level = maxi(highest_level, new_level)
	var previous_stage := stage()
	if new_level < targets()[previous_stage]:
		return {}
	if previous_stage == 4:
		level += 1
		unlock_count = 5
		shuffle_left = 3
		guide_step = -1
		_init_random_board()
		return {"next_level": true, "unlocked": [], "stage": 0}
	var amount := 1 if previous_stage == 3 else 2
	unlock_count = mini(CELL_COUNT, unlock_count + amount)
	var unlocked: Array = []
	for index in range(CELL_COUNT):
		if cells[index].state in [CellState.LOCKED, CellState.REWARD, CellState.LOCK_AD] and unlocked.size() < amount:
			cells[index].state = CellState.UNLOCKABLE
			unlocked.append(index)
	return {"next_level": false, "unlocked": unlocked, "stage": previous_stage + 1}


func unlock_cell(index: int, earned: bool = false) -> bool:
	if index < 0 or index >= cells.size():
		return false
	var state: int = cells[index].state
	if state != CellState.UNLOCKABLE and not (state == CellState.REWARD and earned):
		return false
	cells[index].state = CellState.NORMAL
	normal_order.append(index)
	return true


func finish_tutorial() -> void:
	guide_step = -1
	_enable_reward_cell()


func _enable_reward_cell() -> void:
	for index in range(CELL_COUNT - 1, -1, -1):
		if cells[index].state == CellState.LOCKED:
			cells[index].state = CellState.REWARD
			break


func tutorial_deal() -> Dictionary:
	var result := {}
	for index in range(3):
		var count := 4 if index == 1 else (3 if index == 0 else 1)
		var incoming: Array = []
		for offset in range(count):
			incoming.append(coin(2))
		result[index] = incoming
		cells[index].coins.append_array(incoming)
	return result


func can_deal() -> bool:
	return normal_order.any(func(index: int) -> bool: return cells[index].coins.size() < CAPACITY)


func _weighted(table: Array) -> Variant:
	var total := 0
	for row: Array in table:
		total += int(row[1])
	var value := rng.randi_range(1, total)
	for row: Array in table:
		value -= int(row[1])
		if value <= 0:
			return row[0]
	return table[0][0]


func _deal_seeds(count: int, existing: Array, maximum: int) -> Array:
	var seeds := existing.slice(0, count)
	for value in range(base_level(), maximum):
		if seeds.size() >= count:
			break
		if value not in existing:
			seeds.append(value)
	if seeds.is_empty():
		seeds.append(base_level())
	var offset := 0
	while seeds.size() < count:
		seeds.append(seeds[offset])
		offset += 1
	return seeds


func _need_levels(seed_value: int, extra: int, maximum: int) -> Array:
	var result: Array = [seed_value]
	var candidates: Array = []
	for value in range(base_level(), maximum):
		if value != seed_value:
			candidates.append(value)
	for offset in range(extra):
		# 极端/损坏盘面的候选不足时保留合法等级，不生成空币。
		result.append(seed_value if candidates.is_empty() else candidates.pop_at(rng.randi_range(0, candidates.size() - 1)))
	return result


func deal() -> Dictionary:
	var candidates: Array = []
	var occupied: Array = []
	var existing: Array = []
	var maximum := maximum_level()
	if level == 1 and maximum <= 4:
		maximum = 5
	for index: int in normal_order:
		var stack: Array = cells[index].coins
		for item: Dictionary in stack:
			if item.level != maximum and item.level not in existing:
				existing.append(item.level)
		if stack.size() < CAPACITY:
			candidates.append(index)
			if not stack.is_empty():
				occupied.append(index)
	if candidates.size() > 1:
		var skip_pool := occupied if not occupied.is_empty() else candidates
		candidates.erase(skip_pool[rng.randi_range(0, skip_pool.size() - 1)])
	var counts: Array = []
	for index: int in candidates:
		counts.append(mini(CAPACITY - cells[index].coins.size(), int(_weighted(COUNT_TABLES[stage()]))))
	var seeds := _deal_seeds(candidates.size(), existing, maximum)
	var result := {}
	for offset in range(candidates.size()):
		var index: int = candidates[offset]
		var count: int = counts[offset]
		var seed_value: int = seeds[offset]
		var incoming: Array = []
		if count == 1:
			incoming.append(coin(seed_value))
		else:
			var pattern: String = _weighted(GROUP_TABLES[stage()])
			var type_count := 1
			for position in range(count):
				type_count = maxi(type_count, int(pattern[position]))
			var hidden := level > 1 and count == 4
			var values := _need_levels(seed_value, 1 if hidden else type_count - 1, maximum)
			for position in range(count):
				if hidden:
					incoming.append(coin(values[0 if position < 3 else 1], position < 3))
				else:
					incoming.append(coin(values[int(pattern[position]) - 1]))
		result[index] = incoming
		cells[index].coins.append_array(incoming)
	return result


func is_failed() -> bool:
	for index: int in normal_order:
		if cells[index].coins.size() < CAPACITY or can_merge(index):
			return false
	return true


func rescue(earned: bool = false) -> bool:
	if not is_failed() or shuffle_left <= 0 or (shuffle_left < 3 and not earned):
		return false
	var groups := {}
	var available: Array = []
	for index: int in normal_order:
		if can_merge(index):
			continue
		available.append(index)
		for item: Dictionary in cells[index].coins:
			if not groups.has(item.level):
				groups[item.level] = []
			groups[item.level].append(coin(item.level))
		cells[index].coins = []
	var values: Array = groups.keys()
	values.sort()
	values.reverse()
	for value: int in values:
		var group: Array = groups[value]
		while not group.is_empty() and not available.is_empty():
			var index: int = available.pop_back()
			cells[index].coins = group.slice(0, CAPACITY)
			group = group.slice(CAPACITY)
	shuffle_left -= 1
	return true


func snapshot() -> Dictionary:
	return {"version": SAVE_VERSION, "level": level, "unlock_count": unlock_count,
		"highest_level": highest_level, "shuffle_left": shuffle_left, "guide_step": guide_step,
		"cells": cells.duplicate(true), "normal_order": normal_order.duplicate()}


func restore(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != SAVE_VERSION:
		return false
	for key: String in ["level", "unlock_count", "highest_level", "shuffle_left", "guide_step"]:
		if not _is_integer(data.get(key)):
			return false
	if data.level < 1 or data.level > 100000 or data.unlock_count < 5 or data.unlock_count > CELL_COUNT:
		return false
	if data.highest_level < 1 or data.shuffle_left < 0 or data.shuffle_left > 3 or data.guide_step < -1 or data.guide_step > 10:
		return false
	if not data.get("cells") is Array or data.cells.size() != CELL_COUNT or not data.get("normal_order") is Array:
		return false
	var restored: Array = []
	var playable: Array = []
	for index in range(CELL_COUNT):
		var cell = data.cells[index]
		if not cell is Dictionary or not _is_integer(cell.get("state")) or cell.state < 0 or cell.state > CellState.LOCK_AD:
			return false
		if not cell.get("coins") is Array or cell.coins.size() > CAPACITY:
			return false
		var stack: Array = []
		for item in cell.coins:
			if not item is Dictionary or not _is_integer(item.get("level")) or item.level < 1 or item.level > 1000000 or not item.get("hidden") is bool:
				return false
			stack.append(coin(int(item.level), item.hidden))
		var state := int(cell.state)
		if state == CellState.USING_AD:
			state = CellState.NORMAL
		if state != CellState.NORMAL and not stack.is_empty():
			return false
		if state == CellState.NORMAL:
			playable.append(index)
		restored.append({"state": state, "coins": stack})
	var order: Array = []
	for index in data.normal_order:
		if not _is_integer(index) or int(index) not in playable or int(index) in order:
			return false
		order.append(int(index))
	if order.size() != playable.size() or order.size() < 5:
		return false
	level = int(data.level)
	unlock_count = int(data.unlock_count)
	highest_level = int(data.highest_level)
	shuffle_left = int(data.shuffle_left)
	guide_step = int(data.guide_step)
	cells = restored
	normal_order = order
	return true


static func _is_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))


func load_game(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	return restore(JSON.parse_string(file.get_as_text()))


func save_game(path: String = SAVE_PATH) -> bool:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(snapshot()))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path)) == OK
