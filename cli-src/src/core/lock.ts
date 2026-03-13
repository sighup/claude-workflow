import { openSync, closeSync, writeFileSync, readFileSync, unlinkSync, existsSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { logInfo, logWarning } from '../util/logger.js';

export interface LockHandle {
  path: string;
  fd: number;
}

function isPidAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

export function acquireLock(lockPath: string): LockHandle | null {
  mkdirSync(dirname(lockPath), { recursive: true });

  if (existsSync(lockPath)) {
    try {
      const content = readFileSync(lockPath, 'utf-8').trim();
      const pid = parseInt(content, 10);
      if (!isNaN(pid) && !isPidAlive(pid)) {
        logWarning(`Removing stale lock (PID ${pid} is dead): ${lockPath}`);
        unlinkSync(lockPath);
      } else {
        logWarning(`Lock held by PID ${content}: ${lockPath}`);
        return null;
      }
    } catch {
      try { unlinkSync(lockPath); } catch { /* ignore */ }
    }
  }

  try {
    const fd = openSync(lockPath, 'wx');
    writeFileSync(lockPath, String(process.pid));
    logInfo(`Lock acquired: ${lockPath}`);
    return { path: lockPath, fd };
  } catch {
    return null;
  }
}

export function releaseLock(handle: LockHandle): void {
  try { closeSync(handle.fd); } catch { /* ignore */ }
  try { unlinkSync(handle.path); } catch { /* ignore */ }
  logInfo(`Lock released: ${handle.path}`);
}

export function lockPath(lockDir: string, name: string): string {
  return join(lockDir, `${name}.lock`);
}
