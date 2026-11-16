# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## A detection meter's saved number that is null, or any other value float() can't convert, reads
## as 0 on import, with no script error and the one warning per run its import already gives.
## Values float() converts import as they always did, and a valid save imports unchanged.
## The engine's own log is captured, so a script error or a second warning can't go unseen.

const _Warn := preload("res://addons/bustle/core/warn_once.gd")
const WARNING := "BustleDetectionMeter: import_state() got a value of the wrong type or range"


## Every error and warning the engine logs while it's added.
class Capture:
	extends Logger
	var warnings: Array[String] = []
	var errors: Array[String] = []

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			warnings.append(code + rationale)
		else:
			errors.append(code + rationale)

	func _log_message(_message: String, _error: bool) -> void:
		pass


var _capture: Capture


func before_each() -> void:
	_Warn.reset()
	_capture = Capture.new()
	OS.add_logger(_capture)


func after_each() -> void:
	OS.remove_logger(_capture)


# A meter that has sensed something, so a value read as 0 shows.
func _busy_meter() -> BustleDetectionMeter:
	var meter := BustleDetectionMeter.new()
	meter.import_state({"level": 0.7, "state": "searching", "last_known": [1.0, 2.0, 3.0], "has_last_known": true,
		"lost_time": 2.0, "search_left": 3.0, "since_sensed": 4.0})
	return meter


func _meter_warnings() -> Array[String]:
	return _capture.warnings.filter(func(w: String) -> bool: return w.begins_with(WARNING))


func test_a_null_level_imported_twice_reads_as_zero_and_warns_once() -> void:
	var meter := _busy_meter()
	var saved := meter.export_state()
	saved["level"] = null
	for i in 2:
		meter.import_state(saved)
		assert_eq(meter.level, 0.0, "import %d: the null level reads as 0" % (i + 1))
	assert_eq(_capture.errors, [] as Array[String], "no script or engine error")
	assert_eq(_meter_warnings().size(), 1, "one warning for both imports")
	assert_true(_Warn.has_warned("BustleDetectionMeter.bad_value"))


func test_every_saved_number_reads_null_as_zero() -> void:
	var meter := _busy_meter()
	var saved := meter.export_state()
	for key: String in ["level", "lost_time", "search_left", "since_sensed"]:
		saved[key] = null
	saved["last_known"] = [null, 2.0, null]
	meter.import_state(saved)
	assert_eq([meter.level, meter._lost_time, meter._search_left, meter.since_sensed], [0.0, 0.0, 0.0, 0.0])
	assert_eq(meter.last_known_position, Vector3(0.0, 2.0, 0.0), "a null coordinate reads as 0")
	assert_eq(meter.state, BustleDetectionMeter.State.SEARCHING, "the good values still import")
	assert_eq(_capture.errors, [] as Array[String])
	assert_eq(_meter_warnings().size(), 1)


func test_values_float_cant_convert_read_as_zero() -> void:
	for bad: Variant in [[0.5], {"x": 1}, Vector2(1, 2), Color.RED, NodePath("a")]:
		var meter := _busy_meter()
		var saved := meter.export_state()
		saved["level"] = bad
		saved["last_known"] = [bad, 2.0, 3.0]
		meter.import_state(saved)
		assert_eq([meter.level, meter.last_known_position.x], [0.0, 0.0], type_string(typeof(bad)))
	assert_eq(_capture.errors, [] as Array[String], "no script error for any of them")
	assert_eq(_meter_warnings().size(), 1, "and still one warning in all")


func test_values_float_converts_import_as_they_always_did() -> void:
	var meter := _busy_meter()
	var saved := meter.export_state()
	saved["level"] = "0.25"
	saved["lost_time"] = true
	saved["search_left"] = &"1.5"
	meter.import_state(saved)
	assert_eq([meter.level, meter._lost_time, meter._search_left], [0.25, 1.0, 1.5])
	assert_eq(_capture.errors, [] as Array[String])
	assert_eq(_meter_warnings().size(), 1, "they're the wrong type, so the import warns")


func test_a_valid_save_imports_unchanged_and_quietly() -> void:
	var meter := _busy_meter()
	var saved := meter.export_state()
	var copy := BustleDetectionMeter.new()
	copy.import_state(saved)
	assert_eq(copy.export_state(), saved)
	assert_eq(_capture.errors, [] as Array[String])
	assert_eq(_meter_warnings(), [] as Array[String])
