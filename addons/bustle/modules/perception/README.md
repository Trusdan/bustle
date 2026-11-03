# perception

Senses for every actor: how visible and how loud a target is, how much light reaches a point, and one detection meter per observer-and-target pair with four awareness states (unaware, suspicious, searching, alert). Plain `RefCounted` and `Resource` classes with no nodes and no physics: the host casts its own sight rays and reports the result. See `docs/perception.md`.
