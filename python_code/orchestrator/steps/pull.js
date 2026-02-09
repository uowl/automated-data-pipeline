import { readFileSync } from 'fs';
import { parse } from 'csv-parse/sync';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DATA_DIR = process.env.LANDING_DATA_DIR || path.join(__dirname, '..', '..', 'data', 'landing');

/**
 * Data Pull (Step 1): load from CSV and JSON into Landing_Orders.
 * In production, ADF would do this (Copy from Blob/REST/etc.).
 */
export function runDataPull(db, runId, options = {}) {
  const { sourceType = 'CSV', fileName = 'sample_orders.csv', filePath: optionsFilePath } = options;
  // Allow full path (e.g. from trigger upload or CLI)
  const filePath = optionsFilePath
    ? path.isAbsolute(optionsFilePath)
      ? optionsFilePath
      : path.join(DATA_DIR, optionsFilePath)
    : path.join(DATA_DIR, fileName);
  const rows = [];

  const ext = path.extname(filePath).toLowerCase();
  if (ext === '.csv') {
    const raw = readFileSync(filePath, 'utf8');
    const parsed = parse(raw, { columns: true, skip_empty_lines: true });
    for (const row of parsed) {
      rows.push({
        RunId: runId,
        OrderId: row.OrderId || row.orderId,
        CustomerId: row.CustomerId || row.customerId,
        Amount: row.Amount ?? row.amount,
        OrderDate: row.OrderDate || row.orderDate,
        SourceType: 'CSV',
        RawPayload: null
      });
    }
  } else if (ext === '.json') {
    const raw = readFileSync(filePath, 'utf8');
    const arr = JSON.parse(raw);
    const list = Array.isArray(arr) ? arr : [arr];
    for (const row of list) {
      rows.push({
        RunId: runId,
        OrderId: row.OrderId || row.orderId,
        CustomerId: row.CustomerId || row.customerId,
        Amount: row.Amount ?? row.amount,
        OrderDate: row.OrderDate || row.orderDate,
        SourceType: 'JSON',
        RawPayload: JSON.stringify(row)
      });
    }
  }

  const ins = db.prepare(`
    INSERT INTO Landing_Orders (RunId, OrderId, CustomerId, Amount, OrderDate, SourceType, RawPayload)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `);
  for (const r of rows) {
    ins.run(r.RunId, r.OrderId, r.CustomerId, r.Amount, r.OrderDate, r.SourceType, r.RawPayload);
  }
  return rows.length;
}
