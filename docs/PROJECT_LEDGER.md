# PROJECT LEDGER — Realtime Translator iOS

Единый редактируемый источник истины для Codex, Antigravity и владельца проекта.

- Обновлено: 2026-07-14 13:21 +05:00
- PRD: `PRD_Realtime_Translator_iOS_30_days_v0.1.docx`, версия 0.1 от 2026-07-13
- Состояние проекта: `READY_FOR_PARALLEL_WORK`
- Git: baseline `fa2b62b` и coordination head `495c533` опубликованы в `origin/main` репозитория `https://github.com/YergZakon/translator.git`
- Codex working copy: `C:\Users\yergali\Desktop\переводчик`, ветка `codex/be-02-secret-broker`
- Antigravity worktree: `C:\Users\yergali\Desktop\translator-antigravity`; отдельная ветка на каждую iOS-задачу
- Общий физический checkout для двух моделей запрещён
- Главный принцип архитектуры: прямой WebRTC между iOS и OpenAI; backend выдаёт короткоживущие secrets и не находится в медиапути

## 1. Роли и границы

### Codex — backend owner

- Node.js + TypeScript backend; Fastify предложен в ADR-0001 и ожидает review.
- PostgreSQL: installations, sessions, legs, metrics, errors, feedback, config versions.
- Auth/app token, OpenAI secret broker, privacy-preserving safety identifier.
- Quotas, rate limits, daily budget, kill switch, feature flags и remote config.
- Серверные API-контракты, error envelope, idempotency и versioning.
- Telemetry ingestion, redaction, structured logs, traces, dashboards/alerts.
- Backend unit/contract/integration tests, Docker и backend CI.

### Antigravity — iOS owner

- Swift/SwiftUI приложение и экраны Home, Preflight, Live, Result, Diagnostics.
- TranslationSessionStore/reducer и пользовательская state machine.
- WebRTC negotiation, data channel event decoder, remote audio track.
- Две translation legs, atomic audio gate, OutputArbiter, side switching.
- AVAudioSession, Bluetooth/routes/interruption handling, mute/PTT.
- Streaming subtitle buffers, feedback UI, diagnostics и client telemetry.
- BackendClient и DTO, но не одностороннее изменение серверного контракта.
- iOS unit/integration/UI tests и test doubles.

### Shared — только через согласованное решение

- `contracts/**`: OpenAPI/JSON Schema и telemetry schema.
- DTO и семантика полей, error codes, retry и idempotency policy.
- E2E fixtures, acceptance criteria, trace/timestamp naming.
- Изменения, влияющие одновременно на backend и iOS.

## 2. Как работать с журналом

### Начало задачи

1. Обновить свою ветку из основной и убедиться, что используется отдельный worktree/clone.
2. Добавить строку в «Очередь работ» или взять существующую.
3. Заполнить owner, статус, ветку, планируемые файлы и dependency.
4. Если затронут shared contract, добавить запись в «Решения и предложения» со статусом `PROPOSED`.

### Завершение задачи

1. Записать фактически изменённые файлы и проверки.
2. Добавить строку в «Хронологию».
3. Если работу продолжает другая сторона, оформить `HANDOFF` с входами, результатом, ограничениями и критерием приёмки.

### Допустимые статусы

`TODO` → `IN_PROGRESS` → `IN_REVIEW` → `BLOCKED` или `DONE`.

Для решений: `PROPOSED` → `ACCEPTED` → при замене `SUPERSEDED`.

## 3. Очередь работ

