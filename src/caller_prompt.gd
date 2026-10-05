class_name CallerPrompt
extends RefCounted
## Builds the system prompt for a caller: the shared rules plus the persona's profile.

## The rules the game uses. v1 and v2 are kept so the benchmark rows that used them can be repeated.
const RULES_PATH := "res://data/caller_rules_v3.txt"

static var _rules_cache := {}


## The shared rules text with {KEYS} (the reply key order) and {EXAMPLES} (sample replies in that order) filled in.
static func rules(path: String = RULES_PATH, order_name: String = ReplyParser.DEFAULT_ORDER) -> String:
	var cache_key := "%s|%s" % [path, order_name]
	if not _rules_cache.has(cache_key):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			push_error("Cannot read %s" % path)
			return ""
		var text := file.get_as_text().strip_edges()
		text = text.replace("{KEYS}", ", ".join(ReplyParser.key_order(order_name)))
		text = text.replace("{EXAMPLES}", examples(order_name))
		_rules_cache[cache_key] = text
	return _rules_cache[cache_key]


## Three sample replies (talk, pay, hang up), written in the chosen key order. They show the format, not the wording.
static func examples(order_name: String) -> String:
	var samples := [
		{"say": "Oh dear, a warranty? Hold on, let me find my glasses.", "suspicion": 12, "action": "talk", "amount": 0},
		{"say": "Fine, you've convinced me. My card is four two four two, four two four two, four two four two, four two four two.", "suspicion": 15, "action": "pay", "amount": 300},
		{"say": "I don't think so. Goodbye.", "suspicion": 95, "action": "hang_up", "amount": 0},
	]
	var lines := PackedStringArray()
	for sample in samples:
		var ordered := {}
		for key in ReplyParser.key_order(order_name):
			ordered[key] = sample[key]
		lines.append(JSON.stringify(ordered))
	return "\n".join(lines)


## Suspicion at the start of the call: trusting callers start near 0, suspicious ones near 40.
static func starting_suspicion(persona: Dictionary) -> int:
	return roundi((1.0 - float(persona["gullibility"])) * 40.0)


static func gullibility_words(gullibility: float) -> String:
	if gullibility >= 0.75:
		return "very gullible"
	if gullibility >= 0.5:
		return "fairly trusting"
	if gullibility >= 0.3:
		return "careful"
	return "hard to fool"


## `options`: rules_path (default RULES_PATH), order (a ReplyParser key order name, default ReplyParser.DEFAULT_ORDER).
static func system_prompt(persona: Dictionary, options: Dictionary = {}) -> String:
	var lines := PackedStringArray()
	lines.append(rules(options.get("rules_path", RULES_PATH), options.get("order", ReplyParser.DEFAULT_ORDER)))
	lines.append("")
	lines.append("YOUR PROFILE")
	lines.append("- Name: %s, age %d." % [persona["name"], persona["age"]])
	lines.append("- Savings: $%d." % persona["savings"])
	lines.append("- Personality: %s (gullibility %.1f out of 1)." % [gullibility_words(persona["gullibility"]), persona["gullibility"]])
	if persona["quirks"].size() > 0:
		lines.append("- Quirks: %s." % "; ".join(persona["quirks"]))
	lines.append("- Scambaiter: %s." % ("YES, you are secretly wasting the scammer's time" if persona["is_scambaiter"] else "no, you are an ordinary victim"))
	lines.append("- Your suspicion at the start of the call: %d." % starting_suspicion(persona))
	return "\n".join(lines)
