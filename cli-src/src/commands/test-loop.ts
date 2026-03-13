import { Command } from 'commander';
import chalk from 'chalk';
import { discoverSession } from '../core/session.js';
import { TaskStore } from '../core/tasks.js';
import { invokeClaude } from '../core/claude.js';
import { loadConfig } from '../util/config.js';
import { sleep } from '../util/process.js';
import { printBanner, logHeader, logInfo, logSuccess, logWarning, logError, formatElapsed } from '../util/logger.js';

export const testLoopCommand = new Command('test-loop')
  .description('Test execution with auto-fix cycles')
  .argument('[project-path]', 'Project directory', process.cwd())
  .option('-c, --max-cycles <n>', 'Max fix cycles', '3')
  .option('-n, --max-iter <n>', 'Max iterations per cycle', '50')
  .option('-m, --model <model>', 'Claude model')
  .option('-s, --sleep <n>', 'Seconds between iterations', '5')
  .option('-v, --verbose', 'Stream JSON output')
  .action(async (projectPath: string, opts) => {
    const config = loadConfig({
      model: opts.model,
      maxIterations: opts.maxIter ? parseInt(opts.maxIter) : undefined,
      sleep: opts.sleep ? parseInt(opts.sleep) : undefined,
      verbose: opts.verbose,
    });

    const maxCycles = parseInt(opts.maxCycles ?? '3');

    printBanner('Claude Workflow - Test Loop');
    logInfo(`Project: ${projectPath}`);
    logInfo(`Model: ${config.model}`);
    logInfo(`Max cycles: ${maxCycles}`);
    logInfo(`Max iterations per cycle: ${config.maxIterations}`);

    logHeader('Discovering session');
    const session = discoverSession(projectPath);
    if (!session) {
      logError('No session with tasks found.');
      process.exit(4);
    }

    const store = new TaskStore(session.tasksDir);
    const startTime = Date.now();

    for (let cycle = 1; cycle <= maxCycles; cycle++) {
      logHeader(`Test Cycle ${cycle} / ${maxCycles}`);

      if (cycle === 1) {
        const counts = store.getTestTaskCounts();
        if (counts.total === 0) {
          logError('No test tasks found. Run cw test-init first.');
          process.exit(3);
        }
        logInfo(`Found ${counts.total} test task(s)`);
      }

      let failures = 0;
      for (let iter = 1; iter <= config.maxIterations; iter++) {
        if (store.allTestsPassed()) {
          const e = Math.floor((Date.now() - startTime) / 1000);
          logSuccess(`All tests passed! (Cycle ${cycle}, Runtime: ${formatElapsed(e)})`);
          store.printTaskStatus();
          process.exit(0);
        }

        const pendingTests = store.getTestTaskCounts().pending;
        if (pendingTests === 0) break;

        const e = Math.floor((Date.now() - startTime) / 1000);
        logInfo(`Cycle ${cycle}, Iteration ${iter} / ${config.maxIterations} [Runtime: ${formatElapsed(e)}]`);
        logInfo(`Pending test tasks: ${pendingTests}`);

        const ok = await invokeClaude(
          "Use the Skill tool to invoke 'cw-testing' with args 'run'. Execute the test loop. Proceed autonomously.",
          config,
          { sessionId: session.sessionId || undefined },
        );

        if (ok) {
          logSuccess('Test execution completed');
          failures = 0;
        } else {
          failures++;
          logError(`Test execution failed (failure ${failures}/${config.maxFailures})`);
          if (failures >= config.maxFailures) {
            logError('Max consecutive failures reached.');
            process.exit(2);
          }
        }

        if (iter < config.maxIterations) await sleep(config.sleep * 1000);
      }

      logHeader(`Cycle ${cycle} Results`);
      const counts = store.getTestTaskCounts();
      console.log(`  Tests:   ${chalk.green(`${counts.passed} passed`)} / ${chalk.red(`${counts.failed} failed`)} / ${chalk.yellow(`${counts.pending} pending`)} (total: ${counts.total})`);

      if (store.allTestsPassed()) {
        const e = Math.floor((Date.now() - startTime) / 1000);
        logSuccess(`All tests passed! (Runtime: ${formatElapsed(e)})`);
        process.exit(0);
      }

      const fixCount = store.getPendingFixCount();
      if (fixCount > 0) {
        logInfo(`Found ${fixCount} pending FIX task(s). Executing...`);
        for (let i = 0; i < config.maxIterations; i++) {
          if (store.getPendingFixCount() === 0) break;
          await invokeClaude(
            "Use the Skill tool to invoke 'cw-execute'. Execute the next pending FIX-* task. Proceed autonomously.",
            config,
            { sessionId: session.sessionId || undefined },
          );
          await sleep(config.sleep * 1000);
        }
      }

      if (cycle < maxCycles) {
        logInfo('Resetting failed test tasks...');
        await invokeClaude(
          'Reset all failed test tasks back to pending. Use TaskList to find test tasks not in pending/completed status, then call TaskUpdate to set status to "pending". Proceed autonomously.',
          config,
          { sessionId: session.sessionId || undefined },
        );
      }
    }

    const elapsed = Math.floor((Date.now() - startTime) / 1000);
    logError(`Max fix cycles (${maxCycles}) exhausted. (Runtime: ${formatElapsed(elapsed)})`);
    const counts = store.getTestTaskCounts();
    console.log(`\n  Final: ${chalk.green(`${counts.passed} passed`)} / ${chalk.red(`${counts.failed} failed`)} (total: ${counts.total})\n`);
    process.exit(5);
  });
