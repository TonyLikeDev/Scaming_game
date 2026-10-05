extends Control
## The flat desk (Phase 2): incoming-call button, transcript, text box, suspicion meter, cash counter.
## The call rules live in CallSession; this script only shows them and passes the typing along.
##
## The day (Phase 4): clock in, answer calls from the queue until the clock runs out, then the boss reviews your numbers.
## Three missed quotas and you are fired. The day and strikes are saved after every review (`user://save.json`).
##
## The model: the one that suits this computer (ModelPicker), from `models/`, `user://models/` or an earlier download. If
## none is installed the first launch offers to download it. `--model=<file>` forces a file; tests use `--no_models`
## (pretend nothing is installed), `--download=hf:owner/repo/file.gguf` (download this instead) and `--settings=user://x.cfg`.
##
## Run:  python scripts/godot_run.py -- scenes/desk.tscn -- [--model=models/x.gguf] [--mute] [--voice=os|kokoro|off] [--no_mic]
## Demo: add  --demo [--shot=path.png]  to play a short scripted call and save a screenshot, then quit.
##       add  --demo_voice  to speak the scripted lines (Kokoro makes the "microphone" audio) instead of typing them.
##       --demo_shift [--shift_s=40] [--shot=path.png]  plays a whole short day with scripted lines, then the review.
##       The demos use their own save file, never your real one.
## Voice: hold V (when the text box is not selected) or the Hold to talk button, release to send. The caller speaks as
## soon as the spoken line is complete, through the OS voices or Kokoro (the drop-down at the bottom).

## The Clock in button turns into Clock out, so a double click would clock you out again and cost a strike.
const CLOCK_OUT_DELAY_MS := 1500
const COLOR_PLAYER := Color("8ecbff")
const COLOR_CALLER := Color("ffe08a")
const COLOR_SYSTEM := Color("9aa3ad")

var llm: LlmService
var session: CallSession
var personas: Array[Dictionary] = []
var state: GameState
var shift: Shift
var queue: CallQueue
var save_path := GameState.SAVE_PATH
var settings_path := ModelPicker.SETTINGS_PATH
var pick: Dictionary = {}  ## ModelPicker.recommend() for this computer
var args := {}

var _cash_label: Label
var _calls_label: Label
var _name_label: Label
var _info_label: Label
var _status_label: Label
var _suspicion_bar: ProgressBar
var _suspicion_label: Label
var _transcript: RichTextLabel
var _line_edit: LineEdit
var _send_button: Button
var _hangup_button: Button
var _call_button: Button
var _download_button: Button
var _download_bar: ProgressBar
var _downloading := false
var _day_label: Label
var _clock_label: Label
var _quota_bar: ProgressBar
var _quota_label: Label
var _strikes_label: Label
var _clock_button: Button
var _reviewing := false
var _shift_started_ms := 0
var _last_report: Dictionary = {}
var _voice_option: OptionButton
var _ptt_button: Button

var voice: VoiceEngine
var voice_input: VoiceInput
var last_voice_ms := {}  ## timing of the last spoken turn, for the demo and for debugging


func _ready() -> void:
	args = _parse_args(OS.get_cmdline_user_args())
	var quiet := args.has("mute") or args.has("demo")
	CallerVoice.muted = quiet
	voice = VoiceEngine.new()
	voice.muted = quiet
	add_child(voice)
	voice_input = VoiceInput.new()
	add_child(voice_input)
	var mods_path := Persona.ensure_user_dir()
	personas = Persona.load_all()
	if args.has("only"):  # for modders: ring only this caller
		var only: Array[Dictionary] = []
		for p in personas:
			if p["id"] == args["only"]:
				only.append(p)
		personas = only
		if only.is_empty():
			push_warning("--only=%s: no caller with that id" % args["only"])
	var demo := args.has("demo") or args.has("demo_shift")
	save_path = args.get("save", "user://desk_demo_save.json" if demo else GameState.SAVE_PATH)
	if demo:
		DirAccess.remove_absolute(save_path)  # a demo never touches the real save
	state = GameState.load_or_new(save_path)
	queue = CallQueue.new(personas)
	_build_ui()
	llm = LlmService.new()
	add_child(llm)
	llm.options = {"context_length": 4096, "allow_thinking": false}
	settings_path = args.get("settings", ModelPicker.SETTINGS_PATH)
	_choose_model()
	_set_idle()
	var mod_count := personas.filter(func(p): return p.get("mod", false)).size()
	if mod_count > 0:
		_say_system("%d custom caller(s) loaded from %s" % [mod_count, mods_path])
	_start.call_deferred()


