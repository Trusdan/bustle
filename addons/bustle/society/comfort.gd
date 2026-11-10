# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleComfort
extends RefCounted

## The comfort hook: an agent who notices a friend in a low mood is offered comforting them. For
## each such friend it adds an advertisement to the agent's [BustleSenses] (option id: the friend;
## relief: [member need], larger the lower the friend's mood; tags: [member tags]) and sets the
## [code]need.<need>[/code] input to 1, so a goal with [member BustleGoalDef.uses_advertisements]
## can pick whom to comfort and a [code]converse[/code] step with a comfort opener can do it.
## [br][br]
## How much an agent cares is its need weight, [code]need.<need>.weight[/code] in its
## [BustleModifierSet], which the brain reads for every advertised need: a trait raises or lowers
## it with [member BustleTraitDef.mults]. Nothing here depends on the mood module: a mood is
## anything with a [code]mood[/code] number.
## @experimental

## Below this mood (0 to 100), a friend needs comforting.
var low_mood: float = 30.0
## The relationship kinds (the agent's of the friend) that count as a friend.
var kinds: Array[StringName] = [&"friend"]
## The need comforting relieves.
var need: StringName = &"comfort"
## The advertisements' tags.
var tags: Array[StringName] = [&"social", &"comfort"]
## (id) → true while that agent is in a low mental state (for example
## [method BustleMentalBehaviour.in_low_state]). A friend in one needs comforting even once its
## mood has started to rise. Empty: mood alone decides.
var low_state_of: Callable = Callable()
## The least comfort a friend in a low state needs (0 to 1), whatever its mood.
var low_state_urgency: float = 0.5


## How much comfort an agent in [param mood] needs: 0 at or above [member low_mood], up to 1 at
## mood 0 (and 0 for no mood).
## @experimental
func urgency(mood: float) -> float:
	if not is_finite(mood) or mood < 0.0 or low_mood <= 0.0:
		return 0.0
	return clampf((low_mood - mood) / low_mood, 0.0, 1.0)


## Adds an advertisement to [param senses] for each agent in [param noticed] that
## [param agent_id] counts as a friend in [param social] and whose mood ([param mood_of], (id) →
## anything with a [code]mood[/code], or null) is low, or who is in a low state
## ([member low_state_of]). Returns how many it added.
## @experimental
func advertise(agent_id: StringName, noticed: Array[StringName], social: BustleSocialPort, mood_of: Callable,
		senses: BustleSenses) -> int:
	if social == null or senses == null or not mood_of.is_valid():
		return 0
	var added := 0
	for other: StringName in noticed:
		if other == agent_id or other == &"" or not _is_friend(social.kinds_between(agent_id, other)):
			continue
		var found: Variant = mood_of.call(other)
		if not found is Object or found.get(&"mood") == null:
			continue
		var amount := urgency(float(found.get(&"mood")))
		if low_state_of.is_valid() and bool(low_state_of.call(other)):
			amount = maxf(amount, clampf(low_state_urgency, 0.0, 1.0))
		if amount <= 0.0:
			continue
		var relief: Dictionary[StringName, float] = {need: amount}
		senses.advertisements.append(BustleAdvertisement.new(other, relief, {}, tags.duplicate()))
		added += 1
	if added > 0:
		senses.inputs[StringName("need." + String(need))] = 1.0
	return added


func _is_friend(between: PackedStringArray) -> bool:
	for kind: StringName in kinds:
		if between.has(String(kind)):
			return true
	return false
