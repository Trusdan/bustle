# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleFindPerson
extends RefCounted

## Works out where to look for someone, in order: sense them now ([member sense]); remember where
## they were ([BustleMemory]); guess from their routine ([member routine]); ask the people the
## seeker can ask ([member ask_whom]), whose memories answer; or give up. Giving up starts a
## cooldown for that seeker and target, during which [method find] fails at once, so an agent
## doesn't search for someone nobody knows about every tick. What is learnt by asking or guessing
## is noted in the seeker's memory ([constant BustleMemory.TOLD], [constant BustleMemory.ROUTINE]).
## [br][br]
## The host supplies each source as a [Callable]; empty ones are skipped.
## @experimental

## Found by sensing them.
const SENSED := &"sensed"
## Found in memory.
const REMEMBERED := &"remembered"
## Guessed from their routine.
const GUESSED := &"guessed"
## Learnt by asking someone.
const ASKED := &"asked"
## Nobody knew.
const UNKNOWN := &"unknown"
## Still cooling down from a search that failed.
const COOLING_DOWN := &"cooling_down"

## (seeker, target) → [code]{area, position}[/code] when the seeker senses the target now, else empty.
var sense: Callable = Callable()
## (target, now) → [code]{area, position}[/code] where the target's routine puts it now, else empty.
var routine: Callable = Callable()
## (seeker) → the ids the seeker can ask (people nearby it knows), in order.
var ask_whom: Callable = Callable()
## (id) → that agent's [BustleMemory], or null.
var memory_of: Callable = Callable()
## How strong a remembered entry must be to act on.
var min_confidence: float = 0.25
## Game minutes before searching again after giving up.
var cooldown_minutes: int = 60

var _cooldowns: Dictionary[String, int] = {}


## Where [param seeker] should look for [param target] at minute [param now]:
## [code]{found, how, area, position, from}[/code]. [code]how[/code] is one of the constants above;
## [code]from[/code] is who answered when asked. When nothing works, [code]found[/code] is false,
## [code]how[/code] is [constant UNKNOWN] and a cooldown starts.
## @experimental
func find(seeker: StringName, target: StringName, now: int) -> Dictionary:
	var key := "%s>%s" % [seeker, target]
	if _cooldowns.get(key, -1) > now:
		return _fail(COOLING_DOWN)
	var own := _memory(seeker)
	var seen := _call(sense, [seeker, target])
	if not seen.is_empty():
		if own != null:
			own.note(BustleMemory.PERSON, target, StringName(seen.get("area", "")), seen.get("position"), BustleMemory.SAW, now)
		return _found(SENSED, seen)
	if own != null:
		var known := own.recall(BustleMemory.PERSON, target, now)
		if not known.is_empty() and float(known["strength"]) >= min_confidence:
			return _found(REMEMBERED, known)
	var guess := _call(routine, [target, now])
	if not guess.is_empty():
		if own != null:
			own.note(BustleMemory.PERSON, target, StringName(guess.get("area", "")), guess.get("position"), BustleMemory.ROUTINE, now)
		return _found(GUESSED, guess)
	if ask_whom.is_valid():
		var people: Variant = ask_whom.call(seeker)
		if people is Array:
			for person: Variant in people:
				if not (person is StringName or person is String) or StringName(person) == seeker:
					continue
				var theirs := _memory(StringName(person))
				var answer := theirs.recall(BustleMemory.PERSON, target, now) if theirs != null else {}
				if answer.is_empty() or float(answer["strength"]) < min_confidence:
					continue
				if own != null:
					own.note(BustleMemory.PERSON, target, answer["area"], answer["position"], BustleMemory.TOLD, now)
				var out := _found(ASKED, answer)
				out["from"] = StringName(person)
				return out
	_cooldowns[key] = now + maxi(cooldown_minutes, 0)
	return _fail(UNKNOWN)


## When [param seeker] may search for [param target] again (a game minute), or -1 for now.
## @experimental
func cooldown_until(seeker: StringName, target: StringName) -> int:
	return _cooldowns.get("%s>%s" % [seeker, target], -1)


func _memory(id: StringName) -> BustleMemory:
	return memory_of.call(id) as BustleMemory if memory_of.is_valid() else null


static func _call(source: Callable, args: Array) -> Dictionary:
	if not source.is_valid():
		return {}
	var out: Variant = source.callv(args)
	return out if out is Dictionary else {}


static func _found(how: StringName, where: Dictionary) -> Dictionary:
	var position: Variant = where.get("position")
	return {"found": true, "how": how, "area": StringName(where.get("area", &"")),
		"position": position if position is Vector3 else null, "from": &""}


static func _fail(how: StringName) -> Dictionary:
	return {"found": false, "how": how, "area": &"", "position": null, "from": &""}
