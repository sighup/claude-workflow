import { Command } from 'commander';
import chalk from 'chalk';
import { commandExists, spawnCommand } from '../util/process.js';
import { fileExists, ensureDir } from '../util/fs.js';
import { loadConfig } from '../util/config.js';
import { printBanner, logSuccess, logError } from '../util/logger.js';

interface Check {
  name: string;
  fn: () => Promise<boolean>;
  fixFn?: () => Promise<void>;
  essential: boolean;
}

export const doctorCommand = new Command('doctor')
  .description('Environment health check')
  .option('--quick', 'Essential checks only')
  .option('--fix', 'Auto-fix what can be fixed')
  .action(async (opts) => {
    const config = loadConfig();
    printBanner('Claude Workflow - Doctor');

    const checks: Check[] = [
      {
        name: 'claude CLI installed',
        fn: () => commandExists('claude'),
        essential: true,
      },
      {
        name: 'git installed',
        fn: () => commandExists('git'),
        essential: true,
      },
      {
        name: 'Node.js >= 20',
        fn: async () => {
          const major = parseInt(process.versions.node.split('.')[0]);
          return major >= 20;
        },
        essential: true,
      },
      {
        name: 'git repo is clean',
        fn: async () => {
          const result = await spawnCommand('git', ['status', '--porcelain']);
          return result.exitCode === 0 && result.stdout.trim() === '';
        },
        essential: false,
      },
      {
        name: 'Queue directory exists',
        fn: async () => fileExists(config.autoQueueDir),
        fixFn: async () => ensureDir(config.autoQueueDir),
        essential: false,
      },
      {
        name: 'Log directory exists',
        fn: async () => fileExists(config.autoLogDir),
        fixFn: async () => ensureDir(config.autoLogDir),
        essential: false,
      },
      {
        name: 'gh CLI installed',
        fn: () => commandExists('gh'),
        essential: false,
      },
      {
        name: 'claude CLI authenticated',
        fn: async () => {
          const result = await spawnCommand('claude', ['--version']);
          return result.exitCode === 0;
        },
        essential: true,
      },
    ];

    const filtered = opts.quick ? checks.filter((c) => c.essential) : checks;

    let passed = 0;
    let failed = 0;
    let fixed = 0;

    for (const check of filtered) {
      const ok = await check.fn();
      if (ok) {
        console.log(`  ${chalk.green('✓')} ${check.name}`);
        passed++;
      } else if (opts.fix && check.fixFn) {
        await check.fixFn();
        console.log(`  ${chalk.yellow('⚡')} ${check.name} (fixed)`);
        fixed++;
      } else {
        console.log(`  ${chalk.red('✗')} ${check.name}`);
        failed++;
      }
    }

    console.log('');
    console.log(`  ${chalk.green(`${passed} passed`)}${fixed > 0 ? `, ${chalk.yellow(`${fixed} fixed`)}` : ''}${failed > 0 ? `, ${chalk.red(`${failed} failed`)}` : ''}`);
    console.log('');

    if (failed > 0) {
      logError('Some checks failed. Fix issues above before running autonomous execution.');
      process.exit(1);
    } else {
      logSuccess('Environment is healthy.');
    }
  });
