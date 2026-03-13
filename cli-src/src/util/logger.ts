import chalk from 'chalk';

export function logHeader(text: string): void {
  const line = '━'.repeat(78);
  console.log(chalk.cyan(line));
  console.log(chalk.cyan(text));
  console.log(chalk.cyan(line));
}

export function logInfo(text: string): void {
  console.log(`${chalk.blue('[INFO]')} ${text}`);
}

export function logSuccess(text: string): void {
  console.log(`${chalk.green('[OK]')} ${text}`);
}

export function logWarning(text: string): void {
  console.log(`${chalk.yellow('[WARN]')} ${text}`);
}

export function logError(text: string): void {
  console.log(`${chalk.red('[ERROR]')} ${text}`);
}

export function printBanner(title: string): void {
  console.log('');
  console.log(chalk.cyan('╔═══════════════════════════════════════════════════════════╗'));
  console.log(chalk.cyan('║') + `  ${title.padEnd(56)} ` + chalk.cyan('║'));
  console.log(chalk.cyan('╚═══════════════════════════════════════════════════════════╝'));
  console.log('');
}

export function formatElapsed(seconds: number): string {
  const hours = Math.floor(seconds / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  const secs = seconds % 60;

  if (hours > 0) return `${hours}h ${mins}m`;
  if (mins > 0) return `${mins}m ${secs}s`;
  return `${secs}s`;
}
