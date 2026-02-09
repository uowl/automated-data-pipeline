#!/usr/bin/env node
/**
 * Run pipeline steps for an existing run (used by API as a child process so the server stays responsive).
 * Env: RUN_ID (required), CSV_PATH (required), DB_PATH (optional, same as API for same DB).
 */

import { initSchema, executePipelineSteps, closeDb } from './index.js';

const runId = process.env.RUN_ID;
const csvPath = process.env.CSV_PATH;

if (!runId || !csvPath) {
  console.error('RUN_ID and CSV_PATH env vars are required');
  process.exit(1);
}

try {
  initSchema();
  executePipelineSteps(runId, { csvPath });
} catch (err) {
  console.error('Pipeline steps failed:', err);
  process.exit(1);
} finally {
  closeDb();
}
