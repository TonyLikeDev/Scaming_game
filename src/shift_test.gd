extends Node
## Phase 4 integration test: a compressed working day on the real model, with the scammer bot standing in for the player.
## clock in -> calls (queue, director, voice-free) -> clock runs out -> boss review -> save -> next day, which must start from the save.
##
##   python scripts/godot_run.py --timeout 900 --log shift -- --headless scenes/shift_test.tscn -- \
##       [--model=models/x.gguf] [--shift_s=90] [--days=2] [--out=docs/playtests/name.md]

var args := {}
var report_lines: PackedStringArray = []
var llm: LlmService
var failures := 0
var calls_seen := 0
var events_seen := 0


func _ready() -> void:
	args = _parse_args(OS.get_cmdline_user_args())
	_run.call_deferred()


func _parse_args(list: PackedStringArray) -> Dictionary:
	var out := {}
	for a in list:
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


func check(condition: bool, label: String) -> void:
	print(("ok    " if condition else "FAIL  ") + label)
	if not condition:
		failures += 1


func _run() -> void:
	var model_path := LlmService.first_existing([args.get("model", "models/gemma-4-E4B-it-Q4_K_M.gguf")])
	if model_path.is_empty():
		print("SHIFT_TEST_ERROR model not found")
		get_tree().quit(2)
		return
	var shift_s := float(args.get("shift_s", "90"))
	var days := int(args.get("days", "2"))
	var save_path := "user://shift_test_save.json"
	DirAccess.remove_absolute(save_path)
	llm = LlmService.new()
	add_child(llm)
	llm.model_path = model_path
	llm.options = {"context_length": 4096, "allow_thinking": false}
	report_lines.append("# Compressed shift test: %s" % model_path.get_file())
	report_lines.append("")
	report_lines.append("Date %s. Each day is %d s long instead of %d s. The scammer is a bot. The boss review is written by the model from the real numbers; the pass or fail is arithmetic done by the game." % [
			Time.get_datetime_string_from_system(false, true), int(shift_s), int(GameState.SHIFT_SECONDS)])
	report_lines.append("")

	var personas := Persona.load_dir("res://callers")
	var queue := CallQueue.new(personas, 2026)
	var voice := VoiceEngine.new()
	voice.muted = true
	add_child(voice)
	for day_index in days:
		var state := GameState.load_or_new(save_path)  # day 2 must start from what day 1 saved
		check(state.day == day_index + 1, "day %d starts from the save (state.day = %d)" % [day_index + 1, state.day])
		var shift := Shift.new()
		shift.save_path = save_path
		add_child(shift)
		var ended := {"report": {}}
		shift.ended.connect(func(r): ended["report"] = r)
		var t_start := Time.get_ticks_msec()
		shift.begin(state, llm, shift_s)
		var call_number := 0
		var quota := state.quota()
		report_lines.append("## Day %d, quota $%d, strikes %d of %d" % [state.day, quota, state.strikes, GameState.MAX_STRIKES])
		report_lines.append("")
		while shift.can_take_call():
			call_number += 1
			var persona := queue.next_caller(state.day)
			await _play_call(shift, persona, call_number)
		# A call may still be running into overtime; wait for the day to end
		var deadline := Time.get_ticks_msec() + 180000
		while ended["report"].is_empty() and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		var report: Dictionary = ended["report"]
		check(not report.is_empty(), "day %d ended with a report" % (day_index + 1))
		if report.is_empty():
			break
		check(report["passed"] == (report["cash"] >= report["quota"]), "the verdict is the arithmetic: $%d against $%d is %s" % [report["cash"], report["quota"], "a pass" if report["passed"] else "a fail"])
		check(report["review"]["text"].length() > 30, "a review was produced (%s, %d ms)" % [report["review"]["source"], report["review"]["ms"]])
		report_lines.append("**Result:** %s, $%d of $%d, %d calls (%d paid), strikes now %d of %d%s. Total real time %.0f s." % [
				"PASSED" if report["passed"] else "FAILED", report["cash"], report["quota"], report["stats"]["calls"], report["stats"]["paid"],
				report["strikes"], GameState.MAX_STRIKES, ", FIRED" if report["fired"] else "", (Time.get_ticks_msec() - t_start) / 1000.0])
		report_lines.append("")
		report_lines.append("**Boss (%s, review took %d ms):** %s" % [report["review"]["source"], report["review"]["ms"], report["review"]["text"]])
		report_lines.append("")
		print("SHIFT_TEST_DAY %d %s" % [report["day"], JSON.stringify({"passed": report["passed"], "cash": report["cash"], "quota": report["quota"],
				"calls": report["stats"]["calls"], "paid": report["stats"]["paid"], "strikes": report["strikes"], "review_ms": report["review"]["ms"], "source": report["review"]["source"]})])
		print("SHIFT_TEST_BOSS ", report["review"]["text"])
		var saved := GameState.load_or_new(save_path)
		check(saved.day == report["day"] + 1 and saved.strikes == report["strikes"] and saved.total_cash == report["total_cash"], "the end of day %d is saved" % report["day"])
		shift.queue_free()
		await get_tree().create_timer(0.5).timeout

	var out_path: String = args.get("out", "")
	if not out_path.is_empty():
		out_path = ProjectSettings.globalize_path("res://" + out_path) if out_path.is_relative_path() else out_path
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string("\n".join(report_lines) + "\n")
		f.close()
		print("SHIFT_TEST_WROTE ", out_path)
	print("SHIFT_TEST_EVENTS %d of %d calls had a surprise" % [events_seen, calls_seen])
	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	llm.shutdown()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(1 if failures > 0 else 0)


