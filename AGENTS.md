## Project Settings

- **Ticket Provider**: GitHub Issues
- **Branch Format**: `<type>/<ticket-number>` (e.g., `feature/123`)
- **Main Branch**: `main`

## Project Overview

UN17 Village Rooftop Gardens — bilingual (Danish/English) registration platform for two rooftop greenhouses (Kronen, Søen) with a 29-box catalog. Public users register without auth; admins use email/password.

Primary references:

- `docs/specs/greenspace-2026-spec.md` — product spec (single source of truth for requirements)
- `docs/architecture.md` — system architecture with diagrams
- `docs/api/openapi.yaml` — API contract
- `docs/data/schema.md` — data contract and invariants

Working agreement: contract-first changes. Update spec/ADR/API/data contract first, then implementation, then tests.

## Repository Layout

npm workspaces monorepo:

- `apps/api` (`@greenspace/api`) — Node 20 / TypeScript backend. Runs as both an AWS Lambda (`src/lambda.ts`) and a local HTTP dev server (`src/dev-server.ts`) wrapping the same `handler` from `src/index.ts`.
- `apps/web` (`@greenspace/web`) — Next.js 15 / React 19 frontend (App Router, inline styles, no CSS framework).
- `packages/shared` (`@greenspace/shared`) — Domain constants, types, validators, DAWA helpers, i18n key contracts. Imported as source (no build step required for consumers; `transpilePackages` is set in `next.config.js`).
- `infra/terraform` — AWS infrastructure (VPC, Lambda, RDS, SES, Amplify, monitoring) split into `bootstrap/`, `environments/{staging,prod}/`, and `modules/greenspace_stack/`.

## Commands

Root (runs against all workspaces via `--if-present`):

```
npm test          # vitest run in each workspace
npm run lint      # eslint
npm run build     # tsc / next build
npm run typecheck # tsc --noEmit
```

Per-workspace (use `--workspace=@greenspace/<name>` from root, or `cd` into the dir):

```
# apps/api
npm run dev --workspace=@greenspace/api       # tsx watch on port 3001
npm run db:setup --workspace=@greenspace/api  # migrate + seed (needs DB_PASSWORD)
npm run bundle --workspace=@greenspace/api    # esbuild → dist/lambda/index.mjs (Lambda artifact)
npm run test --workspace=@greenspace/api -- <pattern>   # single vitest file/pattern

# apps/web
npm run dev --workspace=@greenspace/web       # next dev on port 3000
```

The web dev server proxies `/public/*`, `/admin/*`, and `/health` to `API_URL` (default `http://localhost:3001`) via `next.config.js` rewrites — start the API before exercising any network paths from the UI.

Local DB bootstrap (Postgres 16 required):

```
docker run -d --name greenspace-db -e POSTGRES_DB=greenspace -e POSTGRES_USER=greenspace -e POSTGRES_PASSWORD=localdev -p 5432:5432 postgres:16
DB_PASSWORD=localdev npm run db:setup --workspace=@greenspace/api
DB_PASSWORD=localdev npm run dev --workspace=@greenspace/api
```

Seed admin password defaults to `changeme123` (override with `SEED_ADMIN_PASSWORD`).

## Architecture Notes

### Backend HTTP layer

Custom router (`apps/api/src/router.ts`) — not Express/Fastify. `Router` exposes `get/post/patch/delete(path, handler)` and matches `:param` segments. Add new endpoints by:

1. Writing a handler `(ctx: RequestContext) => Promise<RouteResponse>` in `src/routes/...`.
2. Registering it in `createRouter()` in `src/index.ts`.
3. Wrapping with `requireAdmin(...)` from `src/middleware/auth.ts` for admin endpoints.

`apps/api/src/index.ts#handler` is the single entry point. It dispatches three event shapes: HTTP requests, EventBridge `Scheduled Event` (hourly session cleanup), and `{action: "migrate"}` (one-shot migrate+seed). The `dev-server.ts` and `lambda.ts` files just adapt their respective transports onto this handler.

DB connection is lazily initialized once per Lambda container (`db` singleton in `index.ts`). In deployed environments it loads `host`, `port`, `dbname`, `username`, and `password` from the shared-db Secrets Manager secret pointed at by `DB_SECRET_ID` (e.g. `rds/shared/greenspace_staging`). For local dev, when `DB_SECRET_ID` is unset, it falls back to the individual `DB_HOST`/`DB_PORT`/`DB_NAME`/`DB_USER`/`DB_PASSWORD` env vars.

Staging-only routes (`/admin/staging/*`) are gated by `process.env.ENVIRONMENT === "staging"` — keep destructive helpers behind this guard.

### Database

Kysely query builder over Postgres 16. Migrations live in `apps/api/src/db/migrations/` and are also registered in `migration-registry.ts` (the inline registry is what runs in Lambda — adding a migration file is not enough, you must also add it to the registry). Schema types in `src/db/types.ts` must match the migration shape.

Critical invariants enforced at the DB level (don't replicate in app code, don't bypass):

- One active registration per apartment_key (partial unique index where `status = 'active'`).
- One active occupant per box (partial unique index where `status = 'active'`).
- `audit_events` is append-only — a trigger blocks UPDATE/DELETE.
- Box `state` is `available | occupied | reserved`.

### Time / registration gate (server-authoritative)

The server clock (`Date.now()`) is the only source of truth for whether registration is open. `GET /public/status` returns `isOpen` + `serverTime`; `POST /public/register` re-checks the gate independently. The frontend never trusts the client clock — when API is unreachable it defaults to pre-open (deny). Opening time is stored as `timestamptz` UTC; display uses `Europe/Copenhagen` via `OPENING_TIMEZONE` from `@greenspace/shared`.

### Frontend

State-driven view routing (no URL routes for public flow): `apps/web/src/app/page.tsx` switches between `PreOpenPage` / `LandingPage` / `GreenhouseMapPage` based on local state and `/public/status`. Admin views live under components with `/admin` paths.

i18n via React context (`src/i18n/LanguageProvider.tsx`); language detected from `navigator.language`, manually overridable. Translation keys are contracted in `@greenspace/shared/i18n.ts`; strings live in `apps/web/src/i18n/translations.ts`.

Inline styles only — no Tailwind, no CSS modules. Shared visual constants (e.g. `boxStateColors.ts`) are colocated in `components/`.

### Shared package

`packages/shared` is consumed as source (`main` and `types` point at `src/index.ts`). No need to rebuild after editing — just save and the consumer picks it up. When adding exports, add them to `src/index.ts` and consider whether `index.test.ts`'s export-completeness check needs updating.

### Infra & deploy

- `deploy.yml` triggers on `apps/api/**` or `packages/shared/**` changes to main: bundles via esbuild, deploys to staging Lambda, smoke-tests `/health`, then promotes to prod (gated by GitHub `production` environment protection).
- `terraform.yml` triggers on `infra/terraform/**`; staging applies first, prod after.
- `deploy-web.yml` handles the Amplify-hosted Next.js app.
- `drift-detection.yml` runs daily and opens a GitHub issue if `terraform plan` shows drift.
- All AWS auth uses GitHub OIDC role assumption — no long-lived keys.

## Testing

Vitest in all workspaces. `apps/web` uses `@testing-library/react` + jsdom; `apps/api` runs node-side tests against in-memory or test fixtures (no shared test DB harness — most route tests stub Kysely or use unit-level helpers). Place tests next to the file they cover (`foo.ts` ↔ `foo.test.ts`).
