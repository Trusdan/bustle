# Ambitions

`addons/bustle/modules/ambitions/` gives each agent a long-term aim, one at a time: save money, get promoted, court someone, settle a feud, leave or (when a host turns it on) learn a trade. An ambition never acts on its own: it multiplies the scores of the short-term goals it names.

Everything follows from the agent's personality and circumstances. There's no chance, no limit shared between agents, and an ambition is never given up: it stays until it's achieved or can no longer happen.

## Using it

Make a `BustleAmbitions.new(agent_id, config)` for each agent with a profile; the player can have one too, or none. Then call `update(now, personality, inputs)` regularly. `inputs` holds the circumstances, progress inputs and facts the templates name, by name, for example `{"wallet": 1200.0, "has_role": true}`. The host fills them from its own systems (the trade port's wallet, the roles port, the social store).

`active()` returns the current ambition, `{id, since, progress}`, or an empty dictionary.

## Templates

`BustleAmbitionConfig.templates` holds `BustleAmbitionDef` resources:

- **`weights`:** slider → weight; the score is `Σ weight × (slider − 50) / 100`;
- **`min_sliders`:** the least each slider must be;
- **`requires`:** circumstances that must all be true;
- **`progress_input` and `target`:** the template is done once the input reaches the target and every `done_facts` fact is true;
- **`done_fact`:** a fact that completes it on its own (a host marking it done);
- **`moot_facts`:** facts that make it impossible for good;
- **`next`:** the template to take after completing it;
- **`boosts`:** goal id → score multiplier while it's active;
- **`target_input`:** the input naming the person it's about (only candidates whose option is that person are boosted);
- **`subject_input`** (experimental): the input naming what it's about when that isn't a person to single out, such as a skill. It's kept as `active()["target"]` for progress and saves, but boosts aren't narrowed to it;
- **`enabled`:** false means it's never assigned. A host turns templates off here.

The defaults, all configurable:

| Template | Weights | Eligible | Done | Moot |
| --- | --- | --- | --- | --- |
| `save_money` | greed 1.0, diligence 0.4 | greed ≥ 50 | `wallet` ≥ 2000 | |
| `get_promoted` | diligence 1.0, boldness 0.4 | `has_role` | `promotion_granted` | `role_lost` |
| `court_someone` | sociability 1.0, boldness 0.3 | `has_court_target` | `court_opinion` ≥ 75 and `court_friend` | `court_target_gone` |
| `settle_feud` | honesty 1.0, sociability 0.4 | `has_rival` | `rival_opinion` ≥ 50 and `rival_cleared`, or `feud_settled` | `rival_gone` |
| `leave_settlement` | curiosity 0.8, boldness 0.6, greed −0.3 | | `left_settlement` | `cannot_leave` |
| `learn_trade` (off by default) | curiosity 1.0, diligence 0.4 | curiosity ≥ 50, `has_trade_target` | `skill_level` ≥ 5, or `trade_learned` | `trade_skill_gone`, `trade_unlearnable` |

Default boosts, also configurable:

| Template | Boosts |
| --- | --- |
| `save_money` | `work` ×1.5, `trade` ×1.3 |
| `get_promoted` | `work` ×1.5 |
| `court_someone` | `visit`, `converse`, `gift` ×2, toward `court_target` |
| `settle_feud` | `help`, `gift`, `converse` ×2, toward `rival` |
| `leave_settlement` | `explore` ×1.5 |
| `learn_trade` | `work` ×1.5, `train` ×2, toward any option |

`save_money`'s 2000 is abstract units; a host sets real amounts. A host that doesn't want anyone leaving turns `leave_settlement` off.

## Learning a trade

`learn_trade` (experimental) is an aim to get a skill up to a line. It's in the default library but **off** (`enabled` false), so a host turns it on in data:

```gdscript
var config := BustleAmbitionConfig.new()
config.find(&"learn_trade").enabled = true
```

`BustleTradeTargets.new(skills, config).fill(agent, ambitions.active(), inputs, personality)` adds its inputs before `update`, like `BustleAmbitionTargets`:

- **Installed skills only:** with the skills module (`BustleSkills`) as the skill port, the skills it has defs for. With the default port, where everyone's level is 0, no skill is installed, so `has_trade_target` stays false and the template is never assigned.
- **The line:** the template's `target`, 5 by default (of a skill's default top level, 20; a host sets its own). A skill qualifies while the agent's level in it is below the line.
- **Which skill** (`trade_skill`):
  - `trade_skill` when the host already set it in the inputs (a pin);
  - else, while `learn_trade` is active, the skill it's about, for as long as that skill is installed;
  - else the agent's first passion (`passions_of`, with `personality` for derived ones) that qualifies;
  - else the qualifying skill with the lowest level, ties by id.

  Nothing is random.
