# Demo

A small neutral demo project for Bustle. In 0.1.0 it is a skeleton: one screen that shows the version. Press F5 in the editor to run it.

The demo is not part of a release.

`traits/` holds five neutral demo traits (loner, outgoing, low-spirited, greedy, pious). They are data only, and the tests use them to show that trait data alone changes what agents choose. See `docs/personality.md`.

`social/` holds a neutral interaction set (chitchat, deep talk, kind words, slight, insult, comfort) and a `comfort` goal that runs a `converse` step. See `docs/social.md`.
