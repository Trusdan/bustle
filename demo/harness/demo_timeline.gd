# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends RefCounted

## A demo run's timeline: one entry per thing that happened, in the order it happened, and a stable
## hash of them. Each entry is the game minute, the agent, the event kind and a payload of plain
## strings and whole numbers. The same seed and setup give the same entries, so the same hash.
## See [code]demo/README.md[/code] for what the demos log.

var _entries: Array[Dictionary] = []


## Logs that [param agent] had event [param kind] at minute [param minute], with [param payload]
## (strings and whole numbers only, so it hashes the same everywhere).
func add(minute: int, agent: StringName, kind: StringName, payload: Dictionary = {}) -> void:
	_entries.append({"t": minute, "agent": String(agent), "kind": String(kind), "payload": payload.duplicate(true)})


## Every entry so far, oldest first (copies).
func entries() -> Array[Dictionary]:
	return _entries.duplicate(true)


## The entries of one [param kind] for [param agent] (any agent when empty).
func of(kind: StringName, agent: StringName = &"") -> Array[Dictionary]:
	return _entries.filter(func(e: Dictionary) -> bool:
		return e["kind"] == String(kind) and (agent == &"" or e["agent"] == String(agent)))


## One line per entry: [code]minute|agent|kind|payload[/code], the payload as JSON with its keys
## sorted.
func lines() -> PackedStringArray:
	var out := PackedStringArray()
	for entry: Dictionary in _entries:
		out.append("%d|%s|%s|%s" % [entry["t"], entry["agent"], entry["kind"], JSON.stringify(entry["payload"], "", true)])
	return out


## The SHA-256 of [method lines], joined by newlines, as hex.
func hash() -> String:
	return "\n".join(lines()).sha256_text()


## How many entries there are.
func size() -> int:
	return _entries.size()
