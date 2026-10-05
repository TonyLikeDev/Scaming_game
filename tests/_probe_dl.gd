extends SceneTree
## Throwaway probe: how NobodyWhoModel downloads an hf: model (progress signal, cache listing, failure text).
var model: Node
var chat: Node
var ticks := 0
var last := [0, 0]
var started := false
var failed := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	model = ClassDB.instantiate("NobodyWhoModel")
	var ref: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "hf:NobodyWho/Qwen_Qwen3-0.6B-GGUF:Q4_K_M"
	model.model_path = ref
	model.use_gpu_if_available = false
	root.add_child(model)
	model.download_progress.connect(func(done, total):
		ticks += 1
		last = [done, total]
		if ticks % 20 == 1:
			print("PROBE progress %d / %d" % [done, total]))
	chat = ClassDB.instantiate("NobodyWhoChat")
	chat.model_node = model
	chat.system_prompt = "You are brief."
	root.add_child(chat)
	chat.worker_started.connect(func(): started = true)
	chat.worker_failed.connect(func(e): failed = str(e))
	var t := Time.get_ticks_msec()
	chat.start_worker()
	var deadline := t + 400000
	while not started and failed == "" and Time.get_ticks_msec() < deadline:
		await process_frame
	print("PROBE ref=%s started=%s failed='%s' after %.1f s, %d progress ticks, last %s" % [ref, started, failed.left(300), (Time.get_ticks_msec() - t) / 1000.0, ticks, str(last)])
	print("PROBE cached: ", ClassDB.class_get_method_list("NobodyWhoModel").size() > 0)
	var cached: Variant = model.get_cached_models()
	print("PROBE get_cached_models -> ", cached)
	quit(0)