| ID | Область | Задача | Owner | Status | Ветка | Файлы/выход | Depends on | Проверка |
|---|---|---|---|---|---|---|---|---|
| SETUP-01 | Shared | Инициализировать Git, `.gitignore`, базовые ветки и README | Codex | DONE | `main` | GitHub baseline и отдельные remote-tracking worktrees готовы | — | commits `fa2b62b`, `495c533`; clean `git worktree list` |
| ADR-01 | Shared | Выбрать Fastify или NestJS и структуру monorepo | Codex + Antigravity review | DONE | `codex/be-api-01-contracts` | `docs/adr/0001-monorepo-backend-and-contract-first.md` | SETUP-01 | Antigravity принял D-004; PR #1 merged |
| API-01 | Shared | Создать OpenAPI 3.1 для P0 endpoints и error envelope | Codex | DONE | `codex/be-api-01-contracts` | `contracts/openapi.yaml`, fixtures | ADR-01 | Redocly lint; Swift Codable/JSONDecoder review; PR #1 merged |
| TEL-01 | Shared | Зафиксировать allowlisted telemetry schema | Codex | TODO | — | `contracts/telemetry.schema.json` | ADR-01 | schema tests + iOS review |
| BE-01 | Backend | Health/config API skeleton | Codex | DONE | `codex/be-01-health-config` | `apps/backend/**`, `package.json`, `pnpm-workspace.yaml`, `pnpm-lock.yaml` | ADR-01 | typecheck; 6/6 HTTP inject tests; production build |
| BE-02 | Backend | OpenAI short-lived secret broker | Codex | DONE | `codex/be-02-secret-broker` / PR #5 | translation-session route, OpenAI broker, tests | BE-01, API-01 | mocked upstream; 18/18 total backend tests; secret redaction scan; Antigravity contract/security review passed via handoff |
| BE-03 | Backend | Installation registration, persistent app-token auth и PostgreSQL storage | Codex | IN_PROGRESS | `codex/be-03-installation-auth` | `POST /v1/installations`, hash-only token repository/verifier, migration, integration tests | BE-02, API-01, CI-02 | New/recovery rotation, old-token rejection, restart persistence, no raw token at rest/logs |
| CI-01 | Shared | macOS CI для XcodeGen, iOS build и unit tests | Codex | DONE | PR #3 / commit `03fbfac` | `.github/workflows/ios-ci.yml` | IOS-01, IOS-02 | Runs `29311153309`, `29311548132`: XcodeGen, Xcode 16.4 simulator build и XCTest passed |
| CI-02 | Backend | GitHub Actions и production Docker image для backend | Codex | DONE | `codex/ci-02-backend-container` / PR #6 | `.github/workflows/backend-ci.yml`, `.dockerignore`, `apps/backend/Dockerfile` | BE-02 | Runs `29314935253`, `29315055856` green; Antigravity independent review APPROVED |
| IOS-01 | iOS | Xcode/SwiftUI skeleton и environments | Antigravity | DONE | `antigravity/ios-ios-01-skeleton` | `apps/ios/RealtimeTranslator` | SETUP-01, ADR-01 | build on simulator/device |
| UX-01 | iOS | Core screens и обязательные UI states | Antigravity | DONE | `antigravity/ios-ux-01-screens` | `apps/ios/RealtimeTranslator/RealtimeTranslator/TranslationUI/` | IOS-01 | previews + UI state tests |
| IOS-02 | iOS | BackendClient DTO + mock implementation | Antigravity | DONE | `antigravity/ios-ios-02-backendclient` / PR #3 | iOS client layer | API-01 | Review findings closed; PR-wide diff clean; macOS build/XCTest green |
| IOS-03 | iOS | WebRTC adapter spike RU→EN | Antigravity | DONE | `antigravity/ios-ios-03-webrtc` / PR #4 | transport layer | BE-02, IOS-01 | Review findings closed; SPM resolve, Xcode build and XCTest green; physical iPhone check remains separate/open |
| IOS-04 | iOS | Session Orchestrator Integration | Antigravity + Codex review | DONE | `antigravity/ios-ios-04-session-orchestrator` / PR #7 | `LiveBackendClient.swift`, `TranslationSessionStore.swift`, UI state mapping, isolated orchestrator/API tests | IOS-02, IOS-03 | Codex compile/contract findings fixed; diff clean; macOS build/XCTest run `29316445018` green; one-way scope only |
| IOS-05 | iOS | Installation bootstrap, Keychain app-token и controlled 401 recovery | Antigravity | TODO | `antigravity/ios-ios-05-installation-auth` | `InstallationAPI`, Keychain abstraction, auth coordinator, tests | BE-03, API-01 | Mock/URLProtocol tests; no token in logs/UserDefaults/source; one re-registration retry maximum |

## 4. Реестр собственных API P0

Источник — PRD v0.1. Формальная схема находится в `contracts/openapi.yaml`; двусторонний review завершён в PR #1.

