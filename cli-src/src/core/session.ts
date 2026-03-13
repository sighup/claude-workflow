import { join } from 'node:path';
import { existsSync, readdirSync } from 'node:fs';
import { readJson, listJsonFiles } from '../util/fs.js';
import { logInfo, logError, logWarning } from '../util/logger.js';

const CLAUDE_DIR = join(process.env.HOME ?? '', '.claude');
const CLAUDE_TASKS_DIR = join(CLAUDE_DIR, 'tasks');
const CLAUDE_PROJECTS_DIR = join(CLAUDE_DIR, 'projects');

export interface SessionInfo {
  sessionId: string;
  taskListId: string;
  tasksDir: string;
}

function encodeProjectPath(path: string): string {
  return path.replace(/^\//, '-').replace(/\//g, '-');
}

function resolveTaskListId(projectPath: string): string | null {
  if (process.env.CLAUDE_CODE_TASK_LIST_ID) {
    return process.env.CLAUDE_CODE_TASK_LIST_ID;
  }

  const localSettings = readJson<{ env?: { CLAUDE_CODE_TASK_LIST_ID?: string } }>(
    join(projectPath, '.claude', 'settings.local.json'),
  );
  if (localSettings?.env?.CLAUDE_CODE_TASK_LIST_ID) {
    return localSettings.env.CLAUDE_CODE_TASK_LIST_ID;
  }

  const settings = readJson<{ env?: { CLAUDE_CODE_TASK_LIST_ID?: string } }>(
    join(projectPath, '.claude', 'settings.json'),
  );
  if (settings?.env?.CLAUDE_CODE_TASK_LIST_ID) {
    return settings.env.CLAUDE_CODE_TASK_LIST_ID;
  }

  return null;
}

function hasJsonFiles(dir: string): boolean {
  return listJsonFiles(dir).length > 0;
}

function warnCorruptTasks(tasksDir: string): void {
  const files = listJsonFiles(tasksDir);
  let corrupt = 0;
  for (const f of files) {
    try {
      const content = require('node:fs').readFileSync(f, 'utf-8');
      JSON.parse(content);
    } catch {
      corrupt++;
    }
  }
  if (corrupt > 0) {
    logWarning(`${corrupt} corrupt task file(s) will be skipped`);
  }
}

export function discoverSession(projectPath: string = process.cwd()): SessionInfo | null {
  const taskListId = resolveTaskListId(projectPath);
  if (taskListId) {
    const tlDir = join(CLAUDE_TASKS_DIR, taskListId);
    if (existsSync(tlDir) && hasJsonFiles(tlDir)) {
      logInfo(`Task list: ${taskListId}`);
      logInfo(`Tasks dir: ${tlDir}`);
      warnCorruptTasks(tlDir);
      return { sessionId: '', taskListId, tasksDir: tlDir };
    }
  }

  const encodedPath = encodeProjectPath(projectPath);
  const sessionsIndex = join(CLAUDE_PROJECTS_DIR, encodedPath, 'sessions-index.json');

  if (!existsSync(sessionsIndex)) {
    logError(`No sessions found for project: ${projectPath}`);
    return null;
  }

  const index = readJson<{ entries: { sessionId: string; modified: string }[] }>(sessionsIndex);
  if (!index?.entries) {
    logError(`No session with tasks found for project: ${projectPath}`);
    return null;
  }

  const sorted = [...index.entries].sort(
    (a, b) => new Date(b.modified).getTime() - new Date(a.modified).getTime(),
  );

  for (const entry of sorted) {
    const tasksDir = join(CLAUDE_TASKS_DIR, entry.sessionId);
    if (existsSync(tasksDir)) {
      const contents = readdirSync(tasksDir);
      if (contents.length > 0) {
        logInfo(`Session: ${entry.sessionId}`);
        logInfo(`Tasks dir: ${tasksDir}`);
        warnCorruptTasks(tasksDir);
        return { sessionId: entry.sessionId, taskListId: '', tasksDir };
      }
    }
  }

  logError(`No session with tasks found for project: ${projectPath}`);
  return null;
}
