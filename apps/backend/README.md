# Backend

Fastify + TypeScript service for the translator control plane. Media never passes through this service.

## Local run

From the repository root:

```powershell
pnpm install
$env:APP_TOKENS = "replace-with-a-random-prototype-app-token"
pnpm --filter @translator/backend dev
```

`GET /v1/health` is public and minimal. `GET /v1/config` requires `Authorization: Bearer <app-token>`, `X-App-Version`, and `X-App-Build`. Raw tokens are hashed on startup and are never retained by the verifier.

## Checks

```powershell
pnpm typecheck
pnpm test
pnpm build
```
