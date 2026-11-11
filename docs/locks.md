# Locks

A host locks an agent to hold it to a story beat or a task: to stay at a place, to run a goal (or a sequence), or both. A lock is just a lock; what it's for is the host's business. No chance is involved, and the same calls give the same result.

## Locking and releasing

```gdscript
society.lock(&"agent", BustleLock.make(&"beat", &"square", &"tend_stall"))
society.unlock(&"agent", &"beat")
```

`BustleLock.make(lock_id, place, goal, sequence)` creates a lock:
- **`place`:** an area;
- **`goal`:** a goal from the agent's library;
- **`sequence`:** a `BustleActionSequence` to run instead of a goal.

A lock needs an id and at least one pin.

- **Several locks:** an agent can hold several, by `lock_id`. Locking again with the same id replaces that lock's pin, and it then counts as the newest.
- **Releasing:** `unlock(agent, lock_id)` releases one lock; the others stay.
- **Reading locks:** `is_locked(agent)` is true while any lock is held. `lock_ids(agent)` lists them, oldest first.

## What a lock does

While any lock is held, the agent's brain has one order at the front of its queue, `lock/<agent>`:
- **What it runs:** the newest lock's goal or sequence, then the `hold` action, which never finishes.
- **Where it moves:** the newest lock's place. When the running step doesn't name a `move_to`, the place's position (the world port's) is used.
- **Changes:** the order is rebuilt whenever the locks change, and it's cancelled when the last lock is released.

The order is held, not forced (it competes at ORDERED), and the brain treats it specially:
- **Danger** at CRITICAL can interrupt it. Once the danger is gone, it resumes.
- **URGENT self-care** can interrupt only when it keeps to the pinned place: an option advertised within `society.lock_reach` (5 m). With no place pinned, self-care may go anywhere.
- **Nothing else** displaces it: guarded goals, duty, personal and idle goals all wait.
- **Other orders** the host gives meanwhile wait behind it, and run once the last lock is released.
- **If a goal step fails,** the order is put back while the locks are held.

## What else reads it

`is_locked` is the one source. Made with a society, these use `society.is_locked` (a host or test can still set its own):
- `BustleCrime`: a locked agent steals nothing;
- `BustleMentalBehaviour`: no mental state starts, and an active one's goals and modifiers are held off;
- `BustleAmbitions` (made with `BustleAmbitions.new(agent, config, society)`): no boosts.

## Protection

`set_protection(agent, level)` sets a `BustleLock.Protection` level, and `is_protected(agent)` reports it:

| Level | Protected |
| --- | --- |
| `NONE` (the default) | never |
| `QUEST_LOCKED` | only while it holds a lock |
| `ESSENTIAL` | always |

Bustle never harms or heals anyone. The host's combat or health refuses a killing blow while `is_protected` is true.

## Saving

`export_state` saves each agent's locks (a sequence as its steps' `{action, params}`) and protection. `import_state` restores them, rebuilds the lock orders and refuses malformed or repeated locks. Saves without locks load as before.
