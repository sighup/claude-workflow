import { Command } from 'commander';
import { createInterface } from 'node:readline';
import chalk from 'chalk';
import { discoverSession } from '../core/session.js';
import { TaskStore } from '../core/tasks.js';
import { invokeClaude } from '../core/claude.js';
import { spawnCommand } from '../util/process.js';
import { loadConfig } from '../util/config.js';
import { printBanner, logHeader, logInfo, logSuccess, logError, logWarning } from '../util/logger.js';

function prompt(question: string): Promise<string> {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

export const interactiveCommand = new Command('interactive')
  .description('Human-in-the-loop task execution')
  .argument('[project-path]', 'Project directory', process.cwd())
  .option('-m, --model <model>', 'Claude model')
  .action(async (projectPath: string, opts) => {
    const config = loadConfig({ model: opts.model });

    printBanner('Claude Workflow - Interactive Mode');
    logInfo(`Project: ${projectPath}`);
    logInfo(`Model: ${config.model}`);

    const session = discoverSession(projectPath);
    if (!session) {
      logError("No session with tasks found. Run '/cw-plan' first.");
      process.exit(1);
    }

    const store = new TaskStore(session.tasksDir);
    store.printTaskStatus();
    store.showTaskList();

    const skipped = new Set<string>();

    while (true) {
      console.log('');
      logHeader('Task Selection');

      if (store.isComplete()) {
        logSuccess('All tasks completed!');
        console.log(`\n${chalk.green("Run /cw-validate to verify implementation.")}`);
        process.exit(0);
      }

      const pending = store.getPendingUnblocked().filter((t) => !skipped.has(t.id));
      if (pending.length === 0) {
        logWarning('No remaining unblocked tasks.');
        store.showTaskList();
        process.exit(0);
      }

      pending.sort((a, b) => {
        const an = parseInt(a.id); const bn = parseInt(b.id);
        if (!isNaN(an) && !isNaN(bn)) return an - bn;
        return a.id.localeCompare(b.id);
      });

      const next = pending[0];
      console.log(`\n  Next: ${chalk.cyan(next.id)} - ${next.subject}\n`);
      console.log(`  ${chalk.yellow('[Enter]')} Execute  ${chalk.yellow('[s]')} Skip  ${chalk.yellow('[q]')} Quit  ${chalk.yellow('[d]')} Diff`);

      const action = await prompt('  > ');

      if (action === 'q' || action === 'Q') {
        logInfo('Quitting.');
        process.exit(0);
      } else if (action === 's' || action === 'S') {
        logInfo(`Skipping ${next.id}`);
        skipped.add(next.id);
        continue;
      } else if (action === 'd' || action === 'D') {
        const diff = await spawnCommand('git', ['diff', '--stat', 'HEAD~1']);
        console.log(diff.stdout || '(no changes)');
        continue;
      } else if (action === 'v' || action === 'V') {
        await invokeClaude("Use the Skill tool to invoke 'cw-validate'.", config, {
          sessionId: session.sessionId || undefined,
        });
        continue;
      }

      logInfo(`Executing ${next.id}...`);
      const ok = await invokeClaude(
        "Use the Skill tool to invoke 'cw-execute'. Execute the next available task from the task board.",
        config,
        { sessionId: session.sessionId || undefined },
      );

      if (ok) logSuccess('Task completed');
      else logError('Task execution failed');

      store.printTaskStatus();

      console.log(`  ${chalk.yellow('[Enter]')} Next  ${chalk.yellow('[r]')} Retry  ${chalk.yellow('[v]')} Validate  ${chalk.yellow('[q]')} Quit`);
      const postAction = await prompt('  > ');

      if (postAction === 'q' || postAction === 'Q') process.exit(0);
      else if (postAction === 'v' || postAction === 'V') {
        await invokeClaude("Use the Skill tool to invoke 'cw-validate'.", config, {
          sessionId: session.sessionId || undefined,
        });
      }
    }
  });
