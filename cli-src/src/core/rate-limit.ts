import { sleep } from '../util/process.js';
import { logWarning, logError } from '../util/logger.js';

const RATE_LIMIT_PATTERNS = /429|rate.?limit|too many requests/i;

export function isRateLimited(stderr: string): boolean {
  return RATE_LIMIT_PATTERNS.test(stderr);
}

export async function retryWithBackoff<T>(
  fn: () => Promise<T>,
  opts: {
    maxRetries: number;
    baseDelay: number;
    onRateLimit?: () => void;
  },
): Promise<T> {
  for (let attempt = 1; attempt <= opts.maxRetries; attempt++) {
    try {
      return await fn();
    } catch (err) {
      if (err instanceof Error && isRateLimited(err.message)) {
        if (attempt >= opts.maxRetries) {
          logError(`Rate limited after ${opts.maxRetries} retries`);
          throw err;
        }
        const delay = opts.baseDelay * Math.pow(2, attempt - 1);
        logWarning(`Rate limited. Retrying in ${delay}s (attempt ${attempt}/${opts.maxRetries})...`);
        opts.onRateLimit?.();
        await sleep(delay * 1000);
      } else {
        throw err;
      }
    }
  }
  throw new Error('Max retries exceeded');
}
