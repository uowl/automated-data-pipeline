#!/usr/bin/env node
/**
 * Generate a JSON file with N order records for pipeline testing.
 * Usage: node generate-large-json.mjs [rows]   e.g. node generate-large-json.mjs 10000
 * Or set env ROWS=10000. Default: 10000.
 * Output: data/landing/sample_orders_<rows>.json
 */

import { writeFileSync, mkdirSync } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const OUT_DIR = path.join(__dirname, '..', 'data', 'landing');

const ROWS = parseInt(process.env.ROWS || process.argv[2] || '10000', 10) || 10000;
const suffix = ROWS >= 1000000 ? `${ROWS / 1000000}M` : ROWS >= 1000 ? `${ROWS / 1000}k` : String(ROWS);
const OUT_FILE = path.join(OUT_DIR, `sample_orders_${suffix}.json`);

const amounts = [15.99, 25.00, 33.50, 45.99, 59.00, 75.25, 99.50, 120.00, 150.00, 185.00, 210.00, 275.00, 350.00, 499.99];
const startDate = new Date('2024-01-01');

mkdirSync(OUT_DIR, { recursive: true });

const records = [];
for (let i = 1; i <= ROWS; i++) {
  const dayOffset = i % 400;
  const d = new Date(startDate);
  d.setDate(d.getDate() + dayOffset);
  records.push({
    OrderId: `ORD-${String(i).padStart(6, '0')}`,
    CustomerId: `C${(i % 2000) + 1}`,
    Amount: amounts[i % amounts.length],
    OrderDate: d.toISOString().slice(0, 10)
  });
}

writeFileSync(OUT_FILE, JSON.stringify(records), 'utf8');
console.log(`Wrote ${ROWS} records to ${OUT_FILE}`);
