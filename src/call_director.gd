class_name CallDirector
extends RefCounted
## The game decides what happens, the model decides how it sounds. A small language model plays a character well but is
## unreliable about *when* to pay, and an aligned model refuses to hand over card details at all: in tests Gemma 4 paid in
## 0 of 12 calls without help, including to a very gullible caller, while Qwen paid at random, once on the first turn.
## So every turn the game works out whether the caller is persuaded and attaches a private [DIRECTOR: ...] note to the
## player's line. The model writes the reply that fits the note (tests: Qwen and Gemma obeyed every order).
##
## This is also the lever for game balance: how often callers pay is set here, from gullibility, suspicion and how long
## the call has run, not by whatever the model happens to feel. The calibration targets (a typical call has three asks
## for money) are roughly: Gladys 90%, Barry 40%, a scambaiter 10% of calls end in a payment.

const PAYMENT_WORDS := ["card", "credit", "debit", "account", "bank", "pay", "payment", "deposit", "wire", "voucher", "cvv", "security code",
		"three digits", "number on the back", "fee", "dollars", "price", "cost"]
const MIN_TURN_TO_PAY := 2  ## the caller never pays in their first two replies (turn_index counts replies already given)
const HANG_UP_SUSPICION := 85  ## at or above this the caller is told to end the call whatever was asked

## Mid-call surprises (Phase 5): in some calls, at a random reply, something happens around the caller and they are told to
## react to it. It is never combined with a payment or a hang-up order, so those lines stay clean.
const EVENT_CHANCE := 0.4  ## share of calls that get one surprise
const EVENT_MIN_TURN := 2
const EVENT_MAX_TURN := 5
const EVENTS := [
	"your grandson has just walked in wearing a full suit of armour",
	"the doorbell rings and a man is delivering a very large cheese",
	"a pigeon has flown in through the kitchen window",
	"the power flickers and the lights go out for a moment",
	"your neighbour has started mowing the lawn at the loudest possible volume",
	"your cat has just knocked a glass off the table",
	"the smoke alarm has started beeping",
	"someone outside has started playing the bagpipes",
	"a delivery drone has landed on the windowsill",
	"the kettle has boiled over and is whistling",
]

var rng := RandomNumberGenerator.new()
var event_text := ""  ## this call's surprise, or "" when there is none
var event_turn := -1  ## the reply on which it happens
var event_fired := false


func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()


## Call at the start of every call: decides whether this call gets a surprise, which one, and on which reply.
func plan_call() -> void:
	event_text = ""
	event_turn = -1
	event_fired = false
	if rng.randf() < EVENT_CHANCE:
		event_turn = rng.randi_range(EVENT_MIN_TURN, EVENT_MAX_TURN)
		event_text = EVENTS[rng.randi() % EVENTS.size()]


static func asks_for_payment(player_text: String) -> bool:
	var s := player_text.to_lower()
	for word in PAYMENT_WORDS:
		if s.contains(word):
			return true
	return false


## Chance (0 to 1) that a caller is persuaded on one ask for money. It rises with gullibility (steeply: a careful caller
## needs several pushes), rises a little with every reply, and falls as suspicion grows. Scambaiters almost never pay.
static func willingness(persona: Dictionary, turn_index: int, suspicion: int) -> float:
	var w := pow(float(persona["gullibility"]), 1.6) * (0.6 + 0.1 * float(mini(turn_index, 6))) * (1.0 - 0.9 * float(suspicion) / 100.0)
	if persona["is_scambaiter"]:
		w *= 0.05
	return clampf(w, 0.0, 0.95)


## The most a caller will hand over in one payment.
static func pay_cap(persona: Dictionary) -> int:
	var share := 0.05 + 0.25 * float(persona["gullibility"])
	return clampi(roundi(float(persona["savings"]) * share), 50, int(persona["savings"]))


## The note to append to this turn's player line. It is never empty, so the model has no room to decide on its own.
## `turn_index` is how many replies the caller has already given in this call; `suspicion` is the caller's last value.
## When this call's surprise is due and the turn is not a payment or a hang-up, the surprise is added to the note.
func note_for(persona: Dictionary, player_text: String, turn_index: int, suspicion: int) -> String:
	var note := _base_note(persona, player_text, turn_index, suspicion)
	if event_turn >= 0 and not event_fired and turn_index >= event_turn and not note.contains("action pay") and not note.contains("action hang_up"):
		event_fired = true
		note += "\n[DIRECTOR: Something happens around you right now: %s. React to it briefly in your reply, in character, then carry on with the call.]" % event_text
	return note


func _base_note(persona: Dictionary, player_text: String, turn_index: int, suspicion: int) -> String:
	if suspicion >= HANG_UP_SUSPICION:
		return "\n[DIRECTOR: You have lost your patience. Say a short goodbye and hang up. action hang_up.]"
	if not asks_for_payment(player_text):
		return "\n[DIRECTOR: The caller has not asked you for money yet. Do not pay and read out no numbers. action talk.]"
	if turn_index < MIN_TURN_TO_PAY:
		return "\n[DIRECTOR: It is too early to pay. Stay curious or confused, ask a question. Read out no numbers. action talk.]"
	if rng.randf() < willingness(persona, turn_index, suspicion):
		return ("\n[DIRECTOR: You are now convinced. In this reply you pay: say so out loud and read out a silly fake card number. "
				+ "action pay, amount = the price the caller named, in whole dollars, at most %d.]") % pay_cap(persona)
	return "\n[DIRECTOR: You are not ready to pay yet. Stall in character: a question, a distraction, a haggle. Read out no numbers. action talk.]"
