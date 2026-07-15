export interface QuotaPolicy {
  maxParallelLegs: number;
  maxSecretMintsPerWindow: number;
  secretMintWindowMs: number;
  maxDailyLegMinutes: number;
}

export interface QuotaReservation {
  additionalActiveLegs: number;
  dailyLegMinutes: number;
  secretMints: number;
  policy: QuotaPolicy;
}

export const defaultQuotaPolicy: QuotaPolicy = {
  maxParallelLegs: 2,
  maxSecretMintsPerWindow: 8,
  secretMintWindowMs: 60_000,
  maxDailyLegMinutes: 120
};

function assertPositiveInteger(name: string, value: number): void {
  if (!Number.isInteger(value) || value < 1) {
    throw new Error(`${name} must be a positive integer`);
  }
}

export class QuotaService {
  readonly #policy: QuotaPolicy;

  constructor(policy: QuotaPolicy = defaultQuotaPolicy) {
    assertPositiveInteger('maxParallelLegs', policy.maxParallelLegs);
    assertPositiveInteger('maxSecretMintsPerWindow', policy.maxSecretMintsPerWindow);
    assertPositiveInteger('secretMintWindowMs', policy.secretMintWindowMs);
    assertPositiveInteger('maxDailyLegMinutes', policy.maxDailyLegMinutes);
    this.#policy = { ...policy };
  }

  createSessionReservation(legCount: number, maxDurationSeconds: number): QuotaReservation {
    assertPositiveInteger('legCount', legCount);
    assertPositiveInteger('maxDurationSeconds', maxDurationSeconds);
    return {
      additionalActiveLegs: legCount,
      dailyLegMinutes: Math.ceil((legCount * maxDurationSeconds) / 60),
      secretMints: legCount,
      policy: { ...this.#policy }
    };
  }

  recreateLegReservation(): QuotaReservation {
    return {
      additionalActiveLegs: 0,
      dailyLegMinutes: 0,
      secretMints: 1,
      policy: { ...this.#policy }
    };
  }
}
