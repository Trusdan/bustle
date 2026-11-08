# needs_mood

Mood and thoughts, RimWorld-style. Each thought has a value, a duration (or lasts while its condition holds), a stack limit, an emotion and a reason. Mood heads for its target (the baseline plus every active thought) at configured rates, and stands still while the agent sleeps. The dominant emotion is the emotion with the largest total. It reads the core needs engine for need thoughts and feeds the scorer's `mood` input. See `docs/mood.md`.
