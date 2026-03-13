export interface PipelineStage {
  name: string;
  status: 'pending' | 'in_progress' | 'completed' | 'skipped' | 'failed';
  started_at: string | null;
  completed_at: string | null;
}

export interface PipelineFlags {
  no_test: boolean;
  no_review: boolean;
  no_pr: boolean;
  no_worktree: boolean;
  auto_pr: boolean;
  model: string;
  verbose: boolean;
}

export interface PipelineState {
  version: number;
  feature_name: string;
  mode: 'prompt' | 'spec' | 'auto';
  value: string;
  current_stage: number;
  stages: Record<string, PipelineStage>;
  flags: PipelineFlags;
  created_at: string;
  updated_at: string;
}

export const STAGE_NAMES: Record<number, string> = {
  1: 'worktree',
  2: 'init',
  3: 'execute',
  4: 'validate',
  5: 'review',
  6: 'test-init',
  7: 'test-loop',
  8: 'revalidate',
  9: 'pr',
};
