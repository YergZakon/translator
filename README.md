# Realtime Translator iOS

30-дневный прототип iOS-приложения синхронного голосового перевода RU ↔ EN.

## Архитектура P0

- iOS-клиент устанавливает прямое WebRTC-соединение с OpenAI Realtime Translation.
- Backend выдаёт короткоживущие client secrets, remote config и лимиты, принимает техническую telemetry и feedback.
- Backend не находится в медиапути и не хранит raw audio или полный transcript по умолчанию.

## Структура проекта

- `apps/backend` — TypeScript backend, владелец Codex.
- `apps/ios` — Swift/SwiftUI клиент, текущий владелец Claude Code.
- `contracts` — совместные OpenAPI/JSON Schema контракты.
- `docs/PROJECT_LEDGER.md` — общий журнал работ, решений, API и handoff.
- `AGENTS.md` — обязательные правила совместной работы моделей.
- `CLAUDE.md` — автоматически загружаемые инструкции для Claude Code.
- `docs/CLAUDE_CODE_HANDOFF.md` — текущее состояние и порядок подхвата iOS-работ.
- `PRD_Realtime_Translator_iOS_30_days_v0.1.docx` — исходный PRD.

Каталоги приложений и контрактов будут создаваться по мере принятия ADR-01 и первых задач.

## Порядок начала работы

1. Прочитать PRD, `AGENTS.md` и `docs/PROJECT_LEDGER.md`.
2. Зарезервировать задачу в ledger.
3. Работать в отдельной ветке и отдельном Git worktree/clone.
4. Передавать изменения через маленькие commits/PR и обновлять handoff.
