import { Command } from 'commander';
import { resolve } from 'node:path';
import { writeFileSync } from 'node:fs';
import { QueueStore } from '../core/queue-store.js';
import { HistoryStore } from '../core/history-store.js';
import { importGitHubIssues, commentOnIssue, removeLabel, closeIssue } from '../core/github.js';
import { acquireLock, releaseLock, lockPath } from '../core/lock.js';
import { RateLimitError } from '../core/claude.js';
import { spawnCommand, sleep } from '../util/process.js';
import { loadConfig } from '../util/config.js';
import { ensureDir } from '../util/fs.js';
import {
  printBanner, logHeader, logInfo, logSuccess, logWarning, logError, formatElapsed,
} from '../util/logger.js';
import type { CwConfig } from '../types/config.js';

async function processQueue(
  projectDir: string,
  config: CwConfig,
  history: HistoryStore,
  dryRun: boolean,
): Promise<{ succeeded: number; failed: number; prUrls: string[] }> {
  const queue = new QueueStore(resolve(projectDir, config.autoQueueDir));
  let succeeded = 0;
  let failed = 0;
  const prUrls: string[] = [];

  // Import GitHub issues if configured
  if (config.githubIntakeLabel) {
    logInfo('Importing GitHub issues...');
    const imported = await importGitHubIssues(queue, {
      label: config.githubIntakeLabel,
      repo: config.githubIntakeRepo || undefined,
      projectDir,
    });
    if (imported > 0) logInfo(`Imported ${imported} issue(s)`);
  }

  const pending = queue.list({ status: 'pending' });
  if (pending.length === 0) {
    logInfo('No pending items in queue');
    return { succeeded, failed, prUrls };
  }

  logInfo(`${pending.length} pending item(s) in queue`);
  const maxItems = Math.min(pending.length, config.autoMaxItems);

  for (let i = 0; i < maxItems; i++) {
    const item = pending[i];
    logHeader(`Processing: ${item.name} (${i + 1}/${maxItems})`);

    if (dryRun) {
      logInfo(`[DRY RUN] Would process: ${item.name} (${item.type}: ${item.prompt?.slice(0, 80) ?? item.spec_path})`);
      continue;
    }

    const lock = acquireLock(lockPath(config.autoLockDir, item.name));
    if (!lock) {
      logWarning(`Could not acquire lock for ${item.name}, skipping`);
      continue;
    }

    try {
      queue.update(item.id, { status: 'running', started_at: new Date().toISOString() });

      const scriptDir = resolve(projectDir, 'bin');
      const pipelineArgs: string[] = [];
      if (item.prompt) pipelineArgs.push('--prompt', item.prompt);
      else if (item.spec_path) pipelineArgs.push('--spec', item.spec_path);
      pipelineArgs.push('--name', item.name, '--auto-pr');

      const result = await spawnCommand(`${scriptDir}/cw-pipeline`, pipelineArgs, {
        cwd: projectDir,
        timeout: config.sessionTimeout,
        env: { CW_NON_INTERACTIVE: 'true' },
      });

      // Save logs
      const logDir = resolve(config.autoLogDir, `${item.id}-${item.name}`);
      ensureDir(logDir);
      writeFileSync(resolve(logDir, 'stdout.log'), result.stdout);
      writeFileSync(resolve(logDir, 'stderr.log'), result.stderr);

      if (result.exitCode === 0) {
        queue.update(item.id, {
          status: 'done',
          completed_at: new Date().toISOString(),
          exit_code: 0,
          log_dir: logDir,
        });
        succeeded++;
        logSuccess(`${item.name}: completed`);

        // GitHub post-PR actions
        if (item.github_issue) {
          const repo = item.github_issue.repo || undefined;
          await commentOnIssue(item.github_issue.number, 'Automated PR created by claude-workflow autonomous execution.', { repo });
          if (config.githubIntakeRemoveLabelOnPr && config.githubIntakeLabel) {
            await removeLabel(item.github_issue.number, config.githubIntakeLabel, { repo });
          }
          if (config.githubIntakeCloseOnPr) {
            await closeIssue(item.github_issue.number, { repo });
          }
        }
      } else {
        queue.update(item.id, {
          status: 'failed',
          completed_at: new Date().toISOString(),
          exit_code: result.exitCode,
          log_dir: logDir,
        });
        failed++;
        logError(`${item.name}: failed (exit code ${result.exitCode}${result.timedOut ? ', timed out' : ''})`);
      }
    } catch (err) {
      if (err instanceof RateLimitError) {
        const retries = (item.rate_limit_retries ?? 0) + 1;
        if (retries >= config.ratelimitMaxRetries) {
          queue.update(item.id, { status: 'rate_limited', rate_limit_retries: retries });
          logError(`${item.name}: rate limited after ${retries} retries`);
          failed++;
        } else {
          queue.update(item.id, { status: 'pending', rate_limit_retries: retries });
          const delay = config.ratelimitBaseDelay * Math.pow(2, retries - 1);
          logWarning(`${item.name}: rate limited, will retry (${retries}/${config.ratelimitMaxRetries})`);
          await sleep(delay * 1000);
        }
      } else {
        queue.update(item.id, {
          status: 'failed',
          completed_at: new Date().toISOString(),
          exit_code: 1,
        });
        failed++;
        logError(`${item.name}: ${err instanceof Error ? err.message : 'unknown error'}`);
      }
    } finally {
      releaseLock(lock);
    }
  }

  return { succeeded, failed, prUrls };
}

