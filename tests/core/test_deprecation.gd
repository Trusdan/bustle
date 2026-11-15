# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest

## BustleDeprecation warns once per symbol per run, and says what to use instead.


func before_each() -> void:
	BustleDeprecation.reset()


func after_all() -> void:
	BustleDeprecation.reset()


func test_the_message_names_the_symbol_and_its_replacement() -> void:
	assert_eq(BustleDeprecation.message("BustleExample.old_name"),
		"Bustle: BustleExample.old_name is deprecated and will be removed in the next major release.")
	assert_eq(BustleDeprecation.message("BustleExample.old_name", "BustleExample.new_name"),
		"Bustle: BustleExample.old_name is deprecated and will be removed in the next major release. Use BustleExample.new_name instead.")


func test_it_warns_once_per_symbol() -> void:
	assert_false(BustleDeprecation.has_warned("BustleExample.old_name"))
	# The one deliberate warning in the suite: "Bustle: BustleExample.old_name is deprecated ...".
	assert_true(BustleDeprecation.warn("BustleExample.old_name", "BustleExample.new_name"))
	assert_true(BustleDeprecation.has_warned("BustleExample.old_name"))
	assert_false(BustleDeprecation.warn("BustleExample.old_name", "BustleExample.new_name"), "not twice")
	assert_false(BustleDeprecation.has_warned("BustleExample.other"), "each symbol on its own")


func test_reset_lets_a_symbol_warn_again() -> void:
	BustleDeprecation._warned["BustleExample.old_name"] = true
	BustleDeprecation.reset()
	assert_false(BustleDeprecation.has_warned("BustleExample.old_name"))
