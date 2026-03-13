import { join } from 'node:path';
import { readdirSync, rmSync } from 'node:fs';
import { readJson, writeJson, ensureDir, fileExists } from '../util/fs.js';

export interface RunRecord {
  id: string;
  started_at: string;
  completed_at?: string;
  items_processed: number;
  items_succeeded: number;
  items_failed: number;
  duration_seconds?: number;
  pr_urls: string[];
  project_dir: string;
}

export class HistoryStore {
  constructor(private logDir: string) {
    ensureDir(logDir);
  }

  createRun(projectDir: string): RunRecord {
    const now = new Date();
    const id = now.toISOString().replace(/[:.]/g, '-').slice(0, 19);
    const record: RunRecord = {
      id,
      started_at: now.toISOString(),
      items_processed: 0,
      items_succeeded: 0,
      items_failed: 0,
      pr_urls: [],
      project_dir: projectDir,
    };
    const runDir = join(this.logDir, id);
    ensureDir(runDir);
    writeJson(join(runDir, 'run.json'), record);
    return record;
  }

  updateRun(id: string, patch: Partial<RunRecord>): void {
    const runDir = join(this.logDir, id);
    const runFile = join(runDir, 'run.json');
    const record = readJson<RunRecord>(runFile);
    if (!record) return;
    writeJson(runFile, { ...record, ...patch });
  }

  completeRun(id: string, results: Partial<RunRecord>): void {
    const now = new Date();
    const runDir = join(this.logDir, id);
    const runFile = join(runDir, 'run.json');
    const record = readJson<RunRecord>(runFile);
    if (!record) return;

    const started = new Date(record.started_at);
    const duration = Math.floor((now.getTime() - started.getTime()) / 1000);

    writeJson(runFile, {
      ...record,
      ...results,
      completed_at: now.toISOString(),
      duration_seconds: duration,
    });
  }

  list(limit?: number): RunRecord[] {
    if (!fileExists(this.logDir)) return [];
    const dirs = readdirSync(this.logDir, { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .map((d) => d.name)
      .sort()
      .reverse();

    const records: RunRecord[] = [];
    for (const dir of dirs.slice(0, limit)) {
      const record = readJson<RunRecord>(join(this.logDir, dir, 'run.json'));
      if (record) records.push(record);
    }
    return records;
  }

  show(id: string): RunRecord | null {
    return readJson<RunRecord>(join(this.logDir, id, 'run.json'));
  }

  clean(olderThanDays: number): number {
    if (!fileExists(this.logDir)) return 0;
    const cutoff = Date.now() - olderThanDays * 24 * 60 * 60 * 1000;
    const dirs = readdirSync(this.logDir, { withFileTypes: true }).filter((d) => d.isDirectory());

    let removed = 0;
    for (const dir of dirs) {
      const fullPath = join(this.logDir, dir.name);
      try {
        // Parse ID as date to check age
        const idDate = new Date(dir.name.replace(/-/g, (m, offset: number) => {
          // First 10 chars are date part: YYYY-MM-DD -> restore colons for time
          if (offset > 12) return ':';
          return m;
        }));
        if (idDate.getTime() < cutoff) {
          rmSync(fullPath, { recursive: true });
          removed++;
        }
      } catch {
        // ignore unparseable dirs
      }
    }
    return removed;
  }
}
