# Backend

Fastify + TypeScript service for the translator control plane. Media never passes through this service.

## Local run

From the repository root:

```powershell
pnpm install
$env:APP_TOKENS = "replace-with-a-random-prototype-app-token"
$env:SAFETY_IDENTIFIER_SECRET = "replace-with-at-least-32-random-characters"
$env:OPENAI_API_KEY = "server-side-key-from-secret-manager"
pnpm --filter @translator/backend dev
```

`GET /v1/health` is public and minimal. `GET /v1/config` requires `Authorization: Bearer <app-token>`, `X-App-Version`, and `X-App-Build`. Raw tokens are hashed on startup and are never retained by the verifier.

`POST /v1/translation-sessions` validates the accepted OpenAPI request, enforces kill-switch and idempotency rules, and mints one or two short-lived translation secrets through OpenAI. The standard API key stays server-side. Provider error bodies, Authorization headers, client secrets, SDP, audio, and transcripts are not logged.

The current idempotency store is process-local and evicts responses when their provider credentials expire. Persistent cross-restart idempotency moves to the PostgreSQL-backed session task.

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
  -e APP_TOKENS="replace-with-a-random-prototype-app-token" `
  -e SAFETY_IDENTIFIER_SECRET="replace-with-at-least-32-random-characters" `
  -e OPENAI_API_KEY="server-side-key-from-secret-manager" `
  translator-backend:local
```

The image runs as the unprivileged `node` user and includes a health check for `GET /v1/health`.
