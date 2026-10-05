SELECT
    transaction_id,
    customer_id,
    amount,
    currency,
    "timestamp"
FROM transactions
WHERE year = '2026'
  AND month = '09'
  AND day = '12'
ORDER BY "timestamp";
