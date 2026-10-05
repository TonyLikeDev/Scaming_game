extends SceneTree
## Run: python scripts/godot_run.py --import -- --headless --script tests/test_call_session.gd
## The rules of a call (what ends it, what pays) tested with a scripted brain instead of a model.

var failures := 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("ok    ", label)
	else:
		failures += 1
		print("FAIL  ", label)


## A brain that answers from a script instead of a model. Replies arrive a moment later, like the real thing.
class FakeBrain extends CallerBrain:
	var script_replies: Array = []
	var delay_s := 0.02
	var log: Array = []  ## shared with the test, which outlives this brain (the session frees it when the call ends)

	func ask(player_text: String) -> void:
		log.append(player_text)
		var reply: Dictionary = script_replies.pop_front() if not script_replies.is_empty() else {"ok": false, "reason": "script ran out"}
		_deliver(reply)

	func _deliver(reply: Dictionary) -> void:
		await Engine.get_main_loop().create_timer(delay_s).timeout
		reply_ready.emit(reply)


## A service that hands out the fake brain (or fails to), without loading any model.
class FakeLlm extends LlmService:
	var brain_to_give: CallerBrain = null
	var fail_with := ""

	func start_call(_persona: Dictionary) -> CallerBrain:
		if brain_to_give == null:
			last_error = fail_with
		return brain_to_give


func reply(say: String, action: String, suspicion: int, amount: int = 0) -> Dictionary:
	return {"ok": true, "say": say, "action": action, "amount": amount, "suspicion": suspicion, "corrections": []}


## Runs one scripted call to the end and returns what happened.
func run_call(persona: Dictionary, replies: Array, player_lines: Array) -> Dictionary:
	var llm := FakeLlm.new()
	var brain := FakeBrain.new()
	brain.script_replies = replies
	var asked: Array = []
	brain.log = asked
	llm.brain_to_give = brain
	var session := CallSession.new()
	root.add_child(llm)
	root.add_child(session)
	var result := {"ended": [], "lines": [], "cash": [], "suspicion": [], "asked": asked}
	session.ended.connect(func(reason, summary): result["ended"].append({"reason": reason, "summary": summary}))
	session.transcript_line.connect(func(role, text): result["lines"].append([role, text]))
	session.cash_earned.connect(func(amount): result["cash"].append(amount))
	session.suspicion_changed.connect(func(v): result["suspicion"].append(v))
	var started: bool = await session.start(llm, persona)
	result["started"] = started
	for line in player_lines:
		if not session.active:
			break
		session.player_says(line)
		while session.thinking:
			await process_frame
	result["session"] = session
	result["llm"] = llm
	return result


