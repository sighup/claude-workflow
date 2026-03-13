import { Command } from 'commander';
import { discoverSession } from '../core/session.js';
import { TaskStore } from '../core/tasks.js';
import { invokeClaude } from '../core/claude.js';
import { loadConfig } from '../util/config.js';
import { sleep } from '../util/process.js';
import { printBanner, logHeader, logInfo, logSuccess, logWarning, logError, formatElapsed } from '../util/logger.js';

export const loopCommand = new Command('loop')
  .description('Autonomous execution loop for tasks')
  .argument('[project-path]', 'Project directory', process.cwd())
  .option('-m, --model <model>', 'Claude model')
  .option('-n, --max-iter <n>', 'Maximum iterations', '50')
  .option('-s, --sleep <n>', 'Seconds between iterations', '5')
  .option('-d, --dispatch', 'Use cw-dispatch for parallel execution')
  .option('-v, --verbose', 'Stream JSON output')
  .action(async (projectPath: string, opts) => {
    const config = loadConfig({
      model: opts.model,
      maxIterations: opts.maxIter ? parseInt(opts.maxIter) : undefined,
      sleep: opts.sleep ? parseInt(opts.sleep) : undefined,
      verbose: opts.verbose,
    });

    printBanner('Claude Workflow - Autonomous Loop');

    logInfo(`Project: ${projectPath}`);
    logInfo(`Model: ${config.model}`);
    logInfo(`Max iterations: ${config.maxIterations}`);
    logInfo(`Sleep between: ${config.sleep}s`);
    logInfo(`Max failures: ${config.maxFailures}`);
    logInfo(`Mode: ${opts.dispatch ? 'dispatch (parallel)' : 'execute (sequential)'}`);

    logHeader('Discovering session');

    const session = discoverSession(projectPath);
    if (!session) {
      logError('No session with tasks found.');
      logInfo("Run '/cw-plan' first to create tasks from a spec.");
      process.exit(4);
    }

    const store = new TaskStore(session.tasksDir);
    store.printTaskStatus();
    store.showTaskList();

    const skillPrompt = opts.dispatch
      ? "Use the Skill tool to invoke 'cw-dispatch'. Execute available tasks in parallel from the task board."
      : "Use the Skill tool to invoke 'cw-execute'. Execute the next available task from the task board.";

    const startTime = Date.now();
    let failures = 0;

    for (let iteration = 1; iteration <= config.maxIterations; iteration++) {
      const elapsed = Math.floor((Date.now() - startTime) / 1000);
      logHeader(`Iteration ${iteration} / ${config.maxIterations}  [Runtime: ${formatElapsed(elapsed)}]`);

      if (store.isComplete()) {
        const e = Math.floor((Date.now() - startTime) / 1000);
        logSuccess(`All tasks completed! (Runtime: ${formatElapsed(e)})`);
        store.printTaskStatus();
        process.exit(0);
      }

      const pending = store.getPendingUnblocked();
      if (pending.length === 0) {
        const e = Math.floor((Date.now() - startTime) / 1000);
        logWarning(`No unblocked pending tasks available. (Runtime: ${formatElapsed(e)})`);
        store.printTaskStatus();
        process.exit(3);
      }

      const nextId = store.getNextTaskId();
      logInfo(`Next task: ${nextId} (${pending.length} pending unblocked)`);

      const completedBefore = store.getCompletedCount();

      logInfo(`Invoking Claude with ${opts.dispatch ? 'cw-dispatch' : 'cw-execute'}...`);
      const success = await invokeClaude(skillPrompt, config, { sessionId: session.sessionId || undefined });

      if (success) {
        logSuccess('Execution completed');
        failures = 0;

        const completedAfter = store.getCompletedCount();
        if (completedAfter === completedBefore) {
          logWarning('No tasks were marked completed. Worker may have bypassed cw-execute.');
        } else {
          logInfo(`Tasks completed this iteration: ${completedAfter - completedBefore}`);
        }
      } else {
        failures++;
        logError(`Execution failed (failure ${failures}/${config.maxFailures})`);

        if (failures >= config.maxFailures) {
          const e = Math.floor((Date.now() - startTime) / 1000);
          logError(`Max consecutive failures reached. Aborting. (Runtime: ${formatElapsed(e)})`);
          store.printTaskStatus();
          process.exit(2);
        }
      }

      store.printTaskStatus();

      if (iteration < config.maxIterations) {
        logInfo(`Sleeping ${config.sleep}s before next iteration...`);
        await sleep(config.sleep * 1000);
      }
    }

    const elapsed = Math.floor((Date.now() - startTime) / 1000);
    logWarning(`Max iterations (${config.maxIterations}) exhausted. (Runtime: ${formatElapsed(elapsed)})`);
    store.printTaskStatus();
    process.exit(1);
  });
