# Schedules

Schedules (`addons/bustle/core/schedules/`) are daily routines made of time blocks on the clock port. The scorer sees the current block as an input, so a host's `DUTY` goals follow the routine. A strong enough need or personality can still outscore it.

## Data

A `BustleScheduleBlock` is one block of a day:

| Field | Meaning |
| --- | --- |
| `activity` | What the agent should be doing, seen by the scorer as `schedule.<activity>`. |
| `start_minute`, `end_minute` | Minutes of the day. An end at or before the start runs past midnight, and the block belongs to the day it starts. |
| `place` | Where the block happens. |
| `late_minutes` | How late the agent may arrive and still count as on time. -1 uses the schedule's own tolerance. |

A `BustleScheduleDay` is one day's blocks.

A `BustleScheduleDef` is a routine. It has:

- `day`, the usual day.
- `weekdays`, whole-day overrides by weekday, for example a rest day.
- `seasons`, whole-day overrides by season.
- `late_minutes`, the lateness tolerance, default 15.

A weekday override wins over a season override, which wins over the usual day. Weekdays count from minute 0: game day `d` is weekday `(d + week_offset) mod week_length`, with a 7-day week by default. The season comes from `BustleClockPort.season()`. The default clock has no seasons, so a host overrides that method.

## In play

`BustleSchedule` holds one agent's routine.

- `block_at(now, season)` gives the current block, including one carried over from the night before.
- `fill_inputs(inputs, now, season)` sets `schedule.<activity>` to 1 for the current block, or `schedule.free_time` when no block is current. It erases the routine's other activity inputs and leaves every other input alone.
- `attend(now, activity, season)` records that the agent is doing the current block's activity. Only the first arrival counts. It returns `on_time` or `late`.
- `report(day, now, season)` counts that day's blocks as on time, late, missed or pending:
  - **On time:** the agent turned up within the tolerance.
  - **Late:** the agent turned up after the tolerance.
  - **Missed:** the agent never turned up before the block ended.
  - **Pending:** the block hasn't ended yet and wasn't attended.
- `export_state` and `import_state` save and load attendance as plain data. Seven days are kept.

A typical tick fills the inputs, runs the brain, then calls `attend` with the goal the brain picked. The tests do this for three game days.