func finish(r: Dictionary) -> void:
	r["session"].queue_free()
	r["llm"].queue_free()


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var gladys := Persona.load_file("res://callers/gladys.json")
	var priya := Persona.load_file("res://callers/priya.json")

	# A payment ends the call and adds the cash
	var r := await run_call(gladys, [reply("Fine, take it.", "pay", 12, 300)], ["Card number please."])
	check(r["started"], "the call starts")
	check(r["ended"].size() == 1 and r["ended"][0]["reason"] == "paid", "pay ends the call with 'paid'")
	check(r["cash"] == [300] and r["session"].cash == 300, "the cash is added once (%s)" % str(r["cash"]))
	check(r["suspicion"][0] == 8 and r["suspicion"][-1] == 12, "suspicion starts at 8 for Gladys and follows the reply")
	check(r["lines"].any(func(l): return l[0] == "caller" and l[1] == "Fine, take it."), "the caller's line is in the transcript")
	check(r["ended"][0]["summary"].has("history") and r["ended"][0]["summary"]["persona"] == "gladys", "the summary names the persona and carries the history")
	check(r["asked"].size() == 1 and r["asked"][0].begins_with("Card number please."), "the player's words reach the brain first")
	check(r["asked"][0].contains("[DIRECTOR:"), "the director note is attached to what the brain hears")
	check(not r["lines"].any(func(l): return l[0] == "player" and l[1].contains("DIRECTOR")), "the transcript shows only what the player said")
	finish(r)

	# The caller hangs up
	r = await run_call(gladys, [reply("Goodbye!", "hang_up", 90)], ["Give me money."])
	check(r["ended"].size() == 1 and r["ended"][0]["reason"] == "hung_up", "hang_up ends the call with 'hung_up'")
	check(r["cash"].is_empty(), "no cash on a hang-up")
	finish(r)

	# Suspicion reaching 100 ends the call even when the model says talk
	r = await run_call(gladys, [reply("Hmm, wait a minute.", "talk", 100)], ["Trust me."])
	check(r["ended"].size() == 1 and r["ended"][0]["reason"] == "suspicion", "suspicion 100 ends the call with 'suspicion'")
	finish(r)
	r = await run_call(gladys, [reply("Hmm.", "talk", 99), reply("Hmm.", "talk", 60)], ["Trust me.", "Really."])
	check(r["ended"].is_empty() and r["session"].active, "suspicion 99 does not end the call")
	check(r["session"].turns == 2, "two turns were played")
	r["session"].player_hangs_up()
	check(r["ended"].size() == 1 and r["ended"][0]["reason"] == "player_hung_up", "the player can hang up")
	finish(r)

	# A broken reply never crashes: the line goes dead
	r = await run_call(gladys, [{"ok": false, "reason": "not a JSON object"}], ["Hello?"])
	check(r["ended"].size() == 1 and r["ended"][0]["reason"] == "bad_reply", "a broken reply ends the call with 'bad_reply'")
	check(r["lines"].any(func(l): return l[0] == "system" and l[1].contains("goes dead")), "the player is told the line went dead")
	finish(r)
	r = await run_call(gladys, [], ["Hello?"])
	check(r["ended"].size() == 1 and r["ended"][0]["reason"] == "bad_reply", "an empty script (no reply) also ends with 'bad_reply'")
	finish(r)

	# Counter-attack does not end the call (the minigame arrives in Phase 5)
	r = await run_call(priya, [reply("Gotcha!", "counter_attack", 80), reply("Ha ha.", "talk", 60)], ["Install this.", "Please."])
	check(r["ended"].is_empty() and r["session"].turns == 2, "counter_attack keeps the call going")
	check(r["lines"].any(func(l): return l[0] == "system" and l[1].contains("strikes back")), "the strike is announced")
	r["session"].player_hangs_up()
	finish(r)

	# Input handling
	r = await run_call(gladys, [reply("Yes?", "talk", 8)], ["   ", "", "Hello?"])
	check(r["asked"].size() == 1 and r["session"].turns == 1, "blank lines are ignored")
	r["session"].player_hangs_up()
	r["session"].player_says("anyone there?")
	check(r["asked"].size() == 1, "nothing is sent after the call ended")
	check(r["ended"].size() == 1, "ending twice is not possible")
	finish(r)

	# A planned surprise reaches the brain but never the transcript, and the summary reports it
	var seed_with_event := 0
	for s in range(1, 200):
		var probe := CallDirector.new(s)
		probe.plan_call()
		if probe.event_turn >= 0:
			seed_with_event = s
			break
	var evt_llm := FakeLlm.new()
	var evt_brain := FakeBrain.new()
	evt_brain.script_replies = []
	for i in 7:
		evt_brain.script_replies.append(reply("Hmm, go on.", "talk", 10))
	var evt_asked: Array = []
	evt_brain.log = evt_asked
	evt_llm.brain_to_give = evt_brain
	var evt_session := CallSession.new()
	evt_session.director = CallDirector.new(seed_with_event)
	root.add_child(evt_llm)
	root.add_child(evt_session)
	var evt_summary := {}
	evt_session.ended.connect(func(_r, s): evt_summary.merge(s, true))
	var evt_lines: Array = []
	evt_session.transcript_line.connect(func(role, text): evt_lines.append([role, text]))
	await evt_session.start(evt_llm, gladys)
	check(evt_session.director.event_turn >= 2, "the session planned a surprise (seed %d, reply %d)" % [seed_with_event, evt_session.director.event_turn])
	for i in 7:
		evt_session.player_says("Lovely day, isn't it?")
		while evt_session.thinking:
			await process_frame
	evt_session.player_hangs_up()
	var told := evt_asked.filter(func(a): return String(a).contains("Something happens around you"))
	check(told.size() == 1, "the brain was told about the surprise exactly once")
	check(not evt_lines.any(func(l): return String(l[1]).contains("Something happens") or String(l[1]).contains("DIRECTOR")), "the transcript never shows the surprise or any note")
	check(evt_summary.get("event", "") == evt_session.director.event_text and evt_summary.get("event", "") != "", "the call summary names the surprise")
	evt_session.queue_free()
	evt_llm.queue_free()

	# Hanging up while the caller is still thinking must not produce a second ending
	var llm := FakeLlm.new()
	var brain := FakeBrain.new()
	brain.delay_s = 0.3
	brain.script_replies = [reply("Okay, I will pay.", "pay", 10, 500)]
	llm.brain_to_give = brain
	var session := CallSession.new()
	root.add_child(llm)
	root.add_child(session)
	var endings: Array = []
	session.ended.connect(func(reason, _s): endings.append(reason))
	await session.start(llm, gladys)
	session.player_says("Card number?")
	await create_timer(0.05).timeout
	session.player_hangs_up()
	await create_timer(0.5).timeout
	check(endings == ["player_hung_up"], "hanging up mid-thought gives exactly one ending (%s)" % str(endings))
	check(session.cash == 0, "a late payment after hanging up is not counted")
	session.queue_free()
	llm.queue_free()

	# The model could not be loaded
	var bad_llm := FakeLlm.new()
	bad_llm.fail_with = "model file not found"
	var bad_session := CallSession.new()
	root.add_child(bad_llm)
	root.add_child(bad_session)
	var bad_endings: Array = []
	bad_session.ended.connect(func(reason, summary): bad_endings.append([reason, summary["detail"]]))
	var started: bool = await bad_session.start(bad_llm, gladys)
	check(not started and bad_endings == [["load_failed", "model file not found"]], "a failed model load ends with 'load_failed' and says why")

	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
