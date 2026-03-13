import { Command } from 'commander';
import { resolve } from 'node:path';
import { spawnCommand } from '../util/process.js';
import { loadConfig } from '../util/config.js';
import { logInfo, logSuccess, logError, logWarning } from '../util/logger.js';

const CRON_MARKER = '# claude-workflow-auto';

export const installCommand = new Command('install')
  .description('Set up scheduled autonomous execution');

installCommand
  .command('cron')
  .description('Install crontab entry')
  .option('--schedule <cron>', 'Cron schedule expression')
  .option('--projects <dirs...>', 'Project directories for multi-project mode')
  .action(async (opts) => {
    const config = loadConfig();
    const schedule = opts.schedule ?? config.autoSchedule;
    const projectDir = resolve(process.cwd());
    const cwBin = resolve(projectDir, 'bin', 'cw');

    let cwCommand = `cd ${projectDir} && ${cwBin} auto`;

    if (opts.projects) {
      const projectArgs = opts.projects.map((p: string) => resolve(p)).join(' ');
      cwCommand += ` --projects ${projectArgs}`;
    }

    const cronEntry = `${schedule} ${cwCommand} >> ${projectDir}/logs/auto/cron.log 2>&1 ${CRON_MARKER}`;

    const existing = await spawnCommand('crontab', ['-l']);
    const currentCrontab = existing.exitCode === 0 ? existing.stdout : '';

    if (currentCrontab.includes(CRON_MARKER)) {
      logWarning('Existing claude-workflow cron entry found. Replacing...');
      const lines = currentCrontab.split('\n').filter((l) => !l.includes(CRON_MARKER));
      lines.push(cronEntry);
      const newCrontab = lines.join('\n') + '\n';

      const result = await spawnCommand('bash', ['-c', `echo '${newCrontab.replace(/'/g, "'\\''")}' | crontab -`]);
      if (result.exitCode !== 0) {
        logError(`Failed to update crontab: ${result.stderr}`);
        process.exit(1);
      }
    } else {
      const newCrontab = currentCrontab.trimEnd() + '\n' + cronEntry + '\n';
      const result = await spawnCommand('bash', ['-c', `echo '${newCrontab.replace(/'/g, "'\\''")}' | crontab -`]);
      if (result.exitCode !== 0) {
        logError(`Failed to install crontab: ${result.stderr}`);
        process.exit(1);
      }
    }

    logSuccess(`Cron entry installed: ${schedule}`);
    logInfo(`Command: ${cwCommand}`);
  });

installCommand
  .command('systemd')
  .description('Generate systemd timer unit')
  .action(async () => {
    const projectDir = resolve(process.cwd());
    const cwBin = resolve(projectDir, 'bin', 'cw');

    const serviceUnit = `[Unit]
Description=Claude Workflow Autonomous Execution
After=network.target

[Service]
Type=oneshot
WorkingDirectory=${projectDir}
ExecStart=${cwBin} auto
Environment=HOME=${process.env.HOME}
StandardOutput=append:${projectDir}/logs/auto/systemd.log
StandardError=append:${projectDir}/logs/auto/systemd.log
`;

    const timerUnit = `[Unit]
Description=Claude Workflow Autonomous Timer

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
`;

    console.log('# Save to ~/.config/systemd/user/claude-workflow.service');
    console.log(serviceUnit);
    console.log('# Save to ~/.config/systemd/user/claude-workflow.timer');
    console.log(timerUnit);
    console.log('# Then enable:');
    console.log('#   systemctl --user enable --now claude-workflow.timer');
  });

installCommand
  .command('uninstall')
  .description('Remove scheduled entries')
  .action(async () => {
    const existing = await spawnCommand('crontab', ['-l']);
    if (existing.exitCode !== 0) {
      logInfo('No crontab found');
      return;
    }

    const lines = existing.stdout.split('\n').filter((l) => !l.includes(CRON_MARKER));
    const newCrontab = lines.join('\n');

    await spawnCommand('bash', ['-c', `echo '${newCrontab.replace(/'/g, "'\\''")}' | crontab -`]);
    logSuccess('Cron entry removed');
  });
