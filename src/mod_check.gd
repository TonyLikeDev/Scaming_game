extends Node
## Phase 6 exit check: "dropping a JSON file into the folder adds a new caller", on the real model.
## It writes a made-up caller into the game's real `user://callers/` folder, loads the callers the way the game does,
## has a short call with the new one, and removes the file again.
##
##   python scripts/godot_run.py --timeout 300 --log modcheck -- --headless scenes/mod_check.tscn

const FILE := "user://callers/zz_mod_check_zog.json"
const ZOG := {
	"id": "zog", "name": "Captain Zog", "age": 412, "savings": 9000, "gullibility": 0.6,
	"quirks": ["thinks you are a rival space pirate", "keeps asking where he parked his spaceship", "speaks in sailing terms"],
	"voice": "en-US", "is_scambaiter": false, "kokoro_voice": "am_adam",
}
const LINES := [
	"Good evening, captain. I'm calling from the Moon Warranty Department. Your extended warranty on the Moon is about to expire.",
	"Yes, the Moon. For just three hundred dollars today we can renew it.",
	"The line closes in five minutes, captain. All I need is your card number.",
	"Please read me the card number now, captain. The offer is about to close.",
]

var failures := 0


func check(condition: bool, label: String) -> void:
	print(("ok    " if condition else "FAIL  ") + label)
	if not condition:
		failures += 1


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var folder := Persona.ensure_user_dir()
	var before := Persona.load_all().size()
	var f := FileAccess.open(FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(ZOG, "  "))
	f.close()
	print("MOD_CHECK wrote %s" % ProjectSettings.globalize_path(FILE))
	var all := Persona.load_all()
	var found := all.filter(func(p): return p["id"] == "zog")
	check(all.size() == before + 1 and found.size() == 1, "the new caller appears: %d callers before, %d after" % [before, all.size()])
	if found.size() == 1:
		var zog: Dictionary = found[0]
		check(zog.get("mod", false) and zog["name"] == "Captain Zog" and zog["age"] == 412, "with its own fields, marked as a mod")
		var queue := CallQueue.new(all, 11)
		var rang := false
		for i in 60:
			if queue.next_caller(1)["id"] == "zog":
				rang = true
		check(rang, "the call queue rings the new caller")

		var model_path := LlmService.first_existing(["models/gemma-4-E4B-it-Q4_K_M.gguf"])
		var llm := LlmService.new()
		add_child(llm)
		llm.model_path = model_path
		var session := CallSession.new()
		add_child(session)
		var said := PackedStringArray()
		session.transcript_line.connect(func(role, text): if role != "system": said.append("%s: %s" % [role, text]))
		check(await session.start(llm, zog), "the new caller picks up on the real model")
		for line in LINES:
			if not session.active:
				break
			session.player_says(line)
			while session.thinking:
				await get_tree().process_frame
		for s in said:
			print("MOD_CHECK ", s)
		check(session.turns >= 2 and said.size() >= 4, "they answer (%d turns)" % session.turns)
		var all_text := " ".join(said).to_lower()
		check(all_text.contains("ship") or all_text.contains("pirate") or all_text.contains("sea") or all_text.contains("sail") or all_text.contains("anchor") or all_text.contains("captain") or all_text.contains("moon"), "they are recognisably the new character (quirks or setting show up)")
		if session.active:
			session.player_hangs_up()
		llm.shutdown()
	DirAccess.remove_absolute(FILE)
	check(not FileAccess.file_exists(FILE) and Persona.load_all().size() == before, "the test file is removed again")
	print("MOD_CHECK folder: %s" % folder)
	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(1 if failures > 0 else 0)
