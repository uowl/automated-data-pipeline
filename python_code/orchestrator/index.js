import crypto from 'crypto';
import path from 'path';
import { getDb, initSchema, closeDb } from './db.js';
import { log } from './logger.js';
import { runDataPull } from './steps/pull.js';
import { runExtract } from './steps/extract.js';
import { runTransform } from './steps/transform.js';
import { runMigrate } from './steps/migrate.js';

const PIPELINE_NAME = process.env.PIPELINE_NAME || 'SamplePipeline';
const SOURCE_FILE = process.env.SOURCE_FILE || 'sample_orders.csv';
// Optional CSV path from CLI: node index.js /path/to/file.csv
const CSV_ARG = process.argv[2];

function now() {
  return new Date().toISOString();
}

function updateStepRun(db, stepRunId, status, finishedAt, rowsAffected, errorMessage) {
  db.prepare(`
    UPDATE StepRuns SET Status = ?, FinishedAt = ?, RowsAffected = ?, ErrorMessage = ?
    WHERE StepRunId = ?
  `).run(status, finishedAt, rowsAffected ?? null, errorMessage || null, stepRunId);
}

/**
 * Create a pipeline run and 4 step placeholders. Returns runId immediately (for background execution).
 * @param {Object} [options]
 * @param {string} [options.csvPath] - Full path to CSV (or JSON) file for Data Pull.
 * @returns {string} runId
 */
function startPipelineRun(options = {}) {
  const db = getDb();
  const runId = crypto.randomUUID();
  const startedAt = now();
  const nextRunNumber = (db.prepare('SELECT COALESCE(MAX(RunNumber), 0) + 1 AS n FROM PipelineRuns').get()).n;

  db.prepare(`
    INSERT INTO PipelineRuns (RunId, RunNumber, PipelineName, ADFRunId, StartedAt, Status)
    VALUES (?, ?, ?, ?, ?, 'Running')
  `).run(runId, nextRunNumber, PIPELINE_NAME, `local-${Date.now()}`, startedAt);

  const stepNames = ['Data Pull', 'Extract (SP)', 'Transform (SP)', 'Migrate (SP)'];
  for (let i = 0; i < 4; i++) {
    db.prepare(`
      INSERT INTO StepRuns (RunId, StepNumber, StepName, Status)
      VALUES (?, ?, ?, 'Pending')
    `).run(runId, i + 1, stepNames[i]);
  }
  return runId;
}

/**
 * Execute the four pipeline steps for an existing run (called after startPipelineRun).
 * @param {string} runId - from startPipelineRun
 * @param {Object} [options]
 * @param {string} [options.csvPath] - Full path to CSV (or JSON) file for Data Pull.
 */