- **The other inputs:** `has_trade_target` (that skill qualifies), `skill_level` (the agent's level in it, the progress) and `trade_skill_gone` (the active ambition's skill is no longer installed).
- **Done:** once `skill_level` reaches the line, or the host sets `trade_learned`. Then the 7-day cooldown applies as for any template, and after it the filler picks another skill still below the line.
- **Moot:** only when its skill is no longer installed (`trade_skill_gone`) or the host sets `trade_unlearnable`. The next update picks another skill. Losing a job doesn't end it.
- **Nothing else is needed:** no job, teacher or way to practise. Practice stays the host's: it reports XP to `BustleSkills` (see [skills](skills.md)), and the job board already adds XP for work done. The `train` boost only matters to a host with a `train` goal; Bustle ships none.
- **No age gate:** a host that wants one adds a circumstance to `requires`.
- **No `next`:** after it, the library is scored again. A host can set `next` in its own data.

## Assigning

An agent with no ambition is given one at its next `update`: at spawn, and again after its ambition ends.

- **A pin:** `pin`, a template the host pins on the profile, is taken first whenever it's eligible.
- **After completion:** the completed template's `next` is taken when eligible.
- **Otherwise:** the eligible template with the highest score wins, ties going to the lower id.

Eligible means:
- enabled;
- every `requires` circumstance true;
- every minimum slider met;
- not already done or moot;
- not completed within `cooldown_days` (7).

An ambition that's still active isn't swapped, even if another template now scores higher. `ambition_started(agent, id, info)` is emitted.

## Ending

- **Completed:** once the template is done, `ambition_completed(agent, id, info)` is emitted.
  - With a `social` port, the deed `achieved_ambition` is recorded, with the agent as actor and the template id as target.
  - The template can't be given again for `cooldown_days`. Nor can it while its target is still met.
- **Moot:** once a moot fact holds, `ended_moot(agent, id, fact)` is emitted.
  - There's no cooldown and no `next`. The library is scored again at once, so the same template can start again with someone else (another person to court, say).
- **Nothing else:** there's no other ending, no giving up and no time limit.

## Bias

Set the agent's brain's `score_boost` to `ambitions.boost`. The scorer multiplies each candidate's score by `boost(goal_id, option_id)` last.

- **Bands never change.** A boost can't lift a goal above danger, self-care, crime or mental states (guarded), orders or duty.
- **A bad boost** (not finite, or negative) makes the candidate ineligible.
- **`boost` is 1 (no effect):**
  - with no ambition;
  - while the agent is locked (`locked: true` in the inputs);
  - while ambitions are off;
  - when the active template is disabled, even if it was assigned before the host turned it off;
  - for a goal in `never_boost` (`steal`, `insult`, `quarrel`, `fight`, `attack`): theft stays with the crime module, and no aim makes anyone pick a fight;
  - for a targeted template, toward anyone but its target, and for every option while it has no target right now.
- **Locks:** while locked, the ambition stays assigned, and progress, completion and moot ending still work. `locked` is read at each `update`, so call `update` whenever a lock starts or ends. Or set `is_locked(id)`, which `boost` checks at once, between updates too; `BustleAmbitions.new(agent, config, society)` sets it to `society.is_locked` (see [locks](locks.md)).

## Targets

`BustleAmbitionTargets.new(society, config).fill(agent, ambitions.active(), inputs)` adds the courting and feud inputs before `update`:

- **Courting:** `court_target` is another agent in the same settlement (`settlement_of`, by default the area). They mustn't be family (`family_kinds`, by kind) or gone for good (`is_gone`, by default no longer in the society), and the agent's opinion of them must be at least `like_line` (60). It's the one liked most, ties by id, and the current target is kept while it qualifies. While nobody qualifies (say the one courted is liked less now), the ambition stays but has no target, so it boosts nothing. `active()` keeps `last_target`, the last one it had.
  - `has_court_target`, `court_opinion` and `court_friend` (a friend kind) are filled too.
  - `court_target_gone` is set only when the last target is gone for good and nobody else qualifies. When someone else does, the ambition turns to them.
- **Feuds:** `rival` is the current one, else the rival (by the rival kind) with the lowest opinion, ties by id.
  - `has_rival`, `rival_opinion`, `rival_cleared` (the rival kind is gone, never once the rival is gone for good, so a feud with someone dead ends moot rather than settled) and `rival_gone` are filled too.

## Notes for hosts

- **Fallback:** with the default library, an agent with greed under 50 and no role, rival or court target gets `leave_settlement`, the only template with no requirements. A host that turns it off leaves such agents with no ambition.
- **Negative scores:** a best score below zero is still assigned; there's no minimum score.
- **A fact held true:** a done fact the host leaves true (`trade_learned`, say) keeps the template from being given again, since a template is never eligible while it's already done.
- **Unknown templates:** a saved ambition whose template is no longer in the library ends at the next update with `ended_moot(..., &"unknown_template")`.

## Switching off and saving

- **Off switch:** `bustle/simulation/ambitions` is a project setting for developers and tests (default on, `BustleAmbitionConfig.allowed()`). It isn't a game option. With it off, or with `enabled` false, nothing is assigned and the current ambition is left as it is.
- **Saving:** `export_state()` and `import_state(saved)` cover the active ambition (with its target and last target) and when each template was last completed (for the cooldown). Import refuses unknown templates and malformed data without changing anything.
