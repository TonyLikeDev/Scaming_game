extends Node
## Phase 9 check of the first-launch download, with a small model so it takes a minute instead of half an hour:
## NobodyWho's own 0.6 billion parameter test model (484 MB). `LlmService` is given a Hugging Face reference, downloads it, loads it,
## and the file NobodyWho cached is found. Then a reference to a model that does not exist must fail cleanly, not crash or hang.
## (NobodyWho v11.0.0's separate `NobodyWhoDownloader` panics when started, so the game does not use it.)
##
##   python scripts/godot_run.py --timeout 900 --log download -- --headless scenes/download_check.tscn

const SMALL := "hf:NobodyWho/Qwen_Qwen3-0.6B-GGUF/Qwen_Qwen3-0.6B-Q4_K_M.gguf"
const MISSING := "hf:NobodyWho/this-model-does-not-exist/nothing.gguf"

var failures := 0


func check(condition: bool, label: String) -> void:
	print(("ok    " if condition else "FAIL  ") + label)
	if not condition:
		failures += 1


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var gladys := Persona.load_file("res://callers/gladys.json")
	var llm := LlmService.new()
	add_child(llm)
	llm.model_path = SMALL
	llm.start_timeout_s = 600.0
	check(llm.is_remote() and llm.model_available(), "a Hugging Face reference counts as an available model")
	var progress := {"calls": 0, "last": [0, 0], "monotonic": true}
	llm.download_progress.connect(func(done, total):
		if done < progress["last"][0]:
			progress["monotonic"] = false
		progress["calls"] += 1
		progress["last"] = [done, total])
	var cached_before := LlmService.cached_file("Qwen_Qwen3-0.6B-Q4_K_M.gguf")
	var t := Time.get_ticks_msec()
	var ok := await llm.warm_up(gladys)
	print("DOWNLOAD_CHECK cached before: '%s'; took %.1f s, %d progress updates, last %s" % [cached_before, (Time.get_ticks_msec() - t) / 1000.0, progress["calls"], str(progress["last"])])
	check(ok, "the model downloads and loads (state %s, error '%s')" % [llm.state, llm.last_error])
	if cached_before.is_empty():
		check(progress["calls"] >= 10, "progress was reported while downloading (%d updates)" % progress["calls"])
		check(progress["monotonic"] and progress["last"][0] == progress["last"][1] and progress["last"][1] > 400_000_000, "it only counts upwards and ends complete (%s)" % str(progress["last"]))
	else:
		print("DOWNLOAD_CHECK the model was already cached, so no progress is expected")
	var local := LlmService.cached_file("Qwen_Qwen3-0.6B-Q4_K_M.gguf")
	check(local != "" and FileAccess.file_exists(local), "NobodyWho's cache holds the file: %s" % local)
	var f := FileAccess.open(local, FileAccess.READ)
	var size := f.get_length() if f else 0
	check(size > 400_000_000 and size < 600_000_000, "it is the expected size (%d MB)" % (size / 1048576))
	llm.shutdown()
	await get_tree().create_timer(0.5).timeout

	# From then on the plain file path works, like every later launch
	var again := LlmService.new()
	add_child(again)
	again.model_path = local
	var result: Dictionary = await again.generate_text("You are a cheerful assistant.", "Say hello in one short sentence.", 40, 120.0)
	print("DOWNLOAD_CHECK the downloaded model said: ", result.get("text", ""))
	check(not again.is_remote() and result.get("ok", false) and String(result.get("text", "")).length() > 3, "the cached file loads as a plain path and answers")
	again.shutdown()
	await get_tree().create_timer(0.5).timeout

	# A model that does not exist fails cleanly
	var bad := LlmService.new()
	add_child(bad)
	bad.model_path = MISSING
	bad.start_timeout_s = 90.0
	var t2 := Time.get_ticks_msec()
	var bad_ok := await bad.warm_up(gladys)
	print("DOWNLOAD_CHECK missing model: ok=%s after %.1f s, error '%s'" % [bad_ok, (Time.get_ticks_msec() - t2) / 1000.0, bad.last_error.left(200)])
	check(not bad_ok and bad.state == "failed" and bad.last_error != "", "a model that does not exist ends in a failure message")
	check(bad.last_error.to_lower().contains("404") or bad.last_error.to_lower().contains("not found") or bad.last_error.to_lower().contains("download") or bad.last_error.length() > 5, "and the message says something")
	bad.shutdown()
	check(LlmService.cached_file("no_such_file.gguf") == "", "asking for a file that was never cached gives an empty path")

	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(1 if failures > 0 else 0)
