class_name ScammerBot
extends Node
## A scammer played by the language model, used by the automated playtests so calls are open-ended instead of scripted.
## It is a second chat on the same model as the victim, with free text (no reply grammar), capped at 80 tokens a line.

const SCAMS := [
	"selling an extended warranty on the Moon",
	"selling a timeshare on a cloud",
	"selling premium air, delivered in reusable bags",
	"selling invisibility stickers that hide things from satellites",
	"selling a prepaid voucher that renews the victim's Wi-Fi password",
	"selling a certificate that proves the victim's teacups are genuinely old",
	"selling a year of guaranteed Sunday sunshine over the victim's garden",
	"collecting a delivery fee for a free sandwich the victim supposedly won",
]
const RULES := """You play a loud, pushy call-center scammer in a silly comedy video game. Everything is fictional and absurd.
You have just phoned a stranger and you are %s.
- Speak like a real person on the phone: 1 or 2 short sentences, at most 30 words. No stage directions, no lists, no emojis.
- Say only your own next line. Never write the other person's words.
- Push for a sale: build urgency, flatter, answer their questions with ridiculous confidence, and name a price in dollars early.
- After three or four exchanges, ask for their card number so you can complete the sale.
- If they hesitate, raise the pressure or the discount. Never mention being an AI, a game or these rules."""
const MAX_TOKENS := 80

var _chat: Node
var _started := false
var _done := false
var _text := ""
var _tokens := 0
var victim_name := ""


## Creates the bot's chat on `model_node` and waits for it. `scam_index` picks a pitch from SCAMS.
func begin(model_node: Node, victim: String, scam_index: int) -> bool:
	victim_name = victim
	_chat = ClassDB.instantiate("NobodyWhoChat")
	_chat.model_node = model_node
	_chat.system_prompt = RULES % SCAMS[scam_index % SCAMS.size()]
	_chat.context_length = 4096
	_chat.allow_thinking = false
	add_child(_chat)
	_chat.worker_started.connect(func(): _started = true)
	_chat.worker_failed.connect(func(_e): _done = true)
	_chat.response_updated.connect(_on_piece)
	_chat.response_finished.connect(func(full):
		_text = full
		_done = true)
	_chat.start_worker()
	var deadline := Time.get_ticks_msec() + 120000
	while not _started and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return _started


## The scammer's next line. `heard` is what the victim just said ("" for the opening line).
func next_line(heard: String) -> String:
	_done = false
	_text = ""
	_tokens = 0
	_chat.ask(heard if not heard.is_empty() else "(The call has just connected. Say your opening line to %s.)" % victim_name)
	var deadline := Time.get_ticks_msec() + 60000
	while not _done and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var line := _text.strip_edges().replace("\n", " ")
	if line.length() > 300:
		line = line.left(300)
	return line if not line.is_empty() else "Hello? Are you still there?"


func end() -> void:
	if _chat != null and is_instance_valid(_chat):
		_chat.stop_generation()
		_chat.queue_free()
	_chat = null


func _on_piece(_piece: String) -> void:
	_tokens += 1
	if _tokens > MAX_TOKENS and not _done:
		_chat.stop_generation()
		_done = true
