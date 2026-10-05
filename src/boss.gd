class_name Boss
extends RefCounted
## The boss and the end-of-shift review. Whether you passed is plain arithmetic done by the game (cash against the quota);
## the model only writes the rant that goes with it, from the real numbers and your real best and worst lines. If the model
## cannot answer, a written fallback is used, so a review always happens.

const RULES_PATH := "res://data/boss_rules.txt"
const MAX_TOKENS := 170
const MIN_CHARS := 40
const MAX_CHARS := 700

## Voice data in the shape the voice engine expects of a persona.
const VOICE := {"id": "boss", "name": "Mr. Krunk", "voice": "en-US", "kokoro_voice": "bm_george"}


static func passed(cash: int, quota: int) -> bool:
	return cash >= quota


## How good the day was, as a word the boss can match his temper to. The game works this out, so the model never has to
## judge numbers (it called $1138 against a $400 quota "barely scraped by").
static func performance_word(cash: int, quota: int) -> String:
	var ratio := float(cash) / maxf(float(quota), 1.0)
	if ratio >= 2.0:
		return "outstanding"
	if ratio >= 1.25:
		return "good"
	if ratio >= 1.0:
		return "just enough"
	if ratio >= 0.5:
		return "poor"
	return "disastrous"


const _ONES := ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen",
		"fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
const _TENS := ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]


## A whole number in English words ("four hundred and fifty"). The boss is given amounts in words as well as digits, because
## the model misread $450 as "forty dollars" when it only had the digits.
static func number_words(n: int) -> String:
	if n < 0:
		return "minus " + number_words(-n)
	if n < 20:
		return _ONES[n]
	if n < 100:
		return _TENS[n / 10] + ("" if n % 10 == 0 else "-" + _ONES[n % 10])
	if n < 1000:
		return _ONES[n / 100] + " hundred" + ("" if n % 100 == 0 else " and " + number_words(n % 100))
	if n < 1000000:
		var rest := n % 1000
		var head := number_words(n / 1000) + " thousand"
		if rest == 0:
			return head
		return head + (" and " if rest < 100 else ", ") + number_words(rest)
	return str(n)


## What the boss sounds like for each performance word. This goes into the report as an instruction, because the model
## follows a direct "your tone" line far better than a general rule.
const TONES := {
	"outstanding": "SHOCKED and almost speechless. You are reluctantly impressed and can barely get the praise out. Do not call it a bare pass.",
	"good": "grudging and insulting. You admit it was a good day, through gritted teeth.",
	"just enough": "a sneer. They only just made it and you want them to know how close it was.",
	"poor": "furious. They missed the quota and you shout about the money.",
	"disastrous": "APOPLECTIC. Scream. It was a catastrophe.",
}


## The report handed to the model: plain facts, one per line.
## `report`: {day, passed, cash, quota, strikes, fired, stats} where stats is ShiftStats.to_dictionary().
static func facts(report: Dictionary) -> String:
	var stats: Dictionary = report["stats"]
	var lines := PackedStringArray()
	lines.append("SHIFT REPORT, day %d" % report["day"])
	lines.append("Verdict: %s" % ("PASS" if report["passed"] else "FAIL"))
	lines.append("Cash earned: $%d (%s dollars), quota: $%d (%s dollars)" % [report["cash"], number_words(report["cash"]), report["quota"], number_words(report["quota"])])
	lines.append("Performance: %s (%d%% of the quota)" % [performance_word(report["cash"], report["quota"]), roundi(100.0 * float(report["cash"]) / maxf(float(report["quota"]), 1.0))])
	lines.append("Calls taken: %d (%d paid, %d ended by the caller, %d hung up on by the employee, %d dead lines)" % [
			stats["calls"], stats["paid"], stats["caller_hang_ups"], stats["player_hang_ups"], stats["dead_lines"]])
	var best: Dictionary = stats["best_line"]
	if not best.is_empty():
		lines.append("Best line: \"%s\" (%s paid $%d)" % [best["text"], best["caller"], best["amount"]])
	else:
		lines.append("Best line: none, nobody paid")
	var worst: Dictionary = stats["worst_line"]
	if not worst.is_empty():
		lines.append("Worst line: \"%s\" (%s hung up)" % [worst["text"], worst["caller"]])
	lines.append("Strikes: %d of %d" % [report["strikes"], GameState.MAX_STRIKES])
	if report["fired"]:
		lines.append("This was the third strike: the employee is FIRED.")
	lines.append("Your tone: %s" % TONES[performance_word(report["cash"], report["quota"])])
	lines.append("Give the review.")
	return "\n".join(lines)


## A written review for when the model is unavailable. Uses the same facts, so it is still the right review.
static func fallback_rant(report: Dictionary) -> String:
	var stats: Dictionary = report["stats"]
	if report["fired"]:
		return "That is strike three! You brought in $%d against a quota of $%d. Clear your desk, you are fired, and take the stapler with you!" % [report["cash"], report["quota"]]
	if report["passed"]:
		return "$%d against a quota of $%d. Fine. Don't get a big head, you only took %d calls and %d of them paid. Do it again tomorrow, and try not to hang up on people!" % [
				report["cash"], report["quota"], stats["calls"], stats["paid"]]
	return "$%d! The quota was $%d! That is strike %d of %d, and at three you are out on the pavement. Get on the phones tomorrow and bring me money!" % [
			report["cash"], report["quota"], report["strikes"], GameState.MAX_STRIKES]


## Tidies the model's rant for the screen and the voice, or returns "" if it is unusable.
static func clean_review(text: String) -> String:
	var cleaned := ReplyParser.clean_say(text.replace("\n", " "))
	if cleaned.length() < MIN_CHARS:
		return ""
	if cleaned.length() > MAX_CHARS:
		var cut := cleaned.rfind(".", MAX_CHARS)
		cleaned = cleaned.substr(0, cut + 1) if cut > MIN_CHARS else cleaned.substr(0, MAX_CHARS)
	return cleaned


## Writes the review. Returns {text, source: "model" or "fallback", ms}.
static func review(llm: LlmService, report: Dictionary) -> Dictionary:
	var t := Time.get_ticks_msec()
	var rules := FileAccess.get_file_as_string(RULES_PATH)
	var result: Dictionary = await llm.generate_text(rules, facts(report), MAX_TOKENS)
	var text := clean_review(String(result.get("text", ""))) if result.get("ok", false) else ""
	if text.is_empty():
		return {"text": fallback_rant(report), "source": "fallback", "ms": Time.get_ticks_msec() - t, "reason": result.get("reason", "empty")}
	return {"text": text, "source": "model", "ms": Time.get_ticks_msec() - t}