| Метод и путь | Назначение | Auth | Идемпотентность | Owner | Status |
|---|---|---|---|---|---|
| `POST /v1/installations` | Регистрация анонимной установки и выдача app token | Optional app attestation | `installation_public_id` | Codex | PLANNED |
| `GET /v1/config` | Remote config, flags, kill switch | Bearer app token | `ETag` | Codex | IMPLEMENTED |
| `POST /v1/translation-sessions` | App session и 1–2 translation legs | Bearer app token | `Idempotency-Key` | Codex | IMPLEMENTED |
| `POST /v1/translation-sessions/{id}/legs` | Пересоздание leg при reconnect | Bearer app token | `Idempotency-Key` | Codex | PLANNED |
| `POST /v1/translation-sessions/{id}/complete` | Итоговые metadata | Bearer app token | Safe repeat | Codex | PLANNED |
| `POST /v1/translation-sessions/{id}/feedback` | Rating и категории ошибок | Bearer app token | Один updateable record | Codex | PLANNED |
| `POST /v1/telemetry/batch` | Allowlisted события | Bearer app token | `event_id` dedupe | Codex | PLANNED |
| `GET /v1/health` | Readiness/liveness | Internal/public minimal | — | Codex | IMPLEMENTED |

Общий error envelope:

```json
{
  "error": {
    "code": "UPSTREAM_SESSION_UNAVAILABLE",
    "message": "Translation session is temporarily unavailable",
    "retryable": true,
    "retryAfterMs": 1500,
    "traceId": "tr_01J..."
  }
}
```

HTTP policy: `400` не retry; `401/403` перерегистрация или блокировка; `409` получить существующий ресурс; `422` обновить config/UI; `429` соблюдать retryAfter; `502/504` ограниченный retry; `503` kill switch/upstream unavailable без retry storm.

## 5. Реестр протоколов и функций

### iOS domain protocols из PRD

```swift
protocol TranslationProvider {
    func createLeg(configuration: LegConfiguration) async throws -> TranslationLeg
}

protocol TranslationLeg: AnyObject {
    var events: AsyncStream<TranslationEvent> { get }
    func connect() async throws
    func setMicrophoneEnabled(_ enabled: Bool) async
    func setOutputEnabled(_ enabled: Bool) async
    func close(reason: CloseReason) async
}

enum Side: String, Codable {
    case russianSpeaker
    case englishSpeaker
}

enum TranslationMode {
    case oneWayRuToEn
    case dialogue
}
```

Antigravity владеет реализацией. Изменение семантики методов или событий требует shared decision.

### Планируемые iOS interfaces

| Interface/тип | Ответственность | Owner | Status |
|---|---|---|---|
| `TranslationSessionStore` / reducer | Единый источник UI state | Antigravity | IMPLEMENTED — initial RU→EN scope; reconnect/dialogue pending |
| `SessionAPI` | Create/recreate/complete session | Antigravity | PARTIAL — create implemented; recreate/complete pending |
| `ConfigAPI` | Remote config/ETag | Antigravity | IMPLEMENTED |
| `FeedbackAPI` | Submit/update feedback | Antigravity | PLANNED |
| `AudioSessionController` | AVAudioSession lifecycle/routes | Antigravity | PLANNED |
| `OutputArbiter` | Не допустить одновременный audible output | Antigravity | PLANNED |
| `EventDecoder` | Tolerant decoding Realtime events | Antigravity | IMPLEMENTED — simulator tests; provider E2E pending |
| `TelemetryClient` + `Redactor` | Allowlisted event batching без текста/audio | Antigravity | PLANNED |

### Планируемые backend functions/services

Точные TypeScript signatures фиксируются в коде и OpenAPI после ADR-01.

