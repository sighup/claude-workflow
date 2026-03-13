import { readFileSync, writeFileSync, existsSync, readdirSync, mkdirSync, unlinkSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';

export function readJson<T>(path: string): T | null {
  try {
    return JSON.parse(readFileSync(path, 'utf-8')) as T;
  } catch {
    return null;
  }
}

export function writeJson(path: string, data: unknown): void {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, JSON.stringify(data, null, 2) + '\n');
}

export function fileExists(path: string): boolean {
  return existsSync(path);
}

export function listJsonFiles(dir: string): string[] {
  if (!existsSync(dir)) return [];
  return readdirSync(dir)
    .filter((f) => f.endsWith('.json'))
    .map((f) => join(dir, f));
}

export function ensureDir(dir: string): void {
  mkdirSync(dir, { recursive: true });
}

export function removeFile(path: string): void {
  try {
    unlinkSync(path);
  } catch {
    // ignore
  }
}

export function findLatestFile(dir: string, pattern: RegExp, exclude?: RegExp): string | null {
  if (!existsSync(dir)) return null;

  const files: { path: string; mtime: number }[] = [];

  function walk(d: string): void {
    for (const entry of readdirSync(d, { withFileTypes: true })) {
      const full = join(d, entry.name);
      if (entry.isDirectory()) {
        walk(full);
      } else if (pattern.test(entry.name) && (!exclude || !exclude.test(entry.name))) {
        files.push({ path: full, mtime: statSync(full).mtimeMs });
      }
    }
  }

  walk(dir);
  if (files.length === 0) return null;
  files.sort((a, b) => b.mtime - a.mtime);
  return files[0].path;
}