export const autoCommand = new Command('auto')
  .description('Run autonomous execution cycle (process work queue)')
  .option('--dry-run', 'Preview without executing')
  .option('--max-items <n>', 'Max items per run')
  .option('--projects <dirs...>', 'Multi-project mode')
  .option('--strategy <s>', 'Multi-project strategy: priority or round-robin')
  .action(async (opts) => {
    const config = loadConfig({
      autoMaxItems: opts.maxItems ? parseInt(opts.maxItems) : undefined,
      autoProjects: opts.projects,
      autoProjectStrategy: opts.strategy,
    });

    printBanner('Claude Workflow - Autonomous Execution');

    const dryRun = opts.dryRun ?? false;
    if (dryRun) logWarning('DRY RUN MODE — no changes will be made');

    // Run doctor quick check
    logInfo('Running pre-flight checks...');
    const doctorResult = await spawnCommand(process.argv[0], [process.argv[1], 'doctor', '--quick'], {
      cwd: process.cwd(),
    });
    if (doctorResult.exitCode !== 0) {
      logError('Pre-flight checks failed. Run "cw doctor" for details.');
      if (!dryRun) process.exit(1);
    }

    const history = new HistoryStore(config.autoLogDir);

    const projects = config.autoProjects.length > 0
      ? config.autoProjects.map((p) => resolve(p))
      : [process.cwd()];

    logInfo(`Projects: ${projects.length}`);
    for (const p of projects) logInfo(`  ${p}`);

    const startTime = Date.now();
    let totalSucceeded = 0;
    let totalFailed = 0;
    const allPrUrls: string[] = [];

    const run = history.createRun(projects[0]);

    for (const projectDir of projects) {
      logHeader(`Project: ${projectDir}`);

      const elapsed = Math.floor((Date.now() - startTime) / 1000);
      if (elapsed >= config.autoGlobalTimeout) {
        logWarning(`Global timeout (${formatElapsed(config.autoGlobalTimeout)}) reached`);
        break;
      }

      const result = await processQueue(projectDir, config, history, dryRun);
      totalSucceeded += result.succeeded;
      totalFailed += result.failed;
      allPrUrls.push(...result.prUrls);
    }

    const elapsed = Math.floor((Date.now() - startTime) / 1000);
    history.completeRun(run.id, {
      items_processed: totalSucceeded + totalFailed,
      items_succeeded: totalSucceeded,
      items_failed: totalFailed,
      pr_urls: allPrUrls,
    });

    logHeader('Summary');
    logInfo(`Duration: ${formatElapsed(elapsed)}`);
    logInfo(`Succeeded: ${totalSucceeded}`);
    logInfo(`Failed: ${totalFailed}`);
    if (allPrUrls.length > 0) {
      logInfo('PRs created:');
      for (const url of allPrUrls) logInfo(`  ${url}`);
    }

    if (totalFailed > 0) {
      logWarning('Some items failed. Run "cw queue list --status failed" for details.');
      process.exit(1);
    } else {
      logSuccess('All items completed successfully');
    }
  });
