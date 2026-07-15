# Backend

Fastify + TypeScript service for the translator control plane. Media never passes through this service.

## Local run

From the repository root:

```powershell
pnpm install
$env:DATABASE_URL = "postgres://translator:password@127.0.0.1:5432/translator"
$env:SAFETY_IDENTIFIER_SECRET = "replace-with-at-least-32-random-characters"
$env:OPENAI_API_KEY = "server-side-key-from-secret-manager"
pnpm --filter @translator/backend dev
```

The service applies versioned PostgreSQL migrations under an advisory lock before it starts listening.

`POST /v1/installations` is public and registers or recovers an anonymous installation. It returns a high-entropy app token once; PostgreSQL stores only its SHA-256 hash. Re-registering the same `installationPublicId` rotates the token and invalidates the old token. Forbidden installations cannot rotate or authenticate.

`GET /v1/health` is public and minimal. `GET /v1/config` requires `Authorization: Bearer <app-token>`, `X-App-Version`, and `X-App-Build`. The safety identifier is stable across token rotation and is derived from the internal installation ID using the server-side safety secret.

`POST /v1/translation-sessions` validates the accepted OpenAPI request, enforces kill-switch and idempotency rules, and mints one or two short-lived translation secrets through OpenAI. The standard API key stays server-side. Provider error bodies, Authorization headers, client secrets, SDP, audio, and transcripts are not logged.

Translation-session ownership, current leg metadata, and create/recreate idempotency results are PostgreSQL-backed. Transactional locks coalesce the same idempotency key across processes, so a retry after restart or on another instance receives the committed result without minting another secret. Responses containing short-lived client credentials are stored only as AES-256-GCM ciphertext using a domain-separated key derived from `SAFETY_IDENTIFIER_SECRET`; expired session/idempotency rows are pruned opportunistically. Rotate that server secret only after previously encrypted replay windows have expired.

Before any OpenAI secret is minted, PostgreSQL atomically enforces per-installation limits for active translation legs, secret mints per rolling minute, and UTC-day reserved billable leg-minutes. Idempotent replays do not consume quota, and a broker failure rolls the reservation back with the surrounding transaction. Configure the server-side policy with `QUOTA_MAX_PARALLEL_LEGS` (default `2`), `QUOTA_SECRET_MINTS_PER_MINUTE` (default `8`), and `QUOTA_DAILY_LEG_MINUTES` (default `120`). A rejected operation returns the existing contract error `429 RATE_LIMITED` with a deterministic `retryAfterMs`; no quota fields are added to the public DTOs.

`POST /v1/translation-sessions/{sessionId}/complete` stores the first authenticated technical completion summary and returns that same completion on later retries. It remains available while the global kill switch is active, rejects foreign or unknown sessions with the same `404`, prevents further leg recreation, and immediately releases the completed session from the active-leg limit. Reserved daily leg-minutes are intentionally not refunded. Audio, transcript text, tokens, and client secrets are never accepted or persisted by this endpoint.

## Checks

```powershell
pnpm typecheck
pnpm test
pnpm build
```

## Production container

Build from the repository root so the workspace lockfile is available:

```powershell
docker build --file apps/backend/Dockerfile --tag translator-backend:local .
```

Runtime secrets are required when the container starts and are never copied into the image:

```powershell
docker run --rm -p 3000:3000 `
  -e DATABASE_URL="postgres://translator:password@host.docker.internal:5432/translator" `
  -e SAFETY_IDENTIFIER_SECRET="replace-with-at-least-32-random-characters" `
  -e OPENAI_API_KEY="server-side-key-from-secret-manager" `
  translator-backend:local
```

The image runs as the unprivileged `node` user and includes a health check for `GET /v1/health`.
