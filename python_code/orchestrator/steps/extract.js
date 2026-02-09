/**
 * Extract (Step 2): read Landing_Orders, normalize into Staging_Orders.
 * In production, ADF calls dbo.usp_Extract_Orders @RunId.
 */
export function runExtract(db, runId) {
  const landing = db.prepare('SELECT * FROM Landing_Orders WHERE RunId = ?').all(runId);
  const ins = db.prepare(`
    INSERT INTO Staging_Orders (RunId, OrderId, CustomerId, Amount, OrderDate)
    VALUES (?, ?, ?, ?, ?)
  `);
  for (const row of landing) {
    const orderId = (row.OrderId || '').trim();
    if (!orderId) continue;
    const orderDate = row.OrderDate ? parseDate(row.OrderDate) : null;
    const amount = row.Amount != null ? Number(row.Amount) : 0;
    ins.run(runId, orderId, (row.CustomerId || '').trim() || 'UNKNOWN', amount, orderDate);
  }
  return landing.length;
}

function parseDate(s) {
  if (!s) return null;
  const d = new Date(s);
  return isNaN(d.getTime()) ? null : d.toISOString().slice(0, 10);
}
