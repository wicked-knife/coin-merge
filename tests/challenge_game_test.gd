extends SceneTree

const Rules = preload("res://scripts/challenge_game.gd")
const SAVE := "user://challenge_rules_test.json"
var checks := 0
var failures := 0


func _initialize() -> void:
	_test_tables_and_generation()
	_test_time_formats()
	_test_movement()
	_test_tutorial_and_completion()
	_test_saves()
	print("CHALLENGE RULES: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _inventory(cells: Array) -> Dictionary:
	var result: Dictionary = {}
	for cell: Dictionary in cells:
		for item: Dictionary in cell.coins:
			result[item.level] = result.get(item.level, 0) + 1
	return result


func _test_tables_and_generation() -> void:
	var original: Array = JSON.parse_string(FileAccess.get_file_as_string("res://docs/rea-reference/challenge-levels-expanded.json"))
	expect(Rules.Data.LEVELS.size() == 100, "all 100 captured challenges are embedded")
	var game := Rules.new()
	for number in range(1, 101):
		var area := Rules.config(number)
		var reference: Dictionary = original[number - 1]
		expect(area.columns == reference.runtime_columns_from_code and area.rows == reference.runtime_rows_from_code, "captured orientation %d" % number)
		var reference_targets: Array = reference.target_layout_linear.map(func(value: Variant) -> int: return int(value))
		expect(area.targets == reference_targets and area.unlock == reference.config.unlockNumeral, "exact captured layout and unlock %d" % number)
		for sample in range(5):
			game.rng.seed = number * 100 + sample
			game.start(number, false)
			var ordered_rng := RandomNumberGenerator.new()
			ordered_rng.seed = number * 100 + sample
			var expected_hidden_count := ordered_rng.randi_range(area.hidden[0], area.hidden[1])
			var shuffled_positions: Array = []
			for index in range(area.targets.size()):
				if area.targets[index] > 0:
					shuffled_positions.append(index)
			for index in range(shuffled_positions.size() - 1, 0, -1):
				var other := ordered_rng.randi_range(0, index)
				var position: int = shuffled_positions[index]
				shuffled_positions[index] = shuffled_positions[other]
				shuffled_positions[other] = position
			var expected_hidden_positions: Array = shuffled_positions.slice(0, expected_hidden_count)
			expected_hidden_positions.sort()
			var expected: Dictionary = {}
			for target: int in area.targets:
				if target > 0:
					expected[target] = expected.get(target, 0) + 10
			expect(game.cells.size() == area.columns * area.rows, "correct board size %d/%d" % [number, sample])
			expect(_inventory(game.cells) == expected, "exact per-color inventory %d/%d" % [number, sample])
			var hidden_groups := 0
			var actual_hidden_positions: Array = []
			var valid := true
			for index in range(game.cells.size()):
				var cell: Dictionary = game.cells[index]
				valid = valid and cell.coins.size() == (10 if cell.target > 0 else 0)
				var hidden := 0
				for item: Dictionary in cell.coins:
					if item.hidden:
						hidden += 1
				valid = valid and hidden in [0, 3]
				if not cell.coins.is_empty():
					valid = valid and not cell.coins.back().hidden
				if hidden == 3:
					hidden_groups += 1
					actual_hidden_positions.append(index)
			expect(valid, "filled targets, empty neutral cells and visible tops %d/%d" % [number, sample])
			expect(hidden_groups >= area.hidden[0] and hidden_groups <= area.hidden[1], "captured hidden group bounds %d/%d" % [number, sample])
			expect(actual_hidden_positions == expected_hidden_positions, "hidden count consumes randomness before position shuffle %d/%d" % [number, sample])
	expect(Rules.unlock_boundary(7) == 2 and Rules.unlock_boundary(8) == 3 and Rules.unlock_boundary(598) == 101, "unlock boundary uses historical coin level")
	expect(not Rules.is_unlocked(0, 1000) and not Rules.is_unlocked(101, 1000), "out-of-range levels remain unavailable")
	expect(Rules.completed_cells(101).is_empty(), "the wait entry has no playable completed board")


func _test_time_formats() -> void:
	var previous_locale := TranslationServer.get_locale()
	for locale: String in ["zh", "en"]:
		var units: Array = ["天", "时", "分", "秒"] if locale == "zh" else ["d", "h", "m", "s"]
		var reference_translation := Translation.new()
		reference_translation.locale = locale
		for index in range(4):
			reference_translation.add_message(["time.day", "time.hour", "time.min", "time.sec"][index], units[index])
		TranslationServer.add_translation(reference_translation)
		TranslationServer.set_locale(locale)
		expect(Rules.format_time(0) == "00:00" and Rules.format_time(65.9) == "01:05" and Rules.format_time(3599) == "59:59", "in-game timer retains MM:SS below one hour: " + locale)
		expect(Rules.format_time(3600) == "1" + units[1] and Rules.format_time(86399) == "23" + units[1], "in-game timer displays whole hours: " + locale)
		expect(Rules.format_time(86400) == "1" + units[0] and Rules.format_time(172861) == "2" + units[0], "in-game timer displays whole days: " + locale)
		expect(Rules.format_result_time(0) == "0" + units[3] and Rules.format_result_time(59.9) == "59" + units[3], "results display seconds below one minute: " + locale)
		expect(Rules.format_result_time(60) == "1" + units[2] + "0" + units[3] and Rules.format_result_time(65.9) == "1" + units[2] + "5" + units[3], "results display localized minutes and seconds: " + locale)
		expect(Rules.format_result_time(3601) == "1" + units[1] + "0" + units[2] and Rules.format_result_time(86399) == "23" + units[1] + "59" + units[2], "results display hours and minutes: " + locale)
		expect(Rules.format_result_time(90061) == "1" + units[0] + "1" + units[1] and Rules.format_result_time(172861) == "2" + units[0] + "0" + units[1], "results display days and hours: " + locale)
		TranslationServer.remove_translation(reference_translation)
	TranslationServer.set_locale(previous_locale)


func _cell(values: Array, target: int = 0) -> Dictionary:
	var coins: Array = []
	for value: Variant in values:
		coins.append(Rules.coin(value[0], value[1]) if value is Array else Rules.coin(value))
	return {"state": 0, "target": target, "coins": coins}


func _test_movement() -> void:
	var game := Rules.new()
	game.cells = [_cell([1, 2, 2, 2]), _cell([3, 2, 2, 2, 2, 2, 2, 2, 2]), _cell([])]
	expect(game.selected_count(0) == 3, "only the contiguous top segment is selected")
	var before := _inventory(game.cells)
	var result := game.move(0, 1)
	expect(result.get("count") == 1 and game.cells[0].coins.size() == 3 and game.cells[1].coins.size() == 10, "partial movement fills the last free space")
	expect(not game.is_tick(1) and game.cells[1].coins.size() == 10, "mixed full stack does not tick or merge")
	expect(_inventory(game.cells) == before, "partial movement preserves all coins")
	game.cells = [_cell([1, [3, true], [4, true], 2, 2]), _cell([])]
	result = game.move(0, 1)
	expect(result.revealed == [2, 1] and not game.cells[0].coins[1].hidden and not game.cells[0].coins[2].hidden, "exposure reveals the complete hidden segment, including different colors")
	game.cells = [_cell([2, [2, true], 2, 2]), _cell([])]
	expect(game.selected_count(0) == 2, "hidden coin is a selection boundary")
	game.cells = [_cell([1, 1, 1], 2), _cell([2, 2, 2, 2, 2, 2, 2], 1)]
	result = game.move(0, 1)
	expect(result.get("kind") == "swap" and game.cells[0].coins.size() == 7 and game.cells[1].coins.size() == 3, "unequal pure-color stacks swap in their entirety")
	expect(game.cells[0].coins[0].level == 2 and game.cells[1].coins[0].level == 1, "swap retains the fixed slot targets")
	game.cells = [_cell([3, 1, 1]), _cell([2, 2])]
	expect(game.move(0, 1).is_empty(), "a top segment cannot swap over other colors")
	game.cells = [_cell([1, 1]), _cell([3, 2, 2])]
	expect(game.move(0, 1).is_empty(), "a mixed target cannot swap")
	game.cells = [_cell([1, 1]), _cell([[2, true], 2])]
	expect(game.move(0, 1).is_empty(), "hidden target coins cannot swap")
	game.cells = [_cell([1, 1, 1, 1, 1, 1, 1, 1, 1, 1], 2), _cell([])]
	expect(not game.is_tick(0) and game.selected_count(0) == 10, "ten coins in the wrong target stay available without upgrading")
	game.cells[0].target = 1
	expect(game.is_tick(0) and game.selected_count(0) == 0 and game.move(0, 1).is_empty(), "a completed target is locked as a source")
	game.cells[1] = _cell([2, 2])
	expect(game.move(1, 0).is_empty(), "a completed target cannot participate in swaps")
	game.cells[0].coins[0].hidden = true
	expect(not game.is_tick(0), "hidden coins prevent target completion")
	game.start(1, false)
	before = _inventory(game.cells)
	for attempt in range(2000):
		var from := game.rng.randi_range(0, game.cells.size() - 1)
		var to := game.rng.randi_range(0, game.cells.size() - 1)
		game.move(from, to)
	expect(_inventory(game.cells) == before, "two thousand random move/swap attempts preserve the original inventory")
	for cell: Dictionary in game.cells:
		expect(cell.coins.size() <= 10, "movement never exceeds capacity")


func _test_tutorial_and_completion() -> void:
	var game := Rules.new()
	game.start(1)
	game.advance_time(30)
	expect(game.tutorial and game.cells.size() == 3 and game.elapsed == 0, "first challenge uses the untimed three-slot tutorial")
	for pair: Array in [[0, 2], [1, 2], [1, 0], [2, 1]]:
		expect(not game.move(pair[0], pair[1]).is_empty(), "the documented tutorial solution is playable")
	expect(game.is_won(), "tutorial finishes both colored targets")
	var result := game.finish()
	expect(result.get("tutorial", false) and game.tutorial_done and not game.tutorial and game.cells.size() == 30, "tutorial completion transitions to the real first challenge")
	expect(game.gold == 0 and game.best_times.is_empty() and game.elapsed == 0, "tutorial grants no first-level reward or record")
	game.advance_time(65.5)
	game.cells = Rules.completed_cells(1)
	result = game.finish()
	expect(result.first and result.record and game.gold == 1 and game.best_times["1"] == 65.5, "first completion awards one gold and stores elapsed seconds")
	game.advance_time(100)
	expect(game.elapsed == 65.5 and game.finish().is_empty() and game.gold == 1, "completion stops time and is idempotent")
	expect(game.snapshot().cells.is_empty() and game.snapshot().level == 2, "winning clears the saved board and advances the current level")
	game.start(1, false)
	game.elapsed = 80
	game.cells = Rules.completed_cells(1)
	result = game.finish()
	expect(not result.first and not result.record and game.gold == 1 and game.best_times["1"] == 65.5, "slower replays preserve the best time and grant no gold")
	game.start(1, false)
	game.elapsed = 45
	game.cells = Rules.completed_cells(1)
	result = game.finish()
	expect(not result.first and result.record and game.gold == 1 and game.best_times["1"] == 45, "faster replays update only the record")
	game.start(100, false)
	game.cells = Rules.completed_cells(100)
	expect(not game.finish().is_empty() and game.snapshot().level == 101 and game.snapshot().cells.is_empty(), "last completion saves the original level-101 wait marker without a board")
	var restored := Rules.new()
	expect(restored.restore(game.snapshot()) and restored.level == 101 and restored.cells.is_empty() and restored.dimensions() == Vector2i.ZERO, "level-101 marker restores without accessing a nonexistent configuration")
	expect(game.save_game(SAVE) and restored.load_game(SAVE) and restored.level == 101 and restored.cells.is_empty() and restored.best_times.has("100"), "last completion survives a disk round trip with the wait marker and final record")
	expect(not restored.start(101) and restored.level == 101 and restored.snapshot().level == 101, "wait marker cannot start or advance into an extra challenge")


func _test_saves() -> void:
	var game := Rules.new()
	game.start(1)
	game.move(0, 2)
	var restored := Rules.new()
	expect(game.snapshot().cells.is_empty() and not game.snapshot().tutorial and game.snapshot().elapsed == 0, "tutorial snapshots never save a teaching board or timer")
	expect(restored.restore(game.snapshot()) and restored.cells.is_empty() and not restored.tutorial, "exiting the tutorial leaves no resumable board")
	expect(game.save_game(SAVE) and restored.load_game(SAVE) and restored.cells.is_empty() and not restored.tutorial, "automatic tutorial saves retain metadata without persisting teaching progress")
	expect(restored.start(1) and restored.tutorial and restored.cells[0].coins.size() == 10 and restored.cells[2].coins.is_empty(), "returning to an incomplete tutorial starts it again")
	var legacy_tutorial := game.snapshot()
	legacy_tutorial.tutorial = true
	legacy_tutorial.best_times = {"2": 75.1}
	legacy_tutorial.gold = 1
	legacy_tutorial.cells = []
	for cell: Dictionary in game.cells:
		var stack: Array = []
		for item: Dictionary in cell.coins:
			stack.append([item.level, true] if item.hidden else item.level)
		legacy_tutorial.cells.append([cell.state, stack])
	expect(restored.restore(legacy_tutorial) and restored.cells.is_empty() and not restored.tutorial and restored.best_times == {"2": 75.1} and restored.gold == 1, "old v1 teaching snapshots clear only the teaching board and preserve records and gold")
	legacy_tutorial.tutorial = false
	legacy_tutorial.tutorial_done = true
	legacy_tutorial.cells = []
	expect(restored.restore(legacy_tutorial) and restored.start(1) and restored.tutorial, "legacy tutorial-done flag cannot block teaching when record 1 and a formal board are absent")
	restored.best_times["1"] = 45.0
	restored.cells.clear()
	expect(restored.start(1) and not restored.tutorial and restored.cells.size() == 30, "a best time for challenge 1 bypasses teaching")
	var in_progress := Rules.new()
	in_progress.start(2, false)
	expect(in_progress.start(1) and not in_progress.tutorial and in_progress.cells.size() == 30, "an in-progress formal challenge also bypasses teaching when entering challenge 1")
	var tutorial_reentry := Rules.new()
	tutorial_reentry.start(1)
	tutorial_reentry.move(0, 2)
	expect(tutorial_reentry.start(1) and tutorial_reentry.tutorial and tutorial_reentry.cells[2].coins.is_empty(), "an in-memory teaching board does not count as formal progress")
	game.tutorial_done = true
	game.start(1, false)
	game.elapsed = 123.25
	game.best_times = {"2": 75.1}
	game.gold = 1
	expect(game.save_game(SAVE), "challenge snapshot writes atomically")
	expect(restored.load_game(SAVE) and restored.cells == game.cells and restored.elapsed == game.elapsed, "disk round trip preserves hidden coins, order, targets and elapsed time")
	expect(restored.best_times == game.best_times and restored.gold == 1, "records and first-completion gold survive a restart")
	var invalid := game.snapshot()
	invalid.cells.resize(1)
	expect(restored.restore(invalid) and restored.cells.is_empty() and restored.best_times == game.best_times, "wrong board dimensions discard the board while retaining records")
	invalid = game.snapshot()
	invalid.cells[0][1].pop_back()
	expect(restored.restore(invalid) and restored.cells.is_empty(), "invalid coin inventory cannot be resumed")
	invalid = game.snapshot()
	invalid.best_times = {"101": 42}
	expect(not restored.restore(invalid), "invalid record level is rejected")
	invalid = game.snapshot()
	invalid.elapsed = NAN
	expect(not restored.restore(invalid), "nonfinite elapsed time is rejected")
	invalid = game.snapshot()
	invalid.gold = -1
	expect(not restored.restore(invalid), "negative rewards are rejected")
	invalid = game.snapshot()
	invalid.level = 102
	expect(not restored.restore(invalid), "levels beyond the final wait marker are rejected")
	invalid = game.snapshot()
	invalid.level = 101
	expect(restored.restore(invalid) and restored.cells.is_empty() and restored.best_times == game.best_times and restored.elapsed == 0, "a board cannot attach to the level-101 wait marker while valid records are retained")
	invalid = game.snapshot()
	invalid.tutorial = true
	invalid.level = 101
	expect(not restored.restore(invalid), "the wait marker cannot contain a tutorial")
	expect(game.status(1, 1) == "doing" and game.status(2, 8) == "complete" and game.status(2, 1) == "locked" and game.status(3, 14) == "play", "selection distinguishes in-progress, completed, locked and playable")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
