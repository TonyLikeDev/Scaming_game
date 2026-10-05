extends SceneTree
## Run: python scripts/godot_run.py --import -- --headless --script tests/test_shift_logic.gd
## Game state and saving, the call queue, shift statistics, the boss's facts and the shift clock, all without a model.

var failures := 0
const TMP := "user://test_shift"


func check(condition: bool, label: String) -> void:
	if condition:
		print("ok    ", label)
	else:
		failures += 1
		print("FAIL  ", label)


## A boss that answers from a script, so the shift can be tested without a model.
class FakeLlm extends LlmService:
	var answer := {"ok": true, "text": "You earned barely anything! I am furious, and this is not good enough at all, do you hear me?", "reason": ""}
	var asked_with := ""

	func generate_text(_system: String, user_message: String, _max_tokens := 170, _timeout_s := 90.0) -> Dictionary:
		asked_with = user_message
		return answer


func call_summary(reason: String, cash: int, caller: String, lines: Array, suspicion := 20) -> Dictionary:
	var history: Array = []
	for l in lines:
		history.append({"role": "player", "text": l})
		history.append({"role": "caller", "text": "ok", "action": "talk", "amount": 0, "suspicion": suspicion})
	return {"reason": reason, "cash": cash, "name": caller, "history": history, "suspicion": suspicion, "turns": lines.size()}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(TMP)
	_test_game_state()
	_test_save_load()
	_test_call_queue()
	_test_stats()
	_test_boss()
	await _test_shift_clock()
	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


func _test_game_state() -> void:
	check(GameState.quota_for_day(1) == 400, "day 1 quota is $400")
	check(GameState.quota_for_day(2) == 450 and GameState.quota_for_day(3) == 550, "days 2 and 3: $450 (460 rounded), $550 (529 rounded) (%d, %d)" % [GameState.quota_for_day(2), GameState.quota_for_day(3)])
	check(GameState.quota_for_day(10) == 1400, "day 10 quota is $1400 (%d)" % GameState.quota_for_day(10))
	var rising := true
	for d in range(1, 40):
		if GameState.quota_for_day(d + 1) < GameState.quota_for_day(d):
			rising = false
	check(rising and GameState.quota_for_day(0) == 400, "the quota never goes down; day 0 counts as day 1")
	var g := GameState.new()
	var r := g.finish_shift(450)
	check(r["passed"] and r["day"] == 1 and g.day == 2 and g.strikes == 0, "passing the quota moves to day 2 without a strike")
	r = g.finish_shift(100)
	check(not r["passed"] and g.strikes == 1 and g.day == 3 and not g.fired, "missing the quota is a strike and the day still advances")
	check(g.total_cash == 550 and g.best_day_cash == 450 and g.history.size() == 2, "totals, best day and history are kept")
	g.finish_shift(0)
	var last := g.finish_shift(0)
	check(g.strikes == 3 and g.fired and last["fired"], "three missed days means fired")
	check(g.finish_shift(10_000)["passed"] and g.strikes == 3, "a pass does not remove a strike")
	g.new_run()
	check(g.day == 1 and g.strikes == 0 and not g.fired and g.total_cash == 0 and g.history.is_empty() and g.best_day_cash == 10_000, "new_run resets everything except the best day")
	var big := GameState.new()
	for i in 50:
		big.finish_shift(1000)
	check(big.history.size() == GameState.HISTORY_LIMIT, "history is capped at %d" % GameState.HISTORY_LIMIT)


func _test_save_load() -> void:
	var path := TMP + "/save.json"
	var g := GameState.new()
	g.finish_shift(500)
	g.finish_shift(50)
	check(g.save(path), "a save is written")
	var h := GameState.load_or_new(path)
	check(h.day == g.day and h.strikes == g.strikes and h.total_cash == g.total_cash and h.best_day_cash == g.best_day_cash, "a save loads back the same")
	check(h.history.size() == 2 and h.history[1]["passed"] == false, "the history loads back")
	check(not FileAccess.file_exists(path + ".tmp"), "no temporary file is left behind")
	check(g.save(path) and GameState.load_or_new(path).day == g.day, "saving over an existing save works")
	check(GameState.load_or_new(TMP + "/none.json").day == 1, "a missing save starts a new run")
	for bad in ["", "not json", "[1,2]", '{"day": "ten"}', '{"day": 3, "strikes": "many"}', "{"]:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(bad)
		f.close()
		var s := GameState.load_or_new(path)
		check(s.day == 1 and s.strikes == 0, "a damaged save (%s) starts a new run" % bad.left(14))
	var f2 := FileAccess.open(path, FileAccess.WRITE)
	f2.store_string('{"day": -5, "strikes": 99, "total_cash": -1, "best_day_cash": 12, "history": [1, {"day": 1}, {"day": 2, "cash": 5, "quota": 400, "passed": false}]}')
	f2.close()
	var clamped := GameState.load_or_new(path)
	check(clamped.day == 1 and clamped.strikes == 3 and clamped.fired and clamped.total_cash == 0 and clamped.best_day_cash == 12, "odd values are clamped and three strikes means fired")
	check(clamped.history.size() == 1 and clamped.history[0]["day"] == 2, "bad history entries are dropped, good ones kept")