# --- The model: choosing it, and the first-launch download ----------------------------------------------------------

func _choose_model() -> void:
	pick = ModelPicker.recommend(ModelPicker.detect())
	if args.has("model"):
		llm.model_path = LlmService.first_existing([args["model"]])
		if llm.model_path.is_empty():
			_say_system("No model file at '%s'." % args["model"])
	elif not args.has("no_models"):
		var found := ModelPicker.best_installed(pick["id"], ModelPicker.MODEL_DIRS, settings_path)
		if not found.is_empty():
			llm.model_path = found["path"]
	if not llm.model_path.is_empty():
		var recommended: String = ModelPicker.MODELS[pick["id"]]["name"]
		_say_system("Model: %s (suggested for this computer: %s)" % [llm.model_path.get_file(), recommended])
	else:
		_show_first_launch()


func _show_first_launch() -> void:
	var info: Dictionary = ModelPicker.MODELS[pick["id"]]
	_transcript.clear()
	_transcript.append_text("[b]Welcome to Scam Desk[/b]\n\nThe callers are played by an AI model that runs on your own computer, so nothing you say is sent anywhere and there is nothing to subscribe to. It needs one file, downloaded once: [b]%s[/b] (%.1f GB).\n\n%s\n\nPress Download to get it. You need an internet connection for this step only.\n" % [
			info["name"], info["size_gb"], _esc(pick["reason"])])
	_download_button.text = "Download %s (%.1f GB)" % [info["name"], info["size_gb"]]
	_download_button.disabled = false
	_download_button.visible = true
	_download_bar.visible = false
	_name_label.text = "First launch"
	_info_label.text = "One download, then you can play offline."


func _on_download_pressed() -> void:
	if _downloading:
		return
	_downloading = true
	_download_button.disabled = true
	_download_bar.value = 0
	_download_bar.visible = true
	var info: Dictionary = ModelPicker.MODELS[pick["id"]]
	var ref: String = args.get("download", info["hf"])
	llm.model_path = ref
	llm.start_timeout_s = 3600.0  # a first download of several GB takes a while
	if not llm.download_progress.is_connected(_on_download_progress):
		llm.download_progress.connect(_on_download_progress)
	_status_label.text = "Downloading..."
	_update_scoreboard()
	var ok := await llm.warm_up(personas[0] if not personas.is_empty() else Persona.load_file("res://callers/gladys.json"))
	llm.start_timeout_s = CallerBrain.START_TIMEOUT_S
	_downloading = false
	_download_bar.visible = false
	if ok:
		var local := LlmService.cached_file(ref.get_file())
		if not local.is_empty():
			llm.model_path = local  # from now on a plain file, so the GPU-to-CPU fallback applies
			ModelPicker.remember(pick["id"], local, settings_path)
		_download_button.visible = false
		_say_system("The model is ready. Clock in to start your first shift.")
		_status_label.text = ""
	else:
		var why := llm.last_error
		llm.model_path = ""
		_download_button.text = "Try again"
		_download_button.disabled = false
		_say_system("The download did not work (%s). Check your internet connection and press Try again." % why)
		_status_label.text = "Download failed"
	_update_scoreboard()


func _on_download_progress(done: int, total: int) -> void:
	_download_bar.max_value = maxi(total, 1)
	_download_bar.value = done
	_status_label.text = "Downloading: %d of %d MB" % [done / 1048576, total / 1048576]


func _start() -> void:
	await _setup_voice()
	if args.has("demo_shift"):
		_run_demo_shift()
	elif args.has("demo"):
		_run_demo()


