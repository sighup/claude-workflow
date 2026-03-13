import { Command } from 'commander';
import { statusCommand } from './commands/status.js';
import { loopCommand } from './commands/loop.js';
import { initCommand } from './commands/init.js';
import { pipelineCommand } from './commands/pipeline.js';
import { testInitCommand } from './commands/test-init.js';
import { testLoopCommand } from './commands/test-loop.js';
import { interactiveCommand } from './commands/interactive.js';
import { doctorCommand } from './commands/doctor.js';
import { queueCommand } from './commands/queue.js';
import { historyCommand } from './commands/history.js';
import { autoCommand } from './commands/auto.js';
import { installCommand } from './commands/install.js';

const program = new Command()
  .name('cw')
  .description('Claude Workflow - Unified CLI for spec-driven development with autonomous execution')
  .version('1.0.0');

// Ported commands (replace bash scripts)
program.addCommand(statusCommand);
program.addCommand(loopCommand);
program.addCommand(initCommand);
program.addCommand(pipelineCommand);
program.addCommand(testInitCommand);
program.addCommand(testLoopCommand);
program.addCommand(interactiveCommand);

// New autonomous execution commands
program.addCommand(doctorCommand);
program.addCommand(queueCommand);
program.addCommand(historyCommand);
program.addCommand(autoCommand);
program.addCommand(installCommand);

program.parse();
