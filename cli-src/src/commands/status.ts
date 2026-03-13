import { Command } from 'commander';
import chalk from 'chalk';
import { discoverSession } from '../core/session.js';
import { TaskStore } from '../core/tasks.js';
import { QueueStore } from '../core/queue-store.js';
import { loadConfig } from '../util/config.js';
import { printBanner, logInfo, logError } from '../util/logger.js';

export const statusCommand = new Command('status')
  .description('Display task progress')
  .argument('[project-path]', 'Project directory', process.cwd())
  .option('-l, --list', 'Show full task list')
  .option('-f, --failed', 'Show only failed tasks')
  .option('-p, --pending', 'Show only pending unblocked tasks')
  .option('-j, --json', 'Output raw JSON summary')
  .option('-q, --queue', 'Show work queue status')
  .action((projectPath: string, opts) => {
    const session = discoverSession(projectPath);
    if (!session) {
      logError(`No session with tasks found for: ${projectPath}`);
      logInfo("Run '/cw-plan' first to create tasks from a spec.");
      process.exit(1);
    }

    const store = new TaskStore(session.tasksDir);

    if (opts.json) {
      console.log(JSON.stringify(store.getCounts()));
      return;
    }

    printBanner('Claude Workflow Status');
    if (session.taskListId) {
      logInfo(`Task list: ${session.taskListId}`);
    } else {
      logInfo(`Session: ${session.sessionId}`);
    }

    if (opts.failed) {
      console.log('');
      console.log(chalk.red('Failed Tasks:'));
      store.showFailedTasks();
    } else if (opts.pending) {
      console.log('');
      console.log(chalk.yellow('Pending Unblocked Tasks:'));
      store.showPendingUnblockedTasks();
    } else if (opts.list) {
      console.log('');
      store.showTaskList();
    } else {
      store.printTaskStatus();
    }

    const specPath = store.getSpecPath();
    if (specPath) {
      console.log(`  Spec: ${chalk.cyan(specPath)}`);
      console.log('');
    }

    if (opts.queue) {
      const config = loadConfig();
      const queue = new QueueStore(config.autoQueueDir);
      const items = queue.list();
      const pending = items.filter((i) => i.status === 'pending').length;
      const running = items.filter((i) => i.status === 'running').length;
      const done = items.filter((i) => i.status === 'done').length;
      const failed = items.filter((i) => i.status === 'failed').length;

      console.log('');
      console.log(chalk.cyan('Work Queue:'));
      console.log(`  ${chalk.yellow('Pending:')}  ${pending}`);
      console.log(`  ${chalk.blue('Running:')}  ${running}`);
      console.log(`  ${chalk.green('Done:')}     ${done}`);
      console.log(`  ${chalk.red('Failed:')}   ${failed}`);
      console.log('');
    }
  });