## Loads speech-to-text and the chosen voice. Never blocks the desk for long and never fails the game: without them the
## player simply types and reads.
func _setup_voice() -> void:
	if voice_input.setup(not args.has("no_mic")):
		if voice_input.has_microphone():
			_say_system("Voice input ready: hold V (text box not selected) or the Hold to talk button.")
		else:
			_say_system("No microphone found, so type instead.")
	else:
		_say_system("Voice input is off: %s" % voice_input.last_error)
	_ptt_button.disabled = not voice_input.model_ready or not voice_input.has_microphone()
	var wanted: String = args.get("voice", "os")
	if wanted == "kokoro" or args.has("demo_voice"):
		await _use_kokoro(wanted != "kokoro")
	elif wanted == "off":
		voice.engine = "off"
	_sync_voice_option()


func _use_kokoro(then_back_to_os := false) -> void:
	_say_system("Loading the Kokoro voices (the first time this downloads 326 MB)...")
	if await voice.use_kokoro():
		_say_system("Kokoro voices ready.")
		if then_back_to_os:
			voice.use_os()
	else:
		_say_system("Kokoro could not start (%s): using the OS voices." % voice.last_error)
		voice.use_os()
	_sync_voice_option()


func _sync_voice_option() -> void:
	_voice_option.select({"os": 0, "kokoro": 1, "off": 2}.get(voice.engine, 0))


func _on_voice_option(index: int) -> void:
	match index:
		0:
			voice.use_os()
		1:
			await _use_kokoro()
		2:
			voice.engine = "off"
			voice.stop()


func _parse_args(list: PackedStringArray) -> Dictionary:
	var out := {}
	for a in list:
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out


# --- UI ------------------------------------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1b1f27")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	var title := Label.new()
	title.text = "SCAM DESK"
	title.add_theme_font_size_override("font_size", 28)
	top.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_calls_label = Label.new()
	_calls_label.add_theme_font_size_override("font_size", 20)
	top.add_child(_calls_label)
	var gap := Control.new()
	gap.custom_minimum_size.x = 32
	top.add_child(gap)
	_cash_label = Label.new()
	_cash_label.add_theme_font_size_override("font_size", 28)
	_cash_label.add_theme_color_override("font_color", Color("7be08a"))
	top.add_child(_cash_label)

	var hud := HBoxContainer.new()
	hud.add_theme_constant_override("separation", 20)
	root.add_child(hud)
	_day_label = Label.new()
	_day_label.add_theme_font_size_override("font_size", 22)
	hud.add_child(_day_label)
	_clock_label = Label.new()
	_clock_label.add_theme_font_size_override("font_size", 28)
	_clock_label.custom_minimum_size.x = 90
	hud.add_child(_clock_label)
	_quota_bar = ProgressBar.new()
	_quota_bar.custom_minimum_size = Vector2(300, 22)
	_quota_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_quota_bar.show_percentage = false
	hud.add_child(_quota_bar)
	_quota_label = Label.new()
	hud.add_child(_quota_label)
	_strikes_label = Label.new()
	hud.add_child(_strikes_label)
	var hud_spacer := Control.new()
	hud_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.add_child(hud_spacer)
	_download_bar = ProgressBar.new()
	_download_bar.custom_minimum_size = Vector2(240, 22)
	_download_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_download_bar.show_percentage = false
	_download_bar.visible = false
	hud.add_child(_download_bar)
	_download_button = Button.new()
	_download_button.visible = false
	_download_button.pressed.connect(_on_download_pressed)
	hud.add_child(_download_button)
	_clock_button = Button.new()
	_clock_button.pressed.connect(_on_clock_pressed)
	hud.add_child(_clock_button)

	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 12)
	root.add_child(main)

	var caller_panel := PanelContainer.new()
	caller_panel.custom_minimum_size.x = 300
	main.add_child(caller_panel)
	var cp := VBoxContainer.new()
	cp.add_theme_constant_override("separation", 8)
	caller_panel.add_child(cp)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 24)
	cp.add_child(_name_label)
	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cp.add_child(_info_label)
	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", COLOR_SYSTEM)
	cp.add_child(_status_label)
	var sus_title := Label.new()
	sus_title.text = "Suspicion"
	cp.add_child(sus_title)
	_suspicion_bar = ProgressBar.new()
	_suspicion_bar.min_value = 0
	_suspicion_bar.max_value = 100
	_suspicion_bar.show_percentage = false
	_suspicion_bar.custom_minimum_size.y = 22
	cp.add_child(_suspicion_bar)
	_suspicion_label = Label.new()
	cp.add_child(_suspicion_label)

	_transcript = RichTextLabel.new()
	_transcript.bbcode_enabled = true
	_transcript.scroll_following = true
	_transcript.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_transcript.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(_transcript)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	root.add_child(bottom)
	_line_edit = LineEdit.new()
	_line_edit.placeholder_text = "Type what you say to the caller, then press Enter"
	_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line_edit.text_submitted.connect(func(_t): _on_send())
	bottom.add_child(_line_edit)
	_send_button = Button.new()
	_send_button.text = "Say it"
	_send_button.pressed.connect(_on_send)
	bottom.add_child(_send_button)
	_hangup_button = Button.new()
	_hangup_button.text = "Hang up"
	_hangup_button.pressed.connect(func(): if session: session.player_hangs_up())
	bottom.add_child(_hangup_button)
	_voice_option = OptionButton.new()
	_voice_option.add_item("Voice: OS voices")
	_voice_option.add_item("Voice: Kokoro")
	_voice_option.add_item("Voice: off")
	_voice_option.item_selected.connect(_on_voice_option)
	bottom.add_child(_voice_option)
	_ptt_button = Button.new()
	_ptt_button.text = "Hold to talk (V)"
	_ptt_button.disabled = true
	_ptt_button.button_down.connect(_start_ptt)
	_ptt_button.button_up.connect(_stop_ptt)
	bottom.add_child(_ptt_button)
	_call_button = Button.new()
	_call_button.text = "Answer the phone"
	_call_button.pressed.connect(_on_call_pressed)
	bottom.add_child(_call_button)
	_update_scoreboard()


