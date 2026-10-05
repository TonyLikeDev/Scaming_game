extends Node
## Phase 1 model test. Runs the scripted scam calls in data/test_scams.json against one GGUF model and prints
## one line per turn and a summary. Every number is measured here, never estimated.
##
## python scripts/godot_run.py --timeout 900 --log bench -- --headless scenes/model_test.tscn -- \
##     --model=models/x.gguf --label=name [--gpu=1] [--ctx=4096] [--thinking=0] [--warmup=1] [--calls=2] \
##     [--personas=gladys,barry,priya] [--order=default|action_first] [--constraint=grammar|schema] [--director=1] [--rules=res://data/caller_rules_v2.txt]
##     [--out=docs/runs/name.jsonl]

var args := {}


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


func _fail(message: String) -> void:
	printerr("MODEL_TEST_ERROR ", message)
	print("MODEL_TEST_ERROR ", message)
	get_tree().quit(2)


func _run() -> void:
	var model_path: String = args.get("model", "")
	if model_path.is_empty() or not FileAccess.file_exists(model_path):
		return _fail("--model=<path to .gguf> is missing or the file does not exist: '%s'" % model_path)
	var abs_path := ProjectSettings.globalize_path("res://" + model_path) if model_path.is_relative_path() else model_path
	var label: String = args.get("label", model_path.get_file())
	var use_gpu: bool = args.get("gpu", "1") == "1"
	var ctx := int(args.get("ctx", "4096"))
	var thinking: bool = args.get("thinking", "0") == "1"
	var warmups := int(args.get("warmup", "1"))
	var max_calls := int(args.get("calls", "2"))
	var out_path: String = args.get("out", "")
	if not out_path.is_empty() and out_path.is_relative_path():
		out_path = ProjectSettings.globalize_path("res://" + out_path)
	var persona_ids: PackedStringArray = String(args.get("personas", "gladys,barry,priya")).split(",")
	var closers := int(args.get("closers", "2"))
	var use_director: bool = args.get("director", "0") == "1"
	var director := CallDirector.new(42)  # fixed seed so a run can be repeated

	var scams: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/test_scams.json"))
	var personas := {}
	for p in Persona.load_dir("res://callers"):
		personas[p["id"]] = p
	if not ClassDB.class_exists("NobodyWhoModel"):
		return _fail("NobodyWho addon not loaded; run python scripts/setup_addons.py")

	var meta := {
		"label": label, "model": model_path.get_file(), "gpu": use_gpu, "ctx": ctx, "thinking": thinking,
		"machine": OS.get_processor_name(), "os": OS.get_name(), "godot": Engine.get_version_info()["string"],
		"model_mb": snappedf(_file_mb(abs_path), 0.1),
		"date": Time.get_datetime_string_from_system(false, true), "commit": _git_commit(),
		"calls": max_calls, "closers": closers, "director": use_director, "warmup": warmups, "order": args.get("order", ReplyParser.DEFAULT_ORDER), "constraint": args.get("constraint", "grammar"),
		"rules": String(args.get("rules", CallerPrompt.RULES_PATH)).get_file(),
	}
	print("MODEL_TEST_START ", JSON.stringify(meta))

	var ram0 := SysStats.process_ram_mb()
	var vram0 := SysStats.gpu_used_mb()
	var model: Node = ClassDB.instantiate("NobodyWhoModel")
	model.model_path = abs_path
	model.use_gpu_if_available = use_gpu
	if args.has("log"):
		model.set_log_level(args["log"])
	add_child(model)

	var options := {"context_length": ctx, "allow_thinking": thinking, "order": args.get("order", ReplyParser.DEFAULT_ORDER),
			"constraint": args.get("constraint", "grammar"), "rules_path": args.get("rules", CallerPrompt.RULES_PATH)}
	var first_persona: Dictionary = personas[persona_ids[0]]

	# Load: the model is read when the first chat's worker starts.
	var t_load := Time.get_ticks_msec()
	var brain0 := CallerBrain.new()
	add_child(brain0)
	brain0.begin(model, first_persona, options)
	if not await brain0.wait_started():
		return _fail("model failed to load: %s" % (brain0.failure_reason if not brain0.failure_reason.is_empty() else "timeout after %d s" % int(CallerBrain.START_TIMEOUT_S)))
	var load_ms := Time.get_ticks_msec() - t_load
	var ram1 := SysStats.process_ram_mb()
	var vram1 := SysStats.gpu_used_mb()
	print("MODEL_TEST_LOADED load_ms=%d ram_mb=%.0f (+%.0f) vram_mb=%.0f (+%.0f)" % [load_ms, ram1, ram1 - ram0, vram1, vram1 - vram0])

	# Warm-up turns on the first chat, thrown away (graph compile, caches).
	for i in warmups:
		brain0.ask("Hello, is this a good time to talk?")
		var warm: Dictionary = await brain0.reply_ready
		print("MODEL_TEST_WARMUP %d total_ms=%d ok=%s" % [i + 1, warm.get("total_ms", -1), warm.get("ok")])
	brain0.end_call()
	brain0.queue_free()  # freed at the end of this frame; the wait below lets the GPU memory come back (8 GB cards cannot hold two contexts)
	await get_tree().create_timer(0.3).timeout

	var rows: Array[Dictionary] = []
	var out_file: FileAccess = null
	if not out_path.is_empty():
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		out_file = FileAccess.open(out_path, FileAccess.WRITE)
		out_file.store_line(JSON.stringify({"meta": meta, "load_ms": load_ms, "ram_after_load_mb": ram1, "vram_after_load_mb": vram1}))

	for pid in persona_ids:
		var calls: Array = scams.get(pid, [])
		for call_index in mini(calls.size(), max_calls):
			var brain := CallerBrain.new()
			add_child(brain)
			brain.begin(model, personas[pid], options)
			if not await brain.wait_started():
				return _fail("chat failed to start for %s: %s" % [pid, brain.failure_reason])
			var turn := 0
			var lines: Array = (calls[call_index] as Array).duplicate()
			lines.append_array((scams.get("closers", []) as Array).slice(0, closers))
			for line in lines:
				turn += 1
				var note := director.note_for(personas[pid], line, brain.turn_count, brain.suspicion) if use_director else ""
				brain.ask(line + note)
				var reply: Dictionary = await brain.reply_ready
				var secs := maxf(float(reply.get("total_ms", 0)) - maxf(float(reply.get("ttft_ms", 0)), 0.0), 1.0) / 1000.0
				var said := String(reply.get("say", ""))
				var row := {
					"label": label, "persona": pid, "call": call_index + 1, "turn": turn, "player": line,
					"ok": reply["ok"], "reason": reply.get("reason", ""), "corrections": reply.get("corrections", []),
					"say": said, "suspicion": reply.get("suspicion", -1), "action": reply.get("action", ""), "amount": reply.get("amount", 0),
					"ttft_ms": reply.get("ttft_ms", -1), "say_ms": reply.get("say_ms", -1), "total_ms": reply.get("total_ms", -1),
					"tokens": reply.get("tokens", 0), "tok_per_s": snappedf(float(reply.get("tokens", 0)) / secs, 0.1),
					"words": said.split(" ", false).size(), "raw": reply.get("raw", ""),
					"pay_mismatch": reply["ok"] and reply["action"] != "pay" and ReplyParser.say_implies_payment(said),
					"note_kind": _note_kind(note),
				}
				rows.append(row)
				if out_file:
					out_file.store_line(JSON.stringify(row))
				print("MODEL_TEST_TURN %s c%d t%d ok=%s ttft=%d say=%d total=%d tok=%d tps=%.1f act=%s sus=%d | %s" % [
					pid, call_index + 1, turn, reply["ok"], row["ttft_ms"], row["say_ms"], row["total_ms"], row["tokens"],
					row["tok_per_s"], row["action"], row["suspicion"], said if reply["ok"] else "FAILED: %s" % row["reason"]])
				if not reply["ok"] or reply["action"] in ["hang_up", "pay"]:
					break
			brain.end_call()
			brain.queue_free()
			await get_tree().create_timer(0.4).timeout

	var ram2 := SysStats.process_ram_mb()
	var vram2 := SysStats.gpu_used_mb()
	var summary := _summarize(rows, meta, load_ms, ram0, ram1, ram2, vram0, vram1, vram2)
	print("MODEL_TEST_SUMMARY ", JSON.stringify(summary))
	if out_file:
		out_file.store_line(JSON.stringify({"summary": summary}))
		out_file.close()

	model.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)


