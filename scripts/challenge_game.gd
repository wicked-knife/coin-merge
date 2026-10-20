extends RefCounted
## Challenge rules. Coin arrays run from the bottom to the playable top.

const Data = preload("res://scripts/challenge_data.gd")
const CAPACITY := 10
const SAVE_PATH := "user://challenge_game.json"
const SAVE_VERSION := 1
static var requested_level := 1

var cells: Array = []
var level := 1
var elapsed := 0.0
# Retained for v1 save/UI compatibility; tutorial eligibility uses records and the board.
var tutorial_done := false
var tutorial := false
var finished := false
var best_times: Dictionary = {}
var gold := 0
var started_at := 0.0
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


static func coin(value: int, hidden: bool = false) -> Dictionary:
	return {"level": value, "hidden": hidden}


static func config(number: int) -> Dictionary:
	return Data.LEVELS[number - 1] if number >= 1 and number <= Data.LEVELS.size() else {}


static func is_unlocked(number: int, highest_coin: int) -> bool:
	return not config(number).is_empty() and config(number).unlock <= highest_coin


static func unlock_boundary(highest_coin: int) -> int:
	for number in range(1, Data.LEVELS.size() + 1):
		if not is_unlocked(number, highest_coin):
			return number
	return Data.LEVELS.size() + 1


func status(number: int, highest_coin: int) -> String:
	if not is_unlocked(number, highest_coin):
		return "locked"
	if number == level and not cells.is_empty() and not finished:
		return "doing"
	return "complete" if best_times.has(str(number)) else "play"


func start(number: int, allow_tutorial: bool = true) -> bool:
	if config(number).is_empty():
		return false
	var has_formal_board := not cells.is_empty() and not tutorial and not finished
	var needs_tutorial := allow_tutorial and number == 1 and not best_times.has("1") and not has_formal_board
	level = number
	elapsed = 0.0
	finished = false
	started_at = Time.get_unix_time_from_system() * 1000.0
	tutorial = needs_tutorial
	if tutorial:
		cells = [
			{"state": 0, "target": 1, "coins": _stack([1, 1, 1, 1, 1, 1, 1, 2, 2, 2])},
			{"state": 0, "target": 2, "coins": _stack([1, 1, 1, 2, 2, 2, 2, 2, 2, 2])},
			{"state": 4, "target": 0, "coins": []},
		]
	else:
		cells = _generate(config(number))
	return true


static func _stack(values: Array) -> Array:
	var result: Array = []
	for value: int in values:
		result.append(coin(value))
	return result


func dimensions() -> Vector2i:
	if tutorial:
		return Vector2i(3, 1)
	var area := config(level)
	return Vector2i(area.columns, area.rows) if not area.is_empty() else Vector2i.ZERO


func selected_count(index: int) -> int:
	if index < 0 or index >= cells.size() or is_tick(index) or finished:
		return 0
	var stack: Array = cells[index].coins
	if stack.is_empty():
		return 0
	var count := 1
	for offset in range(stack.size() - 2, -1, -1):
		if stack[offset].level != stack.back().level or stack[offset].hidden:
			break
		count += 1
	return count


static func _all_known_same(stack: Array) -> bool:
	if stack.is_empty():
		return false
	for item: Dictionary in stack:
		if item.hidden or item.level != stack[0].level:
			return false
	return true


func is_tick(index: int) -> bool:
	var cell: Dictionary = cells[index]
	return cell.target > 0 and cell.coins.size() == CAPACITY and _all_known_same(cell.coins) and cell.coins[0].level == cell.target


func completed_count() -> int:
	var count := 0
	for index in range(cells.size()):
		if is_tick(index):
			count += 1
	return count


func target_count() -> int:
	var count := 0
	for cell: Dictionary in cells:
		if cell.target > 0:
			count += 1
	return count


func is_won() -> bool:
	return not cells.is_empty() and target_count() > 0 and completed_count() == target_count()


func move(source: int, target: int) -> Dictionary:
	if source == target or target < 0 or target >= cells.size() or is_tick(target):
		return {}
	var count := selected_count(source)
	if count == 0:
		return {}
	var from: Array = cells[source].coins
	var to: Array = cells[target].coins
	var value: int = from.back().level
	var free := CAPACITY - to.size()
	if free > 0 and (to.is_empty() or to.back().level == value):
		count = mini(count, free)
		var moved := from.slice(from.size() - count)
		from.resize(from.size() - count)
		to.append_array(moved)
		var revealed: Array = []
		for offset in range(from.size() - 1, -1, -1):
			if not from[offset].hidden:
				break
			from[offset].hidden = false
			revealed.append(offset)
		return {"kind": "move", "count": count, "revealed": revealed}
	if count == from.size() and _all_known_same(to) and to[0].level != value:
		cells[source].coins = to
		cells[target].coins = from
		return {"kind": "swap", "count": count, "other_count": to.size(), "revealed": []}
	return {}


