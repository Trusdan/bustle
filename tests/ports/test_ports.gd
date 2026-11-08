# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends GutTest
## Every port's standalone default works with no host and no scene, and BustlePorts builds them all.


func test_bustle_ports_starts_with_every_default() -> void:
	var ports := BustlePorts.new()
	assert_eq(BustlePorts.NAMES.size(), 13)
	assert_eq(ports.missing(), PackedStringArray())
	ports.trade = null
	assert_eq(ports.missing(), PackedStringArray(["trade"]))


func test_the_disposition_port_is_unchanged() -> void:
	var port := BustlePorts.new().disposition
	assert_eq(port.disposition(&"a", &"g1", &"b", &"g2"), BustleDispositionPort.Disposition.NEUTRAL)


func test_social_deeds_are_known_first_hand_and_shared_one_hop() -> void:
	var social := BustleSocialPort.new()
	assert_eq(social.opinion(&"a", &"b"), BustleSocialPort.NEUTRAL_OPINION)
	assert_eq(social.kinds_between(&"a", &"b"), PackedStringArray())
	assert_eq(social.reasons(&"a", &"b"), [])
	assert_eq(social.record_deed(&"", &"helped", &"b", &"well", []), &"", "no actor: no deed")
	var key := social.record_deed(&"a", &"helped", &"b", &"well", [{"id": &"w"}, {"name": "no id"}, {"id": ""}])
	assert_true(social.knows(&"a", key) and social.knows(&"w", key))
	assert_false(social.knows(&"b", key), "the target saw nothing, so doesn't know first-hand")
	assert_false(social.knows(&"a", &"deed_missing"))
	assert_eq(social.share_news(&"w", &"c", &"square"), 1)
	assert_true(social.knows(&"c", key))
	assert_eq(social.share_news(&"w", &"c", &"square"), 0, "already known")
	assert_eq(social.share_news(&"c", &"d", &"square"), 0, "second-hand news isn't passed on")
	assert_eq(social.share_news(&"a", &"a", &"square"), 0)


func test_roles_come_from_a_table_and_announce_changes() -> void:
	var table := BustleRoleTable.new()
	table.holders = {&"baker": &"ann", &"smith": &"ann", &"guard": &""}
	var roles := BustleRolesPort.new(table)
	assert_eq(roles.holder_of(&"baker"), &"ann")
	assert_eq(roles.roles_of(&"ann"), PackedStringArray(["baker", "smith"]))
	assert_eq(roles.holder_of(&"guard"), &"", "an empty holder isn't loaded")
	assert_eq(roles.roles_of(&""), PackedStringArray())
	watch_signals(roles)
	roles.set_holder(&"baker", &"ann")
	assert_signal_not_emitted(roles, "holder_changed", "no change, no signal")
	roles.set_holder(&"baker", &"bo")
	assert_signal_emitted_with_parameters(roles, "holder_changed", [&"baker", &"ann", &"bo"])
	roles.set_holder(&"smith", &"")
	assert_eq(roles.roles_of(&"ann"), PackedStringArray())


func test_the_world_is_one_area_with_no_bodies() -> void:
	var world := BustleWorldPort.new()
	assert_eq([world.area_of(&"a"), world.player_area()], [BustleWorldPort.DEFAULT_AREA, BustleWorldPort.DEFAULT_AREA])
	assert_eq(world.neighbour_areas(BustleWorldPort.DEFAULT_AREA), [])
	assert_false(world.has_place(&"well"))
	assert_eq(world.place_position(&"well"), Vector3.ZERO, "an unknown place answers the origin")
	world.set_place(&"well", Vector3(3, 0, 4))
	world.set_place(&"bad", Vector3(INF, 0, 0))
	assert_true(world.has_place(&"well"))
	assert_false(world.has_place(&"bad"))
	assert_eq(world.place_position(&"well"), Vector3(3, 0, 4))
	assert_eq(world.path_between(&"x", &"x"), [&"x"])
	assert_eq(world.path_between(&"x", &"y"), [&"x", &"y"])
	assert_eq(world.path_between(&"", &"y"), [])
	assert_eq(world.travel_minutes(&"x", &"y"), 0)
	assert_null(world.spawn_body(&"a", Transform3D.IDENTITY))
	world.free_body(&"a")


func test_the_clock_counts_minutes_and_days() -> void:
	var clock := BustleClockPort.new()
	assert_eq([clock.now_minutes(), clock.day_key()], [0, &"day_0"])
	assert_true(clock.advance(1439))
	assert_eq(clock.day_key(), &"day_0")
	clock.advance(1)
	assert_eq(clock.day_key(), &"day_1")
	assert_false(clock.advance(-5))
	assert_eq(clock.now_minutes(), 1440)


func test_combat_resolves_harmlessly() -> void:
	var combat := BustleCombatPort.new()
	assert_eq(combat.status(&"a"), BustleCombatPort.Status.NONE)
	combat.engage(&"a", &"a")
	assert_eq(combat.status(&"a"), BustleCombatPort.Status.NONE, "can't fight yourself")
	combat.engage(&"a", &"b")
	assert_eq(combat.status(&"a"), BustleCombatPort.Status.RESOLVED)
	combat.disengage(&"a")
	assert_eq(combat.status(&"a"), BustleCombatPort.Status.NONE)


func test_trade_never_creates_or_loses_money() -> void:
	var trade := BustleTradePort.new()
	assert_false(trade.set_balance(&"a", -1))
	trade.set_balance(&"a", 100)
	trade.prices = {&"bread": 30, &"water": 0}
	assert_eq(trade.balance(&"stranger"), 0)
	for bad: Array in [[&"a", &"b", -10], [&"a", &"b", 0], [&"a", &"a", 10], [&"", &"b", 10], [&"a", &"b", 101]]:
		assert_false(trade.pay(bad[0], bad[1], bad[2]), "refused: %s" % [bad])
	assert_eq([trade.balance(&"a"), trade.balance(&"b")], [100, 0], "failed payments change nothing")
	assert_true(trade.pay(&"a", &"b", 40))
	assert_false(trade.buy(&"a", &"cake", &"b"), "unpriced")
	assert_true(trade.buy(&"a", &"bread", &"b"))
	assert_true(trade.buy(&"a", &"water", &"b"), "free")
	assert_true(trade.buy(&"a", &"bread", &"b"), "the last 30 buys a second loaf")
	assert_false(trade.buy(&"a", &"bread", &"b"), "nothing left to pay with")
	assert_eq([trade.balance(&"a"), trade.balance(&"b")], [0, 100], "the total stays 100")


func test_the_module_ports_are_neutral() -> void:
	var ports := BustlePorts.new()
	assert_eq(ports.work.job_of(&"a"), &"")
	assert_eq(ports.skills.level(&"a", &"craft"), 0.0)
	assert_eq(ports.life_stages.stage_of(&"a"), &"")
	assert_false(ports.health.is_injured(&"a") or ports.health.is_incapacitated(&"a"))
	assert_eq(ports.environment.room_of(&"a"), &"")
	assert_true(ports.director.allows(&"quarrel"))
