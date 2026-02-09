#!/usr/bin/env node
/**
 * Generate a CSV with N rows for pipeline testing.
 * Usage: node generate-large-csv.mjs [rows]   e.g. node generate-large-csv.mjs 100000
 * Or set env ROWS=100000. Default: 20000.
 * Output: data/landing/sample_orders_<rows>.csv (e.g. sample_orders_100k.csv)
 */

import { writeFileSync, mkdirSync } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const OUT_DIR = path.join(__dirname, '..', 'data', 'landing');

const ROWS = parseInt(process.env.ROWS || process.argv[2] || '20000', 10) || 20000;
const suffix = ROWS >= 1000000 ? `${ROWS / 1000000}M` : ROWS >= 1000 ? `${ROWS / 1000}k` : String(ROWS);
const OUT_FILE = path.join(OUT_DIR, `sample_orders_${suffix}.csv`);

const amounts = [15.99, 25.00, 33.50, 45.99, 59.00, 75.25, 99.50, 120.00, 150.00, 185.00, 210.00, 275.00, 350.00, 499.99];
const startDate = new Date('2024-01-01');

mkdirSync(OUT_DIR, { recursive: true });

const lines = ['OrderId,CustomerId,Amount,OrderDate'];
for (let i = 1; i <= ROWS; i++) {
  const orderId = `ORD-${String(i).padStart(6, '0')}`;
  const customerId = `C${(i % 2000) + 1}`;
  const amount = amounts[i % amounts.length];
  const dayOffset = i % 400;
  const d = new Date(startDate);
  d.setDate(d.getDate() + dayOffset);
  const orderDate = d.toISOString().slice(0, 10);
  lines.push(`${orderId},${customerId},${amount},${orderDate}`);
}

writeFileSync(OUT_FILE, lines.join('\n'), 'utf8');
console.log(`Wrote ${ROWS} rows to ${OUT_FILE}`);
