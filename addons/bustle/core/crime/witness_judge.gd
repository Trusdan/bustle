# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleWitnessJudge
extends RefCounted

## What someone who knows of a theft does about it: exactly one of [constant OUTCOMES]. The default
## decision [BustleCrimeWatch] uses when the host doesn't supply its own
## ([member BustleCrimeWatch.should_report]).
## [br][br]
## Each eligible outcome gets a score from [member config] (the witness's personality, its opinions
## of the thief and the victim, its fear of the thief and, for a report, the authority's standing
## with it), and the highest wins. Ties go to the earlier of [constant OUTCOMES]. Below
## [member BustleWitnessConfig.threshold], the witness stays silent. Nothing here is a chance, and
## the same formulas hold for every agent.
## [br][br]
## Eligibility: a report always; telling the victim when the victim is someone else; confronting
## when the thief is known and within reach; gossiping when there's someone to tell.
## @experimental

## Tell the authority role.
const REPORT := &"report"
## Tell the one it was stolen from.
const TELL_VICTIM := &"tell_victim"
## Accuse the thief face to face (words only).
const CONFRONT := &"confront"
## Tell someone else.
const GOSSIP := &"gossip"
## Do nothing (it still remembers).
const SILENT := &"silent"
## Every outcome, in tie-break order.
const OUTCOMES: Array[StringName] = [REPORT, TELL_VICTIM, CONFRONT, GOSSIP, SILENT]
## The terms besides personality sliders: opinion of the thief, opinion of the victim, fear of the
## thief and the authority's standing, each 0 to 100 (50 when unknown).
const TERMS: Array[StringName] = [&"opinion_thief", &"opinion_victim", &"fear", &"standing"]

## The agents and the social and roles ports.
var society: BustleSociety
## The weights and the threshold.
var config: BustleWitnessConfig
## The role a report goes to (for the standing term).
var authority_role: StringName = &"authority"
## (id) → that agent's [BustlePersonality], or null (neutral sliders).
var personality_of: Callable = Callable()
## (witness, thief) → how much the witness fears the thief, 0 to 100. Empty: 50.
var fear_of: Callable = Callable()
## (witness) → the authority's standing with the witness, 0 to 100. Empty: its opinion of the
## role's holder, or 50 when nobody holds it.
var standing_of: Callable = Callable()


func _init(p_society: BustleSociety = null, p_config: BustleWitnessConfig = null) -> void:
	society = p_society if p_society != null else BustleSociety.new()
	config = p_config if p_config != null else BustleWitnessConfig.new()


## Decides for [param witness]. [param case]: [code]{thief, owner_id, can_confront, gossip_to}[/code]
## (an empty thief is unknown). Returns [code]{outcome, scores}[/code], where [code]scores[/code]
## holds each eligible outcome's score.
## @experimental
func decide(witness: StringName, case: Dictionary) -> Dictionary:
	var thief := StringName(case.get("thief", ""))
	var victim := StringName(case.get("owner_id", ""))
	var values := _values(witness, thief, victim)
	var loyalty := 0.0
	if thief != &"":
		for kind: String in society.ports.social.kinds_between(witness, thief):
			loyalty += config.kind_weights.get(StringName(kind), 0.0)
	var eligible: Dictionary[StringName, bool] = {
		REPORT: true,
		TELL_VICTIM: victim != &"" and victim != witness,
		CONFRONT: thief != &"" and thief != witness and bool(case.get("can_confront", false)),
		GOSSIP: StringName(case.get("gossip_to", "")) != &"",
	}
	var scores := {}
	var best := SILENT
	for outcome: StringName in OUTCOMES:
		if outcome == SILENT or not eligible[outcome]:
			continue
		var score := loyalty
		var terms: Dictionary = config.weights.get(outcome, {})
		for term: StringName in terms:
			score += float(terms[term]) * (float(values.get(term, 50.0)) - 50.0) / 100.0
		scores[String(outcome)] = score
		if score >= config.threshold and (best == SILENT or score > float(scores[String(best)])):
			best = outcome
	return {"outcome": best, "scores": scores}


func _values(witness: StringName, thief: StringName, victim: StringName) -> Dictionary:
	var out := {}
	var found: Variant = personality_of.call(witness) if personality_of.is_valid() else null
	if found is BustlePersonality:
		for slider: StringName in BustlePersonality.SLIDERS:
			out[slider] = (found as BustlePersonality).slider(slider)
	var social := society.ports.social
	if thief != &"" and thief != witness:
		out[&"opinion_thief"] = float(social.opinion(witness, thief))
		if fear_of.is_valid():
			out[&"fear"] = float(fear_of.call(witness, thief))
	if victim != &"" and victim != witness:
		out[&"opinion_victim"] = float(social.opinion(witness, victim))
	if standing_of.is_valid():
		out[&"standing"] = float(standing_of.call(witness))
	else:
		var holder := society.ports.roles.holder_of(authority_role)
		if holder != &"" and holder != witness:
			out[&"standing"] = float(social.opinion(witness, holder))
	return out
