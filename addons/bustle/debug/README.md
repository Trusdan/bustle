# debug

Tools for inspecting a running population while developing. They run only in debug builds (the editor and debug exports): in a release export the console answers that it isn't available and the overlay stays off. Hosts can also leave this folder out of release exports with an export filter.

- `BustleInspector`: reads an agent's state from what its brain already holds: the scorer's own candidates from the last tick, the last intent, the step and the order queue. Parts that need modules not installed yet (rings, memory, schedules, needs) are marked unavailable rather than made up; for needs it shows the raw need inputs the brain was given.
- `BustleDebugConsole`: `help`, `agents`, `why <agent> [goal] [option]`, `need <agent>`, `order <agent> [<sequence> [forced] | cancel <order>]`.
- `BustleDebugOverlay`: a label above each agent's body. Off, it stops processing and frees its labels.
- `BustleDebug.is_available()`: the gate.
