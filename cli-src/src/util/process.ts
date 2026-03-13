import { spawn } from 'node:child_process';

export interface SpawnResult {
  exitCode: number;
  stdout: string;
  stderr: string;
  timedOut: boolean;
}

export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function spawnCommand(
  command: string,
  args: string[],
  opts: {
    cwd?: string;
    stdin?: string;
    timeout?: number;
    env?: Record<string, string>;
  } = {},
): Promise<SpawnResult> {
  return new Promise((resolve) => {
    const child = spawn(command, args, {
      cwd: opts.cwd,
      env: { ...process.env, ...opts.env },
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    let stdout = '';
    let stderr = '';
    let timedOut = false;
    let timer: ReturnType<typeof setTimeout> | undefined;

    if (opts.timeout && opts.timeout > 0) {
      timer = setTimeout(() => {
        timedOut = true;
        child.kill('SIGTERM');
        setTimeout(() => {
          if (!child.killed) child.kill('SIGKILL');
        }, 30_000);
      }, opts.timeout * 1000);
    }

    child.stdout.on('data', (data: Buffer) => {
      stdout += data.toString();
    });

    child.stderr.on('data', (data: Buffer) => {
      stderr += data.toString();
    });

    if (opts.stdin) {
      child.stdin.write(opts.stdin);
      child.stdin.end();
    } else {
      child.stdin.end();
    }

    child.on('close', (code) => {
      if (timer) clearTimeout(timer);
      resolve({
        exitCode: timedOut ? 124 : (code ?? 1),
        stdout,
        stderr,
        timedOut,
      });
    });

    child.on('error', (err) => {
      if (timer) clearTimeout(timer);
      resolve({
        exitCode: 1,
        stdout,
        stderr: stderr + '\n' + err.message,
        timedOut: false,
      });
    });
  });
}

export function commandExists(cmd: string): Promise<boolean> {
  return spawnCommand('which', [cmd]).then((r) => r.exitCode === 0);
}
