# PROJECT LEDGER — Realtime Translator iOS

Единый редактируемый источник истины для Codex, Antigravity и владельца проекта.

- Обновлено: 2026-07-14 09:37 +05:00
- PRD: `PRD_Realtime_Translator_iOS_30_days_v0.1.docx`, версия 0.1 от 2026-07-13
- Состояние проекта: `READY_FOR_PARALLEL_WORK`
- Git: baseline `fa2b62b` и coordination head `495c533` опубликованы в `origin/main` репозитория `https://github.com/YergZakon/translator.git`
- Интеграционная копия: `C:\Users\yergali\Desktop\переводчик`, ветка `main`
- Codex worktree: `C:\Users\yergali\Desktop\translator-codex`, ветка `codex/be-api-01-contracts`
- Antigravity worktree: `C:\Users\yergali\Desktop\translator-antigravity`, ветка `antigravity/ios-ios-01-skeleton`
- Общий физический checkout для двух моделей запрещён
- Главный принцип архитектуры: прямой WebRTC между iOS и OpenAI; backend выдаёт короткоживущие secrets и не находится в медиапути

## 1. Роли и границы

### Codex — backend owner

- Node.js + TypeScript backend (Fastify или NestJS — решение ещё не принято).
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
| ADR-01 | Shared | Выбрать Fastify или NestJS и структуру monorepo | Codex + Antigravity review | TODO | — | Решение D-002 | SETUP-01 | Обе стороны приняли |
| API-01 | Shared | Создать OpenAPI 3.1 для P0 endpoints и error envelope | Codex | TODO | `codex/be-api-01-contracts` | `contracts/openapi.yaml` | ADR-01 | lint + Antigravity review |
| TEL-01 | Shared | Зафиксировать allowlisted telemetry schema | Codex | TODO | — | `contracts/telemetry.schema.json` | ADR-01 | schema tests + iOS review |
| BE-01 | Backend | Health/config API skeleton | Codex | TODO | — | backend service | ADR-01 | unit + HTTP contract tests |
| BE-02 | Backend | OpenAI short-lived secret broker | Codex | TODO | — | backend service | BE-01, API-01 | mocked upstream + secret redaction |
| IOS-01 | iOS | Xcode/SwiftUI skeleton и environments | Antigravity | TODO | `antigravity/ios-ios-01-skeleton` | iOS project | SETUP-01, ADR-01 | build on simulator/device |
| UX-01 | iOS | Core screens и обязательные UI states | Antigravity | TODO | — | SwiftUI views | IOS-01 | previews + UI state tests |
| IOS-02 | iOS | BackendClient DTO + mock implementation | Antigravity | TODO | — | iOS client layer | API-01 | fixtures decode, error mapping |
| IOS-03 | iOS | WebRTC adapter spike RU→EN | Antigravity | TODO | — | transport layer | BE-02, IOS-01 | physical iPhone spike |

## 4. Реестр собственных API P0

Источник — PRD v0.1. Формальные схемы будут жить в `contracts/openapi.yaml`; до его появления этот раздел является временным контрактом уровня маршрутов.

