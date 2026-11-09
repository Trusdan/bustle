# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleRelationshipRules
extends Resource

## When repeated deeds make one agent count another a friend or a rival, as data. A kind forms
## when the opinion reaches its level and enough deeds of the right sign (opinion entries with a
## deed in their reason) fall inside the window; it lapses only once the opinion crosses back past
## its release level, so it doesn't flicker. These are starting numbers, not tuning.
## @experimental

## The kind repeated kindness forms.
@export var friend_kind: StringName = &"friend"
## The opinion at or above which a friend forms.
@export var friend_at: float = 75.0
## Below this opinion a friend lapses.
@export var friend_release: float = 55.0
## The kind repeated harm forms.
@export var rival_kind: StringName = &"rival"
## The opinion at or below which a rival forms.
@export var rival_at: float = 25.0
## Above this opinion a rival lapses.
@export var rival_release: float = 45.0
## How many deeds of the right sign are needed.
@export var min_deeds: int = 3
## Game days the deeds must fall within.
@export var window_days: float = 14.0
