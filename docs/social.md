# Social store

`BustleSocialStore` (`addons/bustle/society/`) is Bustle's built-in social store. It's a `BustleSocialPort` that keeps opinions with reasons and relationship kinds, for hosts that don't have a social engine of their own.

To use it, give it to the society's ports: `society.set_port(&"social", BustleSocialStore.new())`.

Deeds work exactly as in the port's default:

- The actor and the named witnesses know a deed first-hand.
- `share_news` passes on first-hand deeds only, and only one hop.

## Opinions

An opinion is one-way: how `a` regards `b`, from 0 to 100. It's 50 plus every live opinion entry, clamped to that range.

- `add_opinion(a, b, value, reason, days)` adds an entry.
  - The entry lasts `days` game days from the store's minute.
  - `reason` is plain data. When a deed caused the entry, put the deed's key under `deed`.
- `set_time(now)` moves the store's clock forward. Ended entries go, and every pair's kinds are checked again.
- `reasons(a, b, count)` returns the live entries, strongest first, with their reasons.

## Relationship kinds

Kinds are one-way too: `a` counts `b` a friend. `kinds_between(a, b)` returns them sorted.

**Kinds a host sets** with `set_kind` (kin, for example) stay until `clear_kind` removes them. Both are on `BustleSocialPort`, so modules such as romance (`docs/romance.md`) write kinds through whichever port is installed. `supports_kinds()` says whether a port keeps them; the default keeps none.

**Kinds formed from deeds** come and go with opinion, by `BustleRelationshipRules`. Every number below is a starting default, not tuning:

| | Forms when | Lapses when |
| --- | --- | --- |
| Friend | opinion is 75 or more, with at least 3 positive deed entries within 14 days | opinion falls below 55 |
| Rival | opinion is 25 or less, with at least 3 negative deed entries within 14 days | opinion rises above 45 |

A deed entry is an opinion entry whose reason has a `deed`. The gap between forming and lapsing means a kind doesn't flicker. `kind_changed(a, b, kind, formed)` fires each time a kind forms or lapses.

The rules never add or remove a host's kinds, and `clear_kind` never removes the rules' kinds.

## Compatibility

`BustleCompatibility.of(a, b, world_seed)` says how well two agents get on by nature, from -1 to 1.

- It's fixed for a pair in a world: the same every time, and the same both ways round.
- It differs between worlds and between pairs. It's a hash of the world seed and the two ids.
- It can blend in how close the two agents' personality sliders are: pass both personalities and a weight from 0 to 1. The default weight is 0, which uses the hash alone.

## Interactions and greeting

A `BustleInteractionDef` (a Resource) describes one kind of interaction, such as a greeting, a chat, kind words, a slight or an insult:

| Field | Meaning |
| --- | --- |
| `recipient_value` | How much the recipient's opinion of the initiator moves. |
| `initiator_value` | How much the initiator's opinion of the recipient moves. |
| `spread` | A random amount added or taken away, seeded per pair, minute and interaction. |
| `compatibility_scale` | How much compatibility bends each value, like mood: a compatible pair gains more and loses less, and an incompatible pair the reverse. A gain is multiplied by `1 + compatibility × scale` and a loss by `1 − compatibility × scale`, never below 0. |
| `mood_scale` | How much each side's own mood bends its value. A good mood makes gains larger and losses smaller; a low mood does the reverse. |
| `days` | How long the opinion entries last. |
| `recipient_thought`, `initiator_thought` | Optional thoughts from the mood module, one for each side. |
| `tags` | Tags for the interaction. A conversation picks `curt` ones more often in a low mood. |
| `weight` | How often a conversation picks it (default 1). 0 means only as a conversation's opener. |
| `slider_weights` | Personality slider → how strongly it bends `weight`: × `1 + w × (slider − 50) / 50`, never below 0. |

`BustleSocialInteractions` runs interactions through a social port. Give it the society's (`BustleSocialInteractions.new(society.ports.social, world_seed)`), so interactions land wherever that port keeps them. With no port it makes its own `BustleSocialStore`.

- **`outcome(...)`** is the one pure function every interaction goes through. It records nothing and gives the same result for the same pair, minute, interaction, world seed, compatibility and moods. Visible and abstract conversations both use it.
- **`interact(def, initiator, recipient, now, place, witnesses)`** works out the outcome and records it:
  - a deed through the port's `record_deed`, whose verb is the interaction's id. Its `magnitude` is `to_recipient` and its `return_magnitude` is `to_initiator`;
  - when the port is a `BustleSocialStore`, opinion entries whose reason names that deed: `{deed, interaction, by}` for the recipient and `{deed, interaction, with}` for the initiator. Any other port weighs the deed itself; the Wyrd bridge, for example, uses its magnitude (see `docs/wyrd-bridge.md`);
  - each side's thought, when `mood_of` gives a mood.

  So, on the store, repeated kind interactions form friends by the rules above. Greetings count too: each friendly greeting is a positive deed entry, though a friend still needs the opinion level.
