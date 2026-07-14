# Claude Code — project instructions

Ты заменяешь Antigravity как текущий владелец iOS-направления. Исторические записи Antigravity в Git и ledger не переписывай: это сохранённое авторство уже выполненной работы.

## Перед любым действием

1. Прочитай `AGENTS.md` полностью.
2. Прочитай `docs/PROJECT_LEDGER.md` и `docs/CLAUDE_CODE_HANDOFF.md` полностью.
3. Прочитай `PRD_Realtime_Translator_iOS_30_days_v0.1.docx` перед изменением продуктового поведения.
4. Выполни `git status --short`, `git branch --show-current`, `git fetch origin --prune` и проверь актуальные PR #8/#9.
5. Работай только в отдельном worktree/clone. Не используй физический checkout Codex и не меняй незакоммиченные пользовательские файлы.
6. До правок зарезервируй задачу в `docs/PROJECT_LEDGER.md`; после правок запиши проверки, ограничения и следующий handoff.

## Разделение ответственности

- Claude Code: `apps/ios/**`, Swift/SwiftUI, WebRTC/audio, iOS DTO/client adapters, iOS tests и iOS CI.
- Codex: `apps/backend/**`, PostgreSQL, server auth, OpenAI secret broker, backend tests/Docker/CI.
- Shared: `contracts/**`, DTO semantics, error codes, telemetry schema, ADR и E2E acceptance. Shared change сначала получает запись `PROPOSED`, затем review второй стороны.
- Разрешён read-only review чужой области. Не исправляй backend во время review без отдельного handoff и явного разрешения.

## Неизменяемые инварианты

- Standard `OPENAI_API_KEY` существует только на backend и никогда не попадает в iOS, Git, fixtures, логи или ledger.
- Ephemeral `clientSecret` и app token не логируются; client secret хранится только в памяти, app token — в device-only Keychain.
- Backend не находится в медиапути. Raw audio и полный transcript не отправляются в telemetry.
- Только одна leg получает microphone audio и только одна remote audio track может быть слышима.
- Нельзя тихо менять принятый OpenAPI-контракт, enum raw values, ID regex, HTTP-коды или retry semantics.
- Не закрывай physical-iPhone/stage E2E без реального запуска на устройстве и stage backend.

## Git и качество

- Новые iOS-ветки называй `claude/ios-<task-id>-<slug>`.
- Не делай `force push`, rebase опубликованных общих веток, merge PR или deploy без явного разрешения владельца проекта.
- При конфликте `docs/PROJECT_LEDGER.md` сохрани обе хронологии и handoff-записи.
- Перед commit: `git diff --check`, проверка отсутствия secrets и релевантные тесты.
- Для iOS acceptance: XcodeGen, app build и XCTest на macOS CI. Simulator green не закрывает physical-iPhone acceptance.
- Для актуальных OpenAI, Apple, WebRTC и GitHub требований используй только официальные первичные источники.

## Первая задача

Следуй разделу «First mission» в `docs/CLAUDE_CODE_HANDOFF.md`. Сначала выполни read-only review backend PR #8 и верни явный verdict `APPROVED` либо `CHANGES_REQUESTED`. Не начинай новые iOS-функции и не меняй PR #9 до завершения этого review.
