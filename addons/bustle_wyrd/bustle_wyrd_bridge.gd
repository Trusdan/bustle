# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleWyrdBridge
extends RefCounted

## The optional bridge between Bustle and the Wyrd narrative engine.
##
## @experimental
## It is pinned to one exact Wyrd release ([constant WYRD_VERSION]) and checks it before doing
## anything. It only reads Wyrd's [code]VERSION[/code] file and calls Wyrd by name, so this script
## compiles, and Bustle's core works, with no Wyrd in the project. Nothing in [code]addons/bustle/[/code]
## refers to this folder.

## The exact Wyrd release this bridge is written for.
const WYRD_VERSION: String = "1.0.0"
## Where Wyrd keeps its version.
const WYRD_VERSION_FILE: String = "res://addons/wyrd/VERSION"


## The installed Wyrd version, or an empty string when Wyrd is not in the project.
## @experimental
static func installed_wyrd_version() -> String:
	if not FileAccess.file_exists(WYRD_VERSION_FILE):
		return ""
	return FileAccess.get_file_as_string(WYRD_VERSION_FILE).strip_edges()


## True when the installed Wyrd is exactly the pinned release.
## @experimental
static func is_supported() -> bool:
	return installed_wyrd_version() == WYRD_VERSION