func _test_call_queue() -> void:
	var gladys := Persona.load_file("res://callers/gladys.json")
	var barry := Persona.load_file("res://callers/barry.json")
	var priya := Persona.load_file("res://callers/priya.json")
	var personas: Array[Dictionary] = [gladys, barry, priya]
	var q := CallQueue.new(personas, 99)
	var repeats := 0
	var prev := ""
	var savings_ok := true
	var gull_ok := true
	var seen := {}
	for i in 300:
		var c := q.next_caller(1)
		if c["id"] == prev:
			repeats += 1
		prev = c["id"]
		seen[c["id"]] = int(seen.get(c["id"], 0)) + 1
		var base: Dictionary = {"gladys": gladys, "barry": barry, "priya": priya}[c["id"]]
		var lo: float = float(base["savings"]) * CallQueue.SAVINGS_MIN_FACTOR - 100.0
		var hi: float = float(base["savings"]) * CallQueue.SAVINGS_MAX_FACTOR + 100.0
		if c["savings"] % 100 != 0 or c["savings"] < lo or c["savings"] > hi or c["savings"] < 100:
			savings_ok = false
		if absf(float(c["gullibility"]) - float(base["gullibility"])) > CallQueue.GULLIBILITY_JITTER + 0.0001 or c["gullibility"] < 0.05 or c["gullibility"] > 0.98:
			gull_ok = false
	check(repeats == 0, "the same caller never rings twice in a row")
	check(seen.size() == 3 and seen.values().all(func(n): return n > 60), "all three callers come up often: %s" % str(seen))
	check(savings_ok, "savings are a multiple of $100, within half to one and a half times the persona's own")
	check(gull_ok, "gullibility stays within 0.1 of the persona's own on day 1")
	check(gladys["savings"] == 14000 and gladys["gullibility"] == 0.8, "the persona itself is never changed")
	var easy := 0.0
	var hard := 0.0
	var qa := CallQueue.new([gladys] as Array[Dictionary], 5)
	var qb := CallQueue.new([gladys] as Array[Dictionary], 5)
	for i in 400:
		easy += qa.next_caller(1)["gullibility"]
		hard += qb.next_caller(11)["gullibility"]
	check((easy - hard) / 400.0 > 0.12 and (easy - hard) / 400.0 < 0.17, "day 11 callers are about 0.15 harder to fool than day 1 (%.3f)" % ((easy - hard) / 400.0))
	check(CallQueue.new([] as Array[Dictionary]).next_caller(1).is_empty(), "no personas gives an empty caller, not an error")
	var one := CallQueue.new([gladys] as Array[Dictionary], 1)
	check(one.next_caller(1)["id"] == "gladys" and one.next_caller(1)["id"] == "gladys", "a single persona may repeat (there is nobody else)")
	var q1 := CallQueue.new(personas, 42)
	var q2 := CallQueue.new(personas, 42)
	check(q1.next_caller(3) == q2.next_caller(3), "the same seed gives the same caller")


func _test_stats() -> void:
	var s := ShiftStats.new()
	s.record_call(call_summary("paid", 300, "Gladys Pemberton", ["Give me the card.", "The card, please."]))
	s.record_call(call_summary("paid", 800, "Barry Kowalczyk", ["Premium air, sir.", "Just four thousand."]))
	s.record_call(call_summary("hung_up", 0, "Priya Natarajan", ["Install this program."], 88))
	s.record_call(call_summary("suspicion", 0, "Barry Kowalczyk", ["Trust me, sir."], 100))
	s.record_call(call_summary("player_hung_up", 0, "Gladys Pemberton", ["Bye."]))
	s.record_call(call_summary("bad_reply", 0, "Gladys Pemberton", ["Hello?"]))
	s.record_call({"reason": "load_failed", "cash": 0, "history": []})
	check(s.calls == 6 and s.cash == 1100 and s.paid == 2, "calls, cash and payments add up (a failed model load is not a call)")
	check(s.caller_hang_ups == 2 and s.player_hang_ups == 1 and s.dead_lines == 1, "hang-ups are counted by who ended the call")
	check(s.best_line["text"] == "Just four thousand." and s.best_line["amount"] == 800 and s.best_line["caller"] == "Barry Kowalczyk", "the best line is the last one before the biggest payment")
	check(s.worst_line["text"] == "Trust me, sir." and s.worst_line["suspicion"] == 100, "the worst line is the last one before the most suspicious hang-up")
	check(not str(s.best_line).contains("DIRECTOR") and not str(s.worst_line).contains("DIRECTOR"), "the director's notes are never quoted")
	var e := ShiftStats.new()
	check(e.to_dictionary()["best_line"].is_empty() and e.calls == 0, "an empty shift has no best line")


