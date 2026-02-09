/**
 * Transform (Step 3): read Staging_Orders, apply business rules, write Staging_Orders_Transformed.
 * In production, ADF calls dbo.usp_Transform_Orders @RunId.
 */
export function runTransform(db, runId) {
  const rows = db.prepare('SELECT * FROM Staging_Orders WHERE RunId = ?').all(runId);
  const ins = db.prepare(`
    INSERT INTO Staging_Orders_Transformed (RunId, OrderId, CustomerId, Amount, OrderDate, AmountCategory)
    VALUES (?, ?, ?, ?, ?, ?)
  `);
  for (const row of rows) {
    const amount = Number(row.Amount);
    const category = amount < 50 ? 'Low' : amount < 200 ? 'Medium' : 'High';
    ins.run(runId, row.OrderId, row.CustomerId, row.Amount, row.OrderDate, category);
  }
  return rows.length;
}
