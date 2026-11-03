# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Light sampling: an ambient level plus point sources.


func test_ambient_only_gives_the_ambient_level() -> void:
	var probe := BustlePointLightProbe.new(0.3)
	var sample := probe.sample(Vector3(5, 0, 5))
	assert_almost_eq(sample.level, 0.3, 0.0001)
	assert_eq(sample.sources.size(), 0)


func test_the_base_probe_is_dark() -> void:
	assert_eq(BustleLightProbe.new().sample(Vector3.ZERO).level, 0.0)


func test_a_source_gives_its_energy_at_its_centre_and_nothing_at_its_range() -> void:
	var probe := BustlePointLightProbe.new()
	probe.add_source(BustleLightSource.new(&"torch", Vector3.ZERO, 4.0, 0.8))
	assert_almost_eq(probe.sample(Vector3.ZERO).level, 0.8, 0.0001)
	assert_eq(probe.sample(Vector3.ZERO).sources, [&"torch"] as Array[StringName])
	assert_almost_eq(probe.sample(Vector3(2, 0, 0)).level, 0.8 * 0.25, 0.0001, "half range: a quarter")
	assert_eq(probe.sample(Vector3(4, 0, 0)).level, 0.0, "at its range")
	assert_eq(probe.sample(Vector3(9, 0, 0)).level, 0.0, "beyond it")


func test_sources_add_and_clamp_at_1() -> void:
	var probe := BustlePointLightProbe.new(0.2)
	probe.add_source(BustleLightSource.new(&"a", Vector3.ZERO, 4.0, 0.5))
	assert_almost_eq(probe.sample(Vector3.ZERO).level, 0.7, 0.0001)
	probe.add_source(BustleLightSource.new(&"b", Vector3.ZERO, 4.0, 0.6))
	var sample := probe.sample(Vector3.ZERO)
	assert_eq(sample.level, 1.0)
	assert_eq(sample.sources, [&"a", &"b"] as Array[StringName])


func test_a_disabled_or_removed_source_adds_nothing() -> void:
	var probe := BustlePointLightProbe.new()
	var torch := probe.add_source(BustleLightSource.new(&"torch", Vector3.ZERO, 4.0, 1.0))
	torch.enabled = false
	assert_eq(probe.sample(Vector3.ZERO).level, 0.0)
	torch.enabled = true
	probe.remove_source(torch)
	assert_eq(probe.sample(Vector3.ZERO).level, 0.0)


func test_an_occluded_source_is_dropped() -> void:
	var probe := BustlePointLightProbe.new(0.1)
	probe.add_source(BustleLightSource.new(&"behind_wall", Vector3(-2, 0, 0), 5.0, 1.0))
	probe.add_source(BustleLightSource.new(&"open", Vector3(2, 0, 0), 5.0, 0.2))
	probe.occluded = func(from: Vector3, _to: Vector3) -> bool: return from.x < 0.0
	var sample := probe.sample(Vector3.ZERO)
	assert_eq(sample.sources, [&"open"] as Array[StringName])
	assert_almost_eq(sample.level, 0.1 + 0.2 * 0.36, 0.0001)