- **`greet(initiator, recipient, now)`** runs `greeting` as an interaction, with two cooldowns. `export_state` and `import_state` save the cooldowns that are still running. They aren't part of the port's or the society's export, so a host saves them alongside. On a port other than the store, the cooldowns still running are those at the latest minute an interaction was recorded.

  | Cooldown | Default | What it stops |
  | --- | --- | --- |
  | Per pair (either way round) | 120 minutes | the same two agents greeting again |
  | Per greeter | 10 minutes | one agent greeting everyone at once |

## Conversations

A `BustleConversation` is a few turns (default 4) between two agents, a turn a minute by default. The initiator speaks first, then the two take turns. Each turn picks one interaction from `interactions` by weight and records it through `BustleSocialInteractions.interact`.

It runs two ways with the same results:

- **Abstract:** `run(initiator, recipient, now, opener, place)` does the whole conversation in one call, for agents nobody is watching.
- **Visible:** the `converse` action (`BustleConverseAction`, registered on a sequence runner) does one turn per tick, for agents in view. The partner is `params.with`, or the step's option id when that's empty. `params.opener` names the first turn's interaction. While it runs, the output names the partner as `talk_to`, and each turn's result is in it as `turn`.

Both go through `begin` and `step`. The conversation's state is plain data, so it saves with the runner. Every choice is seeded by the world seed, the pair, the start minute and the turn number, never by when a tick happens. A turn takes place on the first tick at or after its minute, and is recorded at its own minute.

An interaction's weight for the speaker is its `weight`, bent in this order by:

1. the speaker's sliders (`slider_weights`, through `personality_of`);
2. the speaker's modifiers: `conversation.<id>.weight` (through `modifiers_of`), which traits set with `adds` and `mults`;
3. the speaker's opinion of the listener: positive interactions × `1 + opinion_weight × (opinion − 50) / 50`, negative ones × `1 − ...`, never below 0;
4. the speaker's mood: below 50, `curt` interactions × `1 + curt_mood_scale × (50 − mood) / 50`.

A low mood also lowers the chance of starting: `start_chance × (1 − start_mood_scale × (50 − mood) / 50)` below 50. A good mood raises opinion gains through each interaction's `mood_scale`.

| Setting | Default |
| --- | --- |
| `turns` | 4 |
| `turn_minutes` | 1 |
| `start_chance` | 1 |
| `start_mood_scale` | 0.5 (mood 0 halves the chance) |
| `curt_mood_scale` | 1 (mood 0 doubles curt weights) |
| `opinion_weight` | 1 |

`accepts(recipient, initiator, opener)`, when set, lets the recipient turn a start away (for example `BustleMentalBehaviour.accepts` while it's withdrawn). `run` returns `turned_away` then, and `declined` when the roll to start fails. The `converse` action fails with `turned_away`, `declined`, `no_partner` or `nothing_to_say` (no interaction has any weight).

`demo/social/` holds a neutral interaction set: chitchat, deep talk, kind words, slight, insult (both `curt`) and comfort (weight 0, an opener only), plus a `comfort` goal.

## Comfort

`BustleComfort.advertise(agent, noticed, social, mood_of, senses)` is the comfort hook. For each agent in `noticed` that the agent counts as a friend (`kinds`, default `friend`, one-way) and whose mood is below `low_mood` (default 30), it adds an advertisement to the agent's senses:

- the option id is the friend;
- it relieves the need `comfort`, more the lower the friend's mood (`urgency`: 0 at `low_mood`, 1 at mood 0);
- its tags are `social` and `comfort`.

It also sets the `need.comfort` input to 1. The demo `comfort` goal uses these advertisements and runs a `converse` step with the comfort opener, so the agent comforts the friend it picked.

A friend in a low mental state counts too, even once its mood has started to rise. Set `low_state_of` (for example `BustleMentalBehaviour.in_low_state`), and such a friend is advertised with at least `low_state_urgency` (default 0.5). There's no second comfort system.

How much an agent cares is its need weight `need.comfort.weight`, which the brain reads from its modifiers for every advertised need. A trait raises or lowers it with `mults`. The hook doesn't need the mood module: a mood is anything with a `mood` number.

## Inspecting

`BustleSocialStore.deeds_of(agent, count)` lists an agent's deeds, newest first. `opinions_of(agent)` lists its opinions of others, with their kinds and reasons.

The inspector's snapshot has a `social` part that shows both. With a social port other than the store, that part is marked unavailable.

## Saving

`export_state` and `import_state` save and load opinions, both sets of kinds, deeds and the clock as plain data.

Import refuses malformed data and changes nothing when it does. Deed keys carry on after a load and are never reused.
