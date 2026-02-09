#!/usr/bin/env python3
"""Generate a 1 million row sample CSV with OrderId, CustomerId, Amount, OrderDate."""
import csv
import random
from datetime import datetime, timedelta

OUTPUT = "data/samples/sample_1m.csv"
ROWS = 1_000_000

def main():
    start = datetime(2020, 1, 1)
    with open(OUTPUT, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["OrderId", "CustomerId", "Amount", "OrderDate"])
        for i in range(1, ROWS + 1):
            w.writerow([
                f"ORD{i:010d}",
                f"C{random.randint(1, 50000):06d}",
                round(random.uniform(10, 5000), 2),
                (start + timedelta(days=random.randint(0, 1400))).strftime("%Y-%m-%d"),
            ])
    print(f"Wrote {ROWS:,} rows to {OUTPUT}")

if __name__ == "__main__":
    main()
