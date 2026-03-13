import { Command } from 'commander';
import chalk from 'chalk';
import { QueueStore } from '../core/queue-store.js';
import { importGitHubIssues } from '../core/github.js';
import { loadConfig } from '../util/config.js';
import { logInfo, logSuccess, logError } from '../util/logger.js';
import type { QueueItemStatus } from '../types/queue.js';

export const queueCommand = new Command('queue')
  .description('Manage autonomous work queue');

queueCommand
  .command('add')
  .description('Add a work item to the queue')
  .option('--prompt <text>', 'Free-text prompt')
  .option('--spec <path>', 'Pre-existing spec file')
  .option('--name <name>', 'Feature name')
  .option('--priority <n>', 'Priority 1-10 (lower = higher)', '5')
  .option('--project <dir>', 'Project directory')
  .action(async (opts) => {
    const config = loadConfig();
    const queue = new QueueStore(config.autoQueueDir);
    const projectDir = opts.project ?? process.cwd();

    if (!opts.prompt && !opts.spec) {
      logError('Either --prompt or --spec is required');
      process.exit(1);
    }

    const name = opts.name ?? `item-${Date.now()}`;
    const item = queue.add({
      status: 'pending',
      priority: parseInt(opts.priority),
      type: opts.spec ? 'spec' : 'prompt',
      source: 'manual',
      prompt: opts.prompt,
      name,
      spec_path: opts.spec,
      project_dir: projectDir,
    });

    logSuccess(`Queued: ${item.id} (${item.name})`);
  });

queueCommand
  .command('list')
  .description('View queue items')
  .option('--status <s>', 'Filter by status')
  .option('-j, --json', 'Output JSON')
  .action((opts) => {
    const config = loadConfig();
    const queue = new QueueStore(config.autoQueueDir);
    const items = queue.list(opts.status ? { status: opts.status as QueueItemStatus } : undefined);

    if (opts.json) {
      console.log(JSON.stringify(items, null, 2));
      return;
    }

    if (items.length === 0) {
      logInfo('Queue is empty');
      return;
    }

    for (const item of items) {
      const statusColor = {
        pending: chalk.yellow,
        running: chalk.blue,
        done: chalk.green,
        failed: chalk.red,
        rate_limited: chalk.magenta,
        cancelled: chalk.gray,
      }[item.status] ?? chalk.white;

      console.log(`  ${statusColor(`[${item.status}]`)} ${item.id} ${item.name} (priority: ${item.priority}, type: ${item.type})`);
    }

    console.log(`\n  Total: ${items.length}`);
  });

queueCommand
  .command('cancel')
  .description('Cancel a pending queue item')
  .argument('<id>', 'Queue item ID')
  .action((id: string) => {
    const config = loadConfig();
    const queue = new QueueStore(config.autoQueueDir);

    if (queue.cancel(id)) {
      logSuccess(`Cancelled: ${id}`);
    } else {
      logError(`Cannot cancel ${id} (not found or not pending)`);
    }
  });

queueCommand
  .command('retry')
  .description('Retry a failed queue item')
  .argument('<id>', 'Queue item ID')
  .action((id: string) => {
    const config = loadConfig();
    const queue = new QueueStore(config.autoQueueDir);

    if (queue.retry(id)) {
      logSuccess(`Retrying: ${id}`);
    } else {
      logError(`Cannot retry ${id} (not found or not failed)`);
    }
  });

queueCommand
  .command('import')
  .description('Import GitHub issues into the queue')
  .requiredOption('--label <label>', 'GitHub label to filter by')
  .option('--repo <owner/repo>', 'Repository (default: current repo)')
  .action(async (opts) => {
    const config = loadConfig();
    const queue = new QueueStore(config.autoQueueDir);

    const count = await importGitHubIssues(queue, {
      label: opts.label,
      repo: opts.repo,
      projectDir: process.cwd(),
    });

    logSuccess(`Imported ${count} issue(s)`);
  });