function executePipelineSteps(runId, options = {}) {
  const db = getDb();
  const csvPathRaw = options.csvPath || CSV_ARG;
  const csvPath = csvPathRaw
    ? (path.isAbsolute(csvPathRaw) ? csvPathRaw : path.resolve(process.cwd(), csvPathRaw))
    : null;

  const steps = db.prepare('SELECT StepRunId, StepNumber FROM StepRuns WHERE RunId = ? ORDER BY StepNumber').all(runId);
  const stepNames = ['Data Pull', 'Extract (SP)', 'Transform (SP)', 'Migrate (SP)'];

  log(db, runId, {
    level: 'Info',
    message: `Pipeline started${csvPath ? ` with file: ${path.basename(csvPath)}` : ''}`,
    pipelineName: PIPELINE_NAME
  });

  try {
    // Step 1: Data Pull
    const step1 = steps.find(s => s.StepNumber === 1);
    log(db, runId, { message: 'Step 1 started', pipelineName: PIPELINE_NAME, stepNumber: 1, stepName: stepNames[0] });
    db.prepare('UPDATE StepRuns SET Status = ?, StartedAt = ? WHERE StepRunId = ?').run('Running', now(), step1.StepRunId);
    const rowsPull = runDataPull(db, runId, csvPath ? { filePath: csvPath } : { fileName: SOURCE_FILE });
    updateStepRun(db, step1.StepRunId, 'Success', now(), rowsPull, null);
    log(db, runId, { message: `Data Pull completed: ${rowsPull} rows loaded`, pipelineName: PIPELINE_NAME, stepNumber: 1, stepName: stepNames[0], details: `RowsAffected: ${rowsPull}` });

    // Step 2: Extract
    const step2 = steps.find(s => s.StepNumber === 2);
    log(db, runId, { message: 'Step 2 started', pipelineName: PIPELINE_NAME, stepNumber: 2, stepName: stepNames[1] });
    db.prepare('UPDATE StepRuns SET Status = ?, StartedAt = ? WHERE StepRunId = ?').run('Running', now(), step2.StepRunId);
    const rowsExtract = runExtract(db, runId);
    updateStepRun(db, step2.StepRunId, 'Success', now(), rowsExtract, null);
    log(db, runId, { message: `Extract completed: ${rowsExtract} rows`, pipelineName: PIPELINE_NAME, stepNumber: 2, stepName: stepNames[1], details: `RowsAffected: ${rowsExtract}` });

    // Step 3: Transform
    const step3 = steps.find(s => s.StepNumber === 3);
    log(db, runId, { message: 'Step 3 started', pipelineName: PIPELINE_NAME, stepNumber: 3, stepName: stepNames[2] });
    db.prepare('UPDATE StepRuns SET Status = ?, StartedAt = ? WHERE StepRunId = ?').run('Running', now(), step3.StepRunId);
    const rowsTransform = runTransform(db, runId);
    updateStepRun(db, step3.StepRunId, 'Success', now(), rowsTransform, null);
    log(db, runId, { message: `Transform completed: ${rowsTransform} rows`, pipelineName: PIPELINE_NAME, stepNumber: 3, stepName: stepNames[2], details: `RowsAffected: ${rowsTransform}` });

    // Step 4: Migrate
    const step4 = steps.find(s => s.StepNumber === 4);
    log(db, runId, { message: 'Step 4 started', pipelineName: PIPELINE_NAME, stepNumber: 4, stepName: stepNames[3] });
    db.prepare('UPDATE StepRuns SET Status = ?, StartedAt = ? WHERE StepRunId = ?').run('Running', now(), step4.StepRunId);
    const rowsMigrate = runMigrate(db, runId);
    updateStepRun(db, step4.StepRunId, 'Success', now(), rowsMigrate, null);
    log(db, runId, { message: `Migrate completed: ${rowsMigrate} rows`, pipelineName: PIPELINE_NAME, stepNumber: 4, stepName: stepNames[3], details: `RowsAffected: ${rowsMigrate}` });

    const finishedAt = now();
    db.prepare('UPDATE PipelineRuns SET Status = ?, FinishedAt = ? WHERE RunId = ?').run('Success', finishedAt, runId);
    log(db, runId, { message: 'Pipeline completed successfully', pipelineName: PIPELINE_NAME, details: `Total rows migrated: ${rowsMigrate}` });
    return runId;
  } catch (err) {
    log(db, runId, { level: 'Error', message: `Pipeline failed: ${err.message}`, pipelineName: PIPELINE_NAME, details: err.stack });
    const failedStep = steps.find(s => {
      const r = db.prepare('SELECT Status FROM StepRuns WHERE StepRunId = ?').get(s.StepRunId);
      return r && r.Status === 'Running';
    });
    if (failedStep) {
      updateStepRun(db, failedStep.StepRunId, 'Failed', now(), null, err.message);
      log(db, runId, { level: 'Error', message: `Step ${failedStep.StepNumber} failed`, pipelineName: PIPELINE_NAME, stepNumber: failedStep.StepNumber, stepName: stepNames[failedStep.StepNumber - 1], details: err.message });
    }
    db.prepare('UPDATE PipelineRuns SET Status = ?, FinishedAt = ? WHERE RunId = ?').run('Failed', now(), runId);
    throw err;
  }
}

/**
 * Run the full pipeline (start + execute). Use for CLI. For API, use startPipelineRun then executePipelineSteps in background.
 * @param {Object} [options]
 * @param {string} [options.csvPath] - Full path to CSV (or JSON) file for Data Pull.
 * @returns {string} runId
 */
function runPipeline(options = {}) {
  const runId = startPipelineRun(options);
  executePipelineSteps(runId, options);
  return runId;
}

// If run directly (not required by another module)
if (process.argv[1]?.endsWith('index.js')) {
  try {
    initSchema();
    runPipeline(CSV_ARG ? { csvPath: CSV_ARG } : {});
  } finally {
    closeDb();
  }
}

export { runPipeline, startPipelineRun, executePipelineSteps, getDb, initSchema, closeDb };
