import { Command } from 'commander';
import { discoverSession } from '../core/session.js';
import { TaskStore } from '../core/tasks.js';
import { invokeClaude } from '../core/claude.js';
import { resolveSpecInput } from '../core/spec.js';
import { loadConfig } from '../util/config.js';
import { printBanner, logHeader, logInfo, logSuccess, logError } from '../util/logger.js';

export const initCommand = new Command('init')
  .description('Spec + Plan initializer (combines cw-spec and cw-plan)')
  .option('--prompt <text>', 'Generate spec from this prompt, then plan tasks')
  .option('--spec <path>', 'Use an existing spec file, skip to planning')
  .option('-m, --model <model>', 'Claude model')
  .option('-v, --verbose', 'Stream JSON output')
  .action(async (opts) => {
    const config = loadConfig({
      model: opts.model,
      verbose: opts.verbose,
    });

    printBanner('Claude Workflow - Init (Spec + Plan)');
    logInfo(`Model: ${config.model}`);

    let specPath: string;

    // Phase 1: Spec
    if (opts.spec) {
      const input = resolveSpecInput('spec', opts.spec);
      if (!input) process.exit(1);
      logInfo(`Using existing spec: ${input.value}`);
      specPath = input.value;
    } else if (opts.prompt) {
      logHeader('Phase 1: Generating Spec');
      logInfo(`Prompt: ${opts.prompt}`);

      const specPrompt = `Use the Skill tool to invoke 'cw-spec'.

Generate a specification for the following feature. This is running non-interactively, so DO NOT use AskUserQuestion — make reasonable decisions and proceed autonomously.

Feature description:
${opts.prompt}

Important: Generate the complete spec without asking questions. Use your best judgment for any decisions that would normally require user input. Write the spec to docs/specs/ following the standard naming convention.`;

      if (!(await invokeClaude(specPrompt, config))) {
        logError('Spec generation failed');
        process.exit(1);
      }

      logSuccess('Spec generation completed');

      const autoSpec = resolveSpecInput('auto');
      if (!autoSpec) {
        logError('Could not find generated spec file');
        process.exit(1);
      }
      specPath = autoSpec.value;
    } else {
      logInfo('Auto-discovering most recent spec...');
      const autoSpec = resolveSpecInput('auto');
      if (!autoSpec) {
        logError('No spec found. Use --prompt or --spec to provide one.');
        process.exit(1);
      }
      specPath = autoSpec.value;
      logInfo(`Found spec: ${specPath}`);
    }

    // Phase 2: Plan
    logHeader('Phase 2: Generating Task Plan');
    logInfo(`Spec: ${specPath}`);

    const planPrompt = `Use the Skill tool to invoke 'cw-plan'.

Create a task graph from this specification: ${specPath}

This is running non-interactively, so DO NOT use AskUserQuestion — make reasonable decisions and proceed autonomously. Specifically:
- Skip the CLAUDE_CODE_TASK_LIST_ID check (Phase 0)
- Create parent tasks for each demoable unit
- Automatically generate sub-tasks (do not wait for approval)
- Set up all dependencies between tasks

Proceed through all phases without stopping for user input.`;

    if (!(await invokeClaude(planPrompt, config))) {
      logError('Plan generation failed');
      process.exit(2);
    }

    logSuccess('Plan generation completed');

    // Summary
    const session = discoverSession();
    if (session) {
      logHeader('Init Complete');
      logInfo(`Spec: ${specPath}`);
      if (session.taskListId) logInfo(`Task list: ${session.taskListId}`);
      else logInfo(`Session: ${session.sessionId}`);
      const store = new TaskStore(session.tasksDir);
      store.printTaskStatus();
      store.showTaskList();

      console.log('');
      console.log('Ready for execution.');
      console.log('  Autonomous:    cw loop');
      console.log('  Parallel:      cw loop -d');
      console.log('  Interactive:   cw interactive');
      console.log('  Full pipeline: cw pipeline');
    }
  });
