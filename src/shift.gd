class_name Shift
extends Node
## One working day. It owns the clock, collects what happened in each call, and at the end scores the day against the
## quota, saves, and gets the boss's review. A call that is still going when the clock runs out may finish (up to a minute)
## so a sale is never thrown away at the last second.
##
## Usage: begin(state, llm); call call_started() / call_finished(summary) around each call; listen for `ended`.

signal tick(seconds_left: int)
signal overtime_started
signal finishing  ## the clock has run out and the review is being written
signal ended(report: Dictionary)  ## {day, passed, cash, quota, strikes, fired, total_cash, stats, review: {text, source, ms}}

const OVERTIME_LIMIT_S := 60.0

var state: GameState
var llm: LlmService
var stats := ShiftStats.new()
var time_left := 0.0
var running := false
var call_active := false
var save_path := GameState.SAVE_PATH  ## tests point this somewhere else

var _overtime := 0.0
var _last_tick := -1
var _ending := false


## Starts the day. `seconds` overrides the length of the shift (tests and demos use a short one).
func begin(game_state: GameState, service: LlmService, seconds: float = -1.0) -> void:
	state = game_state
	llm = service
	stats = ShiftStats.new()
	time_left = seconds if seconds > 0.0 else state.shift_seconds()
	running = true
	call_active = false
	_overtime = 0.0
	_last_tick = -1
	_ending = false
	tick.emit(int(ceil(time_left)))


## True while there is time to answer another call.
func can_take_call() -> bool:
	return running and not _ending and time_left > 0.0


func call_started() -> void:
	call_active = true


func call_finished(summary: Dictionary) -> void:
	call_active = false
	stats.record_call(summary)


func _process(delta: float) -> void:
	if not running or _ending:
		return
	if time_left > 0.0:
		time_left = maxf(time_left - delta, 0.0)
		var seconds := int(ceil(time_left))
		if seconds != _last_tick:
			_last_tick = seconds
			tick.emit(seconds)
	if time_left > 0.0:
		return
	if call_active and _overtime < OVERTIME_LIMIT_S:
		if _overtime == 0.0:
			overtime_started.emit()
		_overtime += delta
		return
	_finish()


## Clocks out right now (the caller must have hung up any call in progress).
func end_now() -> void:
	if running and not _ending:
		time_left = 0.0
		call_active = false
		_finish()


func _finish() -> void:
	_ending = true
	running = false
	finishing.emit()
	var result := state.finish_shift(stats.cash)
	state.save(save_path)
	var report := {"day": result["day"], "passed": result["passed"], "cash": result["cash"], "quota": result["quota"],
			"strikes": result["strikes"], "fired": result["fired"], "total_cash": state.total_cash, "stats": stats.to_dictionary()}
	report["review"] = await Boss.review(llm, report)
	ended.emit(report)
