# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleUtilityScorer
extends RefCounted

## Scores an agent's goals and picks one. It keeps no state.
##
## - **A goal's score** is [code]base_weight × Π curve(input)[/code]. A failed precondition, or a
##   consideration whose input is missing, malformed or not finite, makes it ineligible with a
##   reason; a missing input is never sampled.
## - **An advertisement's score**, for option [i]o[/i]:
##   [code]need_value = Σ relief(o,n)·curve_n(p_n)·w_n − Σ adds(o,n)·curve_n(p_n + 0.2)·w_n[/code],
##   then [code]× Π tag_mult × distance_falloff × mood_mod × expected_thought_gain[/code]. It is
##   signed. [code]p_n[/code] is the input [code]need.<n>[/code]; a need the agent doesn't have adds
##   nothing. Needs and tags are taken in sorted order. Every number it consumes (need names and
##   pressures, relief and side effects, weights, multipliers, distance, mood, the preview) is checked
##   before any clamping or curve sampling: a malformed or non-finite one makes the score NAN, with
##   a reason, so the candidate is ineligible.
## - **A goal that uses advertisements** makes one candidate per option, scored
##   [code]goal score × advertisement score[/code].
## - **Repeated options:** a goal's first advertisement for an option id is used; each repeat adds a
##   [code]duplicate_option[/code] reason to that first candidate.
## - **A boost** ([member BustleScoreContext.score_boost]) multiplies a candidate's score last. It
##   must be finite and not negative; it never changes the candidate's band.
## - **Eligible** means the preconditions pass, the numbers are finite, and the raw score is above
##   zero and at least the goal's [member BustleGoalDef.min_score].
## - **Choosing:** only the highest band with an eligible candidate counts. Within it, every
##   candidate whose selection score is within [member BustleScoringConfig.pick_window] of the best
##   is in the window, and one is picked uniformly with the given random generator (no draw when
##   only one is). With nothing eligible, the IDLE fallback is returned.
## @experimental

## How far below the window's edge still counts as inside it.
const EPSILON := 1e-9
## How much worse the side-effect pressure is taken to be.
const SIDE_EFFECT_STEP := 0.2


## Every candidate for [param library] in [param context], in a stable order: band (highest first),
## selection score (highest first), then goal id and option id.
## @experimental
func evaluate(library: BustleGoalLibrary, context: BustleScoreContext, config: BustleScoringConfig) -> Array[BustleCandidate]:
	var out: Array[BustleCandidate] = []
	var seen := {}
	for goal: BustleGoalDef in library.goals:
		if goal == null or goal.id == &"" or seen.has(goal.id):
			continue
		seen[goal.id] = true
		if not goal.uses_advertisements:
			out.append(_candidate(goal, &"", context, config, null))
			continue
		var options := {}
		for ad: BustleAdvertisement in context.advertisements:
			if ad == null:
				continue
			if options.has(ad.option_id):
				(options[ad.option_id] as BustleCandidate).reasons.append({"kind": &"duplicate_option", "option": ad.option_id})
				continue
			var candidate := _candidate(goal, ad.option_id, context, config, ad)
			options[ad.option_id] = candidate
			out.append(candidate)
	sort(out)
	return out


## Sorts [param candidates] in place into the stable order [method evaluate] uses.
## @experimental
static func sort(candidates: Array[BustleCandidate]) -> void:
	candidates.sort_custom(func(a: BustleCandidate, b: BustleCandidate) -> bool:
		if a.band != b.band:
			return a.band > b.band
		if a.selection_score != b.selection_score:
			return a.selection_score > b.selection_score
		if a.goal_id != b.goal_id:
			return String(a.goal_id) < String(b.goal_id)
		return String(a.option_id) < String(b.option_id))


## The eligible candidates of the highest band that has any, in stable order. Empty when none is
## eligible.
## @experimental
static func top_band(candidates: Array[BustleCandidate]) -> Array[BustleCandidate]:
	var best_band := -1
	var out: Array[BustleCandidate] = []
	for candidate: BustleCandidate in candidates:
		if candidate.eligible and candidate.band > best_band:
			best_band = candidate.band
	for candidate: BustleCandidate in candidates:
		if candidate.eligible and candidate.band == best_band:
			out.append(candidate)
	sort(out)
	return out


