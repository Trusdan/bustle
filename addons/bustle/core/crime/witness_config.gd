# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleWitnessConfig
extends Resource

## The numbers behind [BustleWitnessJudge]: what someone who knows of a theft does about it. Each
## outcome's score is [code]Σ weight × (value − 50) / 100[/code] over its terms, plus any loyalty.
## Nothing here is a chance.
## @experimental

## Outcome → term → weight. A term is a personality slider ([constant BustlePersonality.SLIDERS])
## or one of [constant BustleWitnessJudge.TERMS]. By default every outcome weighs honesty, piety,
## boldness and diligence, the witness's opinions of the thief and the victim and its fear of the
## thief; reporting adds the authority's standing, confronting adds temper and gossiping adds
## sociability.
@export var weights: Dictionary[StringName, Dictionary] = {
	&"report": _base({&"standing": 1.0}),
	&"tell_victim": _base({}),
	&"confront": _base({&"temper": 1.0}),
	&"gossip": _base({&"sociability": 1.0}),
}
## Relationship kind between the witness and the thief → loyalty, added to every outcome but
## silence (a negative loyalty, such as for kin, keeps a witness quiet). Empty by default.
@export var kind_weights: Dictionary[StringName, float] = {}
## What the best outcome must reach; below it, the witness stays silent.
@export var threshold: float = 1.0


static func _base(extra: Dictionary) -> Dictionary:
	var out := {&"honesty": 2.0, &"piety": 1.0, &"boldness": 1.0, &"diligence": 1.0,
		&"opinion_thief": -2.0, &"opinion_victim": 2.0, &"fear": -2.0}
	out.merge(extra, true)
	return out
