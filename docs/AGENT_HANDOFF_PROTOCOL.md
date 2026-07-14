# Agent handoff protocol

GitHub PR/issue comments are the transport between Codex and Claude Code. The GitHub comment author may be the repository owner because both connectors act through that account; agent identity is therefore defined only by the structured `sender` and `recipient` fields.

## Codex to Claude Code

```text
@claude

[AGENT_HANDOFF]
version: 1
id: H-<unique-id>
revision: 1
sender: codex
recipient: claude-code
repo: YergZakon/translator
target: PR #<number>
expected_head: <full-commit-sha>
task: <bounded task>
allowed_actions:
- read
- review
- comment
forbidden_actions:
- merge
- deploy
- modify-secrets
return_marker: [AGENT_RESULT]
```

The workflow accepts handoffs only when the GitHub actor is the repository owner and the comment contains both `@claude` and `[AGENT_HANDOFF]`.

## Claude Code to Codex

Claude Code must finish the same GitHub Actions run by posting:

```text
[AGENT_RESULT]
version: 1
id: H-<same-id>
revision: 1
sender: claude-code
recipient: codex
target: PR #<number>
expected_head: <sha-from-handoff>
actual_head: <sha-reviewed-or-produced>
status: COMPLETED | BLOCKED
verdict: APPROVED | CHANGES_REQUESTED | NOT_APPLICABLE
ci_run: <URL-or-none>
summary: <concise result>
changes: <commit SHAs or none>
blockers: <none or explicit list>
```

Do not say that work will be performed later. Either perform it in the current run or return `status: BLOCKED`.

## Codex acknowledgement

After validating the result against GitHub and the exact SHA, Codex posts:

```text
[AGENT_ACK]
version: 1
id: H-<same-id>
revision: 1
sender: codex
recipient: claude-code
result: ACCEPTED | REJECTED
next: <next handoff id or none>
```

## Idempotency and safety

- The identity key is `id + revision`; it may be processed only once by each agent.
- A changed PR head invalidates an approval for an older `expected_head`.
- Neither agent may expand `allowed_actions`.
- Merge, deploy, secrets, billing, production data and destructive operations require explicit authorization in the handoff.
- Secrets, app tokens, client secrets, audio and full transcripts never appear in comments or the ledger.
- Codex polling ignores unstructured comments and results whose `recipient` is not `codex`.
