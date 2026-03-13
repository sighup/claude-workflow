import { spawnCommand } from '../util/process.js';
import { logInfo, logError } from '../util/logger.js';
import type { QueueStore } from './queue-store.js';

interface GitHubIssue {
  number: number;
  title: string;
  body: string;
  url: string;
}

function sanitizeName(title: string): string {
  return title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 50);
}

function extractSection(body: string, heading: string): string | null {
  const regex = new RegExp(`## ${heading}\\s*\\n([\\s\\S]*?)(?=\\n## |$)`, 'i');
  const match = body.match(regex);
  return match ? match[1].trim() : null;
}

export async function importGitHubIssues(
  queue: QueueStore,
  opts: {
    label: string;
    repo?: string;
    projectDir: string;
  },
): Promise<number> {
  const args = ['issue', 'list', '--label', opts.label, '--state', 'open', '--json', 'number,title,body,url'];
  if (opts.repo) args.push('--repo', opts.repo);

  const result = await spawnCommand('gh', args);
  if (result.exitCode !== 0) {
    logError(`Failed to fetch GitHub issues: ${result.stderr}`);
    return 0;
  }

  let issues: GitHubIssue[];
  try {
    issues = JSON.parse(result.stdout);
  } catch {
    logError('Failed to parse GitHub issues response');
    return 0;
  }

  let imported = 0;
  for (const issue of issues) {
    const source = `github#${issue.number}`;

    if (queue.hasExistingSource(source)) {
      logInfo(`Issue #${issue.number} already in queue, skipping`);
      continue;
    }

    const specSection = extractSection(issue.body, 'Spec');
    const promptSection = extractSection(issue.body, 'Prompt');
    const prompt = specSection ?? promptSection ?? issue.body;
    const type = specSection ? ('spec' as const) : ('prompt' as const);
    const repo = opts.repo ?? '';

    queue.add({
      status: 'pending',
      priority: 5,
      type,
      source,
      prompt,
      name: `issue-${issue.number}-${sanitizeName(issue.title)}`,
      spec_path: undefined,
      github_issue: {
        number: issue.number,
        repo,
        title: issue.title,
        url: issue.url,
      },
      project_dir: opts.projectDir,
    });

    logInfo(`Queued issue #${issue.number}: ${issue.title}`);
    imported++;
  }

  return imported;
}

export async function commentOnIssue(
  issueNumber: number,
  comment: string,
  opts: { repo?: string } = {},
): Promise<boolean> {
  const args = ['issue', 'comment', String(issueNumber), '--body', comment];
  if (opts.repo) args.push('--repo', opts.repo);
  const result = await spawnCommand('gh', args);
  return result.exitCode === 0;
}

export async function removeLabel(
  issueNumber: number,
  label: string,
  opts: { repo?: string } = {},
): Promise<boolean> {
  const args = ['issue', 'edit', String(issueNumber), '--remove-label', label];
  if (opts.repo) args.push('--repo', opts.repo);
  const result = await spawnCommand('gh', args);
  return result.exitCode === 0;
}

export async function closeIssue(
  issueNumber: number,
  opts: { repo?: string } = {},
): Promise<boolean> {
  const args = ['issue', 'close', String(issueNumber)];
  if (opts.repo) args.push('--repo', opts.repo);
  const result = await spawnCommand('gh', args);
  return result.exitCode === 0;
}