func _test_boss() -> void:
	check(Boss.passed(400, 400) and Boss.passed(401, 400) and not Boss.passed(399, 400), "passing means cash at least the quota")
	var words := {0: "zero", 7: "seven", 20: "twenty", 21: "twenty-one", 100: "one hundred", 101: "one hundred and one", 450: "four hundred and fifty",
			999: "nine hundred and ninety-nine", 1000: "one thousand", 1138: "one thousand, one hundred and thirty-eight", 1650: "one thousand, six hundred and fifty",
			2005: "two thousand and five", 20000: "twenty thousand", 100000: "one hundred thousand", -5: "minus five"}
	for n in words:
		check(Boss.number_words(n) == words[n], "%d in words is '%s' (got '%s')" % [n, words[n], Boss.number_words(n)])
	check(Boss.performance_word(1138, 400) == "outstanding" and Boss.performance_word(800, 400) == "outstanding", "twice the quota or more is outstanding")
	check(Boss.performance_word(600, 400) == "good" and Boss.performance_word(500, 400) == "good", "a quarter over the quota is good")
	check(Boss.performance_word(400, 400) == "just enough" and Boss.performance_word(499, 400) == "just enough", "meeting the quota is just enough")
	check(Boss.performance_word(399, 400) == "poor" and Boss.performance_word(200, 400) == "poor", "half to just under the quota is poor")
	check(Boss.performance_word(199, 400) == "disastrous" and Boss.performance_word(0, 400) == "disastrous", "under half the quota is disastrous")
	check(Boss.performance_word(0, 0) in ["outstanding", "good", "just enough", "poor", "disastrous"], "a zero quota does not divide by zero")
	var s := ShiftStats.new()
	s.record_call(call_summary("paid", 240, "Gladys Pemberton", ["Sign here, ma'am."]))
	s.record_call(call_summary("hung_up", 0, "Barry Kowalczyk", ["Pay up, sir."], 90))
	var report := {"day": 3, "passed": false, "cash": 240, "quota": 500, "strikes": 2, "fired": false, "stats": s.to_dictionary()}
	var f := Boss.facts(report)
	check(f.contains("day 3") and f.contains("FAIL") and f.contains("$240") and f.contains("$500"), "the facts hold the day, verdict, cash and quota")
	check(f.contains("Performance: disastrous (48% of the quota)"), "the facts carry the performance tier and percentage")
	check(f.contains("two hundred and forty dollars") and f.contains("five hundred dollars"), "the facts spell the amounts out in words as well")
	check(f.contains("Your tone: APOPLECTIC"), "the facts tell the boss which tone to use")
	check(Boss.TONES.keys().all(func(k): return k in ["outstanding", "good", "just enough", "poor", "disastrous"]) and Boss.TONES.size() == 5, "there is a tone for every performance word")
	check(f.contains("Sign here, ma'am.") and f.contains("Gladys Pemberton paid $240"), "the facts quote the best line and who paid")
	check(f.contains("Pay up, sir.") and f.contains("Strikes: 2 of 3"), "the facts quote the worst line and the strikes")
	check(not f.contains("FIRED"), "not fired: no firing in the facts")
	var fired_report := report.duplicate(true)
	fired_report["fired"] = true
	fired_report["strikes"] = 3
	check(Boss.facts(fired_report).contains("FIRED"), "a firing is in the facts")
	var passed_report := report.duplicate(true)
	passed_report["passed"] = true
	check(Boss.facts(passed_report).contains("Verdict: PASS"), "a pass is in the facts")
	var nobody := ShiftStats.new()
	var empty_report := {"day": 1, "passed": false, "cash": 0, "quota": 400, "strikes": 1, "fired": false, "stats": nobody.to_dictionary()}
	check(Boss.facts(empty_report).contains("none, nobody paid"), "a shift with no payments says so")
	check(Boss.fallback_rant(report).contains("$240") and Boss.fallback_rant(report).contains("strike 2"), "the fallback rant uses the real numbers")
	check(Boss.fallback_rant(fired_report).contains("fired") and Boss.fallback_rant(passed_report).contains("$500"), "the fallback covers firing and passing")
	check(Boss.clean_review("") == "" and Boss.clean_review("Too short.") == "", "an empty or tiny review is rejected")
	var long_text := "You are late and wrong and slow. ".repeat(40)
	var cleaned := Boss.clean_review(long_text)
	check(cleaned.length() <= Boss.MAX_CHARS and cleaned.ends_with("."), "a long review is cut at a sentence end (%d characters)" % cleaned.length())
	check(Boss.clean_review("*Slams desk* You brought me $240 and I want more than that, do you understand?").begins_with("Slams desk"), "asterisks are removed from the review")


