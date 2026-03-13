import { existsSync, mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { spawnCommand } from '../util/process.js';
import { logInfo, logSuccess, logError, logWarning } from '../util/logger.js';

export async function createWorktree(
  featureName: string,
  opts: { resume?: boolean } = {},
): Promise<string | null> {
  if (!featureName) {
    logError('Feature name is required');
    return null;
  }

  if (!/^[a-z0-9-]+$/.test(featureName)) {
    logError(`Feature name must be lowercase alphanumeric with hyphens: ${featureName}`);
    return null;
  }

  const worktreeDir = `.worktrees/feature-${featureName}`;
  const branchName = `feature/${featureName}`;

  // Ensure .worktrees is gitignored
  const gitignorePath = '.gitignore';
  if (existsSync(gitignorePath)) {
    const content = readFileSync(gitignorePath, 'utf-8');
    if (!content.includes('.worktrees/')) {
      writeFileSync(gitignorePath, content + '\n.worktrees/\n');
      await spawnCommand('git', ['add', '.gitignore']);
      await spawnCommand('git', ['commit', '-m', 'chore: add .worktrees to gitignore', '--', '.gitignore']);
    }
  }

  if (existsSync(worktreeDir)) {
    if (opts.resume) {
      logInfo(`Reusing existing worktree: ${worktreeDir}`);
      return resolve(worktreeDir);
    } else {
      logError(`Worktree already exists: ${worktreeDir}`);
      logInfo('Use --resume to continue from where you left off');
      return null;
    }
  }

  const branchCheck = await spawnCommand('git', ['show-ref', '--verify', '--quiet', `refs/heads/${branchName}`]);

  let result;
  if (branchCheck.exitCode === 0) {
    logWarning(`Branch ${branchName} already exists, using it`);
    result = await spawnCommand('git', ['worktree', 'add', worktreeDir, branchName]);
  } else {
    result = await spawnCommand('git', ['worktree', 'add', worktreeDir, '-b', branchName]);
  }

  if (result.exitCode !== 0) {
    logError('Failed to create worktree');
    return null;
  }

  const claudeDir = join(worktreeDir, '.claude');
  mkdirSync(claudeDir, { recursive: true });
  writeFileSync(
    join(claudeDir, 'settings.local.json'),
    JSON.stringify(
      { env: { CLAUDE_CODE_TASK_LIST_ID: `feature-${featureName}` } },
      null,
      2,
    ) + '\n',
  );

  const absPath = resolve(worktreeDir);
  logSuccess(`Worktree created: ${worktreeDir} (branch: ${branchName})`);
  return absPath;
}
