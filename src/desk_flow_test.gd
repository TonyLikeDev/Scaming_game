extends Node
## Drives the real desk scene through every button it has, on the real model, to check the interactive flow that the
## demos skip: clock in, answer, talk, hang up, clock out, the review, the next day, three strikes, being fired, New game.
## Nothing is typed by hand; each step presses a button (emits its signal) and waits for the screen to settle.
##
##   python scripts/godot_run.py --timeout 600 --log desk_flow -- scenes/desk_flow_test.tscn -- --mute --no_mic --save=user://desk_flow_save.json

var desk: Control
var failures := 0


func check(condition: bool, label: String) -> void:
	print(("ok    " if condition else "FAIL  ") + label)
	if not condition:
		failures += 1


func _ready() -> void:
	_run.call_deferred()


func settle(seconds := 0.2) -> void:
	await get_tree().create_timer(seconds).timeout


func wait_until(condition: Callable, timeout_s := 120.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return condition.call()


## Waits for the boss's review of the shift that was just clocked out of to be on the screen.
func await_review(timeout_s := 60.0) -> bool:
	return await wait_until(func(): return not desk._last_report.is_empty() and desk.shift == null and not desk._reviewing, timeout_s)


func _run() -> void:
	DirAccess.remove_absolute("user://desk_flow_save.json")
	desk = load("res://scenes/desk.tscn").instantiate()
	add_child(desk)
	await settle(1.5)  # the desk sets up voice input in its first frames

	check(desk.state.day == 1 and desk.state.strikes == 0, "a new game starts on day 1 with no strikes")
	check(desk._clock_button.text == "Clock in (day 1)" and not desk._clock_button.disabled, "the clock button offers to clock in on day 1")
	check(desk._call_button.disabled, "you cannot answer the phone before clocking in")
	check(desk._strikes_label.text == "Strikes: - - -" and desk._quota_label.text == "Quota $400", "the HUD shows no strikes and the day-1 quota")

	# Clock in, answer, speak, hang up
	desk._clock_button.pressed.emit()
	await settle()
	check(desk.shift != null and desk.shift.running, "clocking in starts the shift")
	check(desk._clock_button.text == "Clock out" and not desk._call_button.disabled, "now the button says Clock out and the phone can be answered")
	check(desk._clock_label.text == "8:00" or desk._clock_label.text == "7:59", "the clock shows about 8:00 (%s)" % desk._clock_label.text)
	desk._call_button.pressed.emit()
	await settle(0.1)
	check(desk._call_button.disabled, "the phone cannot be answered twice at once")
	check(await wait_until(func(): return desk.session != null and desk.session.active), "the caller picks up (loads the model the first time)")
	check(desk._line_edit.editable and not desk._hangup_button.disabled, "the text box and Hang up are live during a call")
	desk._line_edit.text = "Good evening ma'am, I'm calling about the extended warranty on your Moon."
	desk._on_send()
	await settle(0.1)
	check(await wait_until(func(): return not desk.session.thinking), "the caller answers")
	check(desk.session.turns == 1 and desk._transcript.get_parsed_text().contains("You:") and desk._transcript.get_parsed_text().contains(desk.session.persona["name"].split(" ")[0] + ":"), "the transcript shows both sides")
	var suspicion_before: int = int(desk._suspicion_bar.value)
	check(suspicion_before >= 0 and desk._suspicion_label.text.begins_with("%d" % suspicion_before), "the suspicion meter shows the caller's number")
	desk._hangup_button.pressed.emit()
	await settle()
	check(desk.session == null or not desk.session.active, "Hang up ends the call")
	check(desk.shift.stats.calls == 1 and desk.shift.stats.player_hang_ups == 1, "the shift counted one call that the player hung up")
	check(not desk._call_button.disabled and desk._line_edit.editable == false, "the phone can be answered again, the text box is closed")

	# Second call, then clock out in the middle of it
	desk._call_button.pressed.emit()
	await wait_until(func(): return desk.session != null and desk.session.active)
	check(desk.session.active, "a second call connects")
	desk._clock_button.pressed.emit()  # Clock out with the call still live
	check(await await_review(), "clocking out mid-call ends the shift and the boss's review appears")
	await settle(0.2)
	check(desk.state.day == 2, "the day moved on to day 2")
	check(desk.shift == null, "the finished shift is gone")
	check(desk.state.strikes == 1 and desk._strikes_label.text == "Strikes: X - -", "no cash means a missed quota and one strike (%s)" % desk._strikes_label.text)
	check(desk._transcript.get_parsed_text().contains("SHIFT OVER: day 1") and desk._transcript.get_parsed_text().contains("FAILED") and desk._transcript.get_parsed_text().contains("Mr. Krunk"), "the review screen shows the day, FAILED and the boss")
	check(not desk._reviewing and desk._clock_button.text == "Clock in (day 2)" and not desk._clock_button.disabled, "the button offers day 2")
	check(desk._call_button.disabled, "no phone between shifts")
	check(desk._quota_label.text == "Quota $450", "the day-2 quota is $450 (%s)" % desk._quota_label.text)
	check(GameState.load_or_new("user://desk_flow_save.json").day == 2, "the save on disk says day 2")

	# Day 2 and 3: clock in and straight out, two more strikes, fired
	for expected_day in [2, 3]:
		desk._clock_button.pressed.emit()
		await settle(0.2)
		check(desk.shift != null and desk.shift.running, "day %d clocks in" % expected_day)
		await settle(1.7)  # the desk ignores a Clock out in the first 1.5 s
		desk._clock_button.pressed.emit()
		check(await await_review(), "day %d clocks out and the review appears" % expected_day)
		await settle(0.2)
	check(desk.state.strikes == 3 and desk.state.fired, "three missed quotas: three strikes and fired")
	check(desk._clock_button.text == "New game", "the button now says New game")
	check(desk._transcript.get_parsed_text().contains("You are fired"), "the review screen says the player is fired")
	check(GameState.load_or_new("user://desk_flow_save.json").fired, "the firing is saved")

	# New game
	desk._clock_button.pressed.emit()
	await settle(0.3)
	check(desk.state.day == 1 and desk.state.strikes == 0 and not desk.state.fired, "New game starts over on day 1 with no strikes")
	check(desk.shift != null and desk.shift.running and desk._strikes_label.text == "Strikes: - - -", "and a new shift is running")
	await settle(1.7)
	desk._clock_button.pressed.emit()
	await await_review()
	check(desk.state.day == 2 and desk.state.strikes == 1, "the new run can be played on")

	# A stray press during the review must do nothing
	desk._clock_button.pressed.emit()  # clock in
	await settle(0.1)
	var before: Shift = desk.shift
	desk._clock_button.pressed.emit()  # an accidental second press right away
	desk._clock_button.pressed.emit()
	await settle(0.1)
	check(desk.shift == before and desk.shift != null and desk.shift.running, "a double click on Clock in does not clock straight out again")
	await settle(1.6)
	desk._clock_button.pressed.emit()  # a real Clock out
	desk._clock_button.pressed.emit()  # a second press while the review is being written
	await await_review()
	check(desk.shift == null and desk.state.day == 3, "a second Clock out during the review changes nothing (day %d)" % desk.state.day)

	desk.llm.shutdown()
	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	await settle(0.5)
	get_tree().quit(1 if failures > 0 else 0)
