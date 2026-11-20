# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleCareerPeriod
extends Resource

## How a rank is reviewed in one host-defined period, as data: a full set of review rules that
## replaces the rank's own while a review window is judged in that period (see
## [member BustleCareerRank.periods] and [method BustleCareers.update_in_period]). Bustle defines
## no periods and assumes no calendar: a period is any id the host chooses, such as a season, a
## busy month or a quiet spell.
## @experimental: Added after 1.0; it may be frozen in a later minor release.

## Working days (days with a career block) in each review window in this period.
@export var review_days: int = 7
## A window's performance (0 to 1) at or above this makes a promotion due in this period.
@export var promote_if: float = 0.75
## A window's performance at or below this makes a demotion due in this period.
@export var demote_if: float = 0.35


## True when it can be used, by the same rules as a rank's own: a review window of at least one
## day, and finite thresholds with [member demote_if] below [member promote_if].
func is_valid() -> bool:
	return review_days >= 1 and is_finite(promote_if) and is_finite(demote_if) and demote_if < promote_if