| Метод и путь | Назначение | Auth | Идемпотентность | Owner | Status |
|---|---|---|---|---|---|
| `POST /v1/installations` | Регистрация анонимной установки и выдача app token | Optional app attestation | `installation_public_id` | Codex | PLANNED |
| `GET /v1/config` | Remote config, flags, kill switch | Bearer app token | `ETag` | Codex | PLANNED |
| `POST /v1/translation-sessions` | App session и 1–2 translation legs | Bearer app token | `Idempotency-Key` | Codex | PLANNED |
| `POST /v1/translation-sessions/{id}/legs` | Пересоздание leg при reconnect | Bearer app token | `Idempotency-Key` | Codex | PLANNED |
| `POST /v1/translation-sessions/{id}/complete` | Итоговые metadata | Bearer app token | Safe repeat | Codex | PLANNED |
| `POST /v1/translation-sessions/{id}/feedback` | Rating и категории ошибок | Bearer app token | Один updateable record | Codex | PLANNED |
| `POST /v1/telemetry/batch` | Allowlisted события | Bearer app token | `event_id` dedupe | Codex | PLANNED |
| `GET /v1/health` | Readiness/liveness | Internal/public minimal | — | Codex | PLANNED |

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
| `TranslationSessionStore` / reducer | Единый источник UI state | Antigravity | PLANNED |
| `SessionAPI` | Create/recreate/complete session | Antigravity | PLANNED |
| `ConfigAPI` | Remote config/ETag | Antigravity | PLANNED |
| `FeedbackAPI` | Submit/update feedback | Antigravity | PLANNED |
| `AudioSessionController` | AVAudioSession lifecycle/routes | Antigravity | PLANNED |
| `OutputArbiter` | Не допустить одновременный audible output | Antigravity | PLANNED |
| `EventDecoder` | Tolerant decoding Realtime events | Antigravity | PLANNED |
| `TelemetryClient` + `Redactor` | Allowlisted event batching без текста/audio | Antigravity | PLANNED |

### Планируемые backend functions/services

Точные TypeScript signatures фиксируются в коде и OpenAPI после ADR-01.

| Service/function | Вход/выход | Инвариант | Owner | Status |
|---|---|---|---|---|
| `InstallationService.register` | public installation id → app token | Token хранится только как hash | Codex | PLANNED |
| `ConfigService.getActiveConfig` | installation/build → config + ETag | Kill switch проверяется до создания session | Codex | PLANNED |
| `SessionService.create` | validated request → app session + 1–2 legs | Одна операция/результат на idempotency key | Codex | PLANNED |
| `LegService.recreate` | session/leg/reason → fresh leg secret | Старый secret не переиспользуется | Codex | PLANNED |
| `OpenAISecretBroker.create` | target language + safety id → short-lived secret | Standard API key никогда не возвращается клиенту | Codex | PLANNED |
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
| D-002 | — | PROPOSED | Выбрать monorepo с `apps/backend`, `apps/ios`, `contracts`, `docs` | Codex | Antigravity | Упрощает общий ledger и contract-first workflow |
| D-003 | — | PROPOSED | Сначала OpenAPI + fixtures, затем параллельно backend producer и iOS consumer | Codex | Antigravity | Снижает взаимную блокировку |

Шаблон новой записи:

```text
| D-NNN | YYYY-MM-DD | PROPOSED | Краткое решение | Автор | Reviewer | Последствия/миграция |
```

## 8. Handoff

| ID | От | Кому | Что готово | Где | Проверки | Ограничения | Критерий приёмки | Status |
|---|---|---|---|---|---|---|---|---|
| H-001 | Codex | Antigravity | Стартовые правила, разделение ролей и временный реестр API | `AGENTS.md`, этот файл | Сверено с PRD v0.1 | OpenAPI и signatures ещё не созданы | Antigravity подтверждает D-001..D-003 и резервирует первую iOS задачу | OPEN |

## 9. Хронология

Добавлять новые записи сверху; не переписывать историю.

| Timestamp | Actor | Task/Decision | Изменения | Проверки | Next |
|---|---|---|---|---|---|
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
| Q-001 | Fastify или NestJS? | Codex, review Antigravity | Day 1 | Backend skeleton/OpenAPI tooling | OPEN |
| Q-002 | Maintained native WebRTC package и минимальная iOS version | Antigravity | Day 1–2 | Physical-device spike | OPEN |
| Q-003 | Актуальные OpenAI translation endpoints/events/TTL | Codex + Antigravity | До BE-02/IOS-03 | Secret broker и event decoder | OPEN |

## 11. Definition of Done

Задача считается `DONE`, только если:

- реализован согласованный scope без незаписанных breaking changes;
- выполнены подходящие unit/contract/integration/UI проверки;
- не появились secrets, raw audio или transcript в коде/логах/fixtures;
- обновлены очередь, реестр функций/контрактов (если менялись), хронология и handoff;
- записаны известные ограничения и следующий владелец, если работа продолжается.