func _test_shift_clock() -> void:
	var llm := FakeLlm.new()
	root.add_child(llm)
	var state := GameState.new()
	var shift := Shift.new()
	shift.save_path = TMP + "/shift_save.json"
	root.add_child(shift)
	var ticks: Array[int] = []
	var reports: Array = []
	shift.tick.connect(func(s): ticks.append(s))
	shift.ended.connect(func(r): reports.append(r))
	shift.begin(state, llm, 3.0)
	check(shift.can_take_call() and shift.running and ticks == [3], "a shift starts running with its length announced")
	shift.call_started()
	shift.call_finished(call_summary("paid", 450, "Gladys Pemberton", ["Card, please."]))
	shift._process(1.2)
	shift._process(1.2)
	check(ticks == [3, 2, 1], "the clock ticks once per second: %s" % str(ticks))
	check(shift.can_take_call(), "calls can still be taken with time left")
	shift._process(1.0)
	await create_timer(0.1).timeout
	check(reports.size() == 1 and not shift.running, "the shift ends when the clock runs out")
	var r: Dictionary = reports[0]
	check(r["passed"] and r["cash"] == 450 and r["quota"] == 400 and r["day"] == 1 and state.day == 2, "the day is scored against the quota and the state moves on")
	check(r["review"]["source"] == "model" and r["review"]["text"].contains("furious"), "the boss review comes from the model's answer")
	check(llm.asked_with.contains("PASS") and llm.asked_with.contains("Card, please."), "the model was given the verdict and the best line")
	check(not shift.can_take_call(), "no calls after the shift")
	check(GameState.load_or_new(TMP + "/shift_save.json").day == 2, "the day is saved when the shift ends")
	shift._process(5.0)
	check(reports.size() == 1, "a finished shift does not end twice")

	# A call in progress when time runs out may finish
	var llm2 := FakeLlm.new()
	llm2.answer = {"ok": false, "text": "", "reason": "model unavailable"}
	root.add_child(llm2)
	var state2 := GameState.new()
	var shift2 := Shift.new()
	shift2.save_path = TMP + "/shift_save2.json"
	root.add_child(shift2)
	var reports2: Array = []
	var overtime2 := [0]
	shift2.ended.connect(func(rep): reports2.append(rep))
	shift2.overtime_started.connect(func(): overtime2[0] += 1)
	shift2.begin(state2, llm2, 2.0)
	shift2.call_started()
	shift2._process(2.5)
	shift2._process(10.0)
	check(reports2.is_empty() and overtime2[0] == 1 and shift2.running, "a call in progress gets overtime instead of being cut off")
	check(not shift2.can_take_call(), "no new call can start in overtime")
	shift2.call_finished(call_summary("paid", 100, "Barry Kowalczyk", ["Sold."]))
	shift2._process(0.1)
	await create_timer(0.1).timeout
	check(reports2.size() == 1 and reports2[0]["cash"] == 100 and not reports2[0]["passed"], "the shift ends when the overtime call finishes, and its cash counts")
	check(reports2[0]["review"]["source"] == "fallback" and reports2[0]["review"]["text"].contains("$100"), "with no model answer the written fallback review is used")
	check(state2.strikes == 1, "missing the quota is a strike")

	# Overtime is limited
	var state3 := GameState.new()
	var shift3 := Shift.new()
	shift3.save_path = TMP + "/shift_save3.json"
	root.add_child(shift3)
	var llm3 := FakeLlm.new()
	root.add_child(llm3)
	var reports3: Array = []
	shift3.ended.connect(func(rep): reports3.append(rep))
	shift3.begin(state3, llm3, 1.0)
	shift3.call_started()
	shift3._process(1.5)
	for i in 7:
		shift3._process(10.0)
	await create_timer(0.1).timeout
	check(reports3.size() == 1, "a call that never ends is cut off after the overtime limit")

	# Clocking out early
	var state4 := GameState.new()
	var shift4 := Shift.new()
	shift4.save_path = TMP + "/shift_save4.json"
	root.add_child(shift4)
	var llm4 := FakeLlm.new()
	root.add_child(llm4)
	var reports4: Array = []
	shift4.ended.connect(func(rep): reports4.append(rep))
	shift4.begin(state4, llm4, 100.0)
	shift4.end_now()
	await create_timer(0.1).timeout
	check(reports4.size() == 1 and reports4[0]["cash"] == 0 and state4.strikes == 1, "clocking out early with no cash is a missed quota")
