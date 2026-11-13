# Demo

A small neutral demo project for Bustle. Press F5 in the editor to run it: the start screen shows the version and has a button for each demo scene.

## House

`house/` is two residents in a house: one is a loner and the other outgoing (the demo traits below). The house has a bed, a stove, a table, a bench and a phone, and there's a morning block of work off site. To run it, press **House** on the start screen, or open `demo/house/house.tscn` and press F6. Each second of real time is an hour of game time, and the screen shows what each resident is doing and how its needs stand.

- **Needs:**
  - **food** rises while awake, and slowly while asleep;
  - **sleep** rises while awake;
  - **company** rises while awake at home. Being in the house together isn't talking, so the phone and the table meet it. Work slows it for both residents, but only the loner's eases there: the outgoing resident's still rises, more slowly;
  - **solitude** rises in company and eases alone.
- **Goals:**
  - `use_object` (personal) uses whatever relieves the most;
  - `eat_now` and `sleep_now` (urgent) go to the stove or the bed once food or sleep presses hard;
  - `work` (duty) goes to work during the work block, which takes the resident off site.
- **Traits:** the loner's and the outgoing resident's traits change how fast company and solitude rise, and how much social and quiet things count. Sleep doesn't count in the scorer until it reaches 0.35.

Every number is a starting point, not tuning (see `house/house.gd`). The same run drives the scene and `tests/demo/test_house.gd`, which checks it headless:

1. Three days on their own: no need stays above 0.95 for more than an hour, and each resident eats and sleeps every day, socialises, and goes to work.
2. With autonomy off, the needs rise and nothing is chosen. A queued list of orders (cook, eat, sleep) runs in turn, then the resident idles.
3. An order interrupts what the resident chose, and when the order is done the resident resumes it.
4. Swapping the loner and outgoing traits changes what is chosen.
5. A player-controlled resident never chooses for itself.

## Colony

`colony/` is four settlers with a bed each, a stove, a crate of stores and a field plot. To run it, press **Colony** on the start screen, or open `demo/colony/colony.tscn` and press F6. Each second of real time is an hour of game time, and the screen shows what each settler is doing, its needs, its mood and any mental state.

- **Needs:** food, sleep and warmth. Warmth stays put until the cold snap; then it rises for everyone, and the stove meets it.
- **Goals:**
  - `use_object` (personal) uses whatever relieves the most;
  - `eat_now`, `sleep_now` and `warm_up` (urgent) go to the stove or the settler's own bed once a need presses hard;
  - `farm` (duty) works the field from 08:00 to 16:00;
  - `rest` (duty) goes to bed from 22:00 to 07:00, while sleep presses;
  - `unwind` (idle) sits by the hearth when nothing else calls, so a free evening isn't hours of standing still (the soak's stuck watch found that);
  - `comfort` (personal, with social on) talks to a friend in a low mood, from `social/comfort_goal.tres`.
- **Mood** (the needs_mood module): held thoughts while hungry, tired or cold; timed ones after a hot meal, a night in bed or a harvest. A low enough mood starts a mental state, which the demo only records.
- **Social** (the built-in social store): A and B are friends, and so are C and D. A settler who notices a friend in a low mood or state is offered comforting them. Comfort, the opener from `social/comfort.tres`, leaves the friend a `comforted` thought in this demo.
- **Perception:** who notices whom. With it off, a settler notices everyone awake in its area.
- **Traits:** A is a loner, B outgoing and C low-spirited; D has none.
- **The cold snap** is a host event the demo injects from 18:00 on the third day, for a day: warmth rises, and everyone gets a `bitter_weather` thought. It isn't a framework feature.

`Colony.build(seed, modules, cold_snap)` leaves out any of the `needs_mood`, `social` and `perception` modules, and the rest still runs. Every number is a starting point, not tuning (see `colony/colony.gd`). `tests/demo/test_colony.gd` checks it headless:

6. A week on their own: each settler works the field and goes to bed on time every day, and food and sleep stay in hand. Mood follows thoughts: the cold snap pulls it down, it comes back once the snap passes, and a new thought moves it toward its target at the configured rate.
7. Forcing bad thoughts on two settlers starts a minor mental state in the step each one's mood crosses the line, both at once, with no spacing or cap. When each state ends, the settler gets the catharsis thought.
8. A friend notices a settler in a low mood and comforts them, opening with comfort, with or without perception. Settlers who aren't friends don't come.
9. The same seed gives the same timeline, and the week's hash is pinned. Another seed gives another conversation, so another hash.
10. With each module left out in turn, and with all three left out, every settler still works and sleeps on time.

`Colony.build(seed, modules, cold_snap, board)` also takes a job board (see `docs/work.md`). Settlers then weigh its postings in their free time (`take_job`, after field duty) against eating and sitting by the hearth. Without a board, nothing changes, the pinned hash included. `tests/demo/test_jobs_demo.gd` checks it with the demo work types:

