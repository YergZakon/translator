import type { SessionRepository } from './session-repository.js';
import { SessionRepositoryError } from './session-repository.js';

export const feedbackCategories = [
  'wrong_meaning',
  'missing_content',
  'critical_entity',
  'latency',
  'audio_quality',
  'echo_loop',
  'connection',
  'ui',
  'other'
] as const;

export type FeedbackCategory = (typeof feedbackCategories)[number];

export interface FeedbackRequest {
  rating: number;
  categories: FeedbackCategory[];
  comment?: string | null;
  consentFlags: {
    storeComment: boolean;
  };
}

export interface FeedbackResponse {
  sessionId: string;
  updatedAt: string;
}

export interface FeedbackContext {
  sessionId: string;
  safetyIdentifier: string;
}

export class FeedbackServiceError extends Error {
  constructor(
    readonly code: 'RESOURCE_NOT_FOUND',
    readonly httpStatus: 404,
    readonly message: string
  ) {
    super(message);
    this.name = 'FeedbackServiceError';
  }
}

const redactionRules: ReadonlyArray<readonly [RegExp, string]> = [
  [/\p{Cc}/gu, ' '],
  [/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/giu, '[email]'],
  [/(?<![\p{L}\p{N}])\+?\d[\d\s().-]{7,}\d(?![\p{L}\p{N}])/gu, '[phone]'],
  [/\b(?:sk[-_]|app_|ek_|ins_|ts_|tr_|leg_)[A-Za-z0-9_-]{8,}\b/gu, '[token]'],
  [/\bBearer\s+[A-Za-z0-9._~-]{8,}\b/giu, '[token]'],
  [/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/gu, '[token]'],
  [/https?:\/\/[^\s]+/giu, '[url]']
];

function clampUnicode(value: string, maximum: number): string {
  return Array.from(value).slice(0, maximum).join('');
}

export function redactFeedbackComment(comment: string): string {
  return clampUnicode(
    redactionRules.reduce(
      (redacted, [pattern, replacement]) => redacted.replace(pattern, replacement),
      comment
    ),
    500
  );
}

export class FeedbackService {
  readonly #repository: SessionRepository;
  readonly #now: () => Date;

  constructor(repository: SessionRepository, now: () => Date = () => new Date()) {
    this.#repository = repository;
    this.#now = now;
  }

  async upsert(request: FeedbackRequest, context: FeedbackContext): Promise<FeedbackResponse> {
    const comment =
      request.consentFlags.storeComment && request.comment !== undefined && request.comment !== null
        ? redactFeedbackComment(request.comment)
        : null;
    try {
      return await this.#repository.upsertFeedback({
        safetyIdentifier: context.safetyIdentifier,
        sessionId: context.sessionId,
        rating: request.rating,
        categories: [...request.categories],
        storeComment: request.consentFlags.storeComment,
        comment,
        now: this.#now()
      });
    } catch (error) {
      if (error instanceof SessionRepositoryError && error.code === 'RESOURCE_NOT_FOUND') {
        throw new FeedbackServiceError(
          'RESOURCE_NOT_FOUND',
          404,
          'Translation session was not found'
        );
      }
      throw error;
    }
  }
}
