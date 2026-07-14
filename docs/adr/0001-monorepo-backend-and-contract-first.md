# ADR-0001: Monorepo, Fastify backend и contract-first интеграция

- Статус: PROPOSED
- Дата: 2026-07-14
- Владельцы: Codex; review — Antigravity
- Связанные задачи: ADR-01, API-01

## Контекст

За 30 календарных дней нужно собрать iOS-прототип синхронного RU ↔ EN перевода. iOS и backend разрабатываются параллельно двумя моделями. Главный интеграционный риск — расхождение DTO, retry/idempotency semantics и telemetry, а не вычислительная сложность backend.

Backend не находится в медиапути. Он регистрирует установку, возвращает remote config, создаёт app session и short-lived OpenAI translation secrets, контролирует лимиты, принимает техническую telemetry и feedback.

## Предлагаемое решение

1. Использовать один репозиторий с верхнеуровневой структурой:

   ```text
   apps/backend/       TypeScript backend
   apps/ios/           Swift/SwiftUI client
   contracts/          OpenAPI, JSON Schema, fixtures
   docs/adr/            Architecture Decision Records
   docs/               Общий project ledger и технические документы
   ```

2. Использовать `pnpm` workspaces для JavaScript/TypeScript частей. Xcode project остаётся нативным и не зависит от Node tooling при сборке приложения.
3. Выбрать Fastify как HTTP framework backend P0.
4. `contracts/openapi.yaml` является источником истины для HTTP DTO и error semantics.
5. Сначала принимаются OpenAPI и fixtures, затем параллельно реализуются backend producer и iOS consumer.
6. Provider-specific OpenAI payloads не становятся публичным контрактом приложения. Их переводит `OpenAISecretBroker`.

## Почему Fastify

- Малый bootstrap и низкая церемониальность подходят прототипу на 30 дней.
- Встроенная ориентация на JSON Schema упрощает runtime validation рядом с OpenAPI.
- `inject()` позволяет быстро писать HTTP contract tests без поднятия TCP-сервера.
- Плагины дают достаточные границы для auth, config, quotas, telemetry и provider adapters без обязательной сложной DI-системы.

## Почему не NestJS для P0

NestJS подходит большой команде и долгоживущему модульному сервису, но для текущего объёма увеличивает bootstrap, количество abstractions и стоимость изменения контрактов. Решение можно пересмотреть после M3, если backend начнёт включать несколько процессов, очереди или сложную организационную модель модулей.

## Backend boundaries

```text
HTTP routes
  -> application services
     -> domain policies
        -> ports: repositories, quota store, OpenAI secret broker, telemetry sink
           -> adapters: PostgreSQL, Redis/managed limiter, OpenAI HTTP, OpenTelemetry
```

Routes не содержат provider payload mapping или бизнес-правила. Standard OpenAI API key доступен только provider adapter через secret manager.

## Contract workflow

1. Codex изменяет OpenAPI и fixtures в отдельном commit.
2. Antigravity проверяет decode/encode feasibility на iOS.
3. До статуса `ACCEPTED` контракт считается draft и может использоваться только через versioned fixtures/mocks.
4. После `ACCEPTED` breaking change требует новой записи решения и изменения API version либо документированной совместимой миграции.
5. Provider endpoint, events и secret response повторно проверяются по официальной OpenAI документации перед реализацией secret broker и перед релизом.

## Security и privacy invariants

- Standard OpenAI API key никогда не возвращается мобильному клиенту.
- Short-lived secret помечается sensitive, не сохраняется в БД и не логируется.
- `OpenAI-Safety-Identifier` формируется backend как privacy-preserving hash внутреннего installation/user id.
- Raw audio и полный transcript запрещены в telemetry и собственном хранении P0.
- Backend возвращает клиенту собственные IDs и нормализованный error envelope; provider error body не прокидывается напрямую.

## Последствия

Положительные:

- iOS может генерировать DTO и mocks до готовности backend.
- Provider API можно менять внутри adapter без breaking change мобильного API.
- Contract tests становятся общей точкой интеграции.

Отрицательные:

- OpenAPI и отдельная telemetry schema требуют дисциплины синхронизации.
- Fastify не навязывает архитектуру; boundaries нужно поддерживать review и тестами.
- Один monorepo требует отдельных worktree и аккуратного merge shared-файлов.

## Критерии принятия

- Antigravity подтверждает, что OpenAPI DTO покрывают iOS flow без provider-specific assumptions.
- Согласованы `apps/backend`, `apps/ios`, `contracts`, `docs`.
- OpenAPI проходит lint и examples/schema validation.
- Нет возражений против Fastify для P0; если есть, они оформлены альтернативой с оценкой влияния на 30-дневный план.

## Проверенные внешние источники

Проверено 2026-07-14:

- [OpenAI Realtime translation guide](https://developers.openai.com/api/docs/guides/realtime-translation)
- [GPT-Realtime-Translate model](https://developers.openai.com/api/docs/models/gpt-realtime-translate)
- [OpenAI Realtime WebRTC guide](https://developers.openai.com/api/docs/guides/realtime-webrtc)
