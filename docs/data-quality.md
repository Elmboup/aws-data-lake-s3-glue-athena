# Data Quality

The raw input intentionally contains defects to demonstrate quality controls.

## Rules

| Rule | Purpose |
|---|---|
| `IsComplete "transaction_id"` | Transaction identifier is required |
| `IsComplete "customer_id"` | Customer identifier is required |
| `IsComplete "account_id"` | Account identifier is required |
| `IsComplete "amount"` | Amount cannot be null |
| `ColumnValues "amount" > 0` | Project business rule for valid payment amount |
| `IsComplete "currency"` | Currency is required |
| `IsComplete "timestamp"` | Timestamp is required |

> The `amount > 0` rule is an explicit project assumption for payment transactions. In a real banking domain, negative amounts may be legitimate depending on the transaction model.

## Observed result

After deduplication there are 10 rows:

- 8 passed all rules
- 2 failed at least one rule

Rule-level metrics:

- amount completeness = 0.9
- 1 record fails `IsComplete "amount"`
- 2 records fail `ColumnValues "amount" > 0`

A row may fail multiple rules, so row failures and rule violations are different metrics.

## Quarantine pattern

Failed records are preserved with:

```text
DataQualityRulesPass
DataQualityRulesFail
DataQualityRulesSkip
DataQualityEvaluationResult
```

This makes quality failures explainable and supports later remediation / reprocessing.