func _update_scoreboard() -> void:
	var shift_cash: int = shift.stats.cash if shift != null else 0
	var quota := state.quota()
	_cash_label.text = "Cash: $%s" % _thousands(shift_cash)
	_calls_label.text = "Calls: %d" % (shift.stats.calls if shift != null else 0)
	_day_label.text = "Day %d" % state.day
	_quota_bar.max_value = quota
	_quota_bar.value = mini(shift_cash, quota)
	_quota_bar.modulate = Color("7be08a") if shift_cash >= quota else Color("e0b34a")
	_quota_label.text = "Quota $%s" % _thousands(quota)
	var marks: Array[String] = []
	for i in GameState.MAX_STRIKES:
		marks.append("X" if i < state.strikes else "-")
	_strikes_label.text = "Strikes: %s" % " ".join(marks)
	_update_buttons()


func _update_buttons() -> void:
	var in_shift := shift != null and shift.running
	var on_call := session != null and session.active
	var model_ok := llm != null and llm.model_available() and not _downloading
	_call_button.disabled = not (in_shift and shift.can_take_call() and not on_call and model_ok) or _reviewing
	_clock_button.disabled = _reviewing or not model_ok
	if in_shift:
		_clock_button.text = "Clock out"
	elif state.fired:
		_clock_button.text = "New game"
	else:
		_clock_button.text = "Clock in (day %d)" % state.day


func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return ("-" if n < 0 else "") + out


func _say_system(text: String) -> void:
	_transcript.append_text("[color=#%s][i]%s[/i][/color]\n" % [COLOR_SYSTEM.to_html(false), _esc(text)])


func _esc(text: String) -> String:
	return text.replace("[", "[lb]")


