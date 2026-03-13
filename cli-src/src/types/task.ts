export interface TaskMetadata {
  task_id?: string;
  spec_path?: string;
  failure_count?: number;
  fix_task_id?: string;
  test_status?: string;
  test_type?: string;
  test_suite?: boolean;
  complexity?: string;
  fix_attempt?: number;
  [key: string]: unknown;
}

export interface Task {
  id: string;
  subject: string;
  status: 'pending' | 'in_progress' | 'completed' | 'failed';
  blockedBy?: string[];
  metadata: TaskMetadata;
}

export interface TaskCounts {
  total: number;
  completed: number;
  pending: number;
  in_progress: number;
  failed: number;
}

export interface TestTaskCounts {
  total: number;
  passed: number;
  failed: number;
  pending: number;
}
