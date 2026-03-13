import { Command } from 'commander';
import chalk from 'chalk';
import { HistoryStore } from '../core/history-store.js';
import { loadConfig } from '../util/config.js';
import { logInfo, logSuccess, formatElapsed } from '../util/logger.js';

export const historyCommand = new Command('history')
  .description('Execution history viewer');

historyCommand
  .command('list')
  .description('Show recent runs')
  .option('--last <n>', 'Number of runs to show', '10')
  .action((opts) => {
    const config = loadConfig();
    const store = new HistoryStore(config.autoLogDir);
    const runs = store.list(parseInt(opts.last));

    if (runs.length === 0) {
      logInfo('No execution history found');
      return;
    }

    for (const run of runs) {
      const status = run.items_failed > 0 ? chalk.red('FAIL') : chalk.green('PASS');
      const duration = run.duration_seconds ? formatElapsed(run.duration_seconds) : 'running';
      const prs = run.pr_urls.length > 0 ? ` | PRs: ${run.pr_urls.length}` : '';

      console.log(
        `  ${status} ${run.id} | ${run.items_succeeded}/${run.items_processed} succeeded | ${duration}${prs}`,
      );
    }
  });

historyCommand
  .command('show')
  .description('Show detailed run report')
  .argument('<run-id>', 'Run ID')
  .action((runId: string) => {
    const config = loadConfig();
    const store = new HistoryStore(config.autoLogDir);
    const run = store.show(runId);

    if (!run) {
      logInfo(`Run not found: ${runId}`);
      return;
    }

    console.log(JSON.stringify(run, null, 2));
  });

historyCommand
  .command('clean')
  .description('Prune old runs')
  .option('--older-than <days>', 'Days to keep', '30')
  .action((opts) => {
    const config = loadConfig();
    const store = new HistoryStore(config.autoLogDir);
    const removed = store.clean(parseInt(opts.olderThan));
    logSuccess(`Removed ${removed} old run(s)`);
  });
