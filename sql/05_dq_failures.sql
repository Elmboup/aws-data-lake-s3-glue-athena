SELECT
    transaction_id,
    amount,
    failed_rule
FROM transactions
CROSS JOIN UNNEST(dataqualityrulesfail) AS t(failed_rule)
ORDER BY transaction_id, failed_rule;
