export interface GitHubIssueRef {
  number: number;
  repo: string;
  title: string;
  url: string;
}

export type QueueItemStatus = 'pending' | 'running' | 'done' | 'failed' | 'rate_limited' | 'cancelled';
export type QueueItemType = 'prompt' | 'spec' | 'github-issue';

export interface QueueItem {
  id: string;
  created_at: string;
  status: QueueItemStatus;
  priority: number;
  type: QueueItemType;
  source: string;
  prompt?: string;
  name: string;
  spec_path?: string;
  github_issue?: GitHubIssueRef;
  project_dir: string;
  worktree?: string;
  started_at?: string;
  completed_at?: string;
  exit_code?: number;
  pr_url?: string;
  log_dir?: string;
  rate_limit_retries: number;
}
