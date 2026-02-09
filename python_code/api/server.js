import express from 'express';
import cors from 'cors';
import multer from 'multer';
import { spawn } from 'child_process';
import Database from 'better-sqlite3';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DB_PATH = process.env.DB_PATH || path.join(__dirname, '..', 'data', 'pipeline.sqlite');
const LANDING_DIR = path.join(__dirname, '..', 'data', 'landing');

import { mkdirSync } from 'fs';
try { mkdirSync(LANDING_DIR, { recursive: true }); } catch (_) {}

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, LANDING_DIR),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase() || '.csv';
    cb(null, `upload_${Date.now()}${ext}`);
  }
});
const upload = multer({
  storage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10 MB
  fileFilter: (req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    if (ext === '.csv' || ext === '.json') return cb(null, true);
    cb(new Error('Only CSV or JSON files are allowed'));
  }
});

const app = express();
app.use(cors());
app.use(express.json());

function getDb() {
  return new Database(DB_PATH, { readonly: true });
}

// GET /runs - list pipeline runs
app.get('/runs', (req, res) => {
  try {
    const db = getDb();
    const pipeline = req.query.pipeline;
    const status = req.query.status;
    let sql = 'SELECT RunId, RunNumber, PipelineName, ADFRunId, StartedAt, FinishedAt, Status, CreatedAt FROM PipelineRuns WHERE 1=1';
    const params = [];
    if (pipeline) {
      params.push(pipeline);
      sql += ' AND PipelineName = ?';
    }
    if (status) {
      params.push(status);
      sql += ' AND Status = ?';
    }
    sql += ' ORDER BY CreatedAt DESC LIMIT 100';
    let rows;
    try {
      rows = db.prepare(sql).all(...params);
    } catch (e) {
      if (e.message && e.message.includes('RunNumber')) {
        const baseSql = 'SELECT RunId, PipelineName, ADFRunId, StartedAt, FinishedAt, Status, CreatedAt FROM PipelineRuns WHERE 1=1' + (pipeline ? ' AND PipelineName = ?' : '') + (status ? ' AND Status = ?' : '') + ' ORDER BY CreatedAt DESC LIMIT 100';
        const list = db.prepare(baseSql).all(...params);
        rows = list.map((r, i) => ({ ...r, RunNumber: list.length - i }));
      } else throw e;
    }
    if (rows && rows[0] && rows[0].RunNumber === undefined) {
      rows = rows.map((r, i) => ({ ...r, RunNumber: rows.length - i }));
    }
    db.close();
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /runs/:runId - run detail with 4 steps
app.get('/runs/:runId', (req, res) => {
  try {
    const db = getDb();
    const runId = req.params.runId;
    let run;
    try {
      run = db.prepare(
        'SELECT RunId, RunNumber, PipelineName, ADFRunId, StartedAt, FinishedAt, Status, CreatedAt FROM PipelineRuns WHERE RunId = ?'
      ).get(runId);
    } catch (e) {
      if (e.message && e.message.includes('RunNumber')) {
        run = db.prepare('SELECT RunId, PipelineName, ADFRunId, StartedAt, FinishedAt, Status, CreatedAt FROM PipelineRuns WHERE RunId = ?').get(runId);
        if (run) run = { ...run, RunNumber: null };
      } else throw e;
    }
    if (!run) {
      db.close();
      return res.status(404).json({ error: 'Run not found' });
    }
    const steps = db.prepare(
      'SELECT StepRunId, RunId, StepNumber, StepName, StartedAt, FinishedAt, Status, RowsAffected, ErrorMessage, CreatedAt FROM StepRuns WHERE RunId = ? ORDER BY StepNumber'
    ).all(runId);
    db.close();
    res.json({ ...run, steps });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /runs/:runId/logs - logs for a single run
app.get('/runs/:runId/logs', (req, res) => {
  try {
    const db = getDb();
    const runId = req.params.runId;
    const run = db.prepare('SELECT RunId FROM PipelineRuns WHERE RunId = ?').get(runId);
    if (!run) {
      db.close();
      return res.status(404).json({ error: 'Run not found' });
    }
    let logs = [];
    try {
      logs = db.prepare(
        'SELECT LogId, RunId, PipelineName, LogAt, Level, StepNumber, StepName, Message, Details FROM PipelineLogs WHERE RunId = ? ORDER BY LogAt ASC'
      ).all(runId);
    } catch (e) {
      if (!e.message?.includes('PipelineLogs')) throw e;
    }
    db.close();
    res.json(logs);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /logs - recent logs for all pipelines (optional: runId, pipeline, level, limit)
app.get('/logs', (req, res) => {
  try {
    const db = getDb();
    const { runId, pipeline, level, limit = '500' } = req.query;
    let logs = [];
    try {
      let sql = 'SELECT LogId, RunId, PipelineName, LogAt, Level, StepNumber, StepName, Message, Details FROM PipelineLogs WHERE 1=1';
      const params = [];
      if (runId) {
        params.push(runId);
        sql += ' AND RunId = ?';
      }
      if (pipeline) {
        params.push(pipeline);
        sql += ' AND PipelineName = ?';
      }
      if (level) {
        params.push(level);
        sql += ' AND Level = ?';
      }
      sql += ' ORDER BY LogAt DESC LIMIT ?';
      params.push(Math.min(parseInt(limit, 10) || 500, 2000));
      logs = db.prepare(sql).all(...params);
    } catch (e) {
      if (!e.message?.includes('PipelineLogs')) throw e;
    }
    db.close();
    res.json(logs);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// POST /pipeline/trigger - upload a CSV (or JSON) and run the pipeline in a child process (so API stays responsive for live status/logs)
app.post('/pipeline/trigger', upload.single('file'), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: 'No file uploaded. Use form field "file" with a CSV or JSON file.' });
  }
  const savedPath = path.join(LANDING_DIR, req.file.filename);
  try {
    const { startPipelineRun, initSchema } = await import('../orchestrator/index.js');
    initSchema();
    const runId = startPipelineRun({ csvPath: savedPath });

    const runStepsPath = path.resolve(__dirname, '..', 'orchestrator', 'run-steps.js');
    const child = spawn(process.execPath, [runStepsPath], {
      env: { ...process.env, RUN_ID: runId, CSV_PATH: savedPath, DB_PATH: path.resolve(DB_PATH) },
      cwd: path.resolve(__dirname, '..'),
      stdio: ['ignore', 'pipe', 'pipe']
    });
    child.stdout?.on('data', (d) => process.stdout.write(d));
    child.stderr?.on('data', (d) => process.stderr.write(d));
    child.on('error', (err) => console.error('Pipeline child process error:', err));
    child.on('exit', (code) => {
      if (code !== 0) console.error('Pipeline child process exited with code', code);
    });

    res.status(201).json({ runId, message: 'Pipeline started in background', file: req.file.filename });
  } catch (err) {
    console.error('Pipeline trigger error:', err);
    res.status(500).json({ error: err.message || 'Pipeline failed' });
  }
});

const PORT = process.env.API_PORT || 3000;
app.listen(PORT, () => {
  console.log(`Pipeline API at http://localhost:${PORT}`);
});
