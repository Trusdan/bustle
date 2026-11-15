# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## The internal warning limiter: one warning per key per run, a reset for tests, and the type
## checks for hook results that give the hook's unset value on a wrong type.

const _Warn := preload("res://addons/bustle/core/warn_once.gd")


func before_each() -> void:
	_Warn.reset()


func test_a_key_warns_once_until_reset() -> void:
	assert_false(_Warn.has_warned("Test.problem"))
	assert_true(_Warn.warn("Test.problem", "Test: a problem"), "the first time warns")
	assert_false(_Warn.warn("Test.problem", "Test: a problem"), "the second time doesn't")
	assert_true(_Warn.warn("Test.other", "Test: another problem"), "another key warns on its own")
	assert_true(_Warn.has_warned("Test.problem"))
	assert_push_warning_count(2)
	_Warn.reset()
	assert_false(_Warn.has_warned("Test.problem"), "reset forgets every key")


func test_each_check_keeps_a_fitting_value_and_unsets_the_rest() -> void:
	# [check, value, unset, expected, warns]
	var cases: Array = [
		[_Warn.as_bool, true, false, true, false],
		[_Warn.as_bool, 0, true, false, false],
		[_Warn.as_bool, null, true, true, true],
		[_Warn.as_bool, "yes", false, false, true],
		[_Warn.as_float, 2, 1.0, 2.0, false],
		[_Warn.as_float, 0.5, 1.0, 0.5, false],
		[_Warn.as_float, null, 1.0, 1.0, true],
		[_Warn.as_float, "0.5", 1.0, 1.0, true],
		[_Warn.as_int, 7, 0, 7, false],
		[_Warn.as_int, 7.0, 0, 7, false],
		[_Warn.as_int, 7.5, 0, 0, true],
		[_Warn.as_int, INF, 0, 0, true],
		[_Warn.as_int, null, 0, 0, true],
		[_Warn.as_name, &"well", &"", &"well", false],
		[_Warn.as_name, "well", &"", &"well", false],
		[_Warn.as_name, 3, &"", &"", true],
		[_Warn.as_name, null, &"x", &"x", true],
	]
	for i in cases.size():
		var row: Array = cases[i]
		_Warn.reset()
		var check: Callable = row[0]
		var got: Variant = check.call(row[1], row[2], "Test.hook")
		assert_eq(got, row[3], "case %d gives %s" % [i, row[3]])
		assert_eq(_Warn.has_warned("Test.hook.wrong_type"), row[4], "case %d warns: %s" % [i, row[4]])


func test_fits_names_what_each_kind_accepts() -> void:
	# [value, wanted, fits]
	var cases: Array = [
		[true, "bool", true], [1, "bool", true], [null, "bool", false], [1.0, "bool", false],
		[1, "number", true], [0.5, "number", true], ["1", "number", false],
		[3, "int", true], [3.0, "int", true], [3.5, "int", false], [NAN, "int", false],
		[&"a", "name", true], ["a", "name", true], [null, "name", false],
	]
	for i in cases.size():
		var row: Array = cases[i]
		_Warn.reset()
		assert_eq(_Warn.fits(row[0], row[1], "Test.hook"), row[2], "case %d" % i)
		assert_eq(_Warn.has_warned("Test.hook.wrong_type"), not row[2], "case %d warns only on a misfit" % i)


func test_a_wrong_type_warns_once_per_hook_however_often_it_comes() -> void:
	for i in 50:
		_Warn.as_bool(null, true, "Test.gate")
		_Warn.as_float("x", 1.0, "Test.gain")
	assert_push_warning_count(2, "one per hook, not one per call")
