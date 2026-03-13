import { join } from 'node:path';
import { readJson, writeJson, listJsonFiles, ensureDir } from '../util/fs.js';
import type { QueueItem, QueueItemStatus } from '../types/queue.js';

function generateId(): string {
  const now = new Date();
  const date = now.toISOString().slice(0, 10).replace(/-/g, '');
  const seq = String(Math.floor(Math.random() * 999) + 1).padStart(3, '0');
  return `${date}-${seq}`;
}

export class QueueStore {
  constructor(private queueDir: string) {
    ensureDir(queueDir);
  }

  add(item: Omit<QueueItem, 'id' | 'created_at' | 'rate_limit_retries'>): QueueItem {
    const full: QueueItem = {
      ...item,
      id: generateId(),
      created_at: new Date().toISOString(),
      rate_limit_retries: 0,
    };
    writeJson(this.itemPath(full.id), full);
    return full;
  }

  list(filter?: { status?: QueueItemStatus }): QueueItem[] {
    const files = listJsonFiles(this.queueDir);
    const items: QueueItem[] = [];
    for (const f of files) {
      const item = readJson<QueueItem>(f);
      if (!item || !item.id) continue;
      if (filter?.status && item.status !== filter.status) continue;
      items.push(item);
    }
    items.sort((a, b) => a.priority - b.priority || a.created_at.localeCompare(b.created_at));
    return items;
  }

  get(id: string): QueueItem | null {
    return readJson<QueueItem>(this.itemPath(id));
  }

  update(id: string, patch: Partial<QueueItem>): void {
    const item = this.get(id);
    if (!item) return;
    writeJson(this.itemPath(id), { ...item, ...patch });
  }

  cancel(id: string): boolean {
    const item = this.get(id);
    if (!item || item.status !== 'pending') return false;
    this.update(id, { status: 'cancelled' });
    return true;
  }

  retry(id: string): boolean {
    const item = this.get(id);
    if (!item || (item.status !== 'failed' && item.status !== 'rate_limited')) return false;
    this.update(id, {
      status: 'pending',
      started_at: undefined,
      completed_at: undefined,
      exit_code: undefined,
      pr_url: undefined,
      log_dir: undefined,
    });
    return true;
  }

  getNextPending(): QueueItem | null {
    const pending = this.list({ status: 'pending' });
    return pending[0] ?? null;
  }

  hasExistingSource(source: string): boolean {
    return this.list().some((item) => item.source === source && item.status !== 'cancelled');
  }

  private itemPath(id: string): string {
    return join(this.queueDir, `${id}.json`);
  }
}
