class_name ModelPicker
extends RefCounted
## Which language model suits this computer, whether it is already installed, and where to get it.
## The numbers come from docs/measurements.md (Windows PC, RTX 3070): the main model (Gemma 4 E4B) needed 3.6 GB of VRAM and
## answered in 0.7 s; the small one (E2B) needed 2.0 GB and answered in 0.5 s on the GPU or 2.1 s on the CPU alone.
## The Mac and AMD or Intel graphics cards have not been measured, so they get the safe choice or a conservative rule.

const SETTINGS_PATH := "user://settings.cfg"
const MODEL_DIRS := ["res://models", "user://models"]

const MODELS := {
	"e4b": {"name": "Gemma 4 E4B", "file": "gemma-4-E4B-it-Q4_K_M.gguf", "hf": "hf:NobodyWho/Google_Gemma4-E4B-GGUF/gemma-4-E4B-it-Q4_K_M.gguf", "size_gb": 4.98},
	"e2b": {"name": "Gemma 4 E2B", "file": "gemma-4-E2B-it-Q4_K_M.gguf", "hf": "hf:NobodyWho/Google_Gemma4-E2B-GGUF/gemma-4-E2B-it-Q4_K_M.gguf", "size_gb": 3.11},
}
## Other models that work, used only if one is already installed.
const FALLBACK_FILES := ["Qwen_Qwen3.5-4B-Q4_K_M-vendor-sampling.gguf"]

const E4B_MIN_VRAM_MB := 6000  ## 3.6 GB measured, plus the desktop and some room
const E4B_MIN_APPLE_RAM_MB := 12000  ## unified memory: the model shares it with everything else (not measured)
const E2B_MIN_VRAM_MB := 3000  ## 2.0 GB measured, plus room
const MIN_RAM_MB := 6000


## What this computer has: {os, arch, ram_mb, vram_mb (-1 when unknown), kind: "nvidia" | "apple" | "other", gpu}.
static func detect() -> Dictionary:
	var ram_mb := int(OS.get_memory_info().get("physical", 0)) / 1048576
	var vram := int(SysStats.gpu_total_mb())  # NVIDIA only, through nvidia-smi
	var kind := "other"
	if OS.get_name() == "macOS" and Engine.get_architecture_name() == "arm64":
		kind = "apple"
	elif vram > 0:
		kind = "nvidia"
	return {"os": OS.get_name(), "arch": Engine.get_architecture_name(), "ram_mb": ram_mb, "vram_mb": vram, "kind": kind,
			"gpu": RenderingServer.get_video_adapter_name()}


## The model for a machine described by `hw` (see detect()). Returns {id, reason, meets_minimum}.
static func recommend(hw: Dictionary) -> Dictionary:
	var ram := int(hw.get("ram_mb", 0))
	var vram := int(hw.get("vram_mb", -1))
	var meets := ram <= 0 or ram >= MIN_RAM_MB
	var id := "e2b"
	var reason := ""
	match String(hw.get("kind", "other")):
		"nvidia":
			if vram >= E4B_MIN_VRAM_MB:
				id = "e4b"
				reason = "Your graphics card has %d MB of memory: the main model replies in under a second." % vram
			elif vram >= E2B_MIN_VRAM_MB:
				reason = "Your graphics card has %d MB of memory: the small model fits and replies in under a second." % vram
			else:
				reason = "Your graphics card has only %d MB of memory, so the small model will run on the processor (replies take about 2 seconds)." % vram
		"apple":
			if ram >= E4B_MIN_APPLE_RAM_MB:
				id = "e4b"
				reason = "Apple silicon with %d MB of memory: the main model should fit (not measured on a Mac yet)." % ram
			else:
				reason = "Apple silicon with %d MB of memory: the small model is the safe choice." % ram
		_:
			reason = "No graphics card was recognised, so the small model is the safe choice (on the processor it replies in about 2 seconds)."
	if not meets:
		reason += " This computer has less than %d GB of memory, so the game may run badly." % (MIN_RAM_MB / 1000)
	return {"id": id, "reason": reason, "meets_minimum": meets}


## Where a model file is, or "" if it is not installed. Looks in `res://models`, `user://models` and the place a first-launch
## download was remembered in.
static func installed_path(id: String, dirs: Array = MODEL_DIRS, settings_path: String = SETTINGS_PATH) -> String:
	var file: String = MODELS[id]["file"]
	var remembered := remembered_path(id, settings_path)
	if not remembered.is_empty() and FileAccess.file_exists(remembered):
		return remembered
	for dir in dirs:
		var path := String(dir).path_join(file)
		if FileAccess.file_exists(path):
			return ProjectSettings.globalize_path(path)
	return ""


## Any installed model, the recommended one first, then the other, then the known fallbacks. {id, path} or {} if none.
static func best_installed(recommended: String, dirs: Array = MODEL_DIRS, settings_path: String = SETTINGS_PATH) -> Dictionary:
	var order: Array = [recommended] + MODELS.keys().filter(func(k): return k != recommended)
	for id in order:
		var path := installed_path(id, dirs, settings_path)
		if not path.is_empty():
			return {"id": id, "path": path}
	for file in FALLBACK_FILES:
		for dir in dirs:
			var path := String(dir).path_join(file)
			if FileAccess.file_exists(path):
				return {"id": "fallback", "path": ProjectSettings.globalize_path(path)}
	return {}


## Remembers where a downloaded model ended up, so the next launch finds it at once.
static func remember(id: String, path: String, settings_path: String = SETTINGS_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(settings_path)
	cfg.set_value("models", id, path)
	cfg.save(settings_path)


static func remembered_path(id: String, settings_path: String = SETTINGS_PATH) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return ""
	return String(cfg.get_value("models", id, ""))
