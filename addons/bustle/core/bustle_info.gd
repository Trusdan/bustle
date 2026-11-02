# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleInfo
extends RefCounted

## Facts about the installed Bustle addon.
##
## @experimental

## The addon's version. It must match [code]VERSION[/code] and [code]plugin.cfg[/code] in this
## folder; a test checks all three.
const VERSION: String = "0.1.0"
## The addon's folders and what each one is for.
const FOLDERS: Dictionary = {
	"core": "Plain data and rules with no nodes, tested headless.",
	"society": "How the members of a population relate to each other.",
	"ports": "The interfaces a host project implements to connect Bustle to its world.",
	"debug": "Tools for inspecting a running population.",
	"modules": "Optional features, each usable on its own.",
}


## The version as [code][major, minor, patch][/code].
## @experimental
static func version_parts() -> PackedInt32Array:
	var out: PackedInt32Array = []
	for part: String in VERSION.split("."):
		out.append(part.to_int())
	return out