func advance_time(delta: float) -> void:
	if not tutorial and not finished and not cells.is_empty() and is_finite(delta) and delta > 0:
		elapsed += delta


func finish() -> Dictionary:
	if finished or not is_won():
		return {}
	if tutorial:
		tutorial_done = true
		start(1, false)
		return {"tutorial": true}
	var key := str(level)
	var first := not best_times.has(key)
	var record := first or elapsed < float(best_times[key])
	if record:
		best_times[key] = elapsed
	if first:
		gold += 1
	finished = true
	return {"tutorial": false, "first": first, "record": record, "time": elapsed, "best": best_times[key]}


static func format_time(seconds: float) -> String:
	var total := maxi(0, floori(seconds))
	if total >= 86400:
		return _time_part(total / 86400, "time.day")
	if total >= 3600:
		return _time_part(total / 3600, "time.hour")
	return "%02d:%02d" % [total / 60, total % 60]


static func format_result_time(seconds: float) -> String:
	var total := maxi(0, floori(seconds))
	if total >= 86400:
		return _time_part(total / 86400, "time.day") + _time_part((total / 3600) % 24, "time.hour")
	if total >= 3600:
		return _time_part(total / 3600, "time.hour") + _time_part((total / 60) % 60, "time.min")
	if total >= 60:
		return _time_part(total / 60, "time.min") + _time_part(total % 60, "time.sec")
	return _time_part(total, "time.sec")


static func _time_part(amount: int, key: String) -> String:
	var text := "%d%s" % [amount, TranslationServer.translate(key)]
	return "\u2066" + text + "\u2069" if TranslationServer.get_locale() == "ar" else text


static func completed_cells(number: int) -> Array:
	var result: Array = []
	var area := config(number)
	if area.is_empty():
		return result
	for target: int in area.targets:
		var stack: Array = []
		if target > 0:
			for offset in range(CAPACITY):
				stack.append(coin(target))
		result.append({"state": 0, "target": target, "coins": stack})
	return result


func _generate(area: Dictionary) -> Array:
	var result: Array = []
	var stock: Dictionary = {}
	var positions: Array = []
	for target: int in area.targets:
		if target > 0:
			stock[target] = stock.get(target, 0) + CAPACITY
			positions.append(result.size())
		result.append({"state": 0, "target": target, "coins": []})
	var hidden_count := rng.randi_range(area.hidden[0], area.hidden[1])
	_shuffle(positions)
	var hidden_positions: Dictionary = {}
	for index: int in positions.slice(0, hidden_count):
		var color := _choose_color(stock, 3)
		if color == 0:
			break
		_append_stock(result[index].coins, stock, color, 3, true)
		hidden_positions[index] = true
		var size := _group_size()
		var other := _choose_color(stock, size, color)
		if other == 0:
			other = _choose_color(stock, 1, color)
			size = mini(CAPACITY - 3, stock.get(other, 0))
		if other > 0:
			_append_stock(result[index].coins, stock, other, size)
	var pure: Array = []
	var mixed: Array = []
	for index in range(result.size()):
		if result[index].target <= 0:
			continue
		var stack: Array = result[index].coins
		for attempt in range(50):
			if stack.size() >= CAPACITY:
				break
			var color := _choose_color(stock)
			if color == 0:
				break
			_append_stock(stack, stock, color, mini(_group_size(), CAPACITY - stack.size()))
		# A defensive fallback preserves inventory if the captured 50-round cap is reached.
		while stack.size() < CAPACITY:
			var color := _choose_color(stock)
			if color == 0:
				break
			_append_stock(stack, stock, color, CAPACITY - stack.size())
		var colors: Dictionary = {}
		for item: Dictionary in stack:
			colors[item.level] = true
		if not hidden_positions.has(index):
			if colors.size() == 1:
				pure.append(index)
			elif colors.size() >= 3:
				mixed.append(index)
	# Captured heuristic: trade corresponding coins between pure and mixed stacks.
	for offset in range(mini(pure.size(), mixed.size())):
		var from: Array = result[pure[offset]].coins
		var to: Array = result[mixed[offset]].coins
		var other := 0
		for item: Dictionary in to:
			if item.level != from[0].level:
				other = item.level
				break
		for index in range(mini(from.size(), to.size())):
			if to[index].level == other:
				var value: int = from[index].level
				from[index].level = other
				to[index].level = value
	return result