func _set_idle() -> void:
	_name_label.text = "No call"
	_info_label.text = "Clock in, then answer the phone."
	_status_label.text = ""
	_set_suspicion(0)
	_suspicion_label.text = ""
	_line_edit.editable = false
	_send_button.disabled = true
	_hangup_button.disabled = true
	_update_buttons()


func _set_suspicion(value: int) -> void:
	_suspicion_bar.value = value
	_suspicion_label.text = "%d / 100" % value
	var t := clampf(value / 100.0, 0.0, 1.0)
	_suspicion_bar.modulate = Color("5fd16f").lerp(Color("ff5a4e"), t)


# --- Call flow -----------------------------------------------------------------------------------------------

func _on_call_pressed() -> void:
	if shift == null or not shift.can_take_call():
		return
	var caller := queue.next_caller(state.day)
	if caller.is_empty():
		_say_system("No callers found in callers/.")
		return
	await start_call(caller)


func start_call(persona: Dictionary) -> bool:
	_call_button.disabled = true
	_transcript.clear()
	_name_label.text = persona["name"]
	_info_label.text = "Age %d, savings $%s" % [persona["age"], _thousands(persona["savings"])]
	_status_label.text = "Ringing..."
	if session != null:
		session.queue_free()
	session = CallSession.new()
	add_child(session)
	session.transcript_line.connect(_on_line)
	session.suspicion_changed.connect(_set_suspicion)
	session.thinking_changed.connect(_on_thinking)
	session.ended.connect(_on_ended)
	if shift != null:
		shift.call_started()
	var ok := await session.start(llm, persona)
	if ok:
		# The caller speaks as soon as the spoken line is complete, before the rest of the reply is finished
		session.brain.say_ready.connect(func(text): voice.speak(ReplyParser.clean_say(text), persona))
		_status_label.text = "On the line"
		_line_edit.editable = true
		_send_button.disabled = false
		_hangup_button.disabled = false
		_line_edit.grab_focus()
	return ok


# --- The shift --------------------------------------------------------------------------------------------------

func _on_clock_pressed() -> void:
	if _reviewing:
		return  # the boss is still talking; the button is disabled, and this guards against a stray signal too
	if shift != null and shift.running:
		if Time.get_ticks_msec() - _shift_started_ms < CLOCK_OUT_DELAY_MS:
			return  # an accidental double click on Clock in
		_clock_out()
	else:
		_begin_shift()


func _begin_shift(seconds: float = -1.0) -> void:
	if _reviewing or (shift != null and shift.running):
		return
	if state.fired:
		state.new_run()
		state.save(save_path)
	_reviewing = false
	_last_report = {}
	_transcript.clear()
	shift = Shift.new()
	shift.save_path = save_path
	add_child(shift)
	shift.tick.connect(_on_tick)
	shift.overtime_started.connect(func(): _say_system("Time is up: finish your call!"))
	shift.finishing.connect(_on_shift_finishing)
	shift.ended.connect(_on_shift_ended.bind(shift))
	shift.begin(state, llm, seconds)
	_shift_started_ms = Time.get_ticks_msec()
	_say_system("You clock in for day %d. Quota: $%s. Answer the phone!" % [state.day, _thousands(state.quota())])
	_status_label.text = ""
	_update_scoreboard()


func _clock_out() -> void:
	if shift == null or not shift.running:
		return
	if session != null and session.active:
		session.player_hangs_up()
	shift.end_now()


func _on_tick(seconds_left: int) -> void:
	_clock_label.text = "%d:%02d" % [seconds_left / 60, seconds_left % 60]
	_clock_label.add_theme_color_override("font_color", Color("ff7a6e") if seconds_left <= 30 else Color("e8ecf1"))


func _on_shift_finishing() -> void:
	_reviewing = true
	_status_label.text = "The boss is reading your numbers..."
	_update_scoreboard()