## The candidates of [param band_candidates] (one band, eligible, sorted) whose selection score is
## within [param window] of the best.
## @experimental
static func pick_window(band_candidates: Array[BustleCandidate], window: float) -> Array[BustleCandidate]:
	var out: Array[BustleCandidate] = []
	if band_candidates.is_empty():
		return out
	var best := band_candidates[0].selection_score
	var cutoff := best * (1.0 - clampf(window, 0.0, 1.0))
	for candidate: BustleCandidate in band_candidates:
		if candidate.selection_score >= cutoff - EPSILON:
			out.append(candidate)
	return out


## Picks from [param candidates]: the highest eligible band, its window, then one uniformly with
## [param rng]. The IDLE fallback when nothing is eligible.
## @experimental
func choose(candidates: Array[BustleCandidate], config: BustleScoringConfig, rng: RandomNumberGenerator) -> BustleCandidate:
	var window := pick_window(top_band(candidates), config.pick_window)
	if window.is_empty():
		return BustleCandidate.idle_fallback()
	if window.size() == 1:
		return window[0]
	return window[rng.randi_range(0, window.size() - 1)]


## The advertisement score of [param ad] for the agent in [param context], with its reasons
## appended to [param reasons]. NAN when a number in it isn't finite.
## @experimental
func advertisement_score(ad: BustleAdvertisement, context: BustleScoreContext, config: BustleScoringConfig,
		reasons: Array[Dictionary] = []) -> float:
	var need_value := 0.0
	var needs: Array[StringName] = []
	for need: StringName in ad.relief:
		needs.append(need)
	for need: StringName in ad.adds:
		if not needs.has(need):
			needs.append(need)
	needs.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for need: StringName in needs:
		var key := StringName("need." + String(need))
		if not BustleInputs.is_valid_input(key):
			reasons.append({"kind": &"invalid_input", "input": key})
			return NAN
		if not context.inputs.has(key):
			reasons.append({"kind": &"no_need", "need": need})
			continue
		var pressure: float = context.inputs[key]
		var weight: float = context.need_weights.get(need, 1.0)
		var relief: float = ad.relief.get(need, 0.0)
		var adds: float = ad.adds.get(need, 0.0)
		if not (is_finite(pressure) and is_finite(weight) and is_finite(relief) and is_finite(adds)):
			reasons.append({"kind": &"not_finite", "what": key})
			return NAN
		var term := relief * _need_curve(config, need, pressure) * weight \
				- adds * _need_curve(config, need, pressure + SIDE_EFFECT_STEP) * weight
		reasons.append({"kind": &"need", "need": need, "value": term})
		need_value += term
	var factor := 1.0
	var tags := ad.tags.duplicate()
	tags.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for tag: StringName in tags:
		var mult := float(context.tag_mults.get(tag, 1.0))
		if not is_finite(mult):
			reasons.append({"kind": &"not_finite", "what": StringName("tag." + String(tag))})
			return NAN
		factor *= mult
	if not is_finite(ad.distance):
		reasons.append({"kind": &"not_finite", "what": &"distance"})
		return NAN
	var distance := config.distance_curve.sample(ad.distance) if config.distance_curve != null else 1.0
	var mood := 1.0
	if context.inputs.has(BustleInputs.MOOD):
		var mood_input: float = context.inputs[BustleInputs.MOOD]
		for tag: StringName in tags:
			var curve: Curve = config.mood_curves.get(tag, null)
			if curve == null:
				continue
			if not is_finite(mood_input):
				reasons.append({"kind": &"not_finite", "what": BustleInputs.MOOD})
				return NAN
			mood *= curve.sample(mood_input)
	var preview := 1.0
	if config.expected_thought_gain.is_valid():
		preview = float(config.expected_thought_gain.call(ad, context))
	if not (is_finite(need_value) and is_finite(distance) and is_finite(mood) and is_finite(preview)):
		reasons.append({"kind": &"not_finite", "what": &"factors"})
		return NAN
	reasons.append({"kind": &"factors", "tags": factor, "distance": distance, "mood": mood, "preview": preview})
	var score := need_value * factor * distance * mood * preview
	return score if is_finite(score) else NAN


