class_name CallerBrain
extends Node
## One phone call. Wraps a NobodyWho chat that plays a persona and answers in the JSON reply format
## (docs/PLAN.md). The model node is shared between calls; each call gets its own chat and history.
##
## Usage:
##   var brain := CallerBrain.new(); add_child(brain)
##   brain.begin(model_node, persona)
##   if await brain.wait_started(): brain.ask("Hello ma'am"); var reply: Dictionary = await brain.reply_ready
##
## `reply_ready` always fires once per ask(). A reply with ok == false means the game hangs up (never a crash).

signal token_streamed(text: String)
signal say_ready(text: String)  ## the spoken line is complete, so TTS can start before the rest is generated
signal reply_ready(reply: Dictionary)  ## ReplyParser result plus timing fields
signal call_failed(reason: String)

const DEFAULT_CONTEXT := 4096
const START_TIMEOUT_S := 180.0
const TURN_TIMEOUT_S := 45.0
## A real reply is about 50-70 tokens. Past this the model is looping, so the turn is cut off and counts as a bad line.
const MAX_REPLY_TOKENS := 220

var persona: Dictionary = {}
var suspicion := 0
var turn_count := 0
var history: Array[Dictionary] = []  ## [{role: "caller"|"player", text, ...}], for the transcript and the boss review

var _chat: Node
var _schema: Dictionary = {}
var _grammar := ""
var _buffer := ""
var _token_count := 0
var _say_sent := false
var _t_ask := 0
var _t_first := -1
var _t_say := -1
var _turn_id := 0
var _busy := false
var _started := false
var _failed := false
var failure_reason := ""


## Creates the chat. Returns false when the NobodyWho addon is missing.
## `options`: context_length, allow_thinking, rules_path, order (reply key order name),
## constraint ("grammar", the default, or "schema": how the reply format is enforced).
func begin(model_node: Node, persona_data: Dictionary, options: Dictionary = {}) -> bool:
	persona = persona_data
	suspicion = CallerPrompt.starting_suspicion(persona)
	if not ClassDB.class_exists("NobodyWhoChat"):
		push_error("NobodyWho addon is not loaded; run scripts/setup_addons.py")
		_failed = true
		return false
	_chat = ClassDB.instantiate("NobodyWhoChat")
	_chat.model_node = model_node
	_schema = ReplyParser.schema_for(options.get("order", ReplyParser.DEFAULT_ORDER))
	_grammar = ReplyParser.grammar_for(options.get("order", ReplyParser.DEFAULT_ORDER)) if options.get("constraint", "grammar") == "grammar" else ""
	_chat.system_prompt = CallerPrompt.system_prompt(persona, options)
	_chat.context_length = int(options.get("context_length", DEFAULT_CONTEXT))
	_chat.allow_thinking = bool(options.get("allow_thinking", false))
	add_child(_chat)
	_chat.response_updated.connect(_on_token)
	_chat.response_finished.connect(_on_finished)
	_chat.worker_started.connect(_on_worker_started)
	_chat.worker_failed.connect(_on_worker_failed)
	_chat.start_worker()
	return true


## Waits until the model is loaded and the chat is ready. Returns false on failure or timeout (see `failure_reason`).
func wait_started(timeout_s: float = START_TIMEOUT_S) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while not _started and not _failed and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return _started and not _failed


## Sends what the player said. Exactly one `reply_ready` follows, even on failure or timeout.
func ask(player_text: String) -> void:
	if _busy or _chat == null or _failed:
		reply_ready.emit({"ok": false, "reason": "call is not ready" if not _failed else "call failed"})
		return
	_busy = true
	_turn_id += 1
	_buffer = ""
	_token_count = 0
	_say_sent = false
	_t_first = -1
	_t_say = -1
	_t_ask = Time.get_ticks_msec()
	history.append({"role": "player", "text": player_text})
	_chat.ask(player_text)
	var this_turn := _turn_id
	get_tree().create_timer(TURN_TIMEOUT_S).timeout.connect(func(): _on_timeout(this_turn))


## Stops any generation and frees the chat. Safe to call twice.
func end_call() -> void:
	if _chat != null and is_instance_valid(_chat):
		_chat.stop_generation()
		_chat.queue_free()
	_chat = null
	_busy = false


func get_stats() -> Dictionary:
	if _chat == null:
		return {}
	var stats: Variant = _chat.get_stats()
	return stats if typeof(stats) == TYPE_DICTIONARY else {"raw": str(stats)}


## The sampler config is dropped if it is set before the worker is up ("Worker not started, dropping sampler config").
func _on_worker_started() -> void:
	if _grammar.is_empty():
		_chat.set_sampler_preset_constrain_with_json_schema(JSON.stringify(_schema))
	else:
		_chat.set_sampler_preset_constrain_with_grammar(_grammar)
	_started = true


func _on_token(piece: String) -> void:
	if not _busy:
		return
	if _t_first < 0:
		_t_first = Time.get_ticks_msec() - _t_ask
	_token_count += 1
	_buffer += piece
	if _token_count > MAX_REPLY_TOKENS:
		_abort_turn("reply too long (over %d tokens)" % MAX_REPLY_TOKENS)
		return
	token_streamed.emit(piece)
	if not _say_sent:
		var said := ReplyParser.say_if_complete(_buffer)
		if not said.is_empty():
			_say_sent = true
			_t_say = Time.get_ticks_msec() - _t_ask
			say_ready.emit(said)


func _on_finished(full_text: String) -> void:
	if not _busy:
		return
	_busy = false
	_turn_id += 1  # cancels the pending timeout
	var total_ms := Time.get_ticks_msec() - _t_ask
	var reply := ReplyParser.parse(full_text, persona)
	reply["raw"] = full_text
	reply["ttft_ms"] = _t_first
	reply["say_ms"] = _t_say
	reply["total_ms"] = total_ms
	reply["tokens"] = _token_count
	turn_count += 1
	if reply["ok"]:
		suspicion = reply["suspicion"]
		history.append({"role": "caller", "text": reply["say"], "suspicion": suspicion, "action": reply["action"], "amount": reply["amount"]})
	reply_ready.emit(reply)


func _on_timeout(turn: int) -> void:
	if _busy and turn == _turn_id:
		_abort_turn("timeout after %d s" % int(TURN_TIMEOUT_S))


## Cuts the current turn off and reports it as a bad reply (the game answers with a hang-up).
func _abort_turn(reason: String) -> void:
	_busy = false
	_turn_id += 1
	if _chat != null:
		_chat.stop_generation()
	reply_ready.emit({"ok": false, "reason": reason, "raw": _buffer, "ttft_ms": _t_first, "say_ms": _t_say,
			"total_ms": Time.get_ticks_msec() - _t_ask, "tokens": _token_count})


func _on_worker_failed(error: String) -> void:
	_failed = true
	failure_reason = error
	push_warning("Caller worker failed: %s" % error)
	call_failed.emit(error)
	if _busy:
		_busy = false
		reply_ready.emit({"ok": false, "reason": "worker failed: %s" % error, "raw": _buffer,
				"ttft_ms": _t_first, "say_ms": _t_say, "total_ms": Time.get_ticks_msec() - _t_ask, "tokens": _token_count})