func _on_shift_ended(report: Dictionary, finished_shift: Shift) -> void:
	_last_report = report
	_reviewing = false
	_transcript.clear()
	var passed: bool = report["passed"]
	var stats: Dictionary = report["stats"]
	_transcript.append_text("[b]SHIFT OVER: day %d[/b]\n" % report["day"])
	_transcript.append_text("[color=#%s][b]%s[/b][/color]  $%s of the $%s quota, %d calls, %d paid.\n\n" % [
			"7be08a" if passed else "ff7a6e", "PASSED" if passed else "FAILED", _thousands(report["cash"]), _thousands(report["quota"]), stats["calls"], stats["paid"]])
	_transcript.append_text("[color=#ffb347][b]Mr. Krunk:[/b] %s[/color]\n\n" % _esc(report["review"]["text"]))
	if report["fired"]:
		_transcript.append_text("[b][color=#ff7a6e]Three strikes. You are fired.[/color][/b] Press New game to start over.\n")
	else:
		_transcript.append_text("Strikes: %d of %d. Press Clock in for day %d.\n" % [report["strikes"], GameState.MAX_STRIKES, state.day])
	voice.speak(report["review"]["text"], Boss.VOICE)
	_name_label.text = "Mr. Krunk"
	_info_label.text = "Your boss"
	_status_label.text = "Review done"
	_set_suspicion(0)
	_suspicion_label.text = ""
	finished_shift.queue_free()
	if shift == finished_shift:
		shift = null
	_clock_label.text = "-"
	_update_scoreboard()


# --- Push to talk ----------------------------------------------------------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or key.keycode != KEY_V or key.echo:
		return
	if key.pressed:
		_start_ptt()
	else:
		_stop_ptt()
	get_viewport().set_input_as_handled()


func _start_ptt() -> void:
	if session == null or not session.active or session.thinking or not voice_input.has_microphone() or voice_input.listening:
		return
	voice.stop()  # talking over the caller cuts them off, as on a real phone
	voice_input.start_listening()
	_status_label.text = "Listening..."


func _stop_ptt() -> void:
	if not voice_input.listening:
		return
	await submit_voice(voice_input.stop_listening())


## Speech to text, then into the call. Public so the demo (and tests) can feed recorded audio instead of the microphone.
func submit_voice(samples: PackedFloat32Array) -> void:
	if session == null or not session.active:
		return
	if samples.is_empty():
		_say_system("(Nothing heard: hold the key while you speak.)")
		_status_label.text = "On the line"
		return
	_status_label.text = "Understanding you..."
	await get_tree().process_frame  # let the label show before the (blocking) transcription
	var heard := voice_input.transcribe(samples)
	last_voice_ms = {"stt_ms": heard["ms"], "released_at": Time.get_ticks_msec() - int(heard["ms"])}
	if String(heard["text"]).is_empty():
		_say_system("(Could not make that out.)")
		_status_label.text = "On the line"
		return
	session.player_says(heard["text"])


func _on_send() -> void:
	if session == null or not session.active:
		return
	var text := _line_edit.text
	_line_edit.clear()
	session.player_says(text)


func _on_line(role: String, text: String) -> void:
	match role:
		"player":
			_transcript.append_text("[color=#%s][b]You:[/b] %s[/color]\n" % [COLOR_PLAYER.to_html(false), _esc(text)])
		"caller":
			_transcript.append_text("[color=#%s][b]%s:[/b] %s[/color]\n" % [COLOR_CALLER.to_html(false), _esc(session.persona["name"].split(" ")[0]), _esc(text)])
		_:
			_say_system(text)


func _on_thinking(is_thinking: bool) -> void:
	if session == null:
		return
	if is_thinking:
		_status_label.text = "Loading the model..." if llm.state != "ready" else "%s is thinking..." % session.persona["name"].split(" ")[0]
		_line_edit.editable = false
		_send_button.disabled = true
	elif session.active:
		_status_label.text = "On the line"
		_line_edit.editable = true
		_send_button.disabled = false
		_line_edit.grab_focus()


