class_name CallQueue
extends RefCounted
## Who rings next. A random persona each call, never the same one twice in a row, with this call's savings and
## gullibility varied around the persona's own numbers so that no two calls with the same person are alike. Later
## days make callers a little harder to fool.

const SAVINGS_MIN_FACTOR := 0.5
const SAVINGS_MAX_FACTOR := 1.5
const GULLIBILITY_JITTER := 0.1
const HARDER_PER_DAY := 0.015  ## gullibility lost per day after the first...
const HARDER_MAX := 0.15  ## ...up to this much

var rng := RandomNumberGenerator.new()
var personas: Array[Dictionary] = []
var last_id := ""


func _init(available: Array[Dictionary] = [], seed_value: int = -1) -> void:
	personas = available
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()


## The next caller as a copy of a persona with this call's own savings and gullibility. {} when there are no personas.
func next_caller(day: int = 1) -> Dictionary:
	if personas.is_empty():
		return {}
	var pool := personas.filter(func(p): return p["id"] != last_id)
	if pool.is_empty():
		pool = personas
	var caller: Dictionary = (pool[rng.randi() % pool.size()] as Dictionary).duplicate(true)
	last_id = caller["id"]
	var savings := float(caller["savings"]) * rng.randf_range(SAVINGS_MIN_FACTOR, SAVINGS_MAX_FACTOR)
	caller["savings"] = maxi(int(roundf(savings / 100.0)) * 100, 100)
	var harder := clampf(float(maxi(day, 1) - 1) * HARDER_PER_DAY, 0.0, HARDER_MAX)
	caller["gullibility"] = clampf(float(caller["gullibility"]) + rng.randf_range(-GULLIBILITY_JITTER, GULLIBILITY_JITTER) - harder, 0.05, 0.98)
	return caller
