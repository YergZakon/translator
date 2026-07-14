export interface AppConfig {
  version: string;
  killSwitch: boolean;
  killSwitchMessage: string | null;
  modelAlias: string;
  allowedModes: Array<'one_way_ru_to_en' | 'dialogue'>;
  allowedTargetLanguages: Array<'en' | 'ru'>;
  maxDurationSeconds: number;
  reconnectPolicy: {
    maxAttempts: number;
    backoffMs: number[];
    disconnectedGraceMs: number;
  };
  outputInterruption: {
    mode: 'finish_current' | 'duck_and_switch' | 'hard_cut';
    delayMs: number;
  };
  telemetrySampleRate: number;
  experiments: Record<string, string>;
}

export const defaultAppConfig: AppConfig = {
  version: '2026-07-14.1',
  killSwitch: false,
  killSwitchMessage: null,
  modelAlias: 'gpt-realtime-translate',
  allowedModes: ['one_way_ru_to_en', 'dialogue'],
  allowedTargetLanguages: ['en', 'ru'],
  maxDurationSeconds: 1800,
  reconnectPolicy: {
    maxAttempts: 3,
    backoffMs: [500, 1500, 3000],
    disconnectedGraceMs: 2000
  },
  outputInterruption: {
    mode: 'duck_and_switch',
    delayMs: 300
  },
  telemetrySampleRate: 1,
  experiments: {
    autoSideDetection: 'control',
    localTranscriptSave: 'disabled'
  }
};
