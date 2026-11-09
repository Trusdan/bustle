# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
class_name BustleCompatibility
extends RefCounted

## How well two agents get on by nature, from -1 (they grate) to 1 (they click). It is fixed for a
## pair in a world: the same for the same two ids and world seed, the same both ways round, and
## different in another world. It comes from a 64-bit FNV-1a hash of the seed and the two ids in
## sorted order. A host may blend in how close the two agents' personality sliders are.
## @experimental


## The compatibility of [param a] and [param b] in a world seeded [param world_seed]. With
## [param a_personality] and [param b_personality] given and [param slider_weight] above 0, that
## share comes from how close their sliders are (1 when equal, -1 when opposite), the rest from the
## hash. 0 for an empty id or an agent paired with itself.
## @experimental
static func of(a: StringName, b: StringName, world_seed: int, a_personality: BustlePersonality = null,
		b_personality: BustlePersonality = null, slider_weight: float = 0.0) -> float:
	if a == &"" or b == &"" or a == b:
		return 0.0
	var first := a if String(a) < String(b) else b
	var second := b if first == a else a
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_s64(0, world_seed)
	bytes.append_array(("%s|%s" % [first, second]).to_utf8_buffer())
	var h := -3750763034362895579 # 0xcbf29ce484222325 as a signed 64-bit int
	for byte: int in bytes:
		h = (h ^ byte) * 1099511628211
	# The top 53 bits as a fraction in [0, 1), then onto [-1, 1].
	var unit := float((h >> 11) & ((1 << 53) - 1)) / float(1 << 53)
	var hashed := unit * 2.0 - 1.0
	var weight := clampf(slider_weight, 0.0, 1.0) if is_finite(slider_weight) else 0.0
	if weight <= 0.0 or a_personality == null or b_personality == null:
		return hashed
	var gap := 0.0
	for slider: StringName in BustlePersonality.SLIDERS:
		gap += absf(a_personality.slider(slider) - b_personality.slider(slider)) / 100.0
	var closeness := 1.0 - 2.0 * gap / float(BustlePersonality.SLIDERS.size())
	return clampf(hashed * (1.0 - weight) + closeness * weight, -1.0, 1.0)
