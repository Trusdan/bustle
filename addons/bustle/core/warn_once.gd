# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends RefCounted

## Internal: the warning limiter behind docs/errors.md's "warn once". One [method @GlobalScope.push_warning]
## per key per run, in every build. A key is a class and a problem, plus a definition id when that's
## what's wrong ([code]"BustleSchedule.invalid_block"[/code]); never an agent id or a minute, so a
## problem in a per-tick path warns once. Also the type checks for hook results: a result of the
## wrong type (null included) warns once and gives the hook's unset value. Not part of the public API.

static var _warned: Dictionary = {}


## Warns [param message] the first time [param key] is seen in this run. True when this call warned.
static func warn(key: String, message: String) -> bool:
	if _warned.has(key):
		return false
	_warned[key] = true
	push_warning(message)
	return true


## Whether [param key] has warned in this run.
static func has_warned(key: String) -> bool:
	return _warned.has(key)


## Forgets every key, so each warns again once. For tests.
static func reset() -> void:
	_warned.clear()


## A hook's bool result: [param value] when it's a bool or an int, otherwise [param unset] with a warning for [param hook].
static func as_bool(value: Variant, unset: bool, hook: String) -> bool:
	if typeof(value) == TYPE_BOOL or typeof(value) == TYPE_INT:
		return bool(value)
	_wrong(hook, value, "a bool")
	return unset


## A hook's number result: [param value] when it's a float or an int, otherwise [param unset] with a warning.
static func as_float(value: Variant, unset: float, hook: String) -> float:
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return float(value)
	_wrong(hook, value, "a number")
	return unset


## A hook's int result: [param value] when it's an int or a whole float, otherwise [param unset] with a warning.
static func as_int(value: Variant, unset: int, hook: String) -> int:
	if typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value) and value == floorf(value)):
		return int(value)
	_wrong(hook, value, "an int")
	return unset


## A hook's id result: [param value] when it's a StringName or a String, otherwise [param unset] with a warning.
static func as_name(value: Variant, unset: StringName, hook: String) -> StringName:
	if typeof(value) == TYPE_STRING_NAME or typeof(value) == TYPE_STRING:
		return StringName(value)
	_wrong(hook, value, "a StringName")
	return unset


## True when [param value] suits [param wanted] ([code]"bool"[/code], [code]"number"[/code],
## [code]"int"[/code] or [code]"name"[/code]); otherwise false, with a warning for [param hook]. For a
## hook whose unset behaviour is Bustle's own fallback rather than a value.
static func fits(value: Variant, wanted: String, hook: String) -> bool:
	var kind := typeof(value)
	var ok := false
	match wanted:
		"bool":
			ok = kind == TYPE_BOOL or kind == TYPE_INT
		"number":
			ok = kind == TYPE_FLOAT or kind == TYPE_INT
		"int":
			ok = kind == TYPE_INT or (kind == TYPE_FLOAT and is_finite(value) and value == floorf(value))
		"name":
			ok = kind == TYPE_STRING_NAME or kind == TYPE_STRING
	if not ok:
		_wrong(hook, value, {"bool": "a bool", "number": "a number", "int": "an int", "name": "a StringName"}[wanted])
	return ok


static func _wrong(hook: String, value: Variant, wanted: String) -> void:
	warn(hook + ".wrong_type", "%s: the hook returned %s, not %s; using its unset value" % [
		hook, type_string(typeof(value)), wanted])
