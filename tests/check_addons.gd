extends SceneTree
## Run: python scripts/godot_run.py --import -- --headless --script tests/check_addons.gd
## Checks that the GDExtension addons registered their classes, and prints each class's API so code can match it.

## Native (GDExtension) classes, looked up in ClassDB.
const NEED := {
	"NobodyWho": ["NobodyWhoModel", "NobodyWhoChat", "NobodyWhoSpeechToText", "NobodyWhoTextToSpeech", "NobodyWhoVoiceActivityDetection"],
	"godot-whisper": ["SpeechToText"],
}
## GDScript classes shipped by the addons, looked up in the global class list.
const NEED_SCRIPT_CLASSES := {"godot-whisper": ["CaptureStreamToText", "AudioStreamToText"]}

var failures := 0


func describe(cls: String) -> void:
	print("--- %s (extends %s)" % [cls, ClassDB.get_parent_class(cls)])
	var props: Array = []
	for p in ClassDB.class_get_property_list(cls, true):
		if p["usage"] & PROPERTY_USAGE_EDITOR or p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			props.append("%s:%s" % [p["name"], type_string(p["type"])])
	print("  properties: ", ", ".join(props))
	var methods: Array = []
	for m in ClassDB.class_get_method_list(cls, true):
		if not (m["name"] as String).begins_with("_"):
			var args: Array = (m["args"] as Array).map(func(a): return "%s:%s" % [a["name"], type_string(a["type"])])
			methods.append("%s(%s)" % [m["name"], ", ".join(args)])
	print("  methods: ", " | ".join(methods))
	var signals: Array = []
	for s in ClassDB.class_get_signal_list(cls, true):
		var args: Array = (s["args"] as Array).map(func(a): return "%s:%s" % [a["name"], type_string(a["type"])])
		signals.append("%s(%s)" % [s["name"], ", ".join(args)])
	print("  signals: ", " | ".join(signals))


func _init() -> void:
	print("Godot ", Engine.get_version_info()["string"])
	for addon in NEED:
		for cls in NEED[addon]:
			if ClassDB.class_exists(cls):
				print("ok    %s: %s registered" % [addon, cls])
			else:
				failures += 1
				print("FAIL  %s: %s NOT registered" % [addon, cls])
	var script_classes: Array = ProjectSettings.get_global_class_list().map(func(c): return c["class"])
	for addon in NEED_SCRIPT_CLASSES:
		for cls in NEED_SCRIPT_CLASSES[addon]:
			if cls in script_classes:
				print("ok    %s: script class %s registered" % [addon, cls])
			else:
				failures += 1
				print("FAIL  %s: script class %s NOT registered" % [addon, cls])
	if "--describe" in OS.get_cmdline_user_args():
		for addon in NEED:
			for cls in NEED[addon]:
				if ClassDB.class_exists(cls):
					describe(cls)
	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
