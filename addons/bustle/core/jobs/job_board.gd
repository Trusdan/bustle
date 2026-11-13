# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleJobBoard
extends RefCounted

## A board of posted, one-off work that agents claim. An employer posts a [BustleWorkType]; an
## agent that passes its gates (role, skill level, tags) can claim it; the claim is exclusive and
## lasts until the work is completed, released, cancelled or expired. Standing jobs stay roles and
## schedules: the board doesn't touch them.
## [br][br]
## An agent takes the open posting it wants most ([method BustleWorkType.score]) among those it can
## do, ties going to the earlier posting id. When several agents want one posting at the same time,
## [method assign] gives it to the highest score, ties going to the lower agent id. Nothing is
## random: the same postings, agents and clock give the same claims. Install it as
## [code]society.ports.work.board[/code].
## @experimental

## Every board change: [param job] was posted, claimed, released, completed, cancelled or expired
## ([param what]); [param agent] is the claimant, if any.
signal changed(job: StringName, what: StringName, agent: StringName)

## The ports the gates read: [code]roles[/code] and [code]skills[/code]. Null: no roles are held and
## every skill is 0.
var ports: BustlePorts

var _types: Dictionary[StringName, BustleWorkType] = {}
var _postings: Dictionary[StringName, BustleJobPosting] = {}
var _next: int = 1


## Starts with [param types] (invalid or repeated ones are skipped with a warning), reading gates
## from [param p_ports].
func _init(types: Array[BustleWorkType] = [], p_ports: BustlePorts = null) -> void:
	ports = p_ports
	for def: BustleWorkType in types:
		if not add_type(def):
			push_warning("BustleJobBoard: skipped work type %s" % (def.id if def != null else &"<null>"))


## Adds [param def]. False (and no change) when it's null, invalid or its id is taken.
## @experimental
func add_type(def: BustleWorkType) -> bool:
	if def == null or not def.is_valid() or _types.has(def.id):
		return false
	_types[def.id] = def
	return true


## The work type [param id], or null.
## @experimental
func type_of(id: StringName) -> BustleWorkType:
	return _types.get(id)


## Posts work of type [param type] for [param employer] at game minute [param now], due at
## [param due] (-1: never), at [param place] (empty: the type's place). Returns the new posting's
## id, or empty (and no change) for an unknown type or a due time before [param now].
## @experimental
func post(type: StringName, employer: StringName, now: int, due: int = -1, place: StringName = &"") -> StringName:
	var def: BustleWorkType = _types.get(type)
	if def == null or (due >= 0 and due < now):
		return &""
	var posting := BustleJobPosting.new()
	posting.id = StringName("job_%d" % _next)
	_next += 1
	posting.type = type
	posting.employer = employer
	posting.place = place if place != &"" else def.place
	posting.opened = now
	posting.due = due
	_postings[posting.id] = posting
	changed.emit(posting.id, &"posted", &"")
	return posting.id


## The posting [param job], or null.
## @experimental
func posting(job: StringName) -> BustleJobPosting:
	return _postings.get(job)


## Every posting's id, in natural order ([code]job_2[/code] before [code]job_10[/code]). With [param open_only], only those nobody has claimed.
## @experimental
func job_ids(open_only: bool = false) -> Array[StringName]:
	var out: Array[StringName] = []
	for job: StringName in _postings:
		if not open_only or _postings[job].is_open():
			out.append(job)
	return _sorted(out)


## The posting [param agent] has claimed, or empty.
## @experimental
func claimed_of(agent: StringName) -> StringName:
	for job: StringName in job_ids():
		if _postings[job].claimed_by == agent and agent != &"":
			return job
	return &""


## True when [param seeker] passes [param job]'s gates: it holds the required role, has at least
## the minimum skill level, and has every required tag. Says nothing about whether the posting is
## open.
## @experimental
func can_do(seeker: BustleJobSeeker, job: StringName) -> bool:
	var posting: BustleJobPosting = _postings.get(job)
	if posting == null or seeker == null or seeker.id == &"":
		return false
	var def: BustleWorkType = _types[posting.type]
	if def.required_role != &"" and (ports == null or not ports.roles.roles_of(seeker.id).has(String(def.required_role))):
		return false
	if def.min_skill > 0.0 and (ports == null or ports.skills.level(seeker.id, def.skill) < def.min_skill):
		return false
	for tag: StringName in def.required_tags:
		if not seeker.tags.has(tag):
			return false
	return true


## True when [param seeker] could claim [param job] now: the posting is open, the seeker holds no
## other claim, and it passes the gates.
## @experimental
func eligible(seeker: BustleJobSeeker, job: StringName) -> bool:
	var posting: BustleJobPosting = _postings.get(job)
	return posting != null and posting.is_open() and seeker != null and claimed_of(seeker.id) == &"" \
			and can_do(seeker, job)


## How much [param seeker] wants [param job] ([method BustleWorkType.score]); 0 for an unknown job.
## @experimental
func score(seeker: BustleJobSeeker, job: StringName) -> float:
	var posting: BustleJobPosting = _postings.get(job)
	return _types[posting.type].score(seeker) if posting != null and seeker != null else 0.0


## The open posting [param seeker] is eligible for and wants most, ties going to the earlier
## posting id in [method job_ids] order. Empty when there is none, or it already holds a claim.
## @experimental
func best_for(seeker: BustleJobSeeker) -> StringName:
	var best := &""
	var best_score := -INF
	for job: StringName in job_ids(true):
		if eligible(seeker, job):
			var value := score(seeker, job)
			if value > best_score:
				best = job
				best_score = value
	return best


