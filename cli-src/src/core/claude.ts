import { spawnCommand, sleep } from '../util/process.js';
import { logError, logWarning } from '../util/logger.js';
import type { CwConfig } from '../types/config.js';

const CRASH_PATTERNS = /No messages returned|unhandled|SIGTERM|SIGKILL/;
const RATE_LIMIT_PATTERNS = /429|rate.?limit|too many requests/i;

export class RateLimitError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'RateLimitError';
  }
}

export async function invokeClaude(
  prompt: string,
  config: CwConfig,
  opts: {
    model?: string;
    sessionId?: string;
    cwd?: string;
  } = {},
): Promise<boolean> {
  const model = opts.model ?? config.model;
  const args = ['--print', '--model', model, '--dangerously-skip-permissions'];

  if (config.verbose) {
    args.push('--verbose', '--output-format', 'stream-json');
  }

  if (opts.sessionId) {
    args.push('--resume', opts.sessionId);
  }

  args.push('-p', prompt);

  const timeout = config.timeout > 0 ? config.timeout : undefined;

  for (let attempt = 1; attempt <= config.invokeRetries; attempt++) {
    const result = await spawnCommand('claude', args, {
      cwd: opts.cwd,
      timeout,
    });

    if (result.timedOut) {
      logError(`Claude invocation timed out after ${config.timeout}s (attempt ${attempt}/${config.invokeRetries})`);
    } else if (RATE_LIMIT_PATTERNS.test(result.stderr)) {
      throw new RateLimitError(result.stderr);
    } else if (CRASH_PATTERNS.test(result.stderr)) {
      logError(`Claude CLI crashed: ${result.stderr.split('\n')[0]} (attempt ${attempt}/${config.invokeRetries})`);
    } else if (result.exitCode === 0) {
      return true;
    } else {
      logError(`Claude invocation failed with exit code ${result.exitCode} (attempt ${attempt}/${config.invokeRetries})`);
    }

    if (attempt < config.invokeRetries) {
      const delay = config.retryDelay * attempt;
      logWarning(`Retrying in ${delay}s...`);
      await sleep(delay * 1000);
    }
  }

  logError(`All ${config.invokeRetries} attempts failed`);
  return false;
}
