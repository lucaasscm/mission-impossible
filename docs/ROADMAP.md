# Videira + Bugio — Pain-driven Roadmap

> **Videira** — video platform (the "guinea pig" app, with standalone portfolio value)
> **Bugio** — error tracking / observability platform that monitors Videira
>
> Golden rule: **no solution before the pain.** Every milestone starts by demonstrating
> the problem (manually or via load), ends running with `docker compose up`, and gets a
> one-paragraph **ADR**: *"Problem X. Considered A and B. Chose B because..."* — the ADRs
> are the interview material.

## Monorepo structure (day 1)

```
impossible/            # or whatever the repo ends up being called
├── docker-compose.yml # everything: apps, postgres, minio (+ redis at M7 if justified, else M9)
├── apps/
│   ├── videira/       # Rails — video platform
│   └── bugio/         # Rails — error tracker (born in Phase 2)
├── packages/
│   └── bugio-ruby/    # SDK gem (born in Phase 2)
├── services/
│   ├── bugio-ingest/    # ingestor in Node/TS (born in Phase 3)
│   ├── bugio-realtime/  # WebSocket/alerts in Node/TS (Phase 5)
│   └── bugio-ingest-go/ # OPTIONAL: Go rewrite of the ingestor for a triple benchmark
├── load/              # k6 scripts + synthetic traffic generator
└── docs/adr/          # 0001-title.md, 0002-...
```

---

## PHASE 1 — Videira becomes a decent guinea pig

> **Core scope:** M0 through M6-B is the finished portfolio project. M7 through M9 are
> expansion milestones pursued only when the preceding measurements justify them.
> M7-G and M10 through M13 are research experiments, never completion requirements.

### M0 — A monolith that works
- **Pain:** none yet — this is the starting point. Publish and watch a video.
- **Solution:** monolithic Rails (`rails new --css=tailwind`). Simple auth, upload via
  Active Storage on local disk, playback with `<video>` serving the original file
  directly. Ugly and synchronous on purpose — Tailwind for styling, not for polish.
- **Concepts:** domain modeling (User, Video, states), the baseline that will be broken.
- **Done when:** I upload an .mp4 and watch it in the browser. ADR-0001 (why a monolith).
- **✅ Done 2026-08-29** — PRs #1 (monolith + compose + CI + ADR), #4 (dropped unused
  `image_processing`), #5 (CI gate job). Repo made public, `main` ruleset with required
  checks. Observed while here: Active Storage's disk service ignores Range requests, so
  the player can't seek — M3 fuel. Host Postgres owns 5432, so compose exposes 5433.

### M1 — Async transcoding
- **Pain (demonstrate):** after Rails has received a large video, doing media processing
  before responding makes the request hang or time out. Upload a .mov — half the browsers
  won't play the original. Measure upload transfer time separately from processing time;
  the file still passes through Rails until M2, so M1 cannot make the transfer itself fast.
- **Solution:** Solid Queue (Rails 8 default, DB-backed — no Redis) + ffmpeg in a
  background job. State machine on Video: `uploaded → processing → ready → failed`. UI
  shows the state.
- **Concepts:** queues, idempotent jobs, retries, state machines.
- **Done when:** once the upload transfer finishes, the response is not delayed by
  transcoding and the video becomes `ready` on its own; killing the worker mid-job and
  restarting corrupts neither state nor output. Compose runs a separate worker with
  ffmpeg, and development uses Solid Queue explicitly. ADR-0002.

### M2 — Object storage
- **Pain (demonstrate):** local media is coupled to an application instance: without the
  current volume mount it disappears when that instance is replaced, multiple Videira
  instances do not share a filesystem, and uploaded media grows the application disk.
  Do not use `docker compose down -v` as evidence: it deliberately deletes MinIO's named
  volume too.
- **Solution:** MinIO in the compose file (S3-compatible API). Direct upload with
  presigned URLs — the file never even passes through Rails.
- **Concepts:** object storage, presigned URLs, getting heavy traffic out of the request
  path.
- **Done when:** uploads go straight from the browser to MinIO; Rails only authorizes the
  upload and records metadata. Browser-reachable presigned URLs and MinIO CORS work from
  outside the Compose network; replacing Videira leaves media intact. ADR-0003.

