import { Command } from 'commander';
import { discoverSession } from '../core/session.js';
import { TaskStore } from '../core/tasks.js';
import { invokeClaude } from '../core/claude.js';
import { resolveSpecInput } from '../core/spec.js';
import { loadConfig } from '../util/config.js';
import { printBanner, logHeader, logInfo, logSuccess, logError } from '../util/logger.js';

export const testInitCommand = new Command('test-init')
  .description('Generate E2E test scenarios from spec or prompt')
  .option('--prompt <text>', 'Generate test scenarios from description')
  .option('--spec <path>', 'Generate test scenarios from spec file')
  .option('-m, --model <model>', 'Claude model')
  .option('-v, --verbose', 'Stream JSON output')
  .action(async (opts) => {
    const config = loadConfig({ model: opts.model, verbose: opts.verbose });

    printBanner('Claude Workflow - Test Init');
    logInfo(`Model: ${config.model}`);

    let specInput;
    if (opts.spec) {
      specInput = resolveSpecInput('spec', opts.spec);
    } else if (opts.prompt) {
      specInput = resolveSpecInput('prompt', opts.prompt);
    } else {
      logInfo('Auto-discovering most recent spec...');
      specInput = resolveSpecInput('auto');
    }

    if (!specInput) {
      logError('No spec found. Use --prompt or --spec.');
      process.exit(1);
    }

    logInfo(`Input mode: ${specInput.mode}`);
    logInfo(`Input value: ${specInput.value}`);

    discoverSession();

    logHeader('Generating Test Scenarios');

    const testPrompt = specInput.mode === 'prompt'
      ? `Use the Skill tool to invoke 'cw-testing' with args 'init'.

Generate E2E test scenarios for the following:
${specInput.value}

This is running non-interactively, so DO NOT use AskUserQuestion — make reasonable decisions and proceed autonomously. Create TEST-* prefixed tasks on the task board.`
      : `Use the Skill tool to invoke 'cw-testing' with args 'init'.

Generate E2E test scenarios from this specification: ${specInput.value}

This is running non-interactively, so DO NOT use AskUserQuestion — make reasonable decisions and proceed autonomously. Create TEST-* prefixed tasks on the task board.`;

    if (!(await invokeClaude(testPrompt, config))) {
      logError('Test scenario generation failed');
      process.exit(1);
    }

    logSuccess('Test scenario generation completed');

    const session = discoverSession();
    if (session) {
      const store = new TaskStore(session.tasksDir);
      const testCount = store.getTestTasks().length;

      if (testCount === 0) {
        logError('No test tasks were created on the task board.');
        process.exit(1);
      }

      logInfo(`Verified ${testCount} test task(s) on the board`);
      logHeader('Test Init Complete');
      store.printTaskStatus();
      store.showTaskList();
      console.log(`\nTest tasks created (${testCount}).`);
      console.log('  Run tests: cw test-loop');
    }
  });
