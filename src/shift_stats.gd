class_name ShiftStats
extends RefCounted
## What happened during one shift, collected from the summary of every finished call. The boss review is built from this.
## The "best line" is the last thing the player said before the biggest payment; the "worst line" is the last thing they
## said before a caller hung up on them or saw through them.

var calls := 0
var cash := 0
var paid := 0
var caller_hang_ups := 0  ## the caller ended the call (hung up, or worked out the scam)
var player_hang_ups := 0
var dead_lines := 0  ## a broken reply cut the call
var best_line := {}  ## {text, caller, amount}
var worst_line := {}  ## {text, caller, suspicion}
var callers: Array[String] = []


## Adds one finished call. `summary` is what CallSession.ended carries.
func record_call(summary: Dictionary) -> void:
	var reason: String = summary.get("reason", "")
	if reason == "load_failed":
		return  # the phone never rang: it is not a call
	calls += 1
	cash += int(summary.get("cash", 0))
	var caller_name: String = summary.get("name", "someone")
	callers.append(caller_name)
	var last_player_line := ""
	for entry in summary.get("history", []):
		if entry.get("role", "") == "player":
			last_player_line = String(entry.get("text", ""))
	match reason:
		"paid":
			paid += 1
			var amount := int(summary.get("cash", 0))
			if not last_player_line.is_empty() and amount > int(best_line.get("amount", 0)):
				best_line = {"text": last_player_line, "caller": caller_name, "amount": amount}
		"hung_up", "suspicion":
			caller_hang_ups += 1
			var suspicion := int(summary.get("suspicion", 0))
			if not last_player_line.is_empty() and suspicion >= int(worst_line.get("suspicion", -1)):
				worst_line = {"text": last_player_line, "caller": caller_name, "suspicion": suspicion}
		"player_hung_up":
			player_hang_ups += 1
		"bad_reply":
			dead_lines += 1


func to_dictionary() -> Dictionary:
	return {"calls": calls, "cash": cash, "paid": paid, "caller_hang_ups": caller_hang_ups, "player_hang_ups": player_hang_ups,
			"dead_lines": dead_lines, "best_line": best_line, "worst_line": worst_line, "callers": callers}
