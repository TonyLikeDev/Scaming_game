extends SceneTree
## Run: python scripts/godot_run.py --import -- --headless --script tests/test_call_director.gd
## The director is plain logic, so its rules can be checked exactly without a model.

var failures := 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("ok    ", label)
	else:
		failures += 1
		print("FAIL  ", label)


## Share of simulated calls that end in a payment when the scammer asks for money on replies 3, 4 and 5 while the
## caller's suspicion creeps up from `start_suspicion` (the shape of the scripted test calls).
func pay_share_of_calls(persona: Dictionary, start_suspicion: int, calls: int) -> float:
	var d := CallDirector.new(123)
	var paid := 0
	for c in calls:
		for ask in 3:
			var note := d.note_for(persona, "Please read me the card number.", 3 + ask, start_suspicion + ask * 8)
			if note.contains("action pay"):
				paid += 1
				break
	return float(paid) / calls


func _init() -> void:
	var gladys := Persona.load_file("res://callers/gladys.json")
	var barry := Persona.load_file("res://callers/barry.json")
	var priya := Persona.load_file("res://callers/priya.json")

	check(CallDirector.asks_for_payment("Please read me the card number."), "card number is a payment ask")
	check(CallDirector.asks_for_payment("There is a small delivery fee of three hundred dollars."), "a fee is a payment ask")
	check(CallDirector.asks_for_payment("I need your account number now."), "account number is a payment ask")
	check(not CallDirector.asks_for_payment("Your warranty on the Moon is about to expire."), "a plain pitch is not a payment ask")
	check(not CallDirector.asks_for_payment("Tell me what you see on the screen."), "a screen question is not a payment ask")

	# Willingness: gullible and calm callers are likelier to pay, suspicious ones and scambaiters are not.
	check(CallDirector.willingness(gladys, 4, 10) > CallDirector.willingness(barry, 4, 10), "Gladys is likelier to pay than Barry")
	check(CallDirector.willingness(gladys, 4, 10) > CallDirector.willingness(gladys, 4, 80), "suspicion lowers willingness")
	check(CallDirector.willingness(gladys, 5, 10) > CallDirector.willingness(gladys, 2, 10), "more turns raise willingness")
	check(CallDirector.willingness(priya, 4, 10) < CallDirector.willingness(gladys, 4, 10) * 0.2, "scambaiters rarely pay")
	var out_of_range := 0
	for p in [gladys, barry, priya]:
		for t in range(0, 12):
			for s in [0, 50, 100]:
				var w := CallDirector.willingness(p, t, s)
				if w < 0.0 or w > 0.95:
					out_of_range += 1
	check(out_of_range == 0, "willingness always stays between 0 and 0.95")
	check(CallDirector.pay_cap(gladys) == 3500, "Gladys pay cap is 3500 (got %d)" % CallDirector.pay_cap(gladys))
	check(CallDirector.pay_cap(priya) <= priya["savings"], "cap never exceeds savings")

	# Every turn gets a note, so the model never decides on its own.
	var d := CallDirector.new(7)
	var plain := d.note_for(gladys, "Your warranty is about to expire.", 3, 10)
	check(plain.contains("has not asked you for money") and plain.contains("action talk"), "no payment ask: stay in the scene, no paying")
	check(d.note_for(gladys, "Read me the card number.", 0, 8).contains("too early"), "too early on the first turn")
	check(d.note_for(gladys, "Read me the card number.", 1, 8).contains("too early"), "too early on the second turn")
	var always_noted := true
	var never_early_pay := true
	for t in range(0, 8):
		for line in ["Hello ma'am.", "Read me the card number."]:
			var note := d.note_for(gladys, line, t, 10)
			if note.is_empty():
				always_noted = false
			if t < 2 and note.contains("action pay"):
				never_early_pay = false
	check(always_noted, "no turn is left without a note")
	check(never_early_pay, "nobody is ever told to pay in the first two replies")

	# Calibration: over a typical call (three asks) Gladys almost always pays, Barry sometimes, a scambaiter rarely.
	var g := pay_share_of_calls(gladys, 10, 3000)
	var b := pay_share_of_calls(barry, 20, 3000)
	var p := pay_share_of_calls(priya, 10, 3000)
	print("share of calls ending in a payment: Gladys %.2f, Barry %.2f, Priya %.2f" % [g, b, p])
	check(g > 0.8 and g < 0.99, "Gladys pays in most calls but not all (%.2f)" % g)
	check(b > 0.25 and b < 0.6, "Barry pays in a minority-to-half of calls (%.2f)" % b)
	check(p < 0.2, "the scambaiter rarely pays (%.2f)" % p)

	# A pay note carries the cap, and a very suspicious caller is told to hang up whatever was asked.
	var found_cap := false
	var dd := CallDirector.new(11)
	for i in 50:
		if dd.note_for(gladys, "Read me the card.", 4, 10).contains("at most 3500"):
			found_cap = true
			break
	check(found_cap, "the pay note carries the cap of 3500")
	var hang := CallDirector.new(5)
	var always_hangs_up := true
	for i in 100:
		if not hang.note_for(barry, "Give me the card number.", 5, 90).contains("action hang_up"):
			always_hangs_up = false
		if not hang.note_for(barry, "Nice weather today.", 5, 90).contains("action hang_up"):
			always_hangs_up = false
	check(always_hangs_up, "suspicion at or above 85 always ends the call")
	check(not CallDirector.new(5).note_for(barry, "Give me the card number.", 5, 84).contains("action hang_up"), "suspicion 84 does not")

	_test_events(gladys, barry)

	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


