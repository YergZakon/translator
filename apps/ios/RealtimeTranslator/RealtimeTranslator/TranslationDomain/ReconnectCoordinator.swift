import Foundation

protocol ReconnectClock {
    /// Must propagate task cancellation (throw `CancellationError`) exactly like `Task.sleep`.
    func sleep(milliseconds: Int) async throws
}

struct SystemReconnectClock: ReconnectClock {
    func sleep(milliseconds: Int) async throws {
        guard milliseconds > 0 else {
            try Task.checkCancellation()
            return
        }
        try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
    }
}

struct ReconnectSessionContext {
    let sessionId: String
    let clientLegId: String
    let side: Side
    let maxAttempts: Int
    let backoffMs: [Int]
}

enum ReconnectOutcome {
    case reconnected(TranslationLeg, TranslationLegCredentials)
    case resourceNotFound
    case killSwitchActive
    case exhausted
}

/// Drives leg replacement for a single failed/disconnected translation leg.
/// The disconnected-grace window is owned by `TranslationSessionStore`: by the time
/// this coordinator runs, the failed leg is already detached and must be drained.
/// Every reconnect attempt (backoff round) uses a freshly generated Idempotency-Key;
/// key reuse for retries within one HTTP call is handled by `LiveBackendClient` itself.
final class ReconnectCoordinator {
    private let sessionAPI: SessionAPI
    private let makeLeg: TranslationLegFactory
    private let diagnostics: DiagnosticsStore
    private let clock: ReconnectClock
    private let idempotencyKeyFactory: () -> String

    init(
        sessionAPI: SessionAPI,
        makeLeg: @escaping TranslationLegFactory,
        diagnostics: DiagnosticsStore,
        clock: ReconnectClock = SystemReconnectClock(),
        idempotencyKeyFactory: @escaping () -> String = { UUID().uuidString }
    ) {
        self.sessionAPI = sessionAPI
        self.makeLeg = makeLeg
        self.diagnostics = diagnostics
        self.clock = clock
        self.idempotencyKeyFactory = idempotencyKeyFactory
    }

    func reconnect(
        failedLeg: TranslationLeg?,
        reason: RecreateLegReason,
        context: ReconnectSessionContext,
        onAttempt: (Int) -> Void = { _ in }
    ) async -> ReconnectOutcome {
        if let failedLeg {
            // Drain before requesting fresh credentials: never let the old leg keep
            // sending microphone audio or playing remote audio while a replacement exists.
            await failedLeg.setMicrophoneEnabled(false)
            await failedLeg.setOutputEnabled(false)
            await failedLeg.close(reason: .connectionTimeout)
        }

        guard context.maxAttempts > 0 else {
            diagnostics.log("Reconnect: no attempts allowed by policy")
            return .exhausted
        }

        var attempt = 1
        while attempt <= context.maxAttempts {
            guard !Task.isCancelled else { return .exhausted }
            onAttempt(attempt)

            let backoff = context.backoffMs.isEmpty
                ? 0
                : context.backoffMs[min(attempt - 1, context.backoffMs.count - 1)]
            do {
                try await clock.sleep(milliseconds: backoff)
            } catch {
                // Cancelled during backoff: the session was stopped, never mint a secret.
                return .exhausted
            }
            guard !Task.isCancelled else { return .exhausted }

            let idempotencyKey = idempotencyKeyFactory()
            diagnostics.log("Reconnect: attempt \(attempt)/\(context.maxAttempts) key=\(idempotencyKey.prefix(8))")

            do {
                let credentials = try await sessionAPI.recreateTranslationLeg(
                    sessionId: context.sessionId,
                    request: RecreateTranslationLegRequest(clientLegId: context.clientLegId, reason: reason),
                    idempotencyKey: idempotencyKey
                )

                // Cancelled while the request was in flight: the fresh secret stays
                // unused (it expires server-side) and no leg may be created for it.
                guard !Task.isCancelled else { return .exhausted }

                let leg = makeLeg(
                    LegConfiguration(
                        clientLegId: credentials.clientLegId,
                        targetLanguage: credentials.targetLanguage.rawValue,
                        clientSecret: credentials.clientSecret,
                        callsUrl: credentials.callsUrl
                    ),
                    context.side,
                    diagnostics
                )

                do {
                    try await leg.connect()
                    return .reconnected(leg, credentials)
                } catch {
                    // A candidate whose connect failed must never linger as an orphan
                    // PeerConnection: keep it inaudible/muted and close it before retrying.
                    await leg.setMicrophoneEnabled(false)
                    await leg.setOutputEnabled(false)
                    await leg.close(reason: .errorOccurred)
                }
            } catch let error as BackendError {
                if case .serverError(let appError) = error {
                    switch appError.code {
                    case .RESOURCE_NOT_FOUND:
                        return .resourceNotFound
                    case .KILL_SWITCH_ACTIVE:
                        return .killSwitchActive
                    default:
                        break
                    }
                }
            } catch is CancellationError {
                return .exhausted
            } catch {
                // Transport-level failure: fall through to the next attempt.
            }

            attempt += 1
        }

        return .exhausted
    }
}
