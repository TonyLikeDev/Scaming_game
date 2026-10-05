class_name GameState
extends RefCounted
## What carries over between shifts: the day, the strikes, the money. Saved to `user://save.json` after every review.
## A missing or damaged save never crashes the game: it starts a new run instead.

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const MAX_STRIKES := 3  ## failed reviews before you are fired
const SHIFT_SECONDS := 480.0  ## about 8 real minutes
const QUOTA_FIRST_DAY := 400
const QUOTA_GROWTH := 1.15  ## each day's quota is 15% higher than the day before, rounded to $50
const HISTORY_LIMIT := 30

var day := 1
var strikes := 0
var total_cash := 0
var best_day_cash := 0
var fired := false
var history: Array[Dictionary] = []  ## [{day, cash, quota, passed}], newest last


## The cash needed to pass a day's review. $400 on day 1, 15% more each day, to the nearest $50.
static func quota_for_day(for_day: int) -> int:
	var raw := float(QUOTA_FIRST_DAY) * pow(QUOTA_GROWTH, float(maxi(for_day, 1) - 1))
	return int(roundf(raw / 50.0)) * 50


func quota() -> int:
	return quota_for_day(day)


## Seconds of shift for the current day. Constant for now; kept here so days could get longer or shorter.
func shift_seconds() -> float:
	return SHIFT_SECONDS


## Ends the day: records the result, moves to the next day and counts a strike if the quota was missed.
## Returns {passed, cash, quota, day, strikes, fired}, where `day` is the day that just ended.
func finish_shift(cash: int) -> Dictionary:
	var ended_day := day
	var needed := quota()
	var passed := cash >= needed
	total_cash += cash
	best_day_cash = maxi(best_day_cash, cash)
	if not passed:
		strikes += 1
	if strikes >= MAX_STRIKES:
		fired = true
	history.append({"day": ended_day, "cash": cash, "quota": needed, "passed": passed})
	if history.size() > HISTORY_LIMIT:
		history = history.slice(history.size() - HISTORY_LIMIT)
	day += 1
	return {"passed": passed, "cash": cash, "quota": needed, "day": ended_day, "strikes": strikes, "fired": fired}


## Starts over after being fired (or on request). The best day survives as a record.
func new_run() -> void:
	var record := best_day_cash
	day = 1
	strikes = 0
	total_cash = 0
	fired = false
	history = []
	best_day_cash = record


func to_dictionary() -> Dictionary:
	return {"version": SAVE_VERSION, "day": day, "strikes": strikes, "total_cash": total_cash, "best_day_cash": best_day_cash,
			"fired": fired, "history": history}


## Writes the save through a temporary file, so a crash while saving cannot leave half a file behind.
func save(path: String = SAVE_PATH) -> bool:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("Cannot write the save (%s)" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(to_dictionary(), "\t"))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_warning("Cannot finish the save (%s)" % error_string(err))
		return false
	return true


## Loads a save, or returns a fresh state when the file is missing or damaged. Values are clamped to sensible ranges.
static func load_or_new(path: String = SAVE_PATH) -> GameState:
	var state := GameState.new()
	if not FileAccess.file_exists(path):
		return state
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("The save file is damaged; starting a new run.")
		return state
	var d: Dictionary = json.data
	for key in ["day", "strikes", "total_cash", "best_day_cash"]:
		if d.has(key) and typeof(d[key]) != TYPE_FLOAT and typeof(d[key]) != TYPE_INT:
			push_warning("The save file has a bad '%s'; starting a new run." % key)
			return GameState.new()
	state.day = clampi(int(d.get("day", 1)), 1, 9999)
	state.strikes = clampi(int(d.get("strikes", 0)), 0, MAX_STRIKES)
	state.total_cash = maxi(int(d.get("total_cash", 0)), 0)
	state.best_day_cash = maxi(int(d.get("best_day_cash", 0)), 0)
	state.fired = bool(d.get("fired", false)) or state.strikes >= MAX_STRIKES
	if typeof(d.get("history")) == TYPE_ARRAY:
		for entry in d["history"]:
			if typeof(entry) == TYPE_DICTIONARY and entry.has("day") and entry.has("cash") and entry.has("quota") and entry.has("passed"):
				state.history.append({"day": int(entry["day"]), "cash": int(entry["cash"]), "quota": int(entry["quota"]), "passed": bool(entry["passed"])})
		if state.history.size() > HISTORY_LIMIT:
			state.history = state.history.slice(state.history.size() - HISTORY_LIMIT)
	return state
