# ADR-0001 — Videira starts as a monolith

**Problem.** Videira needs to exist before it can be broken: M1–M3 each start by
demonstrating a pain (synchronous transcoding, local disk, full-file playback), and a
pain can only be demonstrated on something that runs end to end today.

**Considered.** (A) A single Rails app: auth, upload via Active Storage on local disk,
playback by serving the original file through `<video>`. (B) Starting with the "right"
shape — separate upload service, object storage, background workers — since we already
know where the roadmap ends.

**Chose A** because every piece of B is a solution to a pain we haven't felt yet, and
the roadmap's rule is *no solution before the pain*. The monolith is deliberately ugly
and synchronous: it is the baseline the next three milestones measure against. Rails 8
defaults (Solid Queue/Cache/Cable, Tailwind) are kept so nothing has to be swapped when
those pains arrive — only turned on.
