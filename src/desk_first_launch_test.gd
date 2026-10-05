extends Node
## The first launch, through the real desk: no model installed, the welcome screen, the download with its progress bar, the model
## being remembered, a first shift played on it, and the failure path (a model that cannot be downloaded) with its Try again button.
## A 484 MB test model stands in for the 5 GB one. Nothing here touches your real save or settings.
##
##   python scripts/godot_run.py --timeout 600 --log first_launch -- scenes/desk_first_launch_test.tscn -- \
##       --mute --no_mic --no_models --settings=user://first_launch_test.cfg --save=user://first_launch_save.json \
##       --download=hf:NobodyWho/Qwen_Qwen3-0.6B-GGUF/Qwen_Qwen3-0.6B-Q4_K_M.gguf

const SMALL_FILE := "Qwen_Qwen3-0.6B-Q4_K_M.gguf"

var desk: Control
var failures := 0


func check(condition: bool, label: String) -> void:
	print(("ok    " if condition else "FAIL  ") + label)
	if not condition:
		failures += 1


func wait_until(condition: Callable, timeout_s := 120.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return condition.call()


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var settings := "user://first_launch_test.cfg"
	DirAccess.remove_absolute(settings)
	DirAccess.remove_absolute("user://first_launch_save.json")
	var cached := LlmService.cached_file(SMALL_FILE)
	if not cached.is_empty():
		DirAccess.remove_absolute(cached)  # so the download below is a real one
	desk = load("res://scenes/desk.tscn").instantiate()
	add_child(desk)
	await get_tree().create_timer(1.5).timeout

	# The welcome screen
	var text: String = desk._transcript.get_parsed_text()
	check(desk._download_button.visible and desk._download_button.text.begins_with("Download Gemma 4 E4B"), "the welcome screen offers the recommended model: '%s'" % desk._download_button.text)
	check(text.contains("Welcome to Scam Desk") and text.contains("runs on your own computer") and text.contains("5.0 GB"), "it explains what the download is and its size")
	check(desk._clock_button.disabled and desk._call_button.disabled, "nothing can be played yet: Clock in and the phone are disabled")
	check(desk.llm.model_path == "" and not desk._downloading, "no model is set")

	# Download it
	desk._download_button.pressed.emit()
	await get_tree().create_timer(0.3).timeout
	check(desk._downloading and desk._download_bar.visible and desk._download_button.disabled, "pressing Download shows the progress bar and disables the button")
	check(desk._clock_button.disabled, "Clock in stays disabled while it downloads")
	var saw_progress := await wait_until(func(): return desk._download_bar.value > 0 and desk._status_label.text.begins_with("Downloading:"), 60.0)
	check(saw_progress, "the progress bar moves and the status says how much is done (%s)" % desk._status_label.text)
	check(await wait_until(func(): return not desk._downloading, 300.0), "the download finishes")
	await get_tree().create_timer(0.3).timeout
	check(not desk._download_button.visible and not desk._download_bar.visible, "the download button and bar disappear")
	check(desk.llm.model_path.ends_with(SMALL_FILE) and FileAccess.file_exists(desk.llm.model_path) and not desk.llm.is_remote(), "the game now uses the downloaded file as a plain path: %s" % desk.llm.model_path)
	check(ModelPicker.remembered_path(desk.pick["id"], settings) == desk.llm.model_path, "and remembers it for the next launch")
	check(desk._transcript.get_parsed_text().contains("The model is ready"), "the screen says the model is ready")
	check(not desk._clock_button.disabled and desk._clock_button.text == "Clock in (day 1)", "Clock in is now available")

	# Play a first shift on it
	desk._clock_button.pressed.emit()
	await get_tree().create_timer(0.3).timeout
	desk._call_button.pressed.emit()
	check(await wait_until(func(): return desk.session != null and (desk.session.active or not desk.session.thinking), 90.0), "a caller picks up on the downloaded model")
	if desk.session != null and desk.session.active:
		desk._line_edit.text = "Good evening, I am calling about your extended warranty."
		desk._on_send()
		await get_tree().create_timer(0.1).timeout
		await wait_until(func(): return not desk.session.thinking, 60.0)
		check(desk.session.turns == 1, "the caller answers (or the line goes dead, which also counts as a turn)")
		if desk.session.active:
			desk._hangup_button.pressed.emit()
	await get_tree().create_timer(1.7).timeout  # the desk ignores Clock out in the first 1.5 s
	desk._clock_button.pressed.emit()
	check(await wait_until(func(): return not desk._last_report.is_empty() and desk.shift == null, 90.0), "the shift ends with a review")
	check(GameState.load_or_new("user://first_launch_save.json").day == 2, "and the day is saved")
	desk.llm.shutdown()
	desk.queue_free()
	await get_tree().create_timer(0.8).timeout

	# The next launch: found through the remembered path, no welcome screen
	desk = load("res://scenes/desk.tscn").instantiate()
	add_child(desk)
	await get_tree().create_timer(1.0).timeout
	# (--no_models is still on for this process, so this launch shows the welcome screen again; what is tested is the remembered path)
	check(ModelPicker.installed_path(desk.pick["id"], [], settings).ends_with(SMALL_FILE), "a later launch can find the downloaded model through the remembered path")
	desk.llm.shutdown()
	desk.queue_free()
	await get_tree().create_timer(0.8).timeout

	# The failure path: a model that cannot be downloaded
	DirAccess.remove_absolute(settings)
	desk = load("res://scenes/desk.tscn").instantiate()
	desk.set_meta("fail_test", true)
	add_child(desk)
	await get_tree().create_timer(1.0).timeout
	desk.args["download"] = "hf:NobodyWho/this-model-does-not-exist/nothing.gguf"
	desk._download_button.pressed.emit()
	check(await wait_until(func(): return not desk._downloading, 120.0), "a download that cannot work ends")
	await get_tree().create_timer(0.3).timeout
	check(desk._download_button.visible and desk._download_button.text == "Try again" and not desk._download_button.disabled, "the button becomes Try again")
	check(desk.llm.model_path == "" and desk._clock_button.disabled, "no model is set and nothing can be played")
	check(desk._transcript.get_parsed_text().contains("The download did not work") and desk._status_label.text == "Download failed", "the player is told, in plain words")
	check(ModelPicker.remembered_path(desk.pick["id"], settings) == "", "a failed download is not remembered")
	desk._download_button.pressed.emit()
	check(await wait_until(func(): return not desk._downloading, 120.0), "Try again can be pressed and ends again")
	check(desk._download_button.text == "Try again" and not desk._download_button.disabled, "and it stays retryable")
	desk.llm.shutdown()

	DirAccess.remove_absolute(settings)
	DirAccess.remove_absolute("user://first_launch_save.json")
	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(1 if failures > 0 else 0)
