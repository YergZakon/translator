# Agent handoff protocol

GitHub PR/issue comments are the transport between Codex and the owner's local Claude Code session. Cloud `claude[bot]` and GitHub Actions Claude jobs are not authorized reviewers. The GitHub comment author may be the repository owner because both local connectors act through that account; agent identity is therefore defined by the structured fields plus `channel: local-claude-monitor`.

## Codex to Claude Code

```text
[AGENT_HANDOFF]
version: 1
id: H-<unique-id>
revision: 1
sender: codex
recipient: claude-code
channel: local-claude-monitor
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

The local Claude monitor accepts a handoff only when the comment contains `[AGENT_HANDOFF]`, `recipient: claude-code` and `channel: local-claude-monitor`. New handoffs must not contain `@claude`; this prevents cloud action invocation. Comments or results produced by `claude[bot]`/GitHub Actions are ignored even if their remaining structured fields match.

## Claude Code to Codex

Claude Code must finish the same GitHub Actions run by posting:

```text
[AGENT_RESULT]
version: 1
id: H-<same-id>
revision: 1
sender: claude-code
recipient: codex
channel: local-claude-monitor
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
channel: local-claude-monitor
result: ACCEPTED | REJECTED
next: <next handoff id or none>
```

## Idempotency and safety

- The identity key is `id + revision`; it may be processed only once by each agent.
- Exactly one authoritative result is allowed for `id + revision`: the result returned through `channel: local-claude-monitor`. Cloud bot results are non-authoritative and never ACKed.
- If multiple otherwise valid results exist or the channel is absent/mismatched, Codex posts `REJECTED`, stops merge/deploy, and asks the owner to resolve the collision.
- A changed PR head invalidates an approval for an older `expected_head`.
- Neither agent may expand `allowed_actions`.
- Merge, deploy, secrets, billing, production data and destructive operations require explicit authorization in the handoff.
- Secrets, app tokens, client secrets, audio and full transcripts never appear in comments or the ledger.
- Codex polling ignores unstructured comments, cloud bot output, and results whose `recipient` is not `codex` or whose `channel` is not `local-claude-monitor`.
