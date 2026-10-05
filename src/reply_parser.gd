class_name ReplyParser
extends RefCounted
## Turns the caller model's raw text into a checked reply, or a failure the game answers with a hang-up.
## A broken or empty reply never crashes a call (docs/PLAN.md, "What the AI sends back on every turn").

const ACTIONS := ["talk", "pay", "hang_up", "counter_attack"]

## Key order of the reply JSON. `say` is always first so speech can start before the rest is generated.
## "default" is the order in docs/PLAN.md; "action_first" puts `action` and `amount` right after `say`, so the decision is
## made while the spoken line is fresh and the two are less likely to disagree.
## The order the game uses (see docs/PLAN.md); "default" is the first draft, kept so the old test runs can be repeated.
const DEFAULT_ORDER := "action_first"

const KEY_ORDERS := {
	"default": ["say", "suspicion", "action", "amount"],
	"action_first": ["say", "action", "amount", "suspicion"],
}

const _PROPERTY_SCHEMAS := {
	"say": {"type": "string"},
	"suspicion": {"type": "integer", "minimum": 0, "maximum": 100},
	"action": {"type": "string", "enum": ["talk", "pay", "hang_up", "counter_attack"]},
	"amount": {"type": "integer", "minimum": 0},
}

## JSON schema handed to the model's sampler so the format is enforced while it generates.
const SCHEMA := {
	"type": "object",
	"properties": _PROPERTY_SCHEMAS,
	"required": ["say", "suspicion", "action", "amount"],
	"additionalProperties": false,
}


static func key_order(order_name: String = DEFAULT_ORDER) -> Array:
	return KEY_ORDERS.get(order_name, KEY_ORDERS[DEFAULT_ORDER])


## GBNF grammar rules shared by every key order. The JSON schema route lets the model pick any key order and emit endless
## whitespace (a Gemma 4 reply ran to 3420 tokens of newlines), so the game constrains replies with this grammar instead:
## fixed key order, no whitespace outside the spoken text, and `say` capped at 300 characters.
const _GBNF_RULES := r'''
text ::= char{1,300}
char ::= [^"\\\x00-\x1F] | "\\" ["\\/bfnrt]
pct ::= "100" | [1-9] [0-9] | [0-9]
action ::= "talk" | "pay" | "hang_up" | "counter_attack"
money ::= "0" | [1-9] [0-9]{0,6}
'''

const _GBNF_FIELDS := {
	"say": r'"\"say\":\"" text "\""',
	"suspicion": r'"\"suspicion\":" pct',
	"action": r'"\"action\":\"" action "\""',
	"amount": r'"\"amount\":" money',
}


## A GBNF grammar that accepts exactly one reply object with its keys in the named order, e.g.
## {"say":"Hello?","suspicion":8,"action":"talk","amount":0}
static func grammar_for(order_name: String) -> String:
	var fields: Array[String] = []
	for key in key_order(order_name):
		fields.append(_GBNF_FIELDS[key])
	return 'root ::= "{" %s "}"\n%s' % [' "," '.join(fields), _GBNF_RULES]


## The reply schema with its properties in the named key order.
static func schema_for(order_name: String) -> Dictionary:
	var props := {}
	for key in key_order(order_name):
		props[key] = _PROPERTY_SCHEMAS[key]
	return {"type": "object", "properties": props, "required": key_order(order_name).duplicate(), "additionalProperties": false}


