import chalk from 'chalk';
import { readJson, listJsonFiles } from '../util/fs.js';
import type { Task, TaskCounts, TestTaskCounts } from '../types/task.js';

export class TaskStore {
  constructor(private tasksDir: string) {}

  getAll(): Task[] {
    const files = listJsonFiles(this.tasksDir);
    const tasks: Task[] = [];
    for (const f of files) {
      const task = readJson<Task>(f);
      if (task && task.id && task.status) {
        tasks.push(task);
      }
    }
    return tasks;
  }

  getPendingUnblocked(): Task[] {
    const all = this.getAll();
    const completedIds = new Set(all.filter((t) => t.status === 'completed').map((t) => t.id));

    return all.filter((t) => {
      if (t.status !== 'pending') return false;
      const blockers = t.blockedBy ?? [];
      return blockers.every((id) => completedIds.has(id));
    });
  }

  getNextTaskId(): string | null {
    const pending = this.getPendingUnblocked();
    if (pending.length === 0) return null;

    pending.sort((a, b) => {
      const aNum = parseInt(a.id, 10);
      const bNum = parseInt(b.id, 10);
      if (!isNaN(aNum) && !isNaN(bNum)) return aNum - bNum;
      return a.id.localeCompare(b.id);
    });

    return pending[0].id;
  }

  isComplete(): boolean {
    const all = this.getAll();
    if (all.length === 0) return false;
    return (
      all.filter((t) => t.status === 'pending').length === 0 &&
      all.filter((t) => t.status === 'in_progress').length === 0
    );
  }

  getCounts(): TaskCounts {
    const all = this.getAll();
    return {
      total: all.length,
      completed: all.filter((t) => t.status === 'completed').length,
      pending: all.filter((t) => t.status === 'pending').length,
      in_progress: all.filter((t) => t.status === 'in_progress').length,
      failed: all.filter((t) => (t.metadata?.failure_count ?? 0) > 0).length,
    };
  }

  getCompletedCount(): number {
    return this.getAll().filter((t) => t.status === 'completed').length;
  }

  getPendingFixCount(): number {
    return this.getAll().filter((t) => {
      if (t.status !== 'pending') return false;
      const subj = t.subject ?? '';
      const taskId = t.metadata?.task_id ?? '';
      return /^FIX/i.test(subj) || /^FIX/i.test(taskId) || t.metadata?.fix_task_id != null;
    }).length;
  }

  getTestTaskCounts(): TestTaskCounts {
    const tests = this.getTestTasks();
    return {
      total: tests.length,
      passed: tests.filter(
        (t) => t.metadata?.test_status === 'passed' || t.status === 'completed',
      ).length,
      failed: tests.filter(
        (t) => t.metadata?.test_status === 'failed' || t.metadata?.test_status === 'blocked',
      ).length,
      pending: tests.filter(
        (t) =>
          t.metadata?.test_status === 'pending' ||
          (t.metadata?.test_status == null && t.status === 'pending'),
      ).length,
    };
  }

  getTestTasks(): Task[] {
    return this.getAll().filter((t) => {
      if (t.metadata?.test_suite === true) return false;
      return (
        t.metadata?.test_status != null ||
        t.metadata?.test_type === 'e2e' ||
        /^TEST/i.test(t.subject ?? '') ||
        /^TEST/i.test(t.metadata?.task_id ?? '')
      );
    });
  }

  allTestsPassed(): boolean {
    const counts = this.getTestTaskCounts();
    return counts.total > 0 && counts.failed === 0 && counts.total === counts.passed;
  }

  getTaskSubject(taskId: string): string {
    const task = readJson<Task>(`${this.tasksDir}/${taskId}.json`);
    return task?.subject ?? '';
  }

  getSpecPath(): string | null {
    const all = this.getAll();
    for (const t of all) {
      if (t.metadata?.spec_path) return t.metadata.spec_path as string;
    }
    return null;
  }

  // Display helpers

  printTaskStatus(): void {
    const counts = this.getCounts();
    console.log('');
    console.log(`  ${chalk.green('Completed:')}   ${counts.completed}/${counts.total}`);
    console.log(`  ${chalk.yellow('Pending:')}     ${counts.pending}`);
    console.log(`  ${chalk.blue('In Progress:')} ${counts.in_progress}`);
    console.log(`  ${chalk.red('Failed:')}      ${counts.failed}`);
    console.log('');

    if (counts.total > 0) {
      const pct = Math.floor((counts.completed * 100) / counts.total);
      console.log(`  Progress: ${chalk.green(`${pct}%`)}`);
      console.log('');
    }
  }

  showTaskList(): void {
    const all = this.getAll();
    if (all.length === 0) {
      console.log(chalk.yellow('  No tasks found.'));
      return;
    }

    const lines: string[] = [];
    for (const t of all) {
      const id = t.metadata?.task_id ?? t.id;
      if (t.status === 'completed') {
        lines.push(`  ${chalk.green('[✓]')} ${id}: ${t.subject}`);
      } else if ((t.metadata?.failure_count ?? 0) > 0) {
        lines.push(`  ${chalk.red('[✗]')} ${id}: ${t.subject}`);
      } else if (t.status === 'in_progress') {
        lines.push(`  ${chalk.yellow('[~]')} ${id}: ${t.subject}`);
      } else {
        lines.push(`  [ ] ${id}: ${t.subject}`);
      }
    }

    lines.sort();
    for (const line of lines) console.log(line);
  }

  showFailedTasks(): void {
    const failed = this.getAll().filter((t) => (t.metadata?.failure_count ?? 0) > 0);
    if (failed.length === 0) {
      console.log('  (none)');
    } else {
      for (const t of failed) {
        console.log(`  [${t.metadata?.task_id ?? t.id}] ${t.subject}`);
      }
    }
  }

  showPendingUnblockedTasks(): void {
    const pending = this.getPendingUnblocked();
    if (pending.length === 0) {
      console.log('  (none - all pending tasks are blocked)');
    } else {
      for (const t of pending) {
        const complexity = t.metadata?.complexity ?? 'unknown';
        console.log(`  [${t.metadata?.task_id ?? t.id}] ${t.subject} (complexity: ${complexity})`);
      }
    }
  }
}