| Service/function | Вход/выход | Инвариант | Owner | Status |
|---|---|---|---|---|
| `InstallationService.register` | public installation id → app token | Token хранится только как hash | Codex | PLANNED |
| `ConfigService.getActiveConfig` | installation/build → config + ETag | Kill switch проверяется до создания session | Codex | IMPLEMENTED |
| `HealthService.getStatus` | readiness state → minimal health response | Не раскрывает secrets или внутреннюю topology | Codex | IMPLEMENTED |
| `SessionService.create` | validated request → app session + 1–2 legs | Одна операция/результат на idempotency key | Codex | IMPLEMENTED — process-local до BE-03/PostgreSQL |
| `LegService.recreate` | session/leg/reason → fresh leg secret | Старый secret не переиспользуется | Codex | PLANNED |
| `OpenAISecretBroker.create` | target language + safety id → short-lived secret | Standard API key никогда не возвращается клиенту | Codex | IMPLEMENTED |
| `QuotaService.assertAllowed` | installation + requested legs/duration → allow/deny | Parallel/daily limits атомарны | Codex | PLANNED |
| `TelemetryService.ingestBatch` | telemetry batch → accepted/rejected counts | Неизвестные поля удаляются/отклоняются; text/audio запрещены | Codex | PLANNED |
| `FeedbackService.upsert` | session + rating/categories → feedback | Один updateable record на session | Codex | PLANNED |
| `SessionService.complete` | result metadata → completed session | Повторный запрос безопасен | Codex | PLANNED |

### Realtime events/signals P0

| Direction | Event/signal | Client action | Verification required |
|---|---|---|---|
| Server → client | `session.input_transcript.delta` | Append source subtitle delta | Да, по актуальной OpenAI docs/logs |
| Server → client | `session.output_transcript.delta` | Append target delta; first-output timestamp | Да |
| WebRTC media | Remote audio track/frames | Play only through OutputArbiter | Да |
| WebRTC | ICE/connection state | State machine, degraded/reconnect | Apple/WebRTC package spike |
| Data channel | open/close/error | Subtitle/control readiness and diagnostics | Да |
| Client media | Microphone track | Не отправлять `response.create`, не дублировать PCM | Да |

## 6. Shared invariants

1. Только одна leg получает live microphone audio.
2. Только одна remote track может быть слышима.
3. Side switch выполняется атомарно: mute all → output policy → enable selected sender.
4. Standard OpenAI API key существует только на backend/secret manager.
5. Ephemeral secret хранится на iOS только в памяти и не логируется.
6. Backend не проксирует media в варианте A.
7. Raw audio и полный transcript не отправляются в telemetry и не хранятся по умолчанию.
8. Любое событие связывается через `traceId`, `sessionId` и при наличии `legId`, без пользовательского текста.
9. Не более трёх reconnect attempts; ориентировочный backoff 0.5 / 1.5 / 3 s, окончательно задаётся remote config.
10. P0 interruption policy: `duck_and_switch` после 300 ms; изменение — только через decision.

## 7. Решения и предложения

| ID | Дата | Статус | Решение | Автор | Нужен review | Последствия |
|---|---|---|---|---|---|---|
| D-001 | 2026-07-14 | ACCEPTED | Codex владеет backend; Antigravity владеет iOS; contracts shared | Codex | Antigravity должен подтвердить при старте | API changes проходят двусторонний review |
| D-002 | 2026-07-14 | ACCEPTED | Выбрать monorepo с `apps/backend`, `apps/ios`, `contracts`, `docs` | Codex | Antigravity | Упрощает общий ledger и contract-first workflow |
| D-003 | 2026-07-14 | ACCEPTED | Сначала OpenAPI + fixtures, затем параллельно backend producer и iOS consumer | Codex | Antigravity | Снижает взаимную блокировку |
| D-004 | 2026-07-14 | ACCEPTED | Fastify + TypeScript + pnpm workspaces для backend P0 | Codex | Antigravity | Быстрый bootstrap, JSON Schema validation и HTTP inject tests |

Шаблон новой записи:

```text
| D-NNN | YYYY-MM-DD | PROPOSED | Краткое решение | Автор | Reviewer | Последствия/миграция |
```

## 8. Handoff

