# Demo

A small neutral demo project for Bustle. Press F5 in the editor to run it: the start screen shows the version and has a button for each demo scene.

## House

`house/` is two residents in a house: one is a loner and the other outgoing (the demo traits below). The house has a bed, a stove, a table, a bench and a phone, and there's a morning block of work off site. To run it, press **House** on the start screen, or open `demo/house/house.tscn` and press F6. Each second of real time is an hour of game time, and the screen shows what each resident is doing and how its needs stand.

- **Needs:**
  - **food** rises while awake, and slowly while asleep;
  - **sleep** rises while awake;
  - **company** rises while awake at home. Being in the house together isn't talking, so the phone and the table meet it. It eases among others at work;
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

## The harness and the timeline

`harness/demo_harness.gd` runs a demo population headless, one fixed step of game time at a time (10 minutes by default), the way a host would. For each agent, in id order, it:

1. moves the needs on;
2. fills the senses: needs, schedule, personality, and the objects the agent can use;
3. ticks the brain;
4. acts on the intent.

Objects are used by the demo's `use` action (`harness/demo_use_action.gd`): it holds the object, waits out its time, then finishes the use, which lowers the needs it meets.

Each run keeps a **timeline** (`harness/demo_timeline.gd`): one entry per event, in order. An entry is the game minute, the agent, the kind and a payload of strings and whole numbers:

| Kind | Logged when | Payload |
| --- | --- | --- |
| `choice` | an agent's choice changes | `{goal, option, order}`, or `{player: 1}` under player control |
| `used` | a use of an object finishes | `{object}` |
| `order` | an order finishes | `{order, outcome}` |
| `attend` | an agent first turns up for a schedule block | `{activity, arrival}` |

`lines()` writes each entry as `minute|agent|kind|payload`, with the payload as JSON and its keys sorted. `hash()` is the SHA-256 of those lines, as hex. The same seed and setup give the same timeline, so the same hash.

## Data and releases

The demo is not part of a release.

`traits/` holds five neutral demo traits (loner, outgoing, low-spirited, greedy, pious). They are data only, and the tests use them to show that trait data alone changes what agents choose. See `docs/personality.md`.

`social/` holds a neutral interaction set (chitchat, deep talk, kind words, slight, insult, comfort) and a `comfort` goal that runs a `converse` step. See `docs/social.md`.

`trade/` holds a neutral food stall that sells bread through the trade port. See `docs/affordances.md`.
