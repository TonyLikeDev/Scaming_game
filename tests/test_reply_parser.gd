extends SceneTree
## Run: python scripts/godot_run.py --import -- --headless --script tests/test_reply_parser.gd
## Every malformed model reply must become a clean failure or a documented correction, never an error.

var failures := 0
var gladys := {"savings": 14000, "is_scambaiter": false}
var priya := {"savings": 500, "is_scambaiter": true}


func check(condition: bool, label: String) -> void:
	if condition:
		print("ok    ", label)
	else:
		failures += 1
		print("FAIL  ", label)


func _init() -> void:
	var r := ReplyParser.parse('{"say":"Kevin? Is that you?","suspicion":35,"action":"talk","amount":0}', gladys)
	check(r["ok"] and r["say"] == "Kevin? Is that you?" and r["suspicion"] == 35 and r["action"] == "talk" and r["amount"] == 0, "plan example parses")
	check(r["corrections"].is_empty(), "plan example needs no corrections")

	r = ReplyParser.parse('{"say":"Take it all, dear","suspicion":10,"action":"pay","amount":250}', gladys)
	check(r["ok"] and r["action"] == "pay" and r["amount"] == 250, "valid pay kept")
	r = ReplyParser.parse('{"say":"Take it all","suspicion":10,"action":"pay","amount":99999}', gladys)
	check(r["ok"] and r["amount"] == 14000 and r["corrections"].size() == 1, "pay above savings is capped")
	r = ReplyParser.parse('{"say":"Hmm","suspicion":10,"action":"pay","amount":0}', gladys)
	check(r["ok"] and r["action"] == "talk", "pay of 0 becomes talk")
	r = ReplyParser.parse('{"say":"Hmm","suspicion":10,"action":"talk","amount":50}', gladys)
	check(r["ok"] and r["amount"] == 0, "amount dropped on non-pay")
	r = ReplyParser.parse('{"say":"Hmm","suspicion":150,"action":"talk","amount":0}', gladys)
	check(r["ok"] and r["suspicion"] == 100, "suspicion above 100 clamped")
	r = ReplyParser.parse('{"say":"Hmm","suspicion":-4,"action":"talk","amount":0}', gladys)
	check(r["ok"] and r["suspicion"] == 0, "negative suspicion clamped")
	r = ReplyParser.parse('{"say":"Boom","suspicion":90,"action":"counter_attack","amount":0}', gladys)
	check(r["ok"] and r["action"] == "talk", "counter_attack by a victim becomes talk")
	r = ReplyParser.parse('{"say":"Boom","suspicion":90,"action":"counter_attack","amount":0}', priya)
	check(r["ok"] and r["action"] == "counter_attack", "counter_attack by a scambaiter kept")
	r = ReplyParser.parse('{"say":"Hi","suspicion":35.7,"action":"talk","amount":0.0}', gladys)
	check(r["ok"] and r["suspicion"] == 35, "float numbers accepted")
	r = ReplyParser.parse('```json\n{"say":"Hi","suspicion":5,"action":"talk","amount":0}\n```', gladys)
	check(r["ok"] and r["say"] == "Hi", "code fence around the object tolerated")

	# Failures: each must be {ok:false, reason} and never raise.
	for bad in ["", "   ", "nonsense", "[1,2]", "{", '{"say":"hi"}', '{"say":"","suspicion":1,"action":"talk","amount":0}',
			'{"say":"hi","suspicion":1,"action":"explode","amount":0}', '{"say":"hi","suspicion":"high","action":"talk","amount":0}',
			'{"say":"hi","suspicion":1,"action":"talk","amount":"lots"}', '{"say":5,"suspicion":1,"action":"talk","amount":0}',
			'{"say":"hi","suspicion":1,"action":null,"amount":0}', "null", '"just a string"']:
		r = ReplyParser.parse(bad, gladys)
		check(not r["ok"] and r.has("reason"), "bad reply rejected: %s -> %s" % [bad.replace("\n", " ").left(40), r.get("reason")])

	# Streaming: the spoken text is known as soon as the say string closes.
	check(ReplyParser.say_if_complete('{"say":"Hello the') == "", "partial say is not complete")
	check(ReplyParser.say_if_complete('{"say":"Hello there, dear.","susp') == "Hello there, dear.", "complete say found early")
	check(ReplyParser.say_if_complete('{"say":"She said \\"no\\" twice","suspicion":3') == 'She said "no" twice', "escaped quotes decoded")
	check(ReplyParser.say_if_complete("") == "", "empty stream")

	# Spoken text is cleaned of markdown a voice would read aloud
	r = ReplyParser.parse('{"say":"Forty-nine dollars *and* one hundred? **Really**?","suspicion":5,"action":"talk","amount":0}', gladys)
	check(r["ok"] and r["say"] == "Forty-nine dollars and one hundred? Really?", "asterisks are stripped from the spoken line (%s)" % r.get("say"))
	check(ReplyParser.clean_say("  a   b  ") == "a b", "extra spaces are collapsed")
	check(ReplyParser.clean_say("Mr. Biscuits_says `hi` #1") == "Mr. Biscuits says hi 1", "stray markdown is removed")
	check(ReplyParser.clean_say(":Moon warranty? Oh my goodness.") == "Moon warranty? Oh my goodness.", "a stray leading colon is removed")
	check(ReplyParser.clean_say(":. What kind of air is this?") == "What kind of air is this?", "a stray leading colon and full stop are removed")
	check(ReplyParser.clean_say("...Well, I never.") == "Well, I never.", "a leading ellipsis is removed")
	check(ReplyParser.clean_say("$300? That is a lot.") == "$300? That is a lot.", "a leading dollar sign is kept")
	check(ReplyParser.clean_say(":::") == "", "only punctuation leaves nothing")

	# The payment heuristic (used only to measure models)
	for yes in ["My card is four two four two, four two four two.", "It's 1234-5678-9012-3456, dear.", "Here you go, take my money!",
			"The number is 77-Sparkle-9000-Whiskers.", "one two three four five", "Okay, my card number is on the fridge."]:
		check(ReplyParser.say_implies_payment(yes), "implies payment: %s" % yes)
	for no in ["The Moon? Mr. Biscuits never mentioned a Moon.", "What kind of deposit is that, dear?", "I only have three hundred dollars, you know.",
			"One moment, two minutes, please.", "Can I call my nephew Kevin first?"]:
		check(not ReplyParser.say_implies_payment(no), "does not imply payment: %s" % no)

	# The grammar must name every key once, in the chosen order, and cap the spoken text.
	var g := ReplyParser.grammar_for("default")
	check(g.begins_with('root ::= "{" '), "grammar root rule")
	check(g.find('\\"say\\"') < g.find('\\"suspicion\\"') and g.find('\\"suspicion\\"') < g.find('\\"action\\"') and g.find('\\"action\\"') < g.find('\\"amount\\"'), "default grammar key order")
	var g2 := ReplyParser.grammar_for("action_first")
	check(g2.find('\\"say\\"') < g2.find('\\"action\\"') and g2.find('\\"amount\\"') < g2.find('\\"suspicion\\"'), "action_first grammar key order")
	check(g.contains("char{1,300}"), "say is capped at 300 characters")

	# The schema itself must be valid JSON the sampler can take, with say first.
	var schema_text := JSON.stringify(ReplyParser.SCHEMA)
	check(JSON.parse_string(schema_text) != null, "schema serializes")
	check((ReplyParser.SCHEMA["properties"] as Dictionary).keys() == ["say", "suspicion", "action", "amount"], "schema key order: say first")

	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