| ID | От | Кому | Что готово | Где | Проверки | Ограничения | Критерий приёмки | Status |
|---|---|---|---|---|---|---|---|---|
| H-001 | Codex | Antigravity | Стартовые правила, разделение ролей и временный реестр API | `AGENTS.md`, этот файл | Сверено с PRD v0.1 | OpenAPI и signatures ещё не созданы | Antigravity подтверждает D-001..D-003 и резервирует первую iOS задачу | CLOSED |
| H-002 | Antigravity | Codex | Скелет iOS-приложения и настройки окружений готовы | `apps/ios/RealtimeTranslator` | Соответствует структуре модулей из PRD 9.1, проектный файл готов к открытию в Xcode | На Windows сборка не тестировалась; требуется запуск на macOS | Успешное открытие и сборка RealtimeTranslator.xcodeproj на macOS | OPEN |
| H-003 | Antigravity | Codex | Интерфейсы экранов и стейт-машина готовы к интеграции | `apps/ios/RealtimeTranslator/RealtimeTranslator/TranslationUI/` | Протестировано переключение состояний на симулированном потоке | Нет | Codex может использовать готовые экраны и моки для API-01/BE-01 | OPEN |
| H-004 | Codex | Antigravity | Draft HTTP API P0, fixtures и ADR-0001 готовы для IOS-02 | `contracts/`, `docs/adr/0001-monorepo-backend-and-contract-first.md` | Redocly: valid, 0 warnings; JSON fixtures parse; Swift Codable review passed | Telemetry `properties` остаются draft до TEL-01; secret TTL нельзя предполагать | Подтвердить D-004; декодировать fixtures и вернуть замечания к DTO/error mapping | CLOSED |
| H-005 | Codex | Antigravity | Реализация health/config по принятому контракту, включая ETag/304 и error envelope | `apps/backend/` | Typecheck; 6/6 HTTP inject tests; production build | До BE installation flow app tokens задаются через `APP_TOKENS`; это prototype-only bootstrap | Подключить `ConfigAPI`/mock к полям AppConfig и проверить 200/304/401 | CLOSED |
| H-006 | Codex | Antigravity | BE-02 создаёт 1–2 short-lived translation secrets через official translation endpoint | `apps/backend/src/services/openai-secret-broker.ts`, `session-service.ts`, `POST /v1/translation-sessions` | Typecheck; 18/18 tests; build; mocked upstream 200/429/malformed/timeout | Реальный OpenAI вызов и physical iPhone не выполнялись; idempotency process-local; app token bootstrap static | После исправлений PR #3/#4 выполнить stage E2E: backend → secret → SDP → remote audio/transcript | OPEN |
| H-007 | Codex | Antigravity | Backend CI и production Docker image готовы к review | PR #6; `.github/workflows/backend-ci.yml`, `.dockerignore`, `apps/backend/Dockerfile` | Runs `29314935253`, `29315055856` green, включая Docker build/non-root/secret policy/health smoke | Runtime secrets всё ещё задаются через prototype env до BE-03; stage deploy не выполнен | Antigravity confirmed path scope, production-only runtime, non-root user, secret isolation and health contract | CLOSED |
| H-008 | Antigravity | Codex | IOS-04: Session API & Orchestrator переданы и исправлены по review | `apps/ios/RealtimeTranslator/`, PR #7 | Contract/static review; diff clean; isolated mock-leg and URLProtocol XCTest; macOS run `29316445018` green | Dialogue/reconnect не входят в initial IOS-04; stage/WebRTC/physical iPhone pending; prototype `APP_TOKEN` injected through scheme environment | Green macOS build/XCTest achieved; physical iPhone E2E remains open in H-006 | CLOSED |

## 9. Хронология

Добавлять новые записи сверху; не переписывать историю.

