import { createHash } from 'node:crypto';

export const telemetryEventTypes = [
  'app_opened',
  'session_start_tapped',
  'session_create_requested',
  'session_secret_received',
  'webrtc_offer_created',
  'webrtc_connected',
  'mic_enabled_changed',
  'first_input_transcript',
  'first_output_transcript',
  'first_remote_audio',
  'network_degraded',
  'reconnect_attempt',
  'reconnect_result',
  'audio_route_changed',
  'session_completed',
  'feedback_submitted'
] as const;

export type TelemetryEventType = (typeof telemetryEventTypes)[number];

export interface TelemetryEvent {
  eventId: string;
  sessionId?: string | null;
  legId?: string | null;
  type: TelemetryEventType;
  monotonicMs: number;
  properties: Record<string, unknown>;
}

export interface TelemetryBatchRequest {
  schemaVersion: '1.0';
  sentAt: string;
  events: TelemetryEvent[];
}

export interface TelemetryBatchResponse {
  accepted: number;
  rejected: number;
  rejectedEventIds: string[];
}

export interface PersistableTelemetryEvent extends TelemetryEvent {
  payloadFingerprint: Buffer;
}

export interface IngestTelemetryInput {
  safetyIdentifier: string;
  sentAt: Date;
  receivedAt: Date;
  events: PersistableTelemetryEvent[];
}

export interface TelemetryRepository {
  ingest(input: IngestTelemetryInput): Promise<TelemetryBatchResponse>;
}

function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalJson(item)).join(',')}]`;
  }
  if (value !== null && typeof value === 'object') {
    const entries = Object.entries(value as Record<string, unknown>).sort(([left], [right]) =>
      left.localeCompare(right)
    );
    return `{${entries
      .map(([key, entryValue]) => `${JSON.stringify(key)}:${canonicalJson(entryValue)}`)
      .join(',')}}`;
  }
  return JSON.stringify(value);
}

export function fingerprintTelemetryEvent(event: TelemetryEvent): Buffer {
  return createHash('sha256').update(canonicalJson(event), 'utf8').digest();
}

export class TelemetryService {
  readonly #repository: TelemetryRepository;
  readonly #now: () => Date;

  constructor(repository: TelemetryRepository, now: () => Date = () => new Date()) {
    this.#repository = repository;
    this.#now = now;
  }

  async ingest(
    batch: TelemetryBatchRequest,
    context: { safetyIdentifier: string }
  ): Promise<TelemetryBatchResponse> {
    return this.#repository.ingest({
      safetyIdentifier: context.safetyIdentifier,
      sentAt: new Date(batch.sentAt),
      receivedAt: this.#now(),
      events: batch.events.map((event) => ({
        ...event,
        payloadFingerprint: fingerprintTelemetryEvent(event)
      }))
    });
  }
}