## Gives [param job] to [param seeker] at game minute [param now]. Atomic: false (and no change)
## when the posting is already claimed, the seeker already holds a claim, or it fails the gates.
## @experimental
func claim(seeker: BustleJobSeeker, job: StringName, now: int) -> bool:
	if not eligible(seeker, job):
		return false
	_postings[job].claimed_by = seeker.id
	_postings[job].claimed_at = now
	changed.emit(job, &"claimed", seeker.id)
	return true


## Claims for every seeker in [param seekers] at once, at game minute [param now], as when several
## pick work in the same tick. In rounds, each seeker without a claim picks [method best_for]; a
## posting picked by several goes to the highest score, ties going to the lower agent id; the
## others pick again from what's left next round. Returns agent id → the posting it claimed.
## @experimental
func assign(seekers: Array[BustleJobSeeker], now: int) -> Dictionary[StringName, StringName]:
	var out: Dictionary[StringName, StringName] = {}
	var waiting: Array[BustleJobSeeker] = []
	for seeker: BustleJobSeeker in seekers:
		if seeker != null and claimed_of(seeker.id) == &"":
			waiting.append(seeker)
	waiting.sort_custom(func(a: BustleJobSeeker, b: BustleJobSeeker) -> bool: return String(a.id) < String(b.id))
	while not waiting.is_empty():
		var winners: Dictionary[StringName, BustleJobSeeker] = {}
		for seeker: BustleJobSeeker in waiting:
			var job := best_for(seeker)
			if job == &"":
				continue
			var rival: BustleJobSeeker = winners.get(job)
			if rival == null or score(seeker, job) > score(rival, job):
				winners[job] = seeker
		if winners.is_empty():
			break
		for job: StringName in _sorted(winners.keys()):
			if claim(winners[job], job, now):
				out[winners[job].id] = job
		var left: Array[BustleJobSeeker] = []
		for seeker: BustleJobSeeker in waiting:
			if not out.has(seeker.id):
				left.append(seeker)
		waiting = left
	return out


## Lets go of the claim on [param job], so it's open again. False when it isn't claimed.
## @experimental
func release(job: StringName) -> bool:
	var posting: BustleJobPosting = _postings.get(job)
	if posting == null or posting.is_open():
		return false
	var agent := posting.claimed_by
	posting.claimed_by = &""
	posting.claimed_at = -1
	changed.emit(job, &"released", agent)
	return true


## Marks [param job] done by its claimant and takes it off the board. False (and no change) when it
## isn't claimed.
## @experimental
func complete(job: StringName) -> bool:
	var posting: BustleJobPosting = _postings.get(job)
	if posting == null or posting.is_open():
		return false
	_postings.erase(job)
	changed.emit(job, &"completed", posting.claimed_by)
	return true


## Takes [param job] off the board unfinished (its employer withdrew it). False for an unknown job.
## @experimental
func cancel(job: StringName) -> bool:
	var posting: BustleJobPosting = _postings.get(job)
	if posting == null:
		return false
	_postings.erase(job)
	changed.emit(job, &"cancelled", posting.claimed_by)
	return true


## Takes every posting due at or before [param now] off the board, claimed or not, and returns
## their ids, in [method job_ids] order.
## @experimental
func expire(now: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for job: StringName in job_ids():
		var posting: BustleJobPosting = _postings[job]
		if posting.due >= 0 and posting.due <= now:
			_postings.erase(job)
			out.append(job)
			changed.emit(job, &"expired", posting.claimed_by)
	return out


## Every posting, open and claimed, as plain data: [code]{"next": n, "postings": [...]}[/code].
## @experimental
func export_state() -> Dictionary:
	var rows: Array = []
	for job: StringName in job_ids():
		rows.append(_postings[job].to_dict())
	return {"next": _next, "postings": rows}


## Restores [method export_state], replacing every posting. False (and nothing changes) when the
## data is malformed, names an unknown work type, repeats a posting id, gives one agent two claims,
## or has a [code]next[/code] that could repeat an id.
## @experimental
func import_state(saved: Variant) -> bool:
	if not saved is Dictionary or not _is_int(saved.get("next")) or not saved.get("postings") is Array:
		return false
	var next := int(saved["next"])
	var restored: Dictionary[StringName, BustleJobPosting] = {}
	var claimants: Dictionary[StringName, bool] = {}
	for row: Variant in saved["postings"]:
		var posting := _posting_from(row)
		if posting == null or restored.has(posting.id) or not _types.has(posting.type):
			return false
		if not posting.is_open():
			if claimants.has(posting.claimed_by):
				return false
			claimants[posting.claimed_by] = true
		var number := String(posting.id).trim_prefix("job_")
		if number.is_valid_int() and int(number) >= next:
			return false
		restored[posting.id] = posting
	if next < 1:
		return false
	_postings = restored
	_next = next
	return true


static func _posting_from(row: Variant) -> BustleJobPosting:
	if not row is Dictionary:
		return null
	for key: String in ["id", "type", "employer", "place", "claimed_by"]:
		if not row.get(key) is String:
			return null
	for key: String in ["opened", "due", "claimed_at"]:
		if not _is_int(row.get(key)):
			return null
	var posting := BustleJobPosting.new()
	posting.id = StringName(row["id"])
	posting.type = StringName(row["type"])
	posting.employer = StringName(row["employer"])
	posting.place = StringName(row["place"])
	posting.opened = int(row["opened"])
	posting.due = int(row["due"])
	posting.claimed_by = StringName(row["claimed_by"])
	posting.claimed_at = int(row["claimed_at"])
	if posting.id == &"" or posting.due < -1 or (posting.is_open() != (posting.claimed_at == -1)):
		return null
	return posting


# Whole numbers, including those JSON turns into floats.
static func _is_int(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floorf(value))


static func _sorted(ids: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(ids)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a).naturalcasecmp_to(String(b)) < 0)
	return out
