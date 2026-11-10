# Ambitions

`addons/bustle/modules/ambitions/` gives each agent a long-term aim, one at a time: save money, get promoted, court someone, settle a feud or leave. This part assigns and ends ambitions. How an ambition sways the agent's day-to-day choices comes later.

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
- **`enabled`:** false means it's never assigned. A host turns templates off here.

The defaults are configurable experimental values:

| Template | Weights | Eligible | Done | Moot |
| --- | --- | --- | --- | --- |
| `save_money` | greed 1.0, diligence 0.4 | greed ≥ 50 | `wallet` ≥ 2000 | |
| `get_promoted` | diligence 1.0, boldness 0.4 | `has_role` | `promotion_granted` | `role_lost` |
| `court_someone` | sociability 1.0, boldness 0.3 | `has_court_target` | `court_opinion` ≥ 75 and `court_friend` | `court_target_gone` |
| `settle_feud` | honesty 1.0, sociability 0.4 | `has_rival` | `rival_opinion` ≥ 50 and `rival_cleared`, or `feud_settled` | `rival_gone` |
| `leave_settlement` | curiosity 0.8, boldness 0.6, greed −0.3 | | `left_settlement` | `cannot_leave` |

`save_money`'s 2000 is abstract units; a host sets real amounts. A host that doesn't want anyone leaving turns `leave_settlement` off.

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

## Switching off and saving

- **Off switch:** `bustle/simulation/ambitions` is a project setting for developers and tests (default on, `BustleAmbitionConfig.allowed()`). It isn't a game option. With it off, or with `enabled` false, nothing is assigned and the current ambition is left as it is.
- **Saving:** `export_state()` and `import_state(saved)` cover the active ambition and when each template was last completed (for the cooldown). Import refuses unknown templates and malformed data without changing anything.