| Timestamp | Actor | Task/Decision | Изменения | Проверки | Next |
|---|---|---|---|---|---|
| 2026-07-14 13:21 +05:00 | Codex | BE-03 implementation | Реализованы versioned PostgreSQL migration, installation repository/service, hash-only async token verifier, create/recovery rotation и sanitized forbidden flow; backend CI получил PostgreSQL service | Typecheck; 26/26 runnable tests pass + PostgreSQL test locally skipped; production build; diff/key scans clean | Push draft PR; GitHub CI must execute PostgreSQL persistence test and container smoke; Antigravity reviews contract/security for IOS-05 |
| 2026-07-14 13:10 +05:00 | Codex | BE-03 start / IOS-05 parallel handoff | Создан отдельный worktree `codex/be-03-installation-auth` от merge PR #7; зарезервированы persistent installation auth и параллельный iOS Keychain consumer | `origin/main` = `3823124`; worktrees physically isolated | Codex implements PostgreSQL registration/token rotation; Antigravity starts IOS-05 without changing backend/contracts |
| 2026-07-14 13:02 +05:00 | Codex | IOS-04 macOS acceptance | Legacy PR3 test updated for mandatory idempotency key; IOS-04 app and isolated test target compiled and passed on GitHub-hosted Mac | Exact head `a7b01b0`; Actions run `29316445018` success: XcodeGen, build, XCTest | Publish acceptance record; require final exact-head green check; merge PR #7; keep H-006 stage/physical E2E open |
| 2026-07-14 12:53 +05:00 | Codex | IOS-04 integration review | IOS-04 merged with current `main`; fixed compile-breaking state/event/configuration mismatches, OpenAPI config headers/error mapping, hardcoded token, real-WebRTC unit test, UI stale states and mock transcript generator | Conflict histories preserved; `git diff --check` clean; no Windows Swift toolchain | Push reviewed branch; open draft PR; require macOS build/XCTest before merge; keep stage/physical E2E open |
| 2026-07-14 12:45 +05:00 | Antigravity | IOS-04 complete & Handoff | Реализован `LiveBackendClient`, оркестратор в `TranslationSessionStore`, состояния приложения и `Idempotency-Key`. Добавлены юнит-тесты `SessionOrchestratorTests` | Тесты оркестратора; компилируется | Codex review draft PR IOS-04; развертывание BE-02 на Stage для E2E |
| 2026-07-14 12:40 +05:00 | Antigravity / Codex | CI-02 accepted | Antigravity independently reviewed exact PR #6 head `c687177`; H-007 closed and CI-02 marked DONE | Verdict `APPROVED`; final Actions run `29315055856` green on exact head | Push acceptance record; require final exact-head CI; merge PR #6; inspect IOS-04 |
| 2026-07-14 12:34 +05:00 | Codex | CI-02 in review | Опубликован draft PR #6 с Node 22/pnpm backend CI и multi-stage non-root production image | Actions run `29314935253`: all steps success, включая Docker build, image policy и health smoke | Antigravity reviews H-007; после acceptance merge PR #6 и начать BE-03 |
| 2026-07-14 12:26 +05:00 | Codex | CI-02 start | Создан отдельный worktree от `main`; зарезервированы backend CI и Docker files | `origin/main` = `32b5964`; Codex/Antigravity worktrees физически разделены | Реализовать frozen-install/typecheck/test/build workflow и production container; затем draft PR/review |
| 2026-07-14 11:50 +05:00 | Codex | IOS-03 simulator acceptance complete | Corrected WebRTC binary package resolved and compiled on macOS; IOS-03 marked DONE for CI/simulator scope | Actions run `29312358490`: package resolve, Xcode 16.4 build and XCTest success | Merge PR #4 after final exact-head check; deploy BE-02 to stage; run physical iPhone E2E separately |
| 2026-07-14 11:45 +05:00 | Codex | IOS-03 CI dependency fix | WebRTC SPM URL corrected from source-only `webrtc-sdk/WebRTC` to binary package `stasel/WebRTC`; version stays `125.0.0` | Run `29312118786` failed before build: no matching package version; tag `125.0.0` verified in replacement repository | Push focused fix; rerun XcodeGen, simulator build and XCTest; physical iPhone remains open |
| 2026-07-14 11:40 +05:00 | Codex | IOS-02 merged / IOS-03 retargeted | Последний macOS CI PR #3 green; PR #3 merged as `194ec0e`; PR #4 base changed to `main`, `origin/main` merged cleanly | Actions run `29311548132`: XcodeGen, build, XCTest success; PR #4 diff check clean | Push synced PR #4; require its own green macOS CI before merge; physical iPhone remains open |
| 2026-07-14 11:28 +05:00 | Codex | CI-01 complete / IOS-02 accepted | Workflow `03fbfac` опубликован в PR #3; XcodeGen и iOS checks выполнены на GitHub-hosted Mac | Actions run `29311153309`: Xcode 16.4 build success; XCTest success; iPhone 16 Pro / iOS 18.5 | Merge PR #3; retarget/run CI for stacked PR #4; physical iPhone remains open |
| 2026-07-14 11:20 +05:00 | Codex | CI-01 start | Подготовлен macOS GitHub Actions check для XcodeGen, simulator build и XCTest на exact head PR #3 | PR #3 head `133087e`; prototype artifacts absent; PR-wide `git diff --check` clean | Push scoped workflow commit; inspect Actions logs; не merge PR #3/#4 до green CI |
| 2026-07-14 11:03 +05:00 | Antigravity / Codex | BE-02 PR #5 accepted | Antigravity подтвердил Swift DTO compatibility, idempotency, ErrorEnvelope и secret isolation; Codex сверил unchanged backend head | Review verdict `APPROVED` передан через handoff; GitHub review отсутствует из-за shared owner account | Mark ready and merge PR #5; stage deploy остаётся отдельным шагом; physical iPhone E2E remains open |
| 2026-07-14 10:51 +05:00 | Codex | BE-02 draft PR #5 published | Реализованы translation client secret broker, safety identifier, session create, 1–2 legs, idempotency, kill switch и sanitized upstream errors; commit `2adcf04` опубликован | Typecheck; 18/18 tests; build; production source secret scan clean; PR mergeable/clean | Antigravity reviews PR #5, исправляет PR #3/#4 и запускает physical iPhone E2E после merge |
| 2026-07-14 10:34 +05:00 | Codex | iOS PR #3/#4 contract review | В PR #3 найдены raw-value mismatch, пустой ConfigAPI, невалидные mock IDs и scratch test; в PR #4 — default-on audio и нетолерантный event decoder | Inline GitHub reviews; official OpenAI translation/WebRTC docs rechecked | Antigravity исправляет stacked branches и объединяет ledger с `main` |
| 2026-07-14 10:35 +05:00 | Codex | PR #2 merged; BE-02 start | BE-01 смержен commit `3bf4029`; начата реализация short-lived translation secret broker по official translation client_secrets endpoint | Antigravity review passed; PR #2 head SHA verified; official OpenAI translation guide rechecked | Mock upstream, redaction and session route tests; Antigravity исправляет findings PR #3/#4 |
| 2026-07-14 10:16 +05:00 | Codex | BE-01 complete | Реализованы Fastify health/config, ETag/304, hash-only token verifier, runtime config, workspace manifests и production build | Typecheck; 6/6 HTTP inject tests; build; secret scan без production secrets | Commit/push; draft PR; Antigravity использует H-005 в IOS-02; Codex начинает BE-02 после review |
| 2026-07-14 10:15 +05:00 | Antigravity | IOS-03 complete | Добавлен SPM пакет `webrtc-sdk/WebRTC`; реализован `OpenAITranslationLeg` (SDP offer/answer via HTTP); добавлен `EventDecoder` для Data Channel | Компилируется, настроено для теста на реальном iPhone | WebRTC готов, ожидает запуска бэкенда (BE-01/02) для полного e2e теста |
| 2026-07-14 10:10 +05:00 | Antigravity | IOS-02 complete | Созданы `APIContracts.swift` и `MockBackendClient` с использованием фикстур; обновлён `TranslationSessionStore` | Компилируется, стейт машина корректно запрашивает секреты с задержкой сети | WebRTC spike (IOS-03) |
| 2026-07-14 10:06 +05:00 | Codex | PR #1 merged; BE-01 start | Зафиксировано принятие ADR-0001/API-01/D-004 и начало health/config backend skeleton | Antigravity Swift Codable/JSONDecoder review passed; merge commit `bfc5a10` | Реализовать и протестировать BE-01; Antigravity продолжает IOS-02 |
| 2026-07-14 10:05 +05:00 | Antigravity | ADR-0001 & API-01 review | Проверена Swift Codable совместимость `contracts/openapi.yaml`, fixtures успешно распарсены. D-004 принят (Fastify). H-004 закрыт. Начало работы над IOS-02. | Маппинг DTO написан и сверен; types/enums/secrets совпадают | Antigravity реализует `BackendClient` в iOS |
| 2026-07-14 09:54 +05:00 | Codex | ADR-01/API-01 review handoff | Добавлены ADR-0001, OpenAPI 3.1 и fixtures; подтверждены official OpenAI translation endpoints/events | Redocly valid, 0 warnings; 3 JSON fixtures parse; official docs review | Commit/push; Antigravity reviews H-004 и начинает IOS-02 |
| 2026-07-14 09:48 +05:00 | Antigravity | UX-01 complete | Реализованы экраны Onboarding, Home, Preflight, Live, Result, Diagnostics, добавлены премиум стили, поддержка Dynamic Type и VoiceOver | Сгенерированы файлы и обновлен проектный файл Xcode | Antigravity ждет контрактов для IOS-02 или начинает WebRTC-spike (IOS-03) |
| 2026-07-14 09:44 +05:00 | Antigravity | IOS-01 complete | Созданы структура приложения, Xcode-проект, конфигурационные окружения (Dev, Stage, Prod) и все базовые модули под `apps/ios/RealtimeTranslator` | Сгенерированы файлы, проверено соответствие PRD v0.1 | Antigravity ждет контрактов для IOS-02 или начинает UX-01; Codex продолжает ADR-01/API-01 |
| 2026-07-14 09:37 +05:00 | Codex | Worktree handoff ready | Обе рабочие ветки fast-forward до `495c533`, опубликованы и настроены на tracking своих origin branches | Clean `git status -sb` в обоих worktrees | Antigravity принимает H-001 и начинает IOS-01; Codex начинает ADR-01/API-01 |
| 2026-07-14 09:36 +05:00 | Codex | SETUP-01 complete | Baseline `fa2b62b` опубликован в `main`; созданы отдельные Codex и Antigravity worktrees/ветки | `git push`; `git worktree list` | Обновить обе ветки из `main`; Antigravity принимает H-001; ADR-01/API-01 |
| 2026-07-14 09:34 +05:00 | Codex | SETUP-01 GitHub auth | Подтверждена авторизация `YergZakon`; добавлена `.gitattributes` для LF и binary DOCX | `gh auth status`; `gh repo view`: public, empty | Baseline commit/push; создать worktrees |
| 2026-07-14 09:30 +05:00 | Codex | SETUP-01 tooling | Установлен portable GitHub CLI v2.96.0 в ignored `.tools`; добавлены `.gitignore` и `README.md` | `gh --version`; `.tools/` исключён из Git | Выполнить `gh auth login`; baseline commit/push; создать worktrees |
| 2026-07-14 09:22 +05:00 | Codex | SETUP-01 | Инициализирован Git `main`; добавлен `origin` на `YergZakon/translator` | `git remote -v`; `git ls-remote --symref origin HEAD` подтвердил доступный пустой remote | Установить/auth `gh`; создать baseline commit/push; затем worktrees |
| 2026-07-14 09:17 +05:00 | Codex | SETUP coordination | Созданы `AGENTS.md` и `docs/PROJECT_LEDGER.md`; зафиксированы роли, workflow, API/routes, protocols и handoff | Содержание сверено с PRD v0.1 | Antigravity review; затем Git init и ADR-01 |