### M3 — Real streaming
- **Pain (demonstrate):** open the Network tab while playing a long video — the browser
  downloads the whole MP4. On a slow connection (throttle), it stalls.
- **Solution:** evolve the M1 transcoding pipeline to HLS at 2–3 qualities
  (480p/720p/1080p), with an explicit representation for the master playlist, rendition
  playlists, and media segments in object storage. Use hls.js on the frontend and decide
  how playlists and segments are authorized/reached by the browser.
- **Concepts:** adaptive streaming, segmentation, the mental model underlying CDNs.
- **Done when:** video plays in segments and switches quality under throttling. ADR-0004.

> **FREEZE:** Videira stops here. No new features on it until Bugio has M4-B running.
> (Anti-pattern to avoid: "just one more little thing on the player".)

---

## PHASE 2 — Bugio is born

### Design system (small, before M4-B — the one non-pain-driven step besides tests/CI)
- **Why here:** Bugio's panel is about to exist; two apps that should look related, and
  the panel becomes React in M9-R. Designing the system against real content from both
  apps beats guessing it in M0. Videira's plum/grape `@theme` tokens are the seed.
- **What:** a Claude Design canvas (palette, type scale, spacing, the handful of
  components: button, field, list row, flash, player frame) kept in sync with the
  Tailwind `@theme` tokens + component classes. Tokens live in `packages/` once Bugio's
  React panel needs them.
- **Done when:** both apps consume the same tokens; the canvas is the reference. No ADR
  needed — it's not an architectural decision. Not learning core: Claude writes it.

### M4-B — Receive, store, list
- **Pain (real, from M1–M3):** ffmpeg fails on an exotic codec, a job blows its timeout,
  an upload hits a network error — and you only find out by grepping container logs.
  Reproduce it: upload a corrupted file to Videira and try to figure out what happened
  without looking at the terminal.
- **Solution:** `bugio` app (Rails, Tailwind) with a minimal `Project` and revocable
  ingest key, an authenticated and size-limited `POST /api/events` endpoint, plus a
  `bugio-ruby` gem (the SDK) that captures unhandled exceptions (Rack middleware + job
  hook) and sends them with context (request, filtered params, backtrace). Install the
  gem in Videira. SDK delivery has short timeouts, bounded payloads, and must never make
  the host application fail when Bugio is unavailable. Panel: a raw list of events.
- **Concepts:** SDK design, Rack middleware, exception serialization, API contracts.
- **Done when:** a forced error in Videira shows up in Bugio's panel within seconds,
  invalid credentials and oversized payloads are rejected, and Bugio being offline does
  not break Videira. ADR-0005 defines the versioned event envelope, including project
  identity; the ingest key belongs to the authenticated transport, not the event body
  (the contract is the heart of the system).

### M5-B — Grouping (fingerprinting)
- **Pain (demonstrate):** run the synthetic generator with 5% broken requests for 10
  minutes — the panel becomes a 3,000-row list of the SAME error. Unusable.
- **Solution:** fingerprint via hash of (exception type + relevant backtrace frames,
  normalizing line numbers/IDs). An `Issue` model aggregating `Events`: counter,
  first/last seen, resolved/unresolved.
- **Concepts:** the central problem of error tracking; normalization; aggregation.
- **Done when:** 3,000 events = a handful of Issues; the panel lists Issues, drill-down
  shows occurrences. ADR-0006 (fingerprint algorithm and trade-offs).

### M6-B — Ingestion out of the request path
- **Pain (demonstrate):** k6 against the ingestion endpoint — writing the event +
  computing the fingerprint + updating the Issue inside the request cycle tanks latency;
  under a spike, events get lost.
- **Solution:** the endpoint only authenticates, bounds, validates, and enqueues (Solid
  Queue — already there); a worker does fingerprinting, persistence, and aggregation.
  Choose and document a concrete overload response (`429`/`503`, queue-depth limit, or
  another measured policy) rather than calling it only "basic backpressure".
- **Concepts:** decoupled ingestion, at-least-once delivery, deduplication by event_id.
- **Done when:** a fixed k6 profile records accepted events/second, p95 endpoint latency,
  queue depth, processed count, duplicate count, lost count, and recovery time after an
  overload. The result may disprove the expected improvement; record what actually
  happens. ADR-0007.

---

## PHASE 3 — Candidate first extracted service (Node/TS)