11. A settler takes the posting it wants most, and swapping two settlers' sliders swaps their picks. Settlers who dislike the work leave it posted and do something else.
12. Mending needs the `mender` role: keener settlers without it never claim it, and the one who holds it does.
13. Two settlers who pick one posting in the same step never share it: the higher score claims it.
14. A completed job pays its wage once and gives practice in its skill, and the same run gives the same timeline.

## The harness and the timeline

`harness/demo_harness.gd` runs a demo population headless, one fixed step of game time at a time (10 minutes by default), the way a host would. For each agent, in id order, it:

1. moves the needs on;
2. fills the senses: needs, schedule, personality, and the objects the agent can use;
3. ticks the brain;
4. acts on the intent.

The optional modules are off until a demo switches them on: `enable_mood`, `enable_social` and `enable_perception`. With mood on, each step also holds the need thoughts, moves the mood on and updates the mental state; with social on, it offers the comfort hook's advertisements and runs conversations through the social store. `add_event` adds a host event with a need condition and a thought.

Objects are used by the demo's `use` action (`harness/demo_use_action.gd`): it holds the object, waits out its time, then finishes the use, which lowers the needs it meets.

Each run keeps a **timeline** (`harness/demo_timeline.gd`): one entry per event, in order. An entry is the game minute, the agent, the kind and a payload of plain data (numbers rounded to three places):

| Kind | Logged when | Payload |
| --- | --- | --- |
| `choice` | an agent's choice changes | `{goal, option, order}`, or `{player: 1}` under player control |
| `used` | a use of an object finishes | `{object}` |
| `order` | an order finishes | `{order, outcome}` |
| `attend` | an agent first turns up for a schedule block | `{activity, arrival}` |
| `event` | a host event starts or ends (no agent) | `{event, phase}` |
| `state` | an agent enters a mental state (mood on) | `{state, tier}` |
| `state_end` | an agent leaves a mental state (mood on) | `{state, reason}` |
| `talk` | a conversation turn (social on) | `{with, interaction}` |
| `thought` | a thought comes or goes (mood on) | `{thought, phase: "add", value, reason}` or `{thought, phase: "end"}` |
| `stuck` | the stuck watch judges an agent stuck | `{reason, since}`: `still`, `fail_loop` or `state_overdue` |
| `unstuck` | a stuck agent makes progress again | `{reason, minutes}` |

`lines()` writes each entry as `minute|agent|kind|payload`, with the payload as JSON and its keys sorted. `hash()` is the SHA-256 of those lines, as hex. The same seed and setup give the same timeline, so the same hash.

## Stuck or busy

`harness/demo_stuck_watch.gd` tells a stuck agent from one in a long, legitimate activity. The harness feeds it every agent every step, and a bench can feed it the same way.

- **Legitimate (never stuck):** asleep, attending a schedule block that hasn't ended (or away for it), using an object while the use is inside its expected time (`using_on_time`), under an order or player control, or in a mental state inside its duration. Travel still closing on its goal, and off-screen catch-up still advancing, count too, for a host that reports them.
- **Stuck:** more than 2 game hours with none of those and no progress: the same goal and step, nothing used up, and no move past 0.5 m (or, off-screen, the same place with no hop pending). Also stuck at once: the same goal failing three steps in a row, or a mental state still active past its end.

The 2-hour bound, the 0.5 m epsilon and the loop count are experimental defaults (`bound_minutes`, `move_epsilon`, `fail_loop`). `longest_still(id)` and `spells()` give the diagnostics. The population bench (`bench/population_bench.gd`) feeds the same watch.

## Soak

`bench/soak.gd` runs both demos, at their own sizes with every module on, for a number of game days from a fixed seed, twice. It reports the seed, the engine version and build commit, the population, the days, the wall time and memory, the timeline's size and hash, whether the replay matched, and the stuck diagnostics. See `docs/perf.md`.

## Data

`traits/` holds five neutral demo traits (loner, outgoing, low-spirited, greedy, pious). They are data only, and the tests use them to show that trait data alone changes what agents choose. See `docs/personality.md`.

`social/` holds a neutral interaction set (chitchat, deep talk, kind words, slight, insult, comfort) and a `comfort` goal that runs a `converse` step. See `docs/social.md`.

`jobs/` holds three neutral work types: a harvest (diligence, practises farming), an errand (curiosity) and mending (needs the `mender` role). See `docs/work.md`.

`skills/` holds a generic skill set (cooking, farming and crafts), a passion for each and a shared `enjoying_work` thought. They are data only; the tests use them. See `docs/skills.md`.

`trade/` holds a neutral food stall that sells bread through the trade port. See `docs/affordances.md`.
