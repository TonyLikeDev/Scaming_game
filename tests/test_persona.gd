extends SceneTree
## Run: godot --headless --path . --script tests/test_persona.gd
## Checks persona loading, validation (bad files are skipped, never crash) and prompt building.

var failures := 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("ok    ", label)
	else:
		failures += 1
		print("FAIL  ", label)


func write_file(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func CallPrompt_has_mod_persona(persona: Dictionary) -> bool:
	var prompt := CallerPrompt.system_prompt(persona)
	return prompt.contains("Captain Zog") and prompt.contains("rival space pirate") and prompt.contains("Savings: $9000")


func _init() -> void:
	var personas := Persona.load_dir("res://callers")
	check(personas.size() == 3, "res://callers loads 3 personas (got %d)" % personas.size())
	var ids: Array = personas.map(func(p): return p["id"])
	check(ids == ["barry", "gladys", "priya"], "ids sorted by file name: %s" % str(ids))
	var gladys := Persona.load_file("res://callers/gladys.json")
	check(gladys["age"] == 82 and gladys["savings"] == 14000, "gladys numbers are ints")
	check(gladys["gullibility"] == 0.8 and gladys["is_scambaiter"] == false, "gladys gullibility and scambaiter flag")
	check(Persona.load_file("res://callers/priya.json")["is_scambaiter"] == true, "priya is a scambaiter")
	check(gladys.get("kokoro_voice") == "bf_emma" and Persona.load_file("res://callers/barry.json").get("kokoro_voice") == "am_michael", "starter personas carry a kokoro_voice")

	# Bad files in a scratch folder: every one must be skipped, the good one kept.
	var dir := "user://test_callers"
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	write_file(dir + "/a_good.json", '{"id":"ok_one","name":" Ok One ","age":5000,"savings":-5,"gullibility":7,"quirks":["a","  ","b","c","d","e","f","g"],"voice":"en-US","is_scambaiter":false}')
	write_file(dir + "/b_broken.json", '{"id": "x", ')
	write_file(dir + "/c_missing.json", '{"id":"x","name":"X"}')
	write_file(dir + "/d_wrongtype.json", '{"id":"y","name":"Y","age":"old","savings":1,"gullibility":0.5,"quirks":[],"voice":"en","is_scambaiter":false}')
	write_file(dir + "/e_dup.json", '{"id":"ok_one","name":"Dup","age":30,"savings":1,"gullibility":0.5,"quirks":[],"voice":"en","is_scambaiter":false}')
	write_file(dir + "/f_array.json", "[1,2,3]")
	write_file(dir + "/g_badid.json", '{"id":"has space","name":"Z","age":30,"savings":1,"gullibility":0.5,"quirks":[],"voice":"en","is_scambaiter":false}')
	write_file(dir + "/h_notjson.txt", "ignore me")
	write_file(dir + "/i_empty.json", "")
	write_file(dir + "/j_badvoice.json", '{"id":"badv","name":"Bad Voice","age":30,"savings":1,"gullibility":0.5,"quirks":[],"voice":"en","is_scambaiter":false,"kokoro_voice":"Not A Voice!"}')
	write_file(dir + "/k_goodvoice.json", '{"id":"goodv","name":"Good Voice","age":30,"savings":1,"gullibility":0.5,"quirks":[],"voice":"en","is_scambaiter":false,"kokoro_voice":"bm_george"}')
	var loaded := Persona.load_dir(dir)
	check(loaded.size() == 2 and loaded[1].get("kokoro_voice") == "bm_george", "8 bad files skipped, 2 good kept, a good kokoro_voice survives (got %d)" % loaded.size())
	if loaded.size() == 2:
		var p: Dictionary = loaded[0]
		check(p["name"] == "Ok One", "name trimmed")
		check(p["age"] == 999 and p["savings"] == 0 and p["gullibility"] == 1.0, "numbers clamped (age to 999, savings to 0, gullibility to 1)")
		check(p["quirks"] == ["a", "b", "c", "d", "e", "f"], "blank quirk dropped, list capped at 6")
	check(Persona.load_dir("res://does_not_exist").is_empty(), "missing folder gives an empty list")
	check(Persona.load_file("res://nope.json").is_empty(), "missing file gives {}")

	# Mods: callers from the player's folder, added to or replacing the built-in ones
	var mods := "user://test_mods"
	DirAccess.make_dir_recursive_absolute(mods)
	for f in DirAccess.get_files_at(mods):
		DirAccess.remove_absolute(mods.path_join(f))
	write_file(mods + "/zog.json", '{"id":"zog","name":"Captain Zog","age":412,"savings":9000,"gullibility":0.6,"quirks":["thinks you are a rival space pirate"],"voice":"en-US","is_scambaiter":false,"kokoro_voice":"am_adam"}')
	write_file(mods + "/gladys_rich.json", '{"id":"gladys","name":"Gladys Pemberton (rich)","age":82,"savings":99000,"gullibility":0.5,"quirks":["owns three cats"],"voice":"en-GB","is_scambaiter":false}')
	write_file(mods + "/broken.json", '{"id": "oops"')
	write_file(mods + "/readme.txt", "not a persona")
	var all := Persona.load_all("res://callers", mods)
	var all_ids: Array = all.map(func(p): return p["id"])
	all_ids.sort()
	check(all_ids == ["barry", "gladys", "priya", "zog"], "built-in plus mod callers: %s" % str(all_ids))
	var gl: Dictionary = all.filter(func(p): return p["id"] == "gladys")[0]
	check(gl["savings"] == 99000 and gl.get("mod", false) == true, "a mod with a built-in id replaces that caller")
	var zog: Dictionary = all.filter(func(p): return p["id"] == "zog")[0]
	check(zog.get("mod", false) and zog["kokoro_voice"] == "am_adam" and zog["age"] == 412, "a new mod caller is added with its fields")
	check(all.filter(func(p): return p["id"] == "barry")[0].get("mod", false) == false, "built-in callers are not marked as mods")
	check(Persona.load_all("res://callers", "user://no_such_mod_folder").size() == 3, "no mod folder: just the built-in callers")
	check(Persona.load_all("res://no_such_folder", mods).size() == 2, "no built-in folder: only the mods")
	check(Persona.load_all("res://no_such_folder", "user://no_such_mod_folder").is_empty(), "nothing at all is an empty list, not an error")
	var real_path := Persona.ensure_user_dir("user://test_mods_made")
	check(DirAccess.dir_exists_absolute("user://test_mods_made") and real_path.is_absolute_path() and real_path.ends_with("test_mods_made"), "the mod folder is created and its real path returned (%s)" % real_path)
	var queue := CallQueue.new(all, 7)
	var queued := {}
	for i in 100:
		queued[queue.next_caller(1)["id"]] = true
	check(queued.size() == 4 and queued.has("zog"), "the call queue rings the mod caller too")
	check(CallPrompt_has_mod_persona(zog), "the mod caller gets a prompt like any other")

	# Prompt building
	var prompt := CallerPrompt.system_prompt(gladys)
	check(prompt.contains("Gladys Pemberton, age 82"), "prompt has name and age")
	check(prompt.contains("Mr. Biscuits"), "prompt has quirks")
	check(prompt.contains("Savings: $14000"), "prompt has savings")
	check(prompt.contains("start of the call: 8."), "gladys starts at suspicion 8 (got: %s)" % prompt.substr(prompt.length() - 60))
	check(CallerPrompt.starting_suspicion(Persona.load_file("res://callers/barry.json")) == 26, "barry starts at suspicion 26")
	check(prompt.contains("no, you are an ordinary victim"), "gladys is not a scambaiter")
	check(CallerPrompt.system_prompt(Persona.load_file("res://callers/priya.json")).contains("YES, you are secretly"), "priya is a scambaiter in the prompt")
	check(prompt.length() < 4000, "prompt is under 4000 characters (%d)" % prompt.length())

	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
