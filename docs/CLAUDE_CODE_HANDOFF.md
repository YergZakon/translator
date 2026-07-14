# Claude Code handoff

Актуально на 2026-07-14. Claude Code заменяет Antigravity как текущий iOS owner. Codex остаётся backend owner и интегратором shared contracts.

## Current snapshot

| Объект | Состояние |
|---|---|
| `main` | `3823124b4eb9f95d7919a51f7d68a8c2ec360da7`; IOS-04 уже merged |
| Backend PR #8 | `codex/be-03-installation-auth`, head `d2a85eb1d6e10459354791d0ca362fe17c62a098`, Draft, mergeable |
| PR #8 CI | exact-head run `29317931855` green; backend typecheck, 27/27 tests, build и container smoke |
| iOS PR #9 | `antigravity/ios-ios-05-installation-auth`, head `001786d82ee5ca1372d4d058f32c8d2d4054ac2d`, Draft, mergeable |
| PR #9 CI | exact-head run `29322484021` green; XcodeGen, app build и 20/20 XCTest |
| Stage/device | Stage deploy и physical iPhone WebRTC E2E остаются открытыми |

Ссылки:

- Backend PR #8: https://github.com/YergZakon/translator/pull/8
- iOS PR #9: https://github.com/YergZakon/translator/pull/9

## Что уже реализовано

### BE-03 / PR #8

- `POST /v1/installations` с PostgreSQL persistence.
- App token хранится только как hash; plaintext возвращается клиенту только при регистрации/ротации.
- Повторная регистрация того же installation public ID ротирует token, старый token отклоняется.
- Repository-backed token verifier используется защищёнными endpoints.
- Миграции и backend CI с PostgreSQL/container smoke готовы.
- H-009 в ветке PR #8 ожидает независимый iOS/security review.

### IOS-05 / PR #9

- `InstallationAPI`, bootstrap при отсутствии/невалидности app token и controlled retry ровно один раз.
- Single-flight refresh coordination предотвращает параллельные независимые rotation requests.
- Keychain update атомарный, accessibility — device-only; storage errors не маскируются.
- App-token response decode-only и redacted; sensitive credentials не `Encodable`.
- Prototype `APP_TOKEN` fallback удалён.
- Contract IDs, `modelClass: "phone"`, ErrorEnvelope и 401 semantics исправлены.
- Codex security/contract review завершён; H-010 закрыт. До merge PR #9 требуется сначала merge BE-03, затем синхронизация с `main` и новый exact-head CI.

## First mission — review PR #8

Это read-only review. Не коммить в backend-ветку и не merge PR.

1. Получи актуальные refs и diff:

   ```powershell
   git fetch origin --prune
   gh pr view 8 --repo YergZakon/translator
   gh pr diff 8 --repo YergZakon/translator
   ```

2. Проверь:

   - request/response `POST /v1/installations` против `contracts/openapi.yaml` и Swift DTO PR #9;
   - `installationId`, `installationPublicId`, `appToken`, `tokenType`, nullable `expiresAt` и ErrorEnvelope;
   - только hash token в PostgreSQL и отсутствие plaintext token/secrets в логах;
   - rotation: новый token работает, старый получает `401 INVALID_APP_TOKEN`;
   - retryability/HTTP semantics совместимы с iOS retry-once;
   - migrations, индексы/uniqueness, transaction/race behavior и restart persistence;
   - удаление prototype static `APP_TOKENS` flow из production path;
   - CI/test coverage для PostgreSQL и container runtime.

3. Верни владельцу проекта и Codex один из двух результатов:

   ```text
   APPROVED
   Reviewed PR #8 exact head d2a85eb1d6e10459354791d0ca362fe17c62a098.
   Contract/security compatibility with IOS-05 confirmed.
   H-009 can be CLOSED.
   ```

   либо:

   ```text
   CHANGES_REQUESTED
   Reviewed exact head: <sha>
   Findings:
   - [severity] file:line — problem, impact, required correction
   H-009 remains OPEN.
   ```

Если head изменился относительно указанного SHA, review проводится заново на новом exact head.

## После APPROVED

Не merge самостоятельно без явного разрешения. После того как Codex/владелец проекта смержит PR #8:

1. Создай отдельный Claude worktree/локальную ветку от remote PR #9:

   ```powershell
   git fetch origin --prune
   git worktree add C:\tmp\translator-claude-ios05 -b claude/ios05-finalize origin/antigravity/ios-ios-05-installation-auth
   ```

2. В этом worktree влей новый `origin/main` обычным merge commit, не rebase/force-push:

   ```powershell
   git merge --no-ff origin/main
   ```

3. При конфликте ledger сохрани записи main, H-009 из PR #8 и H-010/IOS-05 из PR #9. Не выбирай целиком одну сторону.
4. Проверь отсутствие prototype token fallback и контрактную совместимость после merge.
5. Выполни `git diff --check`, secret scan и запусти exact-head iOS CI.
6. Push продолжения существующего PR выполняй явно:

   ```powershell
   git push origin HEAD:antigravity/ios-ios-05-installation-auth
   ```

7. Верни Codex exact SHA, CI run URL, число тестов и список сохранённых handoff-записей. Только после зелёного CI PR #9 можно переводить из Draft/merge по разрешению владельца.

## Следующие задачи после PR #9

Не брать их до завершения PR #8 → PR #9 integration:

1. Stage deployment backend и physical iPhone E2E: installation → app token → config → translation session → ephemeral secret → SDP/WebRTC → remote audio/transcript.
2. Закрытие H-006 только после реального device run; записать модель iPhone, iOS, stage build, trace/session IDs без transcript/audio.
3. Затем выбирать следующую iOS-задачу из ledger: reconnect leg, AudioSessionController/route handling, OutputArbiter/dialogue mode или telemetry — только после reservation и dependency check.

## Инструменты и ограничения окружения

- На Windows нельзя заявлять успешный Xcode build/XCTest; используйте GitHub macOS CI либо MacBook.
- Если `gh` не находится в `PATH`, portable binary доступен в основном checkout: `C:\Users\yergali\Desktop\переводчик\.tools\gh\bin\gh.exe`.
- Не копируй `.env`, Keychain data, OpenAI keys или app tokens между worktree.
- Не удаляй старые worktree/ветки без отдельного разрешения владельца проекта.
