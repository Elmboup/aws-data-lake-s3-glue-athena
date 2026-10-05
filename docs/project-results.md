# Project Results

The project was executed end to end in AWS.

## Raw crawler

Detected:

```text
classification = csv
amount         = double
timestamp      = string
partition keys = year, month, day
```

Three partitions were discovered for 2026-09-10, 2026-09-11 and 2026-09-12.

## Basic ETL validation

Initial technical transformation:

```text
Raw rows    = 11
Silver rows = 10
```

The difference is the duplicate transaction ID.

Schema transformation:

```text
amount:    double → decimal(18,2)
timestamp: string → timestamp
```

## Data Quality run

Final DQ-enabled pipeline:

```text
Raw        = 11
Prepared   = 10
Valid      = 8
Quarantine = 2
```

Rule failures:

```text
IsComplete "amount"       → 1 failed row
ColumnValues "amount" > 0 → 2 failed rows
```

## Quarantine analysis

Using Athena `UNNEST` produced one row per quality violation:

```text
TX005 | -20.00 | ColumnValues "amount" > 0
TX006 | NULL   | ColumnValues "amount" > 0
TX006 | NULL   | IsComplete "amount"
```

Therefore:

```text
2 invalid transactions
3 DQ rule violations
```

## Key takeaway

A technically successful job is not sufficient. The project validates both:

- technical execution (`SUCCEEDED`)
- business/data-quality outcomes (counts, schema and rejected rows)
