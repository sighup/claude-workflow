import { Command } from 'commander';
import { resolve } from 'node:path';
import { existsSync } from 'node:fs';
import chalk from 'chalk';
import { discoverSession } from '../core/session.js';
import { TaskStore } from '../core/tasks.js';
import { invokeClaude } from '../core/claude.js';
import { createWorktree } from '../core/worktree.js';
import {
  pipelineStateInit, pipelineCheckpoint, pipelineGetResumeStage,
  pipelineStateExists, pipelineReadState, pipelineStageName,
} from '../core/pipeline-state.js';
import { loadConfig } from '../util/config.js';
import { spawnCommand } from '../util/process.js';
import {
  printBanner, logHeader, logInfo, logSuccess, logWarning, logError, formatElapsed,
} from '../util/logger.js';
import type { CwConfig } from '../types/config.js';
import type { PipelineFlags } from '../types/pipeline.js';

interface FeatureSpec {
  name: string;
  mode: string;
  value: string;
}

async function runFeaturePipeline(
  feature: FeatureSpec,
  config: CwConfig,
  flags: PipelineFlags,
  resumeMode: boolean,
  fromStage?: number,
): Promise<boolean> {
  const originalDir = process.cwd();
  let workDir = originalDir;
  let startStage = 1;
  let mode = feature.mode;
  let value = feature.value;

  logHeader(`Pipeline: ${feature.name}`);

  // Resume logic
  if (resumeMode) {
    if (!flags.no_worktree) {
      const wtDir = `.worktrees/feature-${feature.name}`;
      if (!existsSync(wtDir)) {
        logError(`No worktree found for '${feature.name}' at ${wtDir}`);
        return false;
      }
      workDir = resolve(wtDir);
    }

    if (!pipelineStateExists(workDir)) {
      logError(`No pipeline state file found in ${workDir}`);
      return false;
    }

    const state = pipelineReadState(workDir);
    if (state) {
      if (!flags.no_test) flags.no_test = state.flags.no_test;
      if (!flags.no_review) flags.no_review = state.flags.no_review;
      if (!flags.no_pr) flags.no_pr = state.flags.no_pr;
      if (!flags.auto_pr) flags.auto_pr = state.flags.auto_pr;
      mode = state.mode;
      value = state.value;
    }

    if (fromStage) {
      startStage = fromStage;
      logInfo(`[${feature.name}] Forced resume from stage ${startStage}`);
    } else {
      const resume = pipelineGetResumeStage(workDir);
      if (resume === 'done') {
        logSuccess(`[${feature.name}] Pipeline already completed`);
        return true;
      }
      startStage = resume;
      logInfo(`[${feature.name}] Resuming from stage ${startStage} (${pipelineStageName(startStage)})`);
    }

    if (!flags.no_worktree) process.chdir(workDir);
  }

  const scriptDir = resolve(originalDir, 'bin');

  // Stage 1: Worktree
  if (startStage <= 1) {
    if (!flags.no_worktree) {
      logInfo(`[${feature.name}] Stage 1: Creating worktree...`);
      const wtPath = await createWorktree(feature.name, { resume: resumeMode });
      if (!wtPath) {
        logError(`[${feature.name}] Failed to create worktree`);
        return false;
      }
      workDir = wtPath;
      process.chdir(workDir);
      logSuccess(`[${feature.name}] Worktree: ${workDir}`);
    } else {
      logInfo(`[${feature.name}] Stage 1: Skipped (--no-worktree)`);
    }

    if (!resumeMode) {
      if (pipelineStateExists(workDir)) {
        logError(`Pipeline state already exists in ${workDir}. Use --resume to continue.`);
        process.chdir(originalDir);
        return false;
      }
      pipelineStateInit(workDir, feature.name, mode, value, flags);
    }

    pipelineCheckpoint(workDir, 1, flags.no_worktree ? 'skipped' : 'completed');
  }

  // Stage 2: Init
  if (startStage <= 2) {
    pipelineCheckpoint(workDir, 2, 'in_progress');
    logInfo(`[${feature.name}] Stage 2: Init (spec + plan)...`);

    const initArgs = ['-m', config.model];
    if (config.verbose) initArgs.push('-v');
    if (mode === 'prompt') initArgs.push('--prompt', value);
    else initArgs.push('--spec', value);

    const result = await spawnCommand(`${scriptDir}/cw-init`, initArgs, { cwd: workDir });
    if (result.exitCode !== 0) {
      logError(`[${feature.name}] Init failed`);
      pipelineCheckpoint(workDir, 2, 'failed');
      process.chdir(originalDir);
      return false;
    }

    logSuccess(`[${feature.name}] Init completed`);
    pipelineCheckpoint(workDir, 2, 'completed');
  }

  // Stage 3: Execute
  if (startStage <= 3) {
    pipelineCheckpoint(workDir, 3, 'in_progress');
    logInfo(`[${feature.name}] Stage 3: Executing tasks...`);

    const loopArgs = ['-d', '-m', config.model];
    if (config.verbose) loopArgs.push('-v');

    const result = await spawnCommand(`${scriptDir}/cw-loop`, loopArgs, {
      cwd: workDir,
      env: { CW_NON_INTERACTIVE: 'true' },
    });

    if (result.exitCode === 0) {
      logSuccess(`[${feature.name}] Task execution completed`);
      pipelineCheckpoint(workDir, 3, 'completed');
    } else {
      logWarning(`[${feature.name}] Task execution exited with code ${result.exitCode}`);
      pipelineCheckpoint(workDir, 3, 'failed');
    }
  }

  // Stage 4: Validate
  if (startStage <= 4) {
    pipelineCheckpoint(workDir, 4, 'in_progress');
    logInfo(`[${feature.name}] Stage 4: Validation...`);

    const session = discoverSession(workDir);
    const ok = await invokeClaude(
      "Use the Skill tool to invoke 'cw-validate'. Run the 6-gate validation. Proceed autonomously without using AskUserQuestion.",
      config,
      { sessionId: session?.sessionId || undefined, cwd: workDir },
    );

    pipelineCheckpoint(workDir, 4, ok ? 'completed' : 'failed');
    if (ok) logSuccess(`[${feature.name}] Validation passed`);
    else logWarning(`[${feature.name}] Validation had issues`);
  }

  // Stage 5: Review
  if (startStage <= 5) {
    if (!flags.no_review) {
      pipelineCheckpoint(workDir, 5, 'in_progress');
      logInfo(`[${feature.name}] Stage 5: Code review...`);

      const session = discoverSession(workDir);
      const ok = await invokeClaude(
        "Use the Skill tool to invoke 'cw-review'. Review all code changes. Create FIX-REVIEW tasks for blocking issues. Proceed autonomously.",
        config,
        { sessionId: session?.sessionId || undefined, cwd: workDir },
      );

      if (ok) {
        const reviewSession = discoverSession(workDir);
        if (reviewSession) {
          const store = new TaskStore(reviewSession.tasksDir);
          const fixCount = store.getPendingFixCount();
          if (fixCount > 0) {
            logInfo(`[${feature.name}] Executing ${fixCount} review fix task(s)...`);
            await spawnCommand(`${scriptDir}/cw-loop`, ['-m', config.model], {
              cwd: workDir,
              env: { CW_NON_INTERACTIVE: 'true' },
            });
          }
        }
      }

      pipelineCheckpoint(workDir, 5, ok ? 'completed' : 'failed');
    } else {
      pipelineCheckpoint(workDir, 5, 'skipped');
    }
  }

  // Stage 6: Test Init
  if (startStage <= 6) {
    if (!flags.no_test) {
      pipelineCheckpoint(workDir, 6, 'in_progress');
      logInfo(`[${feature.name}] Stage 6: Test init...`);

      const testInitArgs = ['-m', config.model];
      if (config.verbose) testInitArgs.push('-v');
      if (mode === 'spec') testInitArgs.push('--spec', value);
      else testInitArgs.push('--prompt', value);

      const result = await spawnCommand(`${scriptDir}/cw-test-init`, testInitArgs, { cwd: workDir });
      pipelineCheckpoint(workDir, 6, result.exitCode === 0 ? 'completed' : 'failed');
    } else {
      pipelineCheckpoint(workDir, 6, 'skipped');
    }
  }

  // Stage 7: Test Loop
  if (startStage <= 7) {
    if (!flags.no_test) {
      pipelineCheckpoint(workDir, 7, 'in_progress');
      logInfo(`[${feature.name}] Stage 7: Test loop...`);

      const testArgs = ['-m', config.model];
      if (config.verbose) testArgs.push('-v');

      const result = await spawnCommand(`${scriptDir}/cw-test-loop`, testArgs, { cwd: workDir });
      pipelineCheckpoint(workDir, 7, result.exitCode === 0 ? 'completed' : 'failed');
    } else {
      pipelineCheckpoint(workDir, 7, 'skipped');
    }
  }

  // Stage 8: Revalidate
  if (startStage <= 8) {
    pipelineCheckpoint(workDir, 8, 'in_progress');
    logInfo(`[${feature.name}] Stage 8: Final validation...`);

    const session = discoverSession(workDir);
    const ok = await invokeClaude(
      "Use the Skill tool to invoke 'cw-validate'. Run the final 6-gate validation. Proceed autonomously.",
      config,
      { sessionId: session?.sessionId || undefined, cwd: workDir },
    );
    pipelineCheckpoint(workDir, 8, ok ? 'completed' : 'failed');
  }

  // Stage 9: PR
  if (startStage <= 9) {
    if (!flags.no_pr) {
      pipelineCheckpoint(workDir, 9, 'in_progress');
      logInfo(`[${feature.name}] Stage 9: PR creation...`);

      const prCheck = await spawnCommand('gh', [
        'pr', 'list', '--head', `feature/${feature.name}`, '--state', 'open', '--json', 'number', '--jq', '.[0].number',
      ]);

      if (prCheck.stdout.trim()) {
        logInfo(`[${feature.name}] PR #${prCheck.stdout.trim()} already exists`);
      } else if (flags.auto_pr || config.nonInteractive) {
        const session = discoverSession(workDir);
        const ok = await invokeClaude(
          "Create a pull request using 'gh pr create'. Summarize changes, reference the spec, include a test plan. Proceed autonomously.",
          config,
          { sessionId: session?.sessionId || undefined, cwd: workDir },
        );
        if (ok) logSuccess(`[${feature.name}] PR created`);
        else logWarning(`[${feature.name}] PR creation failed`);
      }

      pipelineCheckpoint(workDir, 9, 'completed');
    } else {
      pipelineCheckpoint(workDir, 9, 'skipped');
    }
  }

  process.chdir(originalDir);
  logSuccess(`[${feature.name}] Pipeline completed`);
  return true;
}

