# IAM & Security

## Principles

- Never use root credentials for workloads.
- Do not commit access keys, secret keys, account IDs or STS session tokens.
- Use IAM roles assumed by AWS services.
- Separate crawler and ETL responsibilities.
- Grant permissions only to required S3 prefixes.

## Trust policy

Glue service roles trust:

```json
{
  "Principal": {
    "Service": "glue.amazonaws.com"
  },
  "Action": "sts:AssumeRole"
}
```

## Crawler permissions

The crawler role needs read access to the prefixes it catalogs:

```text
s3:ListBucket
s3:GetObject
```

It does not need `PutObject`.

## ETL permissions

The job reads:

```text
raw/transactions/*
scripts/glue/*
```

and writes:

```text
silver/transactions/*
quarantine/transactions/*
```

Because the job uses overwrite semantics, the target prefixes include `s3:DeleteObject`.

## Public access

S3 Block Public Access should remain enabled for all four settings.

## Encryption

S3 encrypts objects at rest. For more controlled production environments, use SSE-KMS with dedicated KMS policies and key rotation.
