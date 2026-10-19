extends SceneTree

const Rules = preload("res://scripts/normal_game.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func stack(values: Array) -> Array:
	return values.map(func(value: int) -> Dictionary: return Rules.coin(value))


func total(game: NormalGame) -> int:
	var result := 0
	for cell: Dictionary in game.cells:
		result += cell.coins.size()
	return result


func _run() -> void:
	_test_tutorial()
	_test_movement()
	_test_progress()
	_test_deal()
	_test_failure_and_rescue()
	_test_save()
	print("NORMAL RULES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _test_tutorial() -> void:
	var game := Rules.new()
	expect(game.cells.size() == 12 and game.normal_order.size() == 5, "tutorial has 12 cells, 5 playable")
	expect(total(game) == 10 and game.selected_count(0) == 5, "tutorial starts with two groups of five")
	var moved := game.move(0, 2)
	expect(moved.count == 5 and game.can_merge(2), "five plus five forms a merge")
	var merged := game.merge_ready()
	expect(merged.size() == 1 and game.cells[2].coins == stack([2, 2]), "ten level 1 becomes two level 2")
	game.tutorial_deal()
	expect(game.cells[0].coins.size() == 3 and game.cells[1].coins.size() == 4 and game.cells[2].coins.size() == 3, "tutorial fixed deal is 3/4/3")
	game.move(0, 1)
	game.move(2, 1)
	game.merge_ready()
	expect(game.cells[1].coins == stack([3, 3]), "tutorial second merge produces two level 3")
	game.finish_tutorial()
	expect(game.guide_step == -1 and game.cells[11].state == Rules.CellState.REWARD, "tutorial completion enables reward slot")


func _test_movement() -> void:
	var game := Rules.new()
	game.cells[0].coins = stack([1, 2, 2, 3, 3, 3])
	expect(game.selected_count(0) == 3, "selection only includes continuous matching top coins")
	game.cells[0].coins = [Rules.coin(1), Rules.coin(2), Rules.coin(2, true), Rules.coin(2), Rules.coin(2)]
	expect(game.selected_count(0) == 2, "hidden coin stops selection")
	game.cells[1].coins = stack([3])
	var before := game.snapshot()
	expect(game.move(0, 1).is_empty() and game.snapshot() == before, "different top is rejected without mutating board")
	expect(game.move(0, 5).is_empty(), "locked slot cannot receive coins")
	game.cells[0].coins = stack([1, 2, 2, 2, 2])
	game.cells[1].coins = stack([3, 3, 2, 2, 2, 2, 2, 2, 2])
	var moved := game.move(0, 1)
	expect(moved.count == 1 and game.cells[0].coins == stack([1, 2, 2, 2]), "partial transfer leaves untransferred coins in source")
	expect(game.cells[1].coins.size() == 10 and not game.can_merge(1), "full mixed slot does not merge")
	game.cells[0].coins = [Rules.coin(1), Rules.coin(4, true), Rules.coin(2, true), Rules.coin(3)]
	game.cells[1].coins = []
	moved = game.move(0, 1)
	expect(moved.revealed == [2, 1] and not game.cells[0].coins[1].hidden, "reveal entire exposed hidden segment across different levels")
	game.cells[0].coins = []
	for index in range(10):
		game.cells[0].coins.append(Rules.coin(2, index == 0))
	expect(not game.can_merge(0), "unknown coin prevents merge even when all levels match")
	game.cells[0].coins[0].hidden = false
	expect(game.can_merge(0), "all ten matching known coins can merge")


func _test_progress() -> void:
	var game := Rules.new()
	game.finish_tutorial()
	for target in [5, 6, 7, 9]:
		game.check_upgrade(target)
	expect(game.cells[11].state == Rules.CellState.UNLOCKABLE, "unopened reward slot becomes yellow on fourth goal")
	game.new_game()
	expect(game.targets() == [5, 6, 7, 9, 10], "first level five targets")
	game.finish_tutorial()
	var event := game.check_upgrade(5)
	expect(game.stage() == 1 and game.unlock_count == 7 and event.unlocked == [5, 6], "first stage grants two unlockable slots")
	expect(not game.is_playable(5) and game.unlock_cell(5) and game.is_playable(5), "unlock eligibility requires a click")
	expect(not game.unlock_cell(11), "reward slot requires earned callback")
	expect(game.unlock_cell(11, true), "reward callback opens slot permanently")
	game.check_upgrade(6)
	game.check_upgrade(7)
	expect(game.stage() == 3 and game.unlock_count == 11, "stage unlock counts 5 -> 7 -> 9 -> 11")
	expect(game.check_upgrade(8).is_empty() and game.stage() == 3, "level 8 does not fulfill target 9")
	game.check_upgrade(9)
	expect(game.stage() == 4 and game.unlock_count == 12, "fourth target adds the last unlock count")
	event = game.check_upgrade(10)
	expect(event.next_level and game.level == 2 and game.targets() == [11, 12, 13, 15, 16], "fifth target enters next major level")
	expect(game.shuffle_left == 3 and game.unlock_count == 5 and game.normal_order.size() == 6, "next level resets rescue count with level-dependent initial space")
	for level in [1, 2, 3, 4, 5, 6, 12]:
		game.level = level
		game.unlock_count = 5
		game.restart()
		expect(game.normal_order.size() == 5 + mini(3, floori(level / 2.0)), "initial playable cell count at level %d" % level)
		for cell: Dictionary in game.cells:
			for item: Dictionary in cell.coins:
				expect(not item.hidden, "initial board keeps published visible-coin behavior")
	game.level = 1
	game.unlock_count = 5
	game.restart()
	game.check_upgrade(100)
	expect(game.stage() == 1, "one upgrade call advances at most one stage")


func _test_deal() -> void:
	var full := Rules.new()
	for index: int in full.normal_order:
		full.cells[index].coins = stack([1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
	expect(not full.can_deal() and not full.is_failed(), "full mergeable board cannot deal before merging")
	for level in range(1, 7):
		for stage in range(5):
			var game := Rules.new()
			game.rng.seed = 12 + level * 100 + stage
			game.level = level
			game.unlock_count = [5, 7, 9, 11, 12][stage]
			game.restart()
			for turn in range(12):
				var old_total := total(game)
				var maximum := game.maximum_level()
				if level == 1 and maximum <= 4:
					maximum = 5
				var candidates := 0
				for index: int in game.normal_order:
					if game.cells[index].coins.size() < 10:
						candidates += 1
				var dealt := game.deal()
				expect(dealt.size() == maxi(0, candidates - 1) if candidates > 1 else dealt.size() == candidates, "deal skips exactly one eligible cell")
				var added := 0
				for index: int in dealt:
					added += dealt[index].size()
					for item: Dictionary in dealt[index]:
						expect(item.level >= game.base_level() and (item.level < maximum or maximum <= game.base_level()), "dealt coin remains in generation range")
					if level > 1 and dealt[index].size() == 4:
						expect(dealt[index][0].hidden and dealt[index][1].hidden and dealt[index][2].hidden and not dealt[index][3].hidden, "actual four-coin deal hides first three")
				expect(total(game) == old_total + added, "deal appends without dropping coins")
				for cell: Dictionary in game.cells:
					expect(cell.coins.size() <= 10, "deal never exceeds cell capacity")
				if game.is_failed():
					break
				game.merge_ready()
	# 只剩一个候选且只剩 4 位，计划数量被截断后仍触发隐藏。
	var game := Rules.new()
	game.level = 2
	game.restart()
	for index: int in game.normal_order:
		game.cells[index].coins = stack([7, 8, 7, 8, 7, 8, 7, 8, 7, 8])
	game.cells[0].coins.resize(6)
	game.unlock_count = 12
	var found := false
	for seed_value in range(50):
		game.rng.seed = seed_value
		game.cells[0].coins.resize(6)
		var dealt := game.deal()
		if dealt[0].size() == 4:
			found = dealt[0][0].hidden and not dealt[0][3].hidden
			break
	expect(found, "capacity-truncated four-coin batch retains hidden rule")


func _test_failure_and_rescue() -> void:
	var game := Rules.new()
	for index: int in game.normal_order:
		game.cells[index].coins = stack([1, 2, 1, 2, 1, 2, 1, 2, 1, 2])
	expect(game.is_failed(), "full mixed playable cells cause failure")
	game.cells[0].coins.pop_back()
	expect(not game.is_failed(), "one free space is enough to avoid failure")
	game.cells[0].coins.append(Rules.coin(2, true))
	expect(game.rescue() and game.shuffle_left == 2, "first rescue consumes one of three uses")
	for cell: Dictionary in game.cells:
		if not cell.coins.is_empty():
			var value: int = cell.coins[0].level
			for item: Dictionary in cell.coins:
				expect(item.level == value and not item.hidden, "rescue groups known coins by level")
	expect(game.cells[4].coins[0].level == 2, "rescue allocates descending levels into cells from end")
	for index: int in game.normal_order:
		game.cells[index].coins = stack([1, 2, 1, 2, 1, 2, 1, 2, 1, 2])
	expect(not game.rescue() and game.shuffle_left == 2, "unearned reward leaves remaining rescues unchanged")
	expect(game.rescue(true) and game.shuffle_left == 1, "successful reserved reward callback enables later rescue")
	game.level = 3
	game.unlock_count = 9
	game.highest_level = 14
	game.restart()
	expect(game.level == 3 and game.unlock_count == 9 and game.highest_level == 14 and game.shuffle_left == 3, "retry retains major progress and resets board/rescues")


func _test_save() -> void:
	var game := Rules.new()
	game.level = 2
	game.restart()
	game.deal()
	var snapshot := game.snapshot()
	var copy := Rules.new()
	expect(copy.restore(JSON.parse_string(JSON.stringify(snapshot))) and copy.snapshot() == snapshot, "JSON round trip preserves hidden coins, order and progress")
	expect(not copy.restore({"version": 1, "cells": []}), "incomplete save is rejected")
	expect(copy.snapshot() == snapshot, "invalid save does not partially overwrite state")
	var corrupt := snapshot.duplicate(true)
	corrupt.cells[0].coins = [Rules.coin(-1)]
	expect(not copy.restore(corrupt), "invalid coin level is rejected")
	var path := "user://normal_game_rule_test.json"
	expect(game.save_game(path), "save writes a snapshot")
	game.shuffle_left = 1
	expect(game.save_game(path), "atomic save replaces existing snapshot on Windows")
	expect(copy.load_game(path) and copy.shuffle_left == 1, "load reads latest saved state")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