### M7 — Ingestor in Node/TypeScript
- **Pain (demonstrate):** compare equivalent Rails and Node candidates doing only
  authentication, schema validation, rate limiting, and enqueueing. Extract only if the
  M6 measurements show Rails misses an explicit SLO and the endpoint needs nothing from
  Rails. If Rails meets the SLO, write the "extraction not justified" ADR and stop here.
- **Solution (only if justified):** `services/bugio-ingest` in Node/TS receives JSON,
  validates the schema (zod), applies per-project token-bucket rate limiting, and appends
  to a Redis Stream. A dedicated Ruby consumer uses a Redis consumer group to acknowledge,
  reclaim, and process messages through Bugio's existing application service. It is not a
  Solid Queue worker: Solid Queue is database-backed and cannot consume Redis. Rails stops
  exposing `/api/events`. This is the ideal Node case: small and IO-bound.
- **Concepts:** first service extracted WITH justification; contracts between services;
  the event loop, backpressure; TS on a small-surface backend — direct synergy with the
  new job.
- **Done when:** ADR-0008 records a fair Rails-vs-Node benchmark with real numbers. If
  extraction is justified, acknowledged, abandoned, reclaimed, duplicate, and poison
  messages have defined behavior and the SDK points at the ingestor with no contract
  change. If it is not justified, the measured decision not to extract is the completed
  outcome.

### M7-G (OPTIONAL, once the new-job onboarding settles) — Go rewrite of the ingestor
- **Pain:** legitimate curiosity + prior investment in Go (Phases 0–2 of the study plan).
- **Solution:** same contract, third implementation in `services/bugio-ingest-go`.
- **Concepts:** goroutines/channels; and the richest ADR in the project — a **triple
  benchmark, Rails vs Node vs Go**, on the same endpoint, with your own numbers.
- **Note:** the service is deliberately small → the rewrite is cheap. Zero deadline
  pressure.

---

## PHASE 4 — Data at scale

### M8 — The events table explodes
- **Pain (demonstrate):** drive failures through Videira so they cross the real pipeline,
  but size the rate and duration to the development machine rather than promising millions
  in 30–60 minutes. Supplement with deterministic mass generation if needed. Preserve
  `EXPLAIN ANALYZE` evidence for slow "last 24h" queries.
- **Solution (stage it):** (1) establish the dataset and query plan; (2) use native
  Postgres date partitioning and automate retention by dropping partitions; (3) add a
  materialized view or hourly rollup; (4) add dashboard caching only if measurements still
  require it. Account for PostgreSQL's requirement that partitioned primary/unique keys
  include the partition key, especially for event IDs and deduplication.
- **Concepts:** partitioning/sharding driven by real pain, retention/TTL, cache layers,
  "what is allowed to be stale?".
- **Done when:** the recorded dataset size is large enough to demonstrate the original
  bad plan, dashboard queries are <200ms on that same dataset, and retention drops old
  partitions automatically. Attribute the improvement to partition pruning, rollups, or
  caching separately. ADR-0009.

---

## PHASE 5 — TypeScript on the frontend and in real time

### M9-R — Bugio's React panel
- **Pain (demonstrate):** Bugio's Hotwire panel starts demanding dense interactivity —
  combined issue filters, time-series charts, stack trace drill-down — and every
  interaction becomes a round-trip/new page.
- **Solution:** React SPA (Vite + TS) consuming the `bugio` app's JSON API. Videira stays
  Hotwire — on purpose.
- **Concepts:** React with TS, JSON API design, client-side state; and the ADR "why
  Hotwire on Videira and React on Bugio" — both frontend paradigms, each where it makes
  sense.
- **Done when:** the React panel covers issues + drill-down + charts reading from the
  API. ADR-0010.

### M9 — Real time
- **Pain (demonstrate):** you keep hitting F5 on the panel waiting for a new error. New
  issues only alert via refresh.
