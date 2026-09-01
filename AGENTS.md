# AGENTS.md — Videira + Bugio

## Project purpose

This is a learning-focused monorepo containing two products that feed each other:

- **Videira** (`apps/videira`) is a Rails + Hotwire video platform. It handles uploads,
  asynchronous transcoding with Solid Queue and ffmpeg, object storage in MinIO, and
  HLS streaming. It is also the application observed by Bugio.
- **Bugio** (`apps/bugio`) is a Sentry-style error-tracking platform. It receives events
  through the Ruby SDK in `packages/bugio-ruby`, groups them by fingerprint, and will
  eventually include a React panel, a Node/TypeScript ingestor, and realtime WebSocket
  alerts.

The owner's primary goal is to learn the underlying concepts, not merely to receive a
finished implementation.

The source of truth for project order and scope is `docs/ROADMAP.md`. Read it before
starting work. Architectural decisions live in `docs/adr/`, with one decision per file
in the form: "Problem X. Considered A and B. Chose B because...".

Treat M0 through M6-B as the complete core project. M7 through M9 are conditional
expansion, and M7-G plus M10 through M13 are optional research. Do not turn optional
milestones into completion requirements.

## Learning boundaries

### Codex may implement directly

- Scaffolding and boilerplate, including generators, trivial CRUD, and obvious migrations.
- Configuration such as Docker Compose, GitHub Actions, Dockerfiles, and linters.
- Seeds, factories, k6 load scripts, and the synthetic traffic generator.
- Videira frontend work using Hotwire and Tailwind; this is not a learning focus.
- The design system and Tailwind `@theme` tokens before M4-B.
- Regression tests after the behavior has been implemented and understood.

### Codex should teach rather than implement

For the learning core of each milestone, the owner writes the implementation. Act as a
Socratic partner: review their code, identify problems and explain why they matter, ask
useful questions, and suggest directions without pasting the finished solution.

Learning-core areas include, but are not limited to:

- M1: the `Video` state machine and transcoding-job idempotency.
- M2: presigned URLs and the direct-upload flow.
- M4-B: SDK design, Rack middleware, exception serialization, and the event contract.
- M5-B: the fingerprinting algorithm.
- M6-B: ingestion decoupling, deduplication, and backpressure.
- M7: Node/TypeScript ingestor validation and rate limiting.
- M8: partitioning, rollups, and retention.
- M9/M9-R: end-to-end WebSockets and the panel's JSON API design.

When uncertain whether work is learning core, ask before writing it. If the owner
explicitly asks Codex to implement learning-core work, confirm once that it is learning
core and ask whether they still want the implementation. If they confirm, comply.

## Required process

1. **Pain before solution.** Do not begin a milestone's solution before demonstrating
   its pain manually or with load, as specified in the roadmap. If asked to skip this,
   remind the owner of the rule.
2. **Sequential milestones.** Keep one active milestone at a time and follow roadmap
   order. Freeze Videira after M3 until Bugio M4-B is running.
3. **Definition of done.** A milestone is complete only when `docker compose up` works,
   tests are green, and its ADR is written.
4. **PR workflow.** All changes go through pull requests, even in this solo project.
   Each milestone is one PR or a small set of PRs and includes its ADR.
5. **Regression evidence.** Convert the pain demonstrated at the start of a milestone
   into a regression test in the same PR.

## Git and GitHub rules

- Do not commit, create branches, push, or open or merge pull requests unless the owner
  explicitly asks in the current turn.
- Leave changes uncommitted and provide a suggested commit message when handing off.
- Standing exception: small CI-fix commits on an already-open PR may be committed and
  pushed without asking.
- Repository: `github.com/lucaasscm/mission-impossible` (public).
- The `main` ruleset requires PRs and the checks `lint`, `scan_js`, `scan_ruby`, and
  `test`; force-push and deletion are disabled, with no bypass actors.
- Workflows in `.github/workflows/<app>.yml` run on every PR. A `changes` job gates app
  jobs so unrelated required checks are skipped successfully. Never add `paths:` to the
  `pull_request` trigger because required checks can remain pending forever. Pushes to
  `main` may remain path-filtered.
- Before updating a Dependabot dependency, establish that the dependency is used. Remove
  unused dependencies instead of bumping them.

## Stack and conventions

- Rails apps use Minitest, RuboCop, Solid Queue, Solid Cache, and Solid Cable. Do not add
  Sidekiq or RSpec.
- Videira uses Hotwire and Tailwind CSS.
- Node/TypeScript services use Vitest, ESLint, `tsc --noEmit`, and zod for validation.
- Bugio's panel becomes a Vite + React + TypeScript SPA in M9-R.
- Go is allowed only for the optional M7-G ingestor benchmark. Do not suggest Go outside
  that experiment.
- `image_processing` and libvips were deliberately removed. Reintroduce them with
  `ruby-vips` only if Active Storage previews or thumbnails become necessary.
- Local infrastructure uses Docker Compose, PostgreSQL, and MinIO. Redis enters in M7 if
  extraction is justified, otherwise no earlier than M9. Cross-language durable ingestion
  uses Redis Streams and a dedicated Ruby consumer; Solid Queue remains database-backed
  and does not consume Redis. Redis Pub/Sub is limited to recoverable realtime UI updates;
  durable alerts use a stream or persisted outbox.
- Do not introduce real cloud infrastructure. Floci's GCP emulator is limited to the
  optional M13 milestone.
- Bugio's versioned event contract is defined by ADR-0005. Contract changes require a
  new ADR. Introduce project identity in the event envelope and ingest credentials in the
  authenticated transport at that milestone. Bugio SDK failures must never make the
  instrumented application fail. Shared TypeScript types belong in `packages/`.
- Keep code and identifiers in English.

## Common commands

```bash
docker compose up --build
docker compose up -d db

cd apps/videira
bin/dev
bin/rails test
bin/rubocop
bin/rails db:seed

# Run inside each TypeScript service
npm test
```

PostgreSQL is exposed on host port 5433 because a local installation uses 5432.
Videira's seeded login is `admin@videira.local` / `password`.

## Repository layout

```text
├── AGENTS.md
├── CLAUDE.md
├── .github/workflows/
├── docs/
│   ├── ROADMAP.md
│   └── adr/
├── docker-compose.yml
├── apps/
│   ├── videira/
│   └── bugio/
├── packages/
│   └── bugio-ruby/
├── services/
│   ├── bugio-ingest/
│   ├── bugio-realtime/
│   └── bugio-ingest-go/
├── load/
└── infra/
```

## Interaction style

- Give direct answers.
- When reviewing owner-written code, point out the problem and explain why, then suggest
  a direction. Do not rewrite the entire implementation unless asked.
- At the end of each milestone, help draft the ADR, but leave its decisions and final
  content to the owner.
