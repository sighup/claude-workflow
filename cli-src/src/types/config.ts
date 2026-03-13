export interface CwConfig {
  // Core
  model: string;
  timeout: number;
  sleep: number;
  maxIterations: number;
  maxFailures: number;
  invokeRetries: number;
  retryDelay: number;
  verbose: boolean;
  nonInteractive: boolean;

  // Autonomous execution
  autoQueueDir: string;
  autoLogDir: string;
  autoSchedule: string;
  autoMaxItems: number;
  autoLockDir: string;

  // Multi-project
  autoProjects: string[];
  autoGlobalTimeout: number;
  autoProjectStrategy: 'priority' | 'round-robin';

  // Timeouts
  taskTimeout: number;
  sessionTimeout: number;

  // GitHub issue intake
  githubIntakeLabel: string;
  githubIntakeRepo: string;
  githubIntakeCloseOnPr: boolean;
  githubIntakeRemoveLabelOnPr: boolean;

  // Rate limiting
  ratelimitMaxRetries: number;
  ratelimitBaseDelay: number;

  // History
  historyRetentionDays: number;
}
