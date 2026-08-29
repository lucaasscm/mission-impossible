# CLAUDE.md — Videira + Bugio

## What this project is

A **learning project** monorepo with two products that feed each other:

- **Videira** (`apps/videira`) — video platform (Rails + Hotwire). Upload, async
  transcoding (Solid Queue + ffmpeg), object storage (MinIO), HLS streaming. It is also
  the application **instrumented/observed** by Bugio.
- **Bugio** (`apps/bugio`) — error tracking platform (Sentry-style). Receives events
  through its own SDK (`packages/bugio-ruby`), groups them by fingerprint, React
  panel, Node/TS ingestor, real-time alerts via WebSocket.

**Source of truth for the plan: `docs/ROADMAP.md`.** Read it before any work.
Decisions live in `docs/adr/` (one file per decision, one paragraph:
"Problem X. Considered A and B. Chose B because...").

## ⚠️ Claude's role in this repo — READ FIRST

This is a learning project. The repo owner's goal is to LEARN the concepts, not
merely to have them implemented. Therefore:

### Claude MAY write directly
- Scaffolding and boilerplate (generators, trivial CRUD, obvious migrations)
- Configs: docker-compose, GitHub Actions, Dockerfiles, linters
- Seeds, factories, load scripts (k6), the synthetic traffic generator
- Videira's frontend (Hotwire, Tailwind) — not a learning focus
- The design system (Claude Design canvas + Tailwind `@theme` tokens), before M4-B
- Regression tests AFTER the behavior has been implemented and understood

### Claude does NOT write — only reviews, questions, and gives direction
The learning core of each milestone. The owner writes; Claude acts as a Socratic
partner: points out problems, asks questions, suggests directions WITHOUT pasting
the finished solution. Includes (non-exhaustive):
- M1: the Video state machine and transcoding job idempotency
- M2: the presigned URL / direct upload flow
- M4-B: SDK design (Rack middleware, exception serialization) and the event contract
- M5-B: the fingerprinting algorithm
- M6-B: ingestion decoupling, dedup, backpressure
- M7: the Node/TS ingestor (validation, rate limiting)
- M8: partitioning, rollups, retention policy
- M9/M9-R: end-to-end WebSocket and the panel's JSON API design

When in doubt about which category something falls into, ask before writing code.
If explicitly asked to "just do it", confirm once ("this is learning core — are you
sure you want me to write it?") and then comply.

## Git and GitHub rules

- **Claude never commits, creates branches, pushes, or opens/merges PRs unless the
  owner explicitly asks in that turn.** Leave work staged/uncommitted and hand off with
  a suggested commit message. Standing exception: small CI-fix commits on an already
  open PR may be committed and pushed without asking.
- Repo: `github.com/lucaasscm/mission-impossible`, **public** (branch rules need it on
  GitHub Free). Owner is the only collaborator; PR creation open to all users.
- `main` ruleset: changes only via PR, no force-push/deletion, required checks
  `lint`, `scan_js`, `scan_ruby`, `test` (not strict). No bypass actors — binds the
  owner too.
- CI (`.github/workflows/<app>.yml`) runs on **every** PR; a `changes` job gates the
  app jobs so PRs that don't touch the app get *skipped* checks (which satisfy the
  ruleset). Do not put `paths:` on `pull_request:` — required checks would stay
  pending forever. `push` to `main` stays path-filtered.
- Dependabot PRs: assess whether the dependency is used at all before merging. An
  unused dependency gets removed, not bumped (precedent: `image_processing`, PR #3/#4).

## Process rules (non-negotiable)

1. **Pain before solution.** No milestone starts before its pain has been
   demonstrated (manually or via k6), as described in the ROADMAP. If the owner asks
   to skip straight to the solution, remind them of the rule.
2. **Sequential.** One active milestone at a time, in ROADMAP order. Videira freezes
   at M3 until Bugio has M4-B running.
3. **Done = `docker compose up` works + green tests + ADR written.**
4. **Everything through PRs**, even solo. Each milestone = one PR (or a few), with
   the ADR in the diff. Merge blocked by branch protection if CI fails.
5. **The demonstrated pain becomes a regression test** in the same PR.

## Stack and conventions

- **Rails** (apps/videira, apps/bugio): Minitest, RuboCop, Solid Queue/Cache/Cable
  (Rails 8 defaults, DB-backed — no Sidekiq), Tailwind CSS (`--css=tailwind`), Hotwire
  on Videira. No RSpec.
- **Node/TS** (services/*): Vitest, ESLint, `tsc --noEmit`. Validation with zod.
- **React** (Bugio panel, from M9-R on): Vite + TS.
- **Go** (`services/bugio-ingest-go`): OPTIONAL, only the M7-G benchmark experiment.
  Do not suggest Go outside of it.
- **Removed on purpose**: `image_processing`/`libvips` (unused — re-add with
  `ruby-vips` only if Active Storage previews/thumbnails are ever wanted).
- **Local infra**: docker-compose with Postgres and MinIO. Redis only enters at M7
  (a queue the Node ingestor can write to) and stays for M9 pub/sub. No real cloud;
  Floci (GCP emulator) only in the optional M13.
- **Contract between services**: Bugio's event format is defined in ADR-0005 and
  versioned; contract changes require a new ADR. Shared TS types in `packages/`.

## Commands

```bash
docker compose up --build    # brings up everything (the "done" criterion of every milestone)
                             # Postgres is exposed on host port 5433 (5432 is a local install)
docker compose up -d db      # infra only, for native development

cd apps/videira
bin/dev                      # Rails + Tailwind watcher at http://localhost:3000
bin/rails test               # Minitest
bin/rubocop                  # lint (CI runs brakeman + bundler-audit + importmap audit too)
bin/rails db:seed            # admin@videira.local / password

npm test                     # inside each TS service (Vitest)
```

Seeded login: `admin@videira.local` / `password`. CI lives in `.github/workflows/<app>.yml`,
one workflow per app, path-filtered.

## Structure

```
├── CLAUDE.md
├── .github/workflows/      # one path-gated workflow per app (videira.yml, ...)
├── docs/
│   ├── ROADMAP.md           # full plan, pain-driven
│   └── adr/                 # 0001-title.md, ...
├── docker-compose.yml
├── apps/
│   ├── videira/
│   └── bugio/
├── packages/
│   ├── bugio-ruby/          # SDK gem
│   └── (shared TS types, from M9 on)
├── services/
│   ├── bugio-ingest/        # Node/TS (Phase 3)
│   ├── bugio-realtime/      # Node/TS (Phase 5)
│   └── bugio-ingest-go/     # optional (M7-G)
├── load/                    # k6 + synthetic traffic generator
└── infra/                   # nginx/caddy, kamal (final phases)
```

## Interaction style

- Direct answers. Code and identifiers in English.
- When reviewing the owner's code: point out the problem and the why, suggest a
  direction, don't rewrite the whole passage unless asked.
- At the end of each milestone, help draft the ADR — but the owner decides its
  content.
