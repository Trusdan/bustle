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
## [br][br]
## [b]With a brain.[/b] [method advertise] offers an agent's postings to its brain as options, so a
## job goal weighs them against its other goals. The board only ranks: it never leaves out work an
## agent dislikes, it just makes that work less appealing. When a brain picks a posting, the host
## calls [method request]; [method settle], at the end of the tick, gives each requested posting to
## the highest score, ties going to the lower agent id. [method work] then adds the work done, with
## practice through the skill port, and completes the posting once its type's minutes are done,
## paying the wage through the trade port.
## @experimental

## Every board change: [param job] was posted, claimed, released, completed, cancelled or expired,
## or its wage was paid or couldn't be ([param what]); [param agent] is the claimant, if any.
signal changed(job: StringName, what: StringName, agent: StringName)

## The tag on every job advertisement.
const TAG := &"job"
## The need a job advertisement relieves (see [method advertise]).
const NEED := &"job"

## The ports it reads: [code]roles[/code] and [code]skills[/code] for the gates, [code]skills[/code]
## for practice and [code]trade[/code] for wages. Null (or a null port): no roles are held, every
## skill is 0, nothing is practised and no wage is paid.
var ports: BustlePorts
## The appeal of a posting an agent scores 0 for (see [method appeal]). An experimental default.
var appeal_base: float = 0.5

var _types: Dictionary[StringName, BustleWorkType] = {}
var _postings: Dictionary[StringName, BustleJobPosting] = {}
var _next: int = 1
## Agent id → the posting it holds, kept in step with the postings.
var _claims: Dictionary[StringName, StringName] = {}
## Agent id → [seeker, posting] it asked for this tick (see [method request]).
var _requests: Dictionary[StringName, Array] = {}


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
	return _claims.get(agent, &"")


## True when [param seeker] passes [param job]'s gates: it holds the required role, has at least
## the minimum skill level, and has every required tag. Says nothing about whether the posting is
## open.
## @experimental
func can_do(seeker: BustleJobSeeker, job: StringName) -> bool:
	var posting: BustleJobPosting = _postings.get(job)
	if posting == null or seeker == null or seeker.id == &"":
		return false
	var def: BustleWorkType = _types[posting.type]
	var roles: BustleRolesPort = ports.roles if ports != null else null
	if def.required_role != &"" and (roles == null or not roles.roles_of(seeker.id).has(String(def.required_role))):
		return false
	var skills: BustleSkillSet = ports.skills if ports != null else null
	if def.min_skill > 0.0 and (skills == null or skills.level(seeker.id, def.skill) < def.min_skill):
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
	_claims[seeker.id] = job
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
	_claims.erase(agent)
	changed.emit(job, &"released", agent)
	return true


## Marks [param job] done by its claimant, takes it off the board and pays its type's wage from the
## employer to the claimant through the trade port, once. A wage the employer can't pay (or with no
## trade port) is not paid, and [signal changed] says [code]unpaid[/code]. False (and no change) when
## it isn't claimed.
## @experimental
func complete(job: StringName) -> bool:
	var posting: BustleJobPosting = _postings.get(job)
	if posting == null or posting.is_open():
		return false
	_remove(job)
	changed.emit(job, &"completed", posting.claimed_by)
	var wage := _types[posting.type].wage
	if wage > 0:
		var trade: BustleTradePort = ports.trade if ports != null else null
		var paid := trade != null and trade.pay(posting.employer, posting.claimed_by, wage)
		changed.emit(job, &"paid" if paid else &"unpaid", posting.claimed_by)
	return true


## Adds [param minutes] of work by [param seeker] on the posting it holds. Practice goes to the skill port when it can take it ([code]add_xp(id, skill, xp,
## personality)[/code], as the skills module does): [member BustleWorkType.xp_per_hour] for each
## hour. Once the work done reaches the type's minutes, the posting is completed
## ([method complete]). False (and no change) when the seeker holds no claim or
## [param minutes] isn't positive.
## @experimental
func work(seeker: BustleJobSeeker, minutes: int) -> bool:
	var job := claimed_of(seeker.id) if seeker != null else &""
	if job == &"" or minutes <= 0:
		return false
	var posting: BustleJobPosting = _postings[job]
	var def: BustleWorkType = _types[posting.type]
	var done := mini(minutes, def.minutes - posting.progress)
	posting.progress += done
	var skills: BustleSkillSet = ports.skills if ports != null else null
	if def.skill != &"" and def.xp_per_hour > 0.0 and skills != null and skills.has_method(&"add_xp"):
		skills.call(&"add_xp", seeker.id, def.skill, def.xp_per_hour * done / 60.0, seeker.personality)
	if posting.progress >= def.minutes:
		complete(job)
	return true


