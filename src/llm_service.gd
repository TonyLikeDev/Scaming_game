class_name LlmService
extends Node
## Owns the one NobodyWho model node that every call shares, and hands out ready CallerBrains.
## If the model fails to load on the GPU it retries once on the CPU (a GPU load failed at random during early tests,
## see ROADMAP.md Phase 1 notes), so a call never dies just because of the graphics driver.

signal model_state_changed(state: String)  ## "loading", "ready", "failed"
signal download_progress(downloaded: int, total: int)  ## while a model given as "hf:owner/repo/file.gguf" is being downloaded

## `model_path` is a file on disk, or a Hugging Face reference "hf:owner/repo/file.gguf", which NobodyWho downloads the first
## time the model is loaded (and keeps in its cache folder).
var model_path := ""
var start_timeout_s := CallerBrain.START_TIMEOUT_S  ## how long to wait for a model to load; a first download needs far longer
var use_gpu := true
var options := {}  ## passed to every CallerBrain.begin(): context_length, allow_thinking, rules_path, order
var state := "idle"
var last_error := ""
var loaded_on_gpu := false

var _model: Node


## Absolute path of the first existing file from `candidates` (paths relative to the project, or absolute), else "".
static func first_existing(candidates: Array) -> String:
	for c in candidates:
		var p: String = c
		var abs_path := ProjectSettings.globalize_path("res://" + p) if p.is_relative_path() else p
		if FileAccess.file_exists(abs_path):
			return abs_path
	return ""


## True when `model_path` names a model that can be loaded: an existing file, or a Hugging Face reference to download.
func model_available() -> bool:
	return is_remote() or (not model_path.is_empty() and FileAccess.file_exists(model_path))


func is_remote() -> bool:
	var p := model_path.to_lower()
	return p.begins_with("hf:") or p.begins_with("huggingface:")


## Loads the model now (downloading it first if `model_path` is a Hugging Face reference), so the first call does not wait.
## Returns true when it is ready. `persona` is any caller; the chat made for the test is thrown away.
func warm_up(persona: Dictionary) -> bool:
	var brain := await start_call(persona)
	if brain == null:
		return false
	brain.end_call()
	brain.queue_free()
	await get_tree().create_timer(0.3).timeout  # let the chat's memory be released before a real call needs it
	return true


## The local file NobodyWho cached for a downloaded model, "" if it is not cached. `file_name` is the .gguf file's name.
static func cached_file(file_name: String) -> String:
	if not ClassDB.class_exists("NobodyWhoModel"):
		return ""
	for entry in ClassDB.instantiate("NobodyWhoModel").get_cached_models():
		if String(entry.get("path", "")).replace("\\", "/").ends_with("/" + file_name):
			return String(entry["path"])
	return ""


## Starts a call: returns a CallerBrain that is ready for `ask()`, or null when no model could be loaded.
func start_call(persona: Dictionary) -> CallerBrain:
	if not model_available():
		_set_state("failed", "model file not found: '%s'" % model_path)
		return null
	if _model == null:
		_make_model(use_gpu)
	var brain := _new_brain(persona)
	if state == "idle" or state == "failed":
		_set_state("loading")
	if await brain.wait_started(start_timeout_s):
		loaded_on_gpu = use_gpu
		_set_state("ready")
		return brain
	var reason := brain.failure_reason
	brain.end_call()
	brain.free()
	if is_remote():
		# A model that could not be downloaded or loaded the first time: there is nothing to fall back to on the CPU
		_set_state("failed", reason if not reason.is_empty() else "the download did not finish")
		return null
	if reason.contains("Could not create context"):
		# The previous call's chat may not have given its GPU memory back yet; wait a moment and try once more.
		await get_tree().create_timer(1.0).timeout
		brain = _new_brain(persona)
		if await brain.wait_started():
			loaded_on_gpu = use_gpu
			_set_state("ready")
			return brain
		reason = brain.failure_reason
		brain.end_call()
		brain.free()
	if use_gpu:
		push_warning("Model failed to load on the GPU (%s); retrying on the CPU" % reason)
		use_gpu = false
		_model.queue_free()
		_model = null
		_make_model(false)
		brain = _new_brain(persona)
		if await brain.wait_started():
			loaded_on_gpu = false
			_set_state("ready")
			return brain
		reason = brain.failure_reason
		brain.end_call()
		brain.queue_free()
	_set_state("failed", reason if not reason.is_empty() else "load timeout")
	return null


## Free-form text with no reply grammar (the boss review uses it): a throwaway chat on the shared model.
## Returns {ok, text, ms, reason}. Never throws: a model that cannot answer gives ok false and a reason.
func generate_text(system_prompt: String, user_message: String, max_tokens := 170, timeout_s := 90.0) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	if not model_available() or not ClassDB.class_exists("NobodyWhoChat"):
		return {"ok": false, "text": "", "reason": "no model", "ms": 0}
	if _model == null:
		_make_model(use_gpu)
	await get_tree().create_timer(0.3).timeout  # the last call's chat is still giving its GPU memory back
	var chat: Node = ClassDB.instantiate("NobodyWhoChat")
	chat.model_node = _model
	chat.system_prompt = system_prompt
	chat.context_length = 2048
	chat.allow_thinking = false
	add_child(chat)
	var state := {"started": false, "failed": "", "done": false, "text": "", "partial": "", "tokens": 0}
	chat.worker_started.connect(func(): state["started"] = true)
	chat.worker_failed.connect(func(error): state["failed"] = str(error))
	chat.response_updated.connect(func(piece):
		state["partial"] += piece
		state["tokens"] += 1
		if state["tokens"] > max_tokens and not state["done"]:
			chat.stop_generation()
			state["done"] = true)
	chat.response_finished.connect(func(full):
		state["text"] = full
		state["done"] = true)
	chat.start_worker()
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while not state["started"] and state["failed"] == "" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not state["started"]:
		chat.queue_free()
		return {"ok": false, "text": "", "reason": state["failed"] if state["failed"] != "" else "timeout while loading", "ms": Time.get_ticks_msec() - t0}
	chat.ask(user_message)
	while not state["done"] and state["failed"] == "" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var text: String = state["text"] if state["text"] != "" else state["partial"]
	chat.stop_generation()
	chat.queue_free()
	await get_tree().create_timer(0.3).timeout  # let the context be released before the next call needs the memory
	if text.strip_edges().is_empty():
		return {"ok": false, "text": "", "reason": state["failed"] if state["failed"] != "" else "empty answer", "ms": Time.get_ticks_msec() - t0}
	return {"ok": true, "text": text, "reason": "", "ms": Time.get_ticks_msec() - t0}


## The shared model node (null until the first call starts). The playtest bot builds its own chat on it.
func get_model_node() -> Node:
	return _model


func shutdown() -> void:
	if _model != null and is_instance_valid(_model):
		_model.queue_free()
	_model = null


func _make_model(gpu: bool) -> void:
	_model = ClassDB.instantiate("NobodyWhoModel")
	_model.model_path = model_path
	_model.use_gpu_if_available = gpu
	_model.download_progress.connect(func(done, total): download_progress.emit(done, total))
	add_child(_model)


func _new_brain(persona: Dictionary) -> CallerBrain:
	var brain := CallerBrain.new()
	add_child(brain)
	brain.begin(_model, persona, options)
	return brain


func _set_state(new_state: String, error := "") -> void:
	state = new_state
	last_error = error
	model_state_changed.emit(new_state)