func _test_events(gladys: Dictionary, barry: Dictionary) -> void:
	# How often and when: about 40% of calls get one surprise, on reply 2 to 5
	var d := CallDirector.new(31)
	var with_event := 0
	var turns_ok := true
	var texts_ok := true
	var n := 4000
	var turn_counts := {}
	for i in n:
		d.plan_call()
		if d.event_turn >= 0:
			with_event += 1
			turn_counts[d.event_turn] = int(turn_counts.get(d.event_turn, 0)) + 1
			if d.event_turn < CallDirector.EVENT_MIN_TURN or d.event_turn > CallDirector.EVENT_MAX_TURN:
				turns_ok = false
			if not d.event_text in CallDirector.EVENTS:
				texts_ok = false
		elif d.event_text != "" or d.event_fired:
			texts_ok = false
	var share := float(with_event) / n
	check(absf(share - CallDirector.EVENT_CHANCE) < 0.03, "about %d%% of calls get a surprise (%.3f)" % [int(CallDirector.EVENT_CHANCE * 100), share])
	check(turns_ok and texts_ok, "a surprise comes on reply 2 to 5 and is one of the listed events")
	check(turn_counts.size() == 4 and turn_counts.values().all(func(c): return c > 250), "all four possible replies are used: %s" % str(turn_counts))
	var shifts_with_one := 0
	var shifts := 2000
	for s in shifts:
		var any := false
		for call in 5:
			d.plan_call()
			if d.event_turn >= 0:
				any = true
		if any:
			shifts_with_one += 1
	check(float(shifts_with_one) / shifts > 0.85, "most shifts of five calls have at least one surprise (%.2f)" % (float(shifts_with_one) / shifts))

	# One call, one surprise, on its reply, never repeated
	var due := CallDirector.new(1)
	due.event_turn = 3
	due.event_text = "the kettle has boiled over"
	check(not due.note_for(gladys, "Nice weather.", 1, 10).contains("Something happens"), "no surprise before its reply")
	check(not due.note_for(gladys, "Nice weather.", 2, 10).contains("Something happens"), "still none one reply earlier")
	var at := due.note_for(gladys, "Nice weather.", 3, 10)
	check(at.contains("Something happens around you right now: the kettle has boiled over."), "the surprise arrives on its reply")
	check(at.contains("action talk"), "the base order is still there next to it")
	check(not due.note_for(gladys, "Nice weather.", 4, 10).contains("Something happens") and due.event_fired, "it is not repeated")
	due.plan_call()
	check(not due.event_fired and (due.event_turn == -1 or due.event_turn >= CallDirector.EVENT_MIN_TURN), "plan_call starts a fresh call: nothing fired, a valid plan or none")

	# It never rides on a payment or a hang-up
	var clash := CallDirector.new(2)
	clash.event_turn = 3
	clash.event_text = "a pigeon has flown in"
	var found_pay := false
	for i in 200:
		var note := clash.note_for(gladys, "Read me the card number.", 4, 5)  # willing, so a pay order is likely
		if note.contains("action pay"):
			found_pay = true
			check(not note.contains("Something happens"), "a payment order carries no surprise")
			break
		clash.event_fired = false  # so the next try can fire it again if it is not a pay order
	check(found_pay, "a payment order came up in the clash test")
	check(not clash.event_fired, "the surprise waits when the turn is a payment")
	var hang := CallDirector.new(3)
	hang.event_turn = 2
	hang.event_text = "a pigeon has flown in"
	var hang_note := hang.note_for(barry, "Give me the card.", 4, 90)
	check(hang_note.contains("action hang_up") and not hang_note.contains("Something happens") and not hang.event_fired, "a hang-up order carries no surprise")
	var later := hang.note_for(barry, "Nice weather.", 5, 10)
	check(later.contains("Something happens") and hang.event_fired, "a surprise held back by a hang-up order comes on the next calm reply")

	# No surprise planned means none ever
	var calm := CallDirector.new(4)
	calm.event_turn = -1
	var any_event := false
	for t in 12:
		if calm.note_for(gladys, "Nice weather.", t, 10).contains("Something happens"):
			any_event = true
	check(not any_event, "a call without a planned surprise never gets one")
	check(CallDirector.EVENTS.size() >= 8 and CallDirector.EVENTS.all(func(e): return not e.contains("DIRECTOR") and not e.ends_with(".")), "the event list has plenty of plain phrases")
