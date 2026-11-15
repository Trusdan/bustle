# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleDeprecation
extends RefCounted

## Warns when deprecated public API is used: once per symbol per run, with [method @GlobalScope.push_warning].
## A deprecated method calls [method warn] first, then keeps working until the next major release
## removes it (see [code]docs/public-api/VERSIONING.md[/code]). Nothing else changes: the warning
## is only a message.
## [codeblock]
## ## @deprecated: Use [method new_name] instead.
## func old_name() -> void:
##     BustleDeprecation.warn("BustleExample.old_name", "BustleExample.new_name")
##     new_name()
## [/codeblock]

static var _warned: Dictionary = {}


## Warns that [param symbol] (such as [code]"BustleExample.old_name"[/code]) is deprecated, naming
## [param instead] when there is a replacement. Only the first call for a symbol in a run warns;
## true when this call did.
static func warn(symbol: String, instead: String = "") -> bool:
	if _warned.has(symbol):
		return false
	_warned[symbol] = true
	push_warning(message(symbol, instead))
	return true


## The warning text for [param symbol], naming [param instead] when it isn't empty.
static func message(symbol: String, instead: String = "") -> String:
	var text: String = "Bustle: %s is deprecated and will be removed in the next major release." % symbol
	if instead != "":
		text += " Use %s instead." % instead
	return text


## Whether [param symbol] has already warned in this run.
static func has_warned(symbol: String) -> bool:
	return _warned.has(symbol)


## Forgets which symbols have warned, so each warns again once.
static func reset() -> void:
	_warned.clear()