export const pipelineCommand = new Command('pipeline')
  .description('Full end-to-end feature development orchestrator')
  .option('--prompt <text>', 'Feature description')
  .option('--spec <path>', 'Existing spec file')
  .option('--name <name>', 'Feature name for worktree/branch')
  .option('--feature <spec...>', 'Multi-feature (format: name:mode:value)')
  .option('--resume', 'Resume from checkpoint')
  .option('--from <n>', 'Force resume from stage N (1-9)')
  .option('--no-worktree', 'Run in current directory')
  .option('--no-test', 'Skip test phase')
  .option('--no-review', 'Skip code review')
  .option('--no-pr', 'Skip PR creation')
  .option('--auto-pr', 'Create PR without confirmation')
  .option('-m, --model <model>', 'Claude model')
  .option('-v, --verbose', 'Stream JSON output')
  .action(async (opts) => {
    const config = loadConfig({
      model: opts.model,
      verbose: opts.verbose,
    });

    const flags: PipelineFlags = {
      no_test: opts.noTest ?? false,
      no_review: opts.noReview ?? false,
      no_pr: opts.noPr ?? false,
      no_worktree: opts.noWorktree ?? false,
      auto_pr: opts.autoPr ?? false,
      model: config.model,
      verbose: config.verbose,
    };

    const features: FeatureSpec[] = [];

    if (opts.feature) {
      for (const spec of opts.feature) {
        const [name, mode, ...rest] = spec.split(':');
        features.push({ name, mode, value: rest.join(':') });
      }
    } else {
      if (!opts.name) {
        logError('--name is required');
        process.exit(4);
      }

      if (opts.resume) {
        features.push({ name: opts.name, mode: 'resume', value: '' });
      } else if (opts.prompt) {
        features.push({ name: opts.name, mode: 'prompt', value: opts.prompt });
      } else if (opts.spec) {
        features.push({ name: opts.name, mode: 'spec', value: opts.spec });
      } else {
        logError('Either --prompt or --spec is required');
        process.exit(4);
      }
    }

    if (opts.from && !opts.resume) {
      logError('--from requires --resume');
      process.exit(4);
    }

    printBanner('Claude Workflow - Pipeline');
    logInfo(`Features: ${features.length}`);
    for (const f of features) logInfo(`  ${f.name} (${f.mode})`);

    const startTime = Date.now();

    if (features.length === 1) {
      const ok = await runFeaturePipeline(
        features[0], config, flags, opts.resume ?? false, opts.from ? parseInt(opts.from) : undefined,
      );
      const elapsed = Math.floor((Date.now() - startTime) / 1000);
      if (ok) {
        logSuccess(`Pipeline completed successfully (Runtime: ${formatElapsed(elapsed)})`);
      } else {
        logError(`Pipeline failed (Runtime: ${formatElapsed(elapsed)})`);
        process.exit(1);
      }
    } else {
      logHeader(`Launching ${features.length} features in parallel`);
      const results = await Promise.all(
        features.map((f) => runFeaturePipeline(f, config, { ...flags }, opts.resume ?? false)),
      );

      const elapsed = Math.floor((Date.now() - startTime) / 1000);
      const failed = results.filter((r) => !r).length;

      logHeader('Pipeline Results');
      for (let i = 0; i < features.length; i++) {
        if (results[i]) {
          console.log(`  ${chalk.green('[PASS]')} ${features[i].name}`);
        } else {
          console.log(`  ${chalk.red('[FAIL]')} ${features[i].name}`);
        }
      }

      if (failed === 0) {
        logSuccess(`All features completed (Runtime: ${formatElapsed(elapsed)})`);
      } else {
        logError(`${failed} feature(s) failed (Runtime: ${formatElapsed(elapsed)})`);
        process.exit(1);
      }
    }
  });
