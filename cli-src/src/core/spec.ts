import { existsSync } from 'node:fs';
import { findLatestFile } from '../util/fs.js';
import { logInfo, logError } from '../util/logger.js';

export interface SpecInput {
  mode: 'prompt' | 'spec';
  value: string;
}

export function resolveSpecInput(mode: string, value?: string): SpecInput | null {
  switch (mode) {
    case 'prompt':
      if (!value) {
        logError('Prompt text is required with --prompt');
        return null;
      }
      return { mode: 'prompt', value };

    case 'spec':
      if (!value) {
        logError('Spec path is required with --spec');
        return null;
      }
      if (!existsSync(value)) {
        logError(`Spec file not found: ${value}`);
        return null;
      }
      return { mode: 'spec', value };

    case 'auto': {
      const latest = findLatestFile('docs/specs', /\.md$/, /questions/i);
      if (!latest) {
        logError('No spec files found in docs/specs');
        return null;
      }
      logInfo(`Auto-discovered spec: ${latest}`);
      return { mode: 'spec', value: latest };
    }

    default:
      logError(`Unknown spec mode: ${mode}`);
      return null;
  }
}
