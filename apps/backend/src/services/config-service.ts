import { createHash } from 'node:crypto';

import type { AppConfig } from '../domain/app-config.js';

export interface ConfigRequestContext {
  appVersion: string;
  appBuild: number;
}

export interface ActiveConfig {
  config: AppConfig;
  etag: string;
}

export class ConfigService {
  readonly #active: ActiveConfig;

  constructor(config: AppConfig) {
    const serialized = JSON.stringify(config);
    const digest = createHash('sha256').update(serialized).digest('hex').slice(0, 16);
    this.#active = {
      config: structuredClone(config),
      etag: `"cfg-${digest}"`
    };
  }

  getActiveConfig(context: ConfigRequestContext): ActiveConfig {
    void context;
    return this.getGlobalActiveConfig();
  }

  getGlobalActiveConfig(): ActiveConfig {
    return {
      config: structuredClone(this.#active.config),
      etag: this.#active.etag
    };
  }
}
