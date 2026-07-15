import {
  type IngestTelemetryInput,
  type TelemetryBatchResponse,
  type TelemetryRepository
} from '../services/telemetry-service.js';

interface SessionScope {
  safetyIdentifier: string;
  sessionId: string;
  legIds: string[];
}

export class InMemoryTelemetryRepository implements TelemetryRepository {
  readonly #sessions = new Map<string, SessionScope>();
  readonly #events = new Map<string, Buffer>();

  constructor(sessionScopes: SessionScope[] = []) {
    for (const scope of sessionScopes) {
      this.#sessions.set(scope.sessionId, scope);
    }
  }

  async ingest(input: IngestTelemetryInput): Promise<TelemetryBatchResponse> {
    const rejectedEventIds: string[] = [];
    let accepted = 0;

    for (const event of input.events) {
      if (!this.#ownsScope(input.safetyIdentifier, event.sessionId, event.legId)) {
        rejectedEventIds.push(event.eventId);
        continue;
      }

      const key = `${input.safetyIdentifier}:${event.eventId}`;
      const existing = this.#events.get(key);
      if (existing !== undefined && !existing.equals(event.payloadFingerprint)) {
        rejectedEventIds.push(event.eventId);
        continue;
      }

      this.#events.set(key, event.payloadFingerprint);
      accepted += 1;
    }

    return {
      accepted,
      rejected: rejectedEventIds.length,
      rejectedEventIds
    };
  }

  #ownsScope(
    safetyIdentifier: string,
    sessionId: string | null | undefined,
    legId: string | null | undefined
  ): boolean {
    if (sessionId == null) {
      return legId == null;
    }
    const session = this.#sessions.get(sessionId);
    if (session === undefined || session.safetyIdentifier !== safetyIdentifier) {
      return false;
    }
    return legId == null || session.legIds.includes(legId);
  }
}