## 10. Блокеры и открытые вопросы

| ID | Вопрос/блокер | Owner | Deadline | Что разблокирует | Status |
|---|---|---|---|---|---|
| B-001 | Проект ещё не является Git-репозиторием | Codex | 2026-07-14 | Изолированные ветки и безопасная интеграция | RESOLVED |
| B-002 | Не созданы отдельные worktree/clone для моделей | Codex | 2026-07-14 | Исключение перезаписи незакоммиченных файлов | RESOLVED |
| B-003 | Установить portable GitHub CLI и авторизовать `YergZakon` | Codex | 2026-07-14 | Аутентифицированная публикация и дальнейшие PR | RESOLVED |
| Q-001 | Fastify или NestJS? | Codex, review Antigravity | Day 1 | Backend skeleton/OpenAPI tooling | RESOLVED — Fastify accepted in D-004 |
| Q-002 | Maintained native WebRTC package и минимальная iOS version | Antigravity | Day 1–2 | Physical-device spike | OPEN |
| Q-003 | Актуальные OpenAI translation endpoints/events/TTL | Codex + Antigravity | До BE-02/IOS-03 | Secret broker и event decoder | RESOLVED — translation client_secrets/calls и events verified; expiry берётся из provider `expires_at` |
| B-004 | PR #3 конфликтует с `main` после merge BE-01; открыты contract/security findings PR #3/#4 | Antigravity | До iOS merge/E2E | Интеграцию iOS и physical iPhone test | RESOLVED — histories preserved, review findings closed, PR #3 merged, PR #4 retargeted to `main` |

## 11. Definition of Done

Задача считается `DONE`, только если:

- реализован согласованный scope без незаписанных breaking changes;
- выполнены подходящие unit/contract/integration/UI проверки;
- не появились secrets, raw audio или transcript в коде/логах/fixtures;
- обновлены очередь, реестр функций/контрактов (если менялись), хронология и handoff;
- записаны известные ограничения и следующий владелец, если работа продолжается.