func _candidate(goal: BustleGoalDef, option_id: StringName, context: BustleScoreContext,
		config: BustleScoringConfig, ad: BustleAdvertisement) -> BustleCandidate:
	var out := BustleCandidate.new()
	out.goal_id = goal.id
	out.option_id = option_id
	out.band = goal.band
	var ok := _preconditions_pass(goal, context, out.reasons)
	var score := goal.base_weight
	for consideration: BustleConsideration in goal.considerations:
		var value := _consider(consideration, context, out.reasons)
		if is_nan(value):
			ok = false
			score = 0.0
			break
		score *= value
	if ok and ad != null:
		var ad_score := advertisement_score(ad, context, config, out.reasons)
		if is_nan(ad_score):
			out.reasons.append({"kind": &"not_finite", "what": &"advertisement"})
			ok = false
			score = 0.0
		else:
			score *= ad_score
	if ok and context.score_boost.is_valid():
		var boost: Variant = context.score_boost.call(goal.id, option_id)
		if (boost is float or boost is int) and is_finite(float(boost)) and float(boost) >= 0.0:
			score *= float(boost)
		else:
			out.reasons.append({"kind": &"not_finite", "what": &"boost"})
			ok = false
			score = 0.0
	if not is_finite(score):
		out.reasons.append({"kind": &"not_finite", "what": &"score"})
		ok = false
		score = 0.0
	out.raw_score = score
	out.selection_score = score
	out.eligible = ok and score > 0.0 and score >= goal.min_score
	if ok and not out.eligible:
		out.reasons.append({"kind": &"below_minimum" if score > 0.0 else &"not_positive", "score": score})
	return out


# NAN (with its reason) when the consideration can't be used.
func _consider(consideration: BustleConsideration, context: BustleScoreContext, reasons: Array[Dictionary]) -> float:
	if consideration == null or consideration.curve == null:
		reasons.append({"kind": &"no_curve"})
		return NAN
	var key := consideration.input
	if not BustleInputs.is_valid_input(key):
		reasons.append({"kind": &"invalid_input", "input": key})
		return NAN
	if not context.inputs.has(key):
		reasons.append({"kind": &"missing_input", "input": key})
		return NAN
	var x: float = context.inputs[key]
	if not is_finite(x):
		reasons.append({"kind": &"not_finite", "what": key})
		return NAN
	var y := consideration.curve.sample(x)
	if not is_finite(y):
		reasons.append({"kind": &"not_finite", "what": key})
		return NAN
	reasons.append({"kind": &"consideration", "input": key, "x": x, "value": y})
	return y


func _preconditions_pass(goal: BustleGoalDef, context: BustleScoreContext, reasons: Array[Dictionary]) -> bool:
	for precondition: Dictionary in goal.preconditions:
		var kind := StringName(str(precondition.get("kind", "")))
		var passed := false
		if kind == &"input":
			var key := StringName(str(precondition.get("input", "")))
			if not BustleInputs.is_valid_input(key):
				reasons.append({"kind": &"invalid_input", "input": key})
				return false
			if context.inputs.has(key) and not is_finite(context.inputs[key]):
				reasons.append({"kind": &"not_finite", "what": key})
				return false
			passed = float(context.inputs.get(key, 0.0)) > 0.0
		elif context.precondition_check.is_valid():
			passed = bool(context.precondition_check.call(goal.id, precondition))
		if not passed:
			reasons.append({"kind": &"precondition_failed", "precondition": precondition})
			return false
	return true


func _need_curve(config: BustleScoringConfig, need: StringName, pressure: float) -> float:
	var curve: Curve = config.need_curves.get(need, null)
	return curve.sample(pressure) if curve != null else clampf(pressure, 0.0, 1.0)