func _note_kind(note: String) -> String:
	if note.is_empty():
		return "none"
	if note.contains("too early"):
		return "early"
	if note.contains("action pay"):
		return "pay"
	if note.contains("action hang_up"):
		return "hangup"
	return "stall"


## Short HEAD hash, with "+wip" when the working tree has uncommitted changes.
func _git_commit() -> String:
	var out: Array = []
	if OS.execute("git", ["rev-parse", "--short", "HEAD"], out) != 0 or out.is_empty():
		return "unknown"
	var hash := str(out[0]).strip_edges()
	var status: Array = []
	if OS.execute("git", ["status", "--porcelain"], status) == 0 and not str(status[0] if status.size() > 0 else "").strip_edges().is_empty():
		hash += "+wip"
	return hash


func _file_mb(path: String) -> float:
	var f := FileAccess.open(path, FileAccess.READ)
	return float(f.get_length()) / 1048576.0 if f else -1.0


func _percentile(sorted_values: Array, p: float) -> float:
	if sorted_values.is_empty():
		return -1.0
	return float(sorted_values[clampi(ceili(p * sorted_values.size()) - 1, 0, sorted_values.size() - 1)])


func _summarize(rows: Array[Dictionary], meta: Dictionary, load_ms: int, ram0: float, ram1: float, ram2: float, vram0: float, vram1: float, vram2: float) -> Dictionary:
	var totals: Array = []
	var warm_totals: Array = []  # turns after the first of a call (system prompt already processed)
	var first_totals: Array = []
	var says: Array = []
	var ttfts: Array = []
	var tps: Array = []
	var ok_count := 0
	var corrected := 0
	var words: Array = []
	for r in rows:
		if r["ok"]:
			ok_count += 1
			words.append(r["words"])
			if not (r["corrections"] as Array).is_empty():
				corrected += 1
		if r["total_ms"] >= 0:
			totals.append(r["total_ms"])
			(first_totals if r["turn"] == 1 else warm_totals).append(r["total_ms"])
		if r["say_ms"] >= 0:
			says.append(r["say_ms"])
		if r["ttft_ms"] >= 0:
			ttfts.append(r["ttft_ms"])
		if r["tok_per_s"] > 0:
			tps.append(r["tok_per_s"])
	var pays := 0
	var hangups := 0
	var mismatches := 0
	var orders := {"pay": 0, "pay_obeyed": 0, "stall": 0, "stall_obeyed": 0, "hangup": 0, "hangup_obeyed": 0, "early": 0, "early_obeyed": 0}
	for r in rows:
		var kind: String = r.get("note_kind", "none")
		if kind != "none" and r["ok"]:
			orders[kind] += 1
			var obeyed: bool = (r["action"] == "pay") if kind == "pay" else ((r["action"] == "hang_up") if kind == "hangup" else (r["action"] != "pay"))
			if kind == "stall" or kind == "early":
				obeyed = r["action"] == "talk"
			if obeyed:
				orders[kind + "_obeyed"] += 1
	var talk_turns := 0
	var calls := {}
	var spread: Array = []  # per call: highest minus lowest suspicion, to see whether it moves at all
	for r in rows:
		var key := "%s/%d" % [r["persona"], r["call"]]
		if not calls.has(key):
			calls[key] = {"min": 101, "max": -1, "paid": false, "persona": r["persona"]}
		if r["ok"]:
			calls[key]["min"] = mini(calls[key]["min"], r["suspicion"])
			calls[key]["max"] = maxi(calls[key]["max"], r["suspicion"])
			if r["action"] == "pay":
				pays += 1
				calls[key]["paid"] = true
			elif r["action"] == "hang_up":
				hangups += 1
			if r["pay_mismatch"]:
				mismatches += 1
	var paid_by := {}
	for key in calls:
		spread.append(calls[key]["max"] - calls[key]["min"])
		paid_by[calls[key]["persona"]] = int(paid_by.get(calls[key]["persona"], 0)) + (1 if calls[key]["paid"] else 0)
	var pay_per_persona := {}
	for key in calls:
		pay_per_persona[calls[key]["persona"]] = "%d/%d" % [paid_by[calls[key]["persona"]], calls.keys().filter(func(k): return calls[k]["persona"] == calls[key]["persona"]).size()]
	var spread_mean := 0.0
	for s in spread:
		spread_mean += float(s)
	spread_mean = spread_mean / maxf(spread.size(), 1)
	for a in [totals, warm_totals, first_totals, says, ttfts, tps, words]:
		a.sort()
	return {
		"label": meta["label"], "turns": rows.size(), "valid_replies": ok_count, "valid_pct": snappedf(100.0 * ok_count / maxf(rows.size(), 1), 0.1),
		"replies_with_corrections": corrected, "load_ms": load_ms,
		"total_ms_median": _percentile(totals, 0.5), "total_ms_p95": _percentile(totals, 0.95),
		"first_turn_total_ms_median": _percentile(first_totals, 0.5), "warm_turn_total_ms_median": _percentile(warm_totals, 0.5),
		"say_ms_median": _percentile(says, 0.5), "ttft_ms_median": _percentile(ttfts, 0.5),
		"tok_per_s_median": _percentile(tps, 0.5), "words_median": _percentile(words, 0.5),
		"ram_mb_before": snappedf(ram0, 1.0), "ram_mb_after_load": snappedf(ram1, 1.0), "ram_mb_after_run": snappedf(ram2, 1.0),
		"vram_mb_before": vram0, "vram_mb_after_load": vram1, "vram_mb_after_run": vram2,
		"vram_delta_mb": vram1 - vram0,
		"calls": calls.size(), "pays": pays, "calls_with_pay": paid_by.values().reduce(func(a, b): return a + b, 0),
		"pay_per_persona": pay_per_persona, "hangups": hangups, "pay_mismatches": mismatches,
		"suspicion_spread_mean": snappedf(spread_mean, 0.1), "director_orders": orders,
	}
