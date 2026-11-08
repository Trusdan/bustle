# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleDebug
extends RefCounted

## Whether Bustle's debug tools may run. They run only in debug builds (the editor and debug
## exports); in a release export the console and overlay do nothing. Hosts can also leave
## [code]addons/bustle/debug/[/code] out of release exports with an export filter.
## @experimental

## For tests only: when not null, overrides whether this counts as a debug build.
static var debug_build_override: Variant = null


## True when the debug tools may run.
## @experimental
static func is_available() -> bool:
	if debug_build_override != null:
		return bool(debug_build_override)
	return OS.is_debug_build()