- **Solution:** `services/bugio-realtime` in Node/TS consumes processed-event Redis
  Pub/Sub messages and pushes them to the React panel via WebSocket. Pub/Sub is acceptable
  for ephemeral UI updates that a refresh can recover. Alert rules ("new issue" / "spike
  of N in M minutes") use a durable Redis Stream or persisted outbox so a disconnected
  alert consumer does not silently lose notifications.
- **Concepts:** WebSockets, pub/sub, the case where Node genuinely shines; TS frontend
  and backend talking through shared types (a `packages/` module with the event types).
- **Done when:** a forced error in Videira appears on the open panel WITHOUT refresh,
  <2s end-to-end. ADR-0011.

---

## PHASE 6 (optional) — Back to Videira, now observed

### M10 — Cache and feed
- **Pain:** k6 on Videira's home with mass seeds → N+1s, slow queries — which you now SEE
  in Bugio (bonus: capture slow queries in the SDK).
- **Solution:** fragment caching, async batched view counters, cached feed.

### M11 — Multiple instances + load balancer
- **Pain:** a single Rails instance saturates under k6.
- **Solution:** Caddy/nginx in front of 2+ instances in compose; discover in practice
  what needs to be stateless (session, local cache). Kamal if it goes to a real VPS.
- **Concepts:** load balancing, statelessness, health checks — monitored by your own
  Bugio, closing the loop.

### M12 — Search
- **Pain:** LIKE gets slow with mass seeds (EXPLAIN as evidence).
- **Solution:** Postgres full-text search first; Meilisearch only if justified.
- **Concepts:** inverted indexes and the criterion for "when the database is enough".

### M13 — Cloud portability (optional, with Floci)
- **Pain:** "what if this ran on managed cloud?" — today everything is a self-hosted
  primitive (MinIO, Redis). Validate the swap with no cost/real account.
- **Solution:** `floci-gcp` (local GCP emulator, MIT, no token): swap MinIO→GCS and the
  queue→Pub/Sub behind an abstraction; measure what changes in the code and the contract.
- **Concepts:** portability, managed services vs self-hosted, the adapter pattern.
- **Note:** MinIO already speaks the S3 protocol, so the AWS SDK experience exists since
  M2 — this milestone is about GCP (professional stack) and about the ADR of the swap.
  Floci is also a candidate for CI (integration tests with 24ms startup). It's a young
  project — validate emulator fidelity per service before trusting it.

---

## Tests and CI — day-1 foundation (NOT pain-driven)

The only exception to the "pain before solution" rule: starts at M0 and holds forever.

- **Tests:** Minitest in the Rails apps; Vitest in the Node/TS services and the React
  panel; `go test` only in the optional experiment. Per-milestone rule: **the
  demonstrated pain becomes a regression test** — e.g. M1 "killing the worker mid-job
  corrupts nothing" → job idempotency test; M5-B fingerprint → pure TDD (pure function:
  exception + backtrace → hash).
- **GitHub Actions:** one workflow per app with **path filtering** (a PR touching only
  `apps/videira` doesn't run bugio's suite). Postgres/Redis via Actions `services:`.
  Suite + RuboCop; ESLint + `tsc --noEmit` on TS services/frontend; `golangci-lint` only
  if the Go experiment (M7-G) happens. Free/unlimited on a public repo.
- **Branch protection (Settings → Branches/Rulesets on `main`):** *required status
  checks* — PR merge blocked while CI isn't green. Without this, CI is decorative.
  *(Done in M0 as a ruleset. Gotcha learned: path filters on `pull_request:` leave
  required checks pending forever on PRs that don't match — gate the jobs instead, so
  they report "skipped".)*
- **Workflow:** even solo, everything through PRs. Each milestone = one PR (or a few),
  with the ADR included in the diff. The history of green PRs becomes part of the
  portfolio.

## Cross-cutting tools

- **k6** (`load/`): load scripts versioned alongside the milestone that uses them.
- **Synthetic generator** (`load/traffic.rb` or Node): navigates Videira performing real
  actions with a configurable rate of broken behavior (invalid file, malformed request).
  This is how observability companies test themselves — the error travels the real path:
  app → SDK → ingestion → fingerprint → panel.
- **Mass seeds**: factories to populate Videira with thousands of videos/users.

## Anti-abandonment rules

1. **Sequential, never parallel.** One active milestone at a time, across both projects.
2. **Pain before solution.** If the problem can't be demonstrated, the milestone doesn't
   start.
3. **Done = `docker compose up` + ADR written.** No exceptions.
4. **Respect the freeze.** Videira stops at M3 until Bugio exists (M4-B).
5. **From M0 through M6-B you already have a better portfolio than 90%.** Everything
   after is a bonus — no guilt if the pace drops.
