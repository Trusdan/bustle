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
## Goals an ambition never boosts, whatever its table says: theft stays with the crime module, and
## no aim makes anyone pick a fight.
@export var never_boost: Array[StringName] = [&"steal", &"insult", &"quarrel", &"fight", &"attack"]
## Courting: the least opinion of someone to court them.
@export var like_line: float = 60.0
## Relationship kinds that make someone family, so never courted.
@export var family_kinds: Array[StringName] = [&"family", &"kin", &"parent", &"child", &"sibling", &"spouse", &"partner"]


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
## [br]Boosts: saving and promotion ×1.5 to [code]work[/code] (saving ×1.3 to [code]trade[/code]);
## courting ×2 to [code]visit[/code], [code]converse[/code] and [code]gift[/code] toward the one
## courted ([code]court_target[/code]); settling ×2 to [code]help[/code], [code]gift[/code] and
## [code]converse[/code] toward the rival ([code]rival[/code]); leaving ×1.5 to [code]explore[/code].
## @experimental
static func default_templates() -> Array[BustleAmbitionDef]:
	var save := BustleAmbitionDef.make(&"save_money", {&"greed": 1.0, &"diligence": 0.4}, [], &"wallet", 2000.0)
	save.min_sliders = {&"greed": 50.0}
	save.boosts = {&"work": 1.5, &"trade": 1.3}
	var promote := BustleAmbitionDef.make(&"get_promoted", {&"diligence": 1.0, &"boldness": 0.4}, [&"has_role"])
	promote.done_fact = &"promotion_granted"
	promote.moot_facts = [&"role_lost"]
	promote.boosts = {&"work": 1.5}
	var court := BustleAmbitionDef.make(&"court_someone", {&"sociability": 1.0, &"boldness": 0.3}, [&"has_court_target"],
		&"court_opinion", 75.0)
	court.done_facts = [&"court_friend"]
	court.moot_facts = [&"court_target_gone"]
	court.boosts = {&"visit": 2.0, &"converse": 2.0, &"gift": 2.0}
	court.target_input = &"court_target"
	var feud := BustleAmbitionDef.make(&"settle_feud", {&"honesty": 1.0, &"sociability": 0.4}, [&"has_rival"],
		&"rival_opinion", 50.0)
	feud.done_facts = [&"rival_cleared"]
	feud.done_fact = &"feud_settled"
	feud.moot_facts = [&"rival_gone"]
	feud.boosts = {&"help": 2.0, &"gift": 2.0, &"converse": 2.0}
	feud.target_input = &"rival"
	var leave := BustleAmbitionDef.make(&"leave_settlement", {&"curiosity": 0.8, &"boldness": 0.6, &"greed": -0.3})
	leave.done_fact = &"left_settlement"
	leave.moot_facts = [&"cannot_leave"]
	leave.boosts = {&"explore": 1.5}
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