func _play_call(shift: Shift, persona: Dictionary, number: int) -> void:
	var session := CallSession.new()
	add_child(session)
	var lines := PackedStringArray()
	session.transcript_line.connect(func(role, text): lines.append("**%s:** %s" % [role.capitalize() if role != "caller" else persona["name"].split(" ")[0], text]))
	var summary := {"data": {}}
	session.ended.connect(func(_reason, s): summary["data"] = s)
	shift.call_started()
	if not await session.start(llm, persona):
		shift.call_finished({"reason": "load_failed"})
		session.queue_free()
		return
	var bot := ScammerBot.new()
	add_child(bot)
	await bot.begin(llm.get_model_node(), persona["name"], number * 3 + number / 3)
	var heard := ""
	var turn := 0
	while session.active and turn < 10:
		turn += 1
		var line := await bot.next_line(heard)
		session.player_says(line)
		while session.thinking:
			await get_tree().process_frame
		if not session.active:
			break
		heard = String(session.last_reply.get("say", ""))
	if session.active:
		session.player_hangs_up()
	await get_tree().process_frame
	bot.end()
	bot.queue_free()
	var s: Dictionary = summary["data"]
	if s.is_empty():
		s = {"reason": "turn_limit", "cash": session.cash, "name": persona["name"], "history": session.log.duplicate(true), "suspicion": session.suspicion}
	shift.call_finished(s)
	var surprise: String = s.get("event", "")
	if not surprise.is_empty():
		events_seen += 1
	report_lines.append("### Call %d: %s (savings $%d, gullibility %.2f): %s, $%d%s" % [number, persona["name"], persona["savings"], persona["gullibility"], s.get("reason", "?"), s.get("cash", 0),
			(", surprise: " + surprise) if not surprise.is_empty() else ""])
	report_lines.append("")
	report_lines.append_array(lines)
	report_lines.append("")
	calls_seen += 1
	print("SHIFT_TEST_CALL %d %s ended=%s cash=%d turns=%d event=%s" % [number, persona["id"], s.get("reason", "?"), s.get("cash", 0), session.turns, surprise if not surprise.is_empty() else "-"])
	session.queue_free()
	await get_tree().create_timer(0.4).timeout  # let the call's GPU memory be released before the next call
