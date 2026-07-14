# Contracts

Shared contracts между backend и iOS.

## Файлы

- `openapi.yaml` — HTTP API P0, source of truth для DTO и error semantics.
- `examples/` — versioned request/response fixtures для contract tests и iOS mocks.
- `telemetry.schema.json` — будет добавлен задачей TEL-01; до этого telemetry properties считаются draft.

## Правила изменений

1. Breaking change сначала оформляется решением `PROPOSED` в `docs/PROJECT_LEDGER.md`.
2. Codex отвечает за server feasibility и реализацию producer.
3. Antigravity отвечает за iOS decode/encode feasibility и реализацию consumer.
4. После двустороннего review решение получает статус `ACCEPTED`.
5. OpenAI provider payload не копируется в публичный app API; backend возвращает нормализованные DTO.

## Проверки

Минимальный gate перед merge:

```powershell
npx --yes @redocly/cli lint contracts/openapi.yaml
```

После появления backend должны добавиться generated-schema tests и fixture round-trip tests.
