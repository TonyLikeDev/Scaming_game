extends Node
## Automated typed playtest (Phase 2). A second chat on the same model plays the scammer (see ScammerBot), so the calls are
## open-ended instead of scripted, while the victim side runs through the real CallSession and every game rule.
## It measures what a script cannot (how calls end, whether anyone pays) and writes transcripts to docs/playtests/ for a
## human to judge. "Stayed in character" and "funny" are judged by reading them; this script does not decide them.
##
## python scripts/godot_run.py --timeout 1500 --log playtest -- --headless scenes/playtest.tscn -- \
##     --model=models/x.gguf --label=name [--calls=10] [--turns=10] [--rules=res://data/caller_rules_v3.txt] \
##     [--order=action_first] [--out=docs/playtests/name.md]

var args := {}
var llm: LlmService
var report: PackedStringArray = []
var results: Array[Dictionary] = []


func _ready() -> void:
	args = _parse_args(OS.get_cmdline_user_args())
	CallerVoice.muted = true
	_run.call_deferred()


func _parse_args(list: PackedStringArray) -> Dictionary:
	var out := {}
	for a in list:
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


func _run() -> void:
	var model_path := LlmService.first_existing([args.get("model", "")])
	if model_path.is_empty():
		print("PLAYTEST_ERROR model not found")
		get_tree().quit(2)
		return
	var label: String = args.get("label", model_path.get_file())
	var n_calls := int(args.get("calls", "10"))
	var max_turns := int(args.get("turns", "10"))
	var personas := Persona.load_dir("res://callers")
	llm = LlmService.new()
	add_child(llm)
	llm.model_path = model_path
	llm.options = {"context_length": 4096, "allow_thinking": false, "order": args.get("order", ReplyParser.DEFAULT_ORDER),
			"constraint": args.get("constraint", "grammar"), "rules_path": args.get("rules", CallerPrompt.RULES_PATH)}
	report.append("# Typed playtest: %s" % label)
	report.append("")
	report.append("Date %s, model `%s`, rules `%s`, key order `%s`. The scammer is a second chat on the same model (a bot, not a human), so the calls are open-ended. **Whether the caller stayed in character and whether it was funny is for a person to judge from the transcripts below.**" % [
		Time.get_datetime_string_from_system(false, true), model_path.get_file(), String(args.get("rules", CallerPrompt.RULES_PATH)).get_file(), args.get("order", ReplyParser.DEFAULT_ORDER)])
	report.append("")

	for i in n_calls:
		var persona: Dictionary = personas[i % personas.size()]
		await _play_call(i + 1, persona, (i * 3 + i / personas.size()) % ScammerBot.SCAMS.size(), max_turns)

	_write_summary(label)
	llm.shutdown()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)


func _play_call(number: int, persona: Dictionary, scam_index: int, max_turns: int) -> void:
	var session := CallSession.new()
	add_child(session)
	var lines := PackedStringArray()
	session.transcript_line.connect(func(role, text): lines.append("**%s:** %s" % [role.capitalize() if role != "caller" else persona["name"].split(" ")[0], text]))
	var ended := {}
	session.ended.connect(func(reason, summary): ended.merge({"reason": reason, "summary": summary}, true))
	if not await session.start(llm, persona):
		report.append("## Call %d: %s: FAILED to start (%s)\n" % [number, persona["name"], llm.last_error])
		results.append({"persona": persona["id"], "reason": "load_failed", "turns": 0, "cash": 0})
		session.queue_free()
		return

	var bot := ScammerBot.new()
	add_child(bot)
	await bot.begin(llm.get_model_node(), persona["name"], scam_index)
	var heard := ""
	var turn := 0
	while session.active and turn < max_turns:
		turn += 1
		session.player_says(await bot.next_line(heard))
		while session.thinking:
			await get_tree().process_frame
		if not session.active:
			break
		heard = String(session.last_reply.get("say", ""))
	if session.active:
		session.player_hangs_up()
	await get_tree().process_frame

	var reason: String = ended.get("reason", "turn_limit")
	report.append("## Call %d: %s (%s), scam: %s" % [number, persona["name"], persona["id"], ScammerBot.SCAMS[scam_index]])
	report.append("")
	report.append_array(lines)
	report.append("")
	report.append("_Ended: %s, turns %d, cash $%d, final suspicion %d._\n" % [reason, session.turns, session.cash, session.suspicion])
	results.append({"persona": persona["id"], "reason": reason, "turns": session.turns, "cash": session.cash,
			"suspicion": session.suspicion, "scam": ScammerBot.SCAMS[scam_index]})
	print("PLAYTEST_CALL %d %s ended=%s turns=%d cash=%d sus=%d" % [number, persona["id"], reason, session.turns, session.cash, session.suspicion])
	bot.end()
	bot.queue_free()
	session.queue_free()
	await get_tree().create_timer(0.4).timeout  # let the call's GPU memory be released before the next call


func _write_summary(label: String) -> void:
	var by_reason := {}
	var cash := 0
	var turns := 0
	for r in results:
		by_reason[r["reason"]] = int(by_reason.get(r["reason"], 0)) + 1
		cash += int(r["cash"])
		turns += int(r["turns"])
	var summary := "calls %d, endings %s, total cash $%d, mean turns %.1f" % [results.size(), JSON.stringify(by_reason), cash, float(turns) / maxf(results.size(), 1)]
	print("PLAYTEST_SUMMARY ", summary)
	report.insert(3, "**Summary:** %s\n" % summary)
	var out_path: String = args.get("out", "docs/playtests/%s.md" % label)
	out_path = ProjectSettings.globalize_path("res://" + out_path) if out_path.is_relative_path() else out_path
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string("\n".join(report) + "\n")
	f.close()
	print("PLAYTEST_WROTE ", out_path)
