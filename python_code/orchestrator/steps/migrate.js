/**
 * Migrate (Step 4): read Staging_Orders_Transformed, merge into Target_Orders.
 * In production, ADF calls dbo.usp_Migrate_Orders @RunId.
 */
export function runMigrate(db, runId) {
  const rows = db.prepare('SELECT OrderId, CustomerId, Amount, OrderDate, AmountCategory FROM Staging_Orders_Transformed WHERE RunId = ?').all(runId);
  const ins = db.prepare(`
    INSERT INTO Target_Orders (OrderId, CustomerId, Amount, OrderDate, AmountCategory, MigratedAt)
    VALUES (?, ?, ?, ?, ?, datetime('now'))
    ON CONFLICT(OrderId) DO UPDATE SET
      CustomerId = excluded.CustomerId,
      Amount = excluded.Amount,
      OrderDate = excluded.OrderDate,
      AmountCategory = excluded.AmountCategory,
      MigratedAt = datetime('now')
  `);
  for (const row of rows) {
    ins.run(row.OrderId, row.CustomerId, row.Amount, row.OrderDate, row.AmountCategory);
  }
  return rows.length;
}
