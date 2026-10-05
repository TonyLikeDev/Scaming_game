extends Node
## Writes the boss's review for six made-up days (outstanding to fired) on the real model, so the tone can be read and
## compared with what the numbers say. The pass or fail is arithmetic; only the rant comes from the model.
##
##   python scripts/godot_run.py --timeout 300 --log boss -- --headless scenes/boss_check.tscn -- [--out=docs/playtests/boss_reviews.md]

var args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	_run.call_deferred()


func _stats(calls: int, paid: int, caller_hangs: int, player_hangs: int, best: Dictionary, worst: Dictionary) -> Dictionary:
	return {"calls": calls, "cash": 0, "paid": paid, "caller_hang_ups": caller_hangs, "player_hang_ups": player_hangs, "dead_lines": 0,
			"best_line": best, "worst_line": worst, "callers": []}


func _run() -> void:
	var model_path := LlmService.first_existing([args.get("model", "models/gemma-4-E4B-it-Q4_K_M.gguf")])
	var llm := LlmService.new()
	add_child(llm)
	llm.model_path = model_path
	var best := {"text": "Only four thousand dollars for lifetime air, sir.", "caller": "Barry Kowalczyk", "amount": 4000}
	var worst := {"text": "Just give me your card number, you old fool.", "caller": "Gladys Pemberton", "suspicion": 92}
	var days := [
		{"label": "outstanding", "day": 3, "cash": 1650, "quota": 550, "strikes": 0, "fired": false, "stats": _stats(10, 5, 2, 3, best, worst)},
		{"label": "good", "day": 4, "cash": 800, "quota": 600, "strikes": 0, "fired": false, "stats": _stats(6, 3, 1, 2, best, worst)},
		{"label": "just enough", "day": 5, "cash": 710, "quota": 700, "strikes": 1, "fired": false, "stats": _stats(5, 2, 2, 1, best, worst)},
		{"label": "poor", "day": 6, "cash": 450, "quota": 800, "strikes": 1, "fired": false, "stats": _stats(5, 1, 3, 1, best, worst)},
		{"label": "disastrous", "day": 7, "cash": 0, "quota": 900, "strikes": 2, "fired": false, "stats": _stats(4, 0, 3, 1, {}, worst)},
		{"label": "fired", "day": 8, "cash": 120, "quota": 1000, "strikes": 3, "fired": true, "stats": _stats(4, 1, 2, 1, best, worst)},
	]
	var out := PackedStringArray()
	out.append("# Boss review check")
	out.append("")
	out.append("Date %s, model `%s`. Six made-up days on the real model. The tone line given to the boss comes from `Boss.TONES`; whether the rant matches it is for a person to judge.\n" % [
			Time.get_datetime_string_from_system(false, true), model_path.get_file()])
	for d in days:
		d["passed"] = Boss.passed(d["cash"], d["quota"])
		var r: Dictionary = await Boss.review(llm, d)
		print("BOSS_CHECK %s (%s, %d ms): %s" % [d["label"], r["source"], r["ms"], r["text"]])
		out.append("## %s: $%d against $%d (%s, strikes %d%s)" % [d["label"], d["cash"], d["quota"], "pass" if d["passed"] else "fail", d["strikes"], ", fired" if d["fired"] else ""])
		out.append("")
		out.append("**Mr. Krunk (%s, %d ms):** %s" % [r["source"], r["ms"], r["text"]])
		out.append("")
	var path: String = args.get("out", "")
	if not path.is_empty():
		path = ProjectSettings.globalize_path("res://" + path) if path.is_relative_path() else path
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string("\n".join(out) + "\n")
		f.close()
	llm.shutdown()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)