func _on_ended(reason: String, summary: Dictionary) -> void:
	if reason == "player_hung_up":
		voice.stop()
	var text: String = {
		"paid": "Call over: they paid.", "hung_up": "Call over: they hung up.", "suspicion": "Call over: they figured you out.",
		"bad_reply": "Call over: the line went dead.", "player_hung_up": "Call over: you hung up.",
		"load_failed": "Could not start the call: %s" % summary.get("detail", "model failed to load"),
	}.get(reason, "Call over.")
	_say_system(text)
	_status_label.text = "Call ended"
	_line_edit.editable = false
	_send_button.disabled = true
	_hangup_button.disabled = true
	if shift != null:
		shift.call_finished(summary)
	_update_scoreboard()


# --- Demo / screenshot mode ------------------------------------------------------------------------------------

## A whole short day with scripted lines: clock in, answer calls from the queue, run out the clock, read the review.
func _run_demo_shift() -> void:
	var scams: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/test_scams.json"))
	_begin_shift(float(args.get("shift_s", "40")))
	var call_number := 0
	while shift != null and shift.can_take_call():
		call_number += 1
		var before := session
		_call_button.pressed.emit()  # the real button path
		while session == before or session == null:  # wait for the new call to exist...
			await get_tree().process_frame
		while session.thinking:  # ...and for the phone to be picked up (the first call also loads the model)
			await get_tree().process_frame
		if not session.active:
			break
		var pid: String = session.persona["id"]
		var lines: Array = (scams[pid][call_number % scams[pid].size()] as Array).duplicate()
		lines.append_array(scams["closers"])
		for line in lines:
			if not session.active:
				break
			_line_edit.text = line
			_on_send()
			while session.thinking:
				await get_tree().process_frame
		if session.active:
			session.player_hangs_up()
		await get_tree().create_timer(0.6).timeout
	var deadline := Time.get_ticks_msec() + 180000
	while _last_report.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var shot: String = args.get("shot", "")
	if not shot.is_empty():
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(shot.get_base_dir())
		get_viewport().get_texture().get_image().save_png(shot)
		print("DESK_DEMO screenshot saved: ", shot)
	if _last_report.is_empty():
		print("DESK_DEMO_SHIFT no report")
		get_tree().quit(2)
		return
	print("DESK_DEMO_SHIFT %s" % JSON.stringify({"day": _last_report["day"], "passed": _last_report["passed"], "cash": _last_report["cash"], "quota": _last_report["quota"],
			"calls": _last_report["stats"]["calls"], "paid": _last_report["stats"]["paid"], "strikes": _last_report["strikes"],
			"review_source": _last_report["review"]["source"], "review_ms": _last_report["review"]["ms"], "saved_day": GameState.load_or_new(save_path).day}))
	print("DESK_DEMO_BOSS ", _last_report["review"]["text"])
	llm.shutdown()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)


func _run_demo() -> void:
	var scams: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/test_scams.json"))
	var pid: String = args.get("persona", "gladys")
	var persona: Dictionary = personas.filter(func(p): return p["id"] == pid)[0]
	_begin_shift(600.0)  # the single-call demo still needs a shift: calls only happen on the clock
	if not await start_call(persona):
		get_tree().quit(2)
		return
	var lines: Array = scams[pid][0]
	for i in mini(int(args.get("turns", "2")), lines.size()):
		if not session.active:
			break
		if args.has("demo_voice"):
			var wav := await voice.synthesize_wav(lines[i], "am_adam")
			var info := AudioUtil.parse_wav(wav)
			await submit_voice(AudioUtil.to_mono_float(info, 16000))
		else:
			_line_edit.text = lines[i]
			_on_send()
		while session.thinking:  # player_says() sets this synchronously, so the loop starts at once
			await get_tree().process_frame
		await get_tree().create_timer(0.8).timeout  # let the caller's voice start before the next line
	await get_tree().create_timer(0.3).timeout
	var shot: String = args.get("shot", "")
	if not shot.is_empty():
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(shot.get_base_dir())
		get_viewport().get_texture().get_image().save_png(shot)
		print("DESK_DEMO screenshot saved: ", shot)
	print("DESK_DEMO cash=%d calls=%d transcript_chars=%d" % [shift.stats.cash, shift.stats.calls, _transcript.get_parsed_text().length()])
	if session.active:
		session.player_hangs_up()
	llm.shutdown()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)
