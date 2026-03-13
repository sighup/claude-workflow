import { join } from 'node:path';
import { readJson, writeJson, fileExists, ensureDir } from '../util/fs.js';
import { logInfo, logWarning } from '../util/logger.js';
import type { PipelineState, PipelineFlags, PipelineStage } from '../types/pipeline.js';
import { STAGE_NAMES } from '../types/pipeline.js';

const STATE_FILE = '.claude/pipeline-state.json';

function now(): string {
  return new Date().toISOString();
}

export function pipelineStateInit(
  workDir: string,
  featureName: string,
  mode: string,
  value: string,
  flags: PipelineFlags,
): void {
  const statePath = join(workDir, STATE_FILE);
  ensureDir(join(workDir, '.claude'));

  const stages: Record<string, PipelineStage> = {};
  for (let i = 1; i <= 9; i++) {
    stages[String(i)] = {
      name: STAGE_NAMES[i],
      status: 'pending',
      started_at: null,
      completed_at: null,
    };
  }

  const state: PipelineState = {
    version: 1,
    feature_name: featureName,
    mode: mode as 'prompt' | 'spec' | 'auto',
    value,
    current_stage: 0,
    stages,
    flags,
    created_at: now(),
    updated_at: now(),
  };

  writeJson(statePath, state);
  logInfo(`Pipeline state initialized: ${statePath}`);
}

export function pipelineCheckpoint(workDir: string, stageNum: number, status: string): void {
  const statePath = join(workDir, STATE_FILE);
  const state = readJson<PipelineState>(statePath);
  if (!state) {
    logWarning(`No pipeline state file found at ${statePath}`);
    return;
  }

  const key = String(stageNum);
  if (!state.stages[key]) return;

  state.stages[key].status = status as PipelineStage['status'];
  if (status === 'in_progress') {
    state.stages[key].started_at = now();
  } else if (status === 'completed' || status === 'skipped') {
    state.stages[key].completed_at = now();
  }

  state.current_stage = stageNum;
  state.updated_at = now();

  writeJson(statePath, state);
}

export function pipelineGetResumeStage(workDir: string): number | 'done' {
  const statePath = join(workDir, STATE_FILE);
  const state = readJson<PipelineState>(statePath);
  if (!state) return 1;

  for (let i = 1; i <= 9; i++) {
    const stage = state.stages[String(i)];
    if (stage && stage.status !== 'completed' && stage.status !== 'skipped') {
      return i;
    }
  }

  return 'done';
}

export function pipelineStateExists(workDir: string): boolean {
  return fileExists(join(workDir, STATE_FILE));
}

export function pipelineReadState(workDir: string): PipelineState | null {
  return readJson<PipelineState>(join(workDir, STATE_FILE));
}

export function pipelineStageName(num: number): string {
  return STAGE_NAMES[num] ?? 'unknown';
}