func _append_stock(stack: Array, stock: Dictionary, color: int, count: int, hidden: bool = false) -> void:
	count = mini(count, stock.get(color, 0))
	for index in range(count):
		stack.append(coin(color, hidden))
	stock[color] -= count


func _choose_color(stock: Dictionary, minimum: int = 1, except_color: int = 0) -> int:
	var total := 0
	for color: int in stock:
		if color != except_color and stock[color] >= minimum:
			total += stock[color]
	if total <= 0:
		return 0
	var roll := rng.randi_range(1, total)
	for color: int in stock:
		if color != except_color and stock[color] >= minimum:
			roll -= int(stock[color])
			if roll <= 0:
				return color
	return 0


func _group_size() -> int:
	var table: Array = Data.GROUP_WEIGHTS[mini(level, 6) - 1]
	var total := 0
	for entry: Array in table:
		total += entry[1]
	var roll := rng.randi_range(1, total)
	for entry: Array in table:
		roll -= int(entry[1])
		if roll <= 0:
			return entry[0]
	return 1


func _shuffle(values: Array) -> void:
	for index in range(values.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var value = values[index]
		values[index] = values[other]
		values[other] = value


func snapshot() -> Dictionary:
	var board: Array = []
	if not finished and not tutorial:
		for cell: Dictionary in cells:
			var stack: Array = []
			for item: Dictionary in cell.coins:
				stack.append([item.level, true] if item.hidden else item.level)
			board.append([cell.state, stack])
	return {"version": SAVE_VERSION, "level": mini(level + 1, Data.LEVELS.size() + 1) if finished else level, "elapsed": elapsed if not finished and not tutorial else 0.0,
		"tutorial_done": tutorial_done, "tutorial": false, "best_times": best_times.duplicate(),
		"gold": gold, "started_at": started_at, "cells": board}


static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= low and value <= high


static func _seconds(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0


func restore(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != SAVE_VERSION:
		return false
	if not _integer(data.get("level"), 1, Data.LEVELS.size() + 1) or not _seconds(data.get("elapsed")):
		return false
	if not data.get("tutorial_done") is bool or not data.get("tutorial") is bool or (data.tutorial and (data.tutorial_done or data.level != 1)):
		return false
	if not _integer(data.get("gold"), 0, 1000000) or not _seconds(data.get("started_at")) or not data.get("best_times") is Dictionary:
		return false
	var records: Dictionary = {}
	for key: Variant in data.best_times:
		if not key is String or not key.is_valid_int() or str(int(key)) != key or not _integer(int(key), 1, Data.LEVELS.size()) or not _seconds(data.best_times[key]):
			return false
		records[key] = float(data.best_times[key])
	var restored: Array = []
	# Teaching boards from older v1 saves are deliberately discarded. The original
	# tutorial has no resumable board, and the 101 marker has no level configuration.
	if not data.tutorial and int(data.level) <= Data.LEVELS.size():
		restored = _restore_board(data.get("cells"), config(int(data.level)).targets)
	level = int(data.level)
	elapsed = float(data.elapsed) if not restored.is_empty() else 0.0
	tutorial_done = data.tutorial_done
	tutorial = false
	best_times = records
	gold = int(data.gold)
	started_at = float(data.started_at)
	cells = restored
	finished = false
	return true


static func _restore_board(board: Variant, targets: Array) -> Array:
	if not board is Array or board.size() != targets.size():
		return []
	var result: Array = []
	var inventory: Dictionary = {}
	var expected: Dictionary = {}
	for index in range(targets.size()):
		if targets[index] > 0:
			expected[targets[index]] = expected.get(targets[index], 0) + CAPACITY
		var entry = board[index]
		if not entry is Array or entry.size() != 2 or not _integer(entry[0], 0, 4) or int(entry[0]) not in [0, 4] or not entry[1] is Array or entry[1].size() > CAPACITY:
			return []
		var stack: Array = []
		for raw: Variant in entry[1]:
			var value: Variant = raw
			var hidden := false
			if raw is Array:
				if raw.size() != 2 or not raw[1] is bool or not raw[1]:
					return []
				value = raw[0]
				hidden = true
			if not _integer(value, 1, 11):
				return []
			stack.append(coin(int(value), hidden))
			inventory[int(value)] = inventory.get(int(value), 0) + 1
		result.append({"state": int(entry[0]), "target": int(targets[index]), "coins": stack})
	return result if inventory == expected else []


func load_game(path: String = SAVE_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	return file != null and restore(JSON.parse_string(file.get_as_text()))


func save_game(path: String = SAVE_PATH) -> bool:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(snapshot()))
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK and DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path)) == OK
