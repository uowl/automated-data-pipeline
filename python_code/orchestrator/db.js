import Database from 'better-sqlite3';
import { readFileSync, mkdirSync } from 'fs';
import { fileURLToPath } from 'url';
import path from 'path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const DB_PATH = process.env.DB_PATH || path.join(__dirname, '..', 'data', 'pipeline.sqlite');

let db = null;

export function getDb() {
  if (!db) {
    const dir = path.dirname(DB_PATH);
    try { mkdirSync(dir, { recursive: true }); } catch (_) {}
    db = new Database(DB_PATH);
    db.pragma('journal_mode = WAL');
  }
  return db;
}

export function initSchema() {
  const db = getDb();
  // Migrate existing PipelineRuns to add RunNumber before running schema (schema creates index on RunNumber)
  const tableExists = db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='PipelineRuns'").get();
  if (tableExists) {
    try {
      db.prepare('SELECT RunNumber FROM PipelineRuns LIMIT 1').get();
    } catch (_) {
      db.exec('ALTER TABLE PipelineRuns ADD COLUMN RunNumber INTEGER');
      const rows = db.prepare('SELECT RunId FROM PipelineRuns ORDER BY CreatedAt ASC').all();
      const upd = db.prepare('UPDATE PipelineRuns SET RunNumber = ? WHERE RunId = ?');
      rows.forEach((r, i) => upd.run(i + 1, r.RunId));
    }
  }
  const schemaPath = path.join(__dirname, '..', 'database', 'sqlite_schema.sql');
  const sql = readFileSync(schemaPath, 'utf8');
  db.exec(sql);
}

export function closeDb() {
  if (db) {
    db.close();
    db = null;
  }
}
