# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleCareerDef
extends Resource

## A career track, as data: the ranks of one standing job. A career is the job itself, held as a
## role with a routine ([BustleRoleSchedules]); the track adds ranks, a wage per rank and a skill
## minimum per rank. Its career block is the routine's block for [member activity]: the agent works
## it off site when [member off_site] is set. Bustle ships none; the host supplies every track.
## @experimental

## Its id, chosen by the host.
@export var id: StringName = &""
## The standing role the track ranks. Only its holder can be on the track.
@export var role: StringName = &""
## The skill its ranks ask for, or empty for none.
@export var skill: StringName = &""
## The routine activity that is the career block (for example [code]work[/code]).
@export var activity: StringName = &""
## True: the agent is off site, out of the world, while it attends the career block.
@export var off_site: bool = true
## The ranks, lowest first.
@export var ranks: Array[BustleCareerRank] = []


## True when it can be used: an id, a role and an activity; at least one rank, every rank valid with
## a unique id; and a skill whenever a rank asks for one.
## @experimental
func is_valid() -> bool:
	if id == &"" or role == &"" or activity == &"" or ranks.is_empty():
		return false
	var seen: Array[StringName] = []
	for rank: BustleCareerRank in ranks:
		if rank == null or not rank.is_valid() or seen.has(rank.id) or (rank.min_skill > 0.0 and skill == &""):
			return false
		seen.append(rank.id)
	return true


## The index of rank [param rank_id], or -1.
## @experimental
func rank_index(rank_id: StringName) -> int:
	for i: int in ranks.size():
		if ranks[i].id == rank_id:
			return i
	return -1
