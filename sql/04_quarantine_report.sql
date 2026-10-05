SELECT
    transaction_id,
    amount,
    dataqualityevaluationresult,
    dataqualityrulesfail
FROM transactions
ORDER BY transaction_id;
