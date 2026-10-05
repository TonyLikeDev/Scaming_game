class_name CallSession
extends Node
## One phone call from ring to hang-up: the rules of the call, with no UI. The desk binds to its signals and the
## automated playtest drives it directly. A call ends on `pay`, `hang_up`, suspicion 100, or a broken reply
## (docs/PLAN.md, Phase 2).

signal transcript_line(role: String, text: String)  ## role: "player", "caller" or "system"
signal suspicion_changed(value: int)
signal thinking_changed(is_thinking: bool)
signal caller_spoke(text: String, persona: Dictionary)
signal cash_earned(amount: int)
signal ended(reason: String, summary: Dictionary)  ## reason: paid, hung_up, suspicion, bad_reply, player_hung_up, load_failed

var persona: Dictionary = {}
var brain: CallerBrain
var active := false
var suspicion := 0
var cash := 0
var turns := 0
var last_reply: Dictionary = {}
## What was said, for the boss review: [{role: "player"|"caller", text, action, amount, suspicion}]. Only the words that
## were spoken: the director's private notes (which the brain hears) are never in here.
var log: Array[Dictionary] = []
var director := CallDirector.new()  ## decides when the caller is persuaded; see call_director.gd
var _llm: LlmService
var thinking := false  ## true while the caller is answering (or the model is loading)


## Dials the caller. Returns false (and emits `ended` with "load_failed") when no model is available.
func start(llm: LlmService, caller: Dictionary) -> bool:
	_llm = llm
	persona = caller
	suspicion = CallerPrompt.starting_suspicion(persona)
	_set_thinking(true)  # covers model loading on the first call
	brain = await llm.start_call(persona)
	_set_thinking(false)
	if brain == null:
		_finish("load_failed", llm.last_error)
		return false
	active = true
	director.plan_call()
	suspicion_changed.emit(suspicion)
	transcript_line.emit("system", "%s picks up." % persona["name"])
	return true


## What the player said (typed, or transcribed from the microphone). Exactly one caller reply follows.
func player_says(text: String) -> void:
	var line := text.strip_edges()
	if not active or thinking or line.is_empty():
		return
	transcript_line.emit("player", line)
	log.append({"role": "player", "text": line})
	_set_thinking(true)
	brain.ask(line + director.note_for(persona, line, turns, suspicion))
	var reply: Dictionary = await brain.reply_ready
	_set_thinking(false)
	if not active:
		return  # the player hung up while the caller was still thinking
	last_reply = reply
	turns += 1
	if not reply["ok"]:
		transcript_line.emit("system", "The line goes dead. (%s)" % reply.get("reason", "bad reply"))
		_finish("bad_reply", reply.get("reason", ""))
		return
	suspicion = reply["suspicion"]
	suspicion_changed.emit(suspicion)
	log.append({"role": "caller", "text": reply["say"], "action": reply["action"], "amount": reply["amount"], "suspicion": suspicion})
	transcript_line.emit("caller", reply["say"])
	caller_spoke.emit(reply["say"], persona)
	match reply["action"]:
		"pay":
			cash += reply["amount"]
			cash_earned.emit(reply["amount"])
			transcript_line.emit("system", "%s pays $%d!" % [persona["name"], reply["amount"]])
			_finish("paid")
		"hang_up":
			transcript_line.emit("system", "%s hangs up." % persona["name"])
			_finish("hung_up")
		"counter_attack":
			transcript_line.emit("system", "%s strikes back!" % persona["name"])  # Phase 5 adds the malware minigame
		_:
			if suspicion >= 100:
				transcript_line.emit("system", "%s has figured you out and hangs up." % persona["name"])
				_finish("suspicion")


func player_hangs_up() -> void:
	if active:
		transcript_line.emit("system", "You hang up.")
		_finish("player_hung_up")


func _finish(reason: String, detail := "") -> void:
	var was_active := active
	active = false
	if brain != null:
		brain.end_call()
		brain.queue_free()
		brain = null
	if was_active or reason == "load_failed":
		ended.emit(reason, {"reason": reason, "detail": detail, "persona": persona.get("id", ""), "cash": cash,
				"turns": turns, "suspicion": suspicion, "history": log.duplicate(true), "name": persona.get("name", ""),
				"event": director.event_text if director.event_fired else ""})


func _set_thinking(value: bool) -> void:
	thinking = value
	thinking_changed.emit(value)
