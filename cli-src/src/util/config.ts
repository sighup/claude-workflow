import type { CwConfig } from '../types/config.js';

function envStr(key: string, def: string): string {
  return process.env[key] ?? def;
}

function envInt(key: string, def: number): number {
  const v = process.env[key];
  return v ? parseInt(v, 10) : def;
}

function envBool(key: string, def: boolean): boolean {
  const v = process.env[key];
  if (!v) return def;
  return v === 'true' || v === '1';
}

function envList(key: string, def: string[]): string[] {
  const v = process.env[key];
  if (!v) return def;
  return v.split(/\s+/).filter(Boolean);
}

export function loadConfig(overrides: Partial<CwConfig> = {}): CwConfig {
  return {
    model: envStr('CW_MODEL', 'sonnet'),
    timeout: envInt('CW_TIMEOUT', 0),
    sleep: envInt('CW_SLEEP', 5),
    maxIterations: envInt('CW_MAX_ITERATIONS', 50),
    maxFailures: envInt('CW_MAX_FAILURES', 3),
    invokeRetries: envInt('CW_INVOKE_RETRIES', 3),
    retryDelay: envInt('CW_RETRY_DELAY', 10),
    verbose: envBool('CW_VERBOSE', false),
    nonInteractive: envBool('CW_NON_INTERACTIVE', false),

    autoQueueDir: envStr('CW_AUTO_QUEUE_DIR', 'docs/queue'),
    autoLogDir: envStr('CW_AUTO_LOG_DIR', 'logs/auto'),
    autoSchedule: envStr('CW_AUTO_SCHEDULE', '0 2 * * *'),
    autoMaxItems: envInt('CW_AUTO_MAX_ITEMS', 5),
    autoLockDir: envStr('CW_AUTO_LOCK_DIR', '/tmp/cw-locks'),

    autoProjects: envList('CW_AUTO_PROJECTS', []),
    autoGlobalTimeout: envInt('CW_AUTO_GLOBAL_TIMEOUT', 28800),
    autoProjectStrategy: envStr('CW_AUTO_PROJECT_STRATEGY', 'priority') as 'priority' | 'round-robin',

    taskTimeout: envInt('CW_TASK_TIMEOUT', 1800),
    sessionTimeout: envInt('CW_SESSION_TIMEOUT', 14400),

    githubIntakeLabel: envStr('CW_GITHUB_INTAKE_LABEL', ''),
    githubIntakeRepo: envStr('CW_GITHUB_INTAKE_REPO', ''),
    githubIntakeCloseOnPr: envBool('CW_GITHUB_INTAKE_CLOSE_ON_PR', false),
    githubIntakeRemoveLabelOnPr: envBool('CW_GITHUB_INTAKE_REMOVE_LABEL_ON_PR', true),

    ratelimitMaxRetries: envInt('CW_RATELIMIT_MAX_RETRIES', 4),
    ratelimitBaseDelay: envInt('CW_RATELIMIT_BASE_DELAY', 30),

    historyRetentionDays: envInt('CW_HISTORY_RETENTION_DAYS', 30),

    ...overrides,
  };
}
