# Affordances

Affordances (`addons/bustle/core/affordances/`) are smart objects, like a bed, a bench or a stall. They tell agents what using them does to their needs, and the scorer weighs those offers, so one generic "use something" goal covers every object.

## Kinds and places

A `BustleAffordanceDef` (a Resource) describes a kind of object:

| Field | What it means |
| --- | --- |
| `relief` | Need → how much one use lowers it. |
| `adds` | Need → how much one use raises it (a side effect). |
| `tags` | Used for tag multipliers, leisure kinds and mood curves. |
| `capacity` | How many agents can hold it at once. |
| `hold_minutes` | How long a reservation lasts. |
| `price` | What one use costs. |
| `item` | When set, each use buys this item from the owner (or payee) through the trade port instead of paying `price`. |
| `others_mult` | How welcome non-owners are, from 0 to 1. |

`is_valid()` refuses negative or non-finite effects, a capacity or hold under 1, a negative price, or an `others_mult` outside 0..1.

A `BustleAffordance` is one placed object: a def with an id, an area, a position and an optional owner.

## Using one

1. **Reserve:** `reserve(agent, now)` holds a place for the def's `hold_minutes`. Holding again renews it. It's refused when every place is held.
2. **Walk and use:** the host walks the agent there and plays the use.
3. **Finish:** `use(agent, now, needs, leisure, trade)` does the rest in one step:
   - takes payment;
   - lowers the relief needs (leisure relief is scaled by tolerance, which then rises);
   - raises the side effects;
   - releases the place.

   If it returns anything but `ok`, nothing changes. The refusals are `no_access`, `full` and `cannot_pay`.

Holds lapse on their own after their time, and `release` lets one go early.

## Ownership and cost

**Access:** an owned affordance scores everyone except its owner at `others_mult`. At 0 they're refused; at 0.5, for example, their relief counts half. Set `access_hook(agent, affordance) -> float` to decide access some other way.

**Price:** each use costs the def's price, and is free to the owner. Set `cost_hook(agent, affordance) -> int` to price it some other way. Payment goes through a `BustleTradePort`:
- it's paid to the owner, or to `payee` when nobody owns it;
- a priced use with nobody to pay, or that the agent can't afford, isn't offered and is refused.

## Buying

A def with an `item` is a shop counter, like a food stall: each use buys one of that item from the owner (or `payee`) with `trade.buy`, at the port's `price_of`, and applies the def's relief. It's offered only while `trade.can_buy` says yes, so a hungry agent goes to buy food only when it can. The owner takes one without buying. With nobody to buy from, it isn't offered.

## The trade port

`BustleTradePort` works in one abstract unit of whole numbers. What that unit is, and any currencies behind it, is the host's business.

| Method | Default |
| --- | --- |
| `balance(id)` | In-memory balances, 0 for an unknown agent. |
| `pay(from, to, amount)` | Moves an exact positive amount between two different named agents who can afford it; otherwise changes nothing. Wages are paid with it. |
| `price_of(item, seller)` | The `prices` list; -1 when unlisted or negative. |
| `can_buy(id, item, seller)` | Sold, two different named agents, and the buyer can pay. Changes nothing. |
| `buy(id, item, seller)` | Pays `price_of` when `can_buy` says yes. A price of 0 moves no money. |
| `export_state()` / `import_state(saved)` | The balances as plain data. Import is all or nothing. Prices are configuration and aren't saved. |

Stock belongs to the host: the default sells any listed item without limit. A host that keeps stock overrides `can_buy` and `buy` together, so an item is offered only when buying it would go through. The same two methods let a host sell on credit, for example staples to an agent who can't pay, keeping the debt itself.

`demo/trade/food_stall.tres` is a neutral food stall that sells `bread`.

## Scoring

**One affordance:** `advertise(agent, now, distance, trade, leisure)` gives the scorer a `BustleAdvertisement`, or null when the agent is refused, the affordance is full, or the agent can't pay.

**All of them:** `BustleAffordanceSet` holds a population's affordances. `advertisements(agent, now, distance, trade, leisure, only)` gives one advertisement per affordance the agent may use, in id order:
- `distance` maps an affordance to its distance;
- `only` limits the list to the affordances the agent knows of.

**Saving:** owners, payees and holds save as plain data with `export_state` and `import_state`. Malformed data, or more holds than the capacity, is refused, and nothing changes.