## How appealing [param job] is to [param seeker], from 0 to 1: [member appeal_base] plus its
## [method score], clamped. It is never left out: a posting the seeker dislikes appeals 0, so its
## brain picks something else.
## @experimental
func appeal(seeker: BustleJobSeeker, job: StringName) -> float:
	return clampf(appeal_base + score(seeker, job), 0.0, 1.0)


## Adds to [param senses] an advertisement for each posting [param seeker] can claim, or only for
## the one it holds. Each relieves the need [constant NEED] by its [method appeal], carries the tag
## [constant TAG], and has the posting id as its option; the input [code]need.job[/code] is set to
## 1. A host gives these options to its job goal only (as with other agents for people goals).
## Returns how many it added.
## @experimental
func advertise(seeker: BustleJobSeeker, senses: BustleSenses) -> int:
	if seeker == null or senses == null:
		return 0
	var held := claimed_of(seeker.id)
	var jobs: Array[StringName] = job_ids(true)
	if held != &"":
		jobs = [held]
	var added := 0
	for job: StringName in jobs:
		if job != held and not eligible(seeker, job):
			continue
		var relief: Dictionary[StringName, float] = {NEED: appeal(seeker, job)}
		senses.advertisements.append(BustleAdvertisement.new(job, relief, {}, [TAG] as Array[StringName]))
		added += 1
	if added > 0:
		senses.inputs[StringName("need." + String(NEED))] = 1.0
	return added


## Asks for [param job] on behalf of [param seeker], whose brain picked it this tick. The claim is
## decided by [method settle]. A later request from the same seeker in the tick replaces it.
## @experimental
func request(seeker: BustleJobSeeker, job: StringName) -> void:
	if seeker != null and seeker.id != &"" and _postings.has(job):
		_requests[seeker.id] = [seeker, job]


## Decides this tick's [method request]s at game minute [param now]: each requested posting goes to
## the requester with the highest score, ties going to the lower agent id, if it can still claim
## it. The others keep no claim and choose again next tick. Returns agent id → the posting it
## claimed.
## @experimental
func settle(now: int) -> Dictionary[StringName, StringName]:
	var winners: Dictionary[StringName, BustleJobSeeker] = {}
	for id: StringName in _sorted(_requests.keys()):
		var seeker: BustleJobSeeker = _requests[id][0]
		var job: StringName = _requests[id][1]
		if not eligible(seeker, job):
			continue
		var rival: BustleJobSeeker = winners.get(job)
		# Requests are taken in agent id order, so on a tie the earlier one stays.
		if rival == null or score(seeker, job) > score(rival, job):
			winners[job] = seeker
	_requests.clear()
	var out: Dictionary[StringName, StringName] = {}
	for job: StringName in _sorted(winners.keys()):
		if claim(winners[job], job, now):
			out[winners[job].id] = job
	return out


## Takes [param job] off the board unfinished (its employer withdrew it). False for an unknown job.
## @experimental
func cancel(job: StringName) -> bool:
	var posting: BustleJobPosting = _postings.get(job)
	if posting == null:
		return false
	_remove(job)
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
			_remove(job)
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
## has times before the posting opened or negative progress, or has a [code]next[/code] that could
## repeat an id.
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
	_claims.clear()
	_requests.clear()
	for job: StringName in _postings:
		if not _postings[job].is_open():
			_claims[_postings[job].claimed_by] = job
	return true


func _remove(job: StringName) -> void:
	var posting: BustleJobPosting = _postings[job]
	_claims.erase(posting.claimed_by)
	_postings.erase(job)


static func _posting_from(row: Variant) -> BustleJobPosting:
	if not row is Dictionary:
		return null
	for key: String in ["id", "type", "employer", "place", "claimed_by"]:
		if not row.get(key) is String:
			return null
	for key: String in ["opened", "due", "claimed_at", "progress"]:
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
	posting.progress = int(row["progress"])
	if posting.id == &"" or posting.due < -1 or (posting.is_open() != (posting.claimed_at == -1)):
		return null
	if (posting.due >= 0 and posting.due < posting.opened) or (posting.claimed_at >= 0 and posting.claimed_at < posting.opened):
		return null
	if posting.progress < 0:
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
