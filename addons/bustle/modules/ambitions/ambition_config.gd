# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleAmbitionConfig
extends Resource

## The ambition library and its numbers, for [BustleAmbitions]. A starting point, not tuning: a host
## sets its own, and turns templates off with [member BustleAmbitionDef.enabled].
## @experimental

## The project setting a developer or a test turns ambitions off with (default on). It isn't a
## game option.
const SETTING := "bustle/simulation/ambitions"

## The templates.
@export var templates: Array[BustleAmbitionDef] = default_templates()
## After a template is completed, how long (game days) before the same agent can be given it again.
## Only after completion: an ambition that ends moot can be given again at once.
@export var cooldown_days: float = 7.0


## The default library, with its circumstance, input and fact names:
## [br]- [code]save_money[/code]: greed 1.0, diligence 0.4, greed at least 50; done when
## [code]wallet[/code] reaches 2000 (abstract units: the host sets real amounts).
## [br]- [code]get_promoted[/code]: diligence 1.0, boldness 0.4; needs [code]has_role[/code]; done
## on [code]promotion_granted[/code]; moot on [code]role_lost[/code].
## [br]- [code]court_someone[/code]: sociability 1.0, boldness 0.3; needs
## [code]has_court_target[/code]; done when [code]court_opinion[/code] reaches 75 and
## [code]court_friend[/code] holds; moot on [code]court_target_gone[/code].
## [br]- [code]settle_feud[/code]: honesty 1.0, sociability 0.4; needs [code]has_rival[/code];
## done when [code]rival_opinion[/code] reaches 50 and [code]rival_cleared[/code] holds, or on
## [code]feud_settled[/code]; moot on [code]rival_gone[/code].
## [br]- [code]leave_settlement[/code]: curiosity 0.8, boldness 0.6, greed −0.3; done on
## [code]left_settlement[/code]; moot on [code]cannot_leave[/code].
## @experimental
static func default_templates() -> Array[BustleAmbitionDef]:
	var save := BustleAmbitionDef.make(&"save_money", {&"greed": 1.0, &"diligence": 0.4}, [], &"wallet", 2000.0)
	save.min_sliders = {&"greed": 50.0}
	var promote := BustleAmbitionDef.make(&"get_promoted", {&"diligence": 1.0, &"boldness": 0.4}, [&"has_role"])
	promote.done_fact = &"promotion_granted"
	promote.moot_facts = [&"role_lost"]
	var court := BustleAmbitionDef.make(&"court_someone", {&"sociability": 1.0, &"boldness": 0.3}, [&"has_court_target"],
		&"court_opinion", 75.0)
	court.done_facts = [&"court_friend"]
	court.moot_facts = [&"court_target_gone"]
	var feud := BustleAmbitionDef.make(&"settle_feud", {&"honesty": 1.0, &"sociability": 0.4}, [&"has_rival"],
		&"rival_opinion", 50.0)
	feud.done_facts = [&"rival_cleared"]
	feud.done_fact = &"feud_settled"
	feud.moot_facts = [&"rival_gone"]
	var leave := BustleAmbitionDef.make(&"leave_settlement", {&"curiosity": 0.8, &"boldness": 0.6, &"greed": -0.3})
	leave.done_fact = &"left_settlement"
	leave.moot_facts = [&"cannot_leave"]
	return [save, promote, court, feud, leave]


## True unless a developer or a test turned [constant SETTING] off.
## @experimental
static func allowed() -> bool:
	return bool(ProjectSettings.get_setting(SETTING, true))


## The template with [param id], or null.
## @experimental
func find(id: StringName) -> BustleAmbitionDef:
	for def: BustleAmbitionDef in templates:
		if def.id == id:
			return def
	return null