## Returns {ok, say, suspicion, action, amount, corrections}, or {ok: false, reason}.
## `corrections` lists every rule the game had to apply on top of the model's own values.
static func parse(raw: String, persona: Dictionary) -> Dictionary:
	var text := raw.strip_edges()
	if text.is_empty():
		return {"ok": false, "reason": "empty reply"}
	var data: Variant = _try_parse(text)
	if typeof(data) != TYPE_DICTIONARY:
		# Tolerate stray text around the object (e.g. a code fence); anything else is a failure.
		var start := text.find("{")
		var end := text.rfind("}")
		if start >= 0 and end > start:
			data = _try_parse(text.substr(start, end - start + 1))
		if typeof(data) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "not a JSON object"}
	for key in ["say", "suspicion", "action", "amount"]:
		if not data.has(key):
			return {"ok": false, "reason": "missing '%s'" % key}
	if typeof(data["say"]) != TYPE_STRING or (data["say"] as String).strip_edges().is_empty():
		return {"ok": false, "reason": "'say' is empty or not text"}
	if typeof(data["action"]) != TYPE_STRING or not (data["action"] in ACTIONS):
		return {"ok": false, "reason": "unknown action '%s'" % str(data["action"])}
	if typeof(data["suspicion"]) != TYPE_FLOAT and typeof(data["suspicion"]) != TYPE_INT:
		return {"ok": false, "reason": "'suspicion' is not a number"}
	if typeof(data["amount"]) != TYPE_FLOAT and typeof(data["amount"]) != TYPE_INT:
		return {"ok": false, "reason": "'amount' is not a number"}

	var corrections: Array[String] = []
	var action: String = data["action"]
	var suspicion := int(data["suspicion"])
	var amount := int(data["amount"])
	if suspicion < 0 or suspicion > 100:
		corrections.append("suspicion %d clamped to 0-100" % suspicion)
		suspicion = clampi(suspicion, 0, 100)
	var savings := int(persona.get("savings", 0))
	if action == "pay":
		if amount <= 0:
			corrections.append("pay with no amount became talk")
			action = "talk"
			amount = 0
		elif amount > savings:
			corrections.append("amount %d capped to savings %d" % [amount, savings])
			amount = savings
	elif amount != 0:
		corrections.append("amount %d dropped, action was %s" % [amount, action])
		amount = 0
	if action == "counter_attack" and not persona.get("is_scambaiter", false):
		corrections.append("counter_attack by a non-scambaiter became talk")
		action = "talk"
	return {
		"ok": true,
		"say": clean_say(data["say"] as String),
		"suspicion": suspicion,
		"action": action,
		"amount": amount,
		"corrections": corrections,
	}


## Spoken text for the transcript and the OS voice: models like to *emphasise* words with asterisks, which a voice reads
## out loud as "asterisk". Strip the markers (and stray markdown) and tidy the spaces.
static func clean_say(text: String) -> String:
	var cleaned := text.replace("*", "").replace("_", " ").replace("`", "").replace("#", "")
	while cleaned.contains("  "):
		cleaned = cleaned.replace("  ", " ")
	cleaned = cleaned.strip_edges()
	# Gemma 4 E2B often begins the line with a stray ":" or ".:" left over from the forced JSON prefix
	while not cleaned.is_empty() and cleaned[0] in [":", ".", ",", ";", " "]:
		cleaned = cleaned.substr(1)
	return cleaned


const _DIGIT_WORDS := ["zero", "oh", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
const _PAY_PHRASES := ["take my money", "here you go", "i'll pay", "i will pay", "sending the money", "sending it now",
		"here's my card", "my card is", "card number is", "account number is", "the number is", "here is my card"]


## Heuristic used only to measure models: does the spoken line sound like the caller is handing over payment details
## (a run of four or more digits or digit words, or a stock phrase)? If so, the action should have been "pay".
static func say_implies_payment(say: String) -> bool:
	var s := say.to_lower()
	var rx := RegEx.create_from_string("\\d[\\d\\- ]{2,}\\d")
	if rx.search(s) != null:
		return true
	for phrase in _PAY_PHRASES:
		if s.contains(phrase):
			return true
	var run := 0
	for word in s.replace(",", " ").replace("-", " ").replace(".", " ").split(" ", false):
		run = run + 1 if word in _DIGIT_WORDS else 0
		if run >= 4:
			return true
	return false


## Finds the end of the `say` string in a partly streamed reply. Returns the spoken text once its closing
## quote has arrived, otherwise "". That moment is when TTS could start, before the rest is generated.
static func say_if_complete(partial: String) -> String:
	var rx := RegEx.new()
	rx.compile('"say"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"')
	var m := rx.search(partial)
	if m == null:
		return ""
	var decoded: Variant = _try_parse('"%s"' % m.get_string(1))
	return decoded if typeof(decoded) == TYPE_STRING else m.get_string(1)


## JSON.parse_string logs an engine error on every bad input; a broken reply is an expected case here, so stay quiet.
static func _try_parse(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) == OK:
		return json.data
	return null
