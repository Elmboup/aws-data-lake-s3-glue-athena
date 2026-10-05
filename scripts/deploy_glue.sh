#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:?Set AWS_REGION}"
: "${BUCKET_NAME:?Set BUCKET_NAME}"
: "${AWS_PROFILE:=default}"

CRAWLER_ROLE="AWSGlueServiceRoleBankingCrawler"
ETL_ROLE="AWSGlueServiceRoleBankingETL"

aws_cli=(aws --profile "$AWS_PROFILE" --region "$AWS_REGION")

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

sed "s/BUCKET_NAME/$BUCKET_NAME/g" \
  infra/iam/glue-crawler-s3-policy.template.json \
  > "$tmp_dir/crawler-policy.json"

sed "s/BUCKET_NAME/$BUCKET_NAME/g" \
  infra/iam/glue-etl-s3-policy.template.json \
  > "$tmp_dir/etl-policy.json"

create_role_if_missing() {
  local role_name="$1"
  if ! "${aws_cli[@]}" iam get-role --role-name "$role_name" >/dev/null 2>&1; then
    "${aws_cli[@]}" iam create-role \
      --role-name "$role_name" \
      --assume-role-policy-document file://infra/iam/glue-trust-policy.json >/dev/null
  fi
  "${aws_cli[@]}" iam attach-role-policy \
    --role-name "$role_name" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole
}

create_role_if_missing "$CRAWLER_ROLE"
create_role_if_missing "$ETL_ROLE"

"${aws_cli[@]}" iam put-role-policy \
  --role-name "$CRAWLER_ROLE" \
  --policy-name BankingCrawlerS3Access \
  --policy-document "file://$tmp_dir/crawler-policy.json"

"${aws_cli[@]}" iam put-role-policy \
  --role-name "$ETL_ROLE" \
  --policy-name BankingETLS3Access \
  --policy-document "file://$tmp_dir/etl-policy.json"

for db in banking_raw_db banking_silver_db banking_quarantine_db; do
  if ! "${aws_cli[@]}" glue get-database --name "$db" >/dev/null 2>&1; then
    "${aws_cli[@]}" glue create-database \
      --database-input "{\"Name\":\"$db\"}" >/dev/null
  fi
done

create_crawler_if_missing() {
  local name="$1"
  local database="$2"
  local path="$3"
  if ! "${aws_cli[@]}" glue get-crawler --name "$name" >/dev/null 2>&1; then
    "${aws_cli[@]}" glue create-crawler \
      --name "$name" \
      --role "$CRAWLER_ROLE" \
      --database-name "$database" \
      --targets "{\"S3Targets\":[{\"Path\":\"$path\"}]}"
  fi
}

create_crawler_if_missing \
  banking-raw-transactions-crawler \
  banking_raw_db \
  "s3://$BUCKET_NAME/raw/transactions/"

create_crawler_if_missing \
  banking-silver-transactions-crawler \
  banking_silver_db \
  "s3://$BUCKET_NAME/silver/transactions/"

create_crawler_if_missing \
  banking-quarantine-transactions-crawler \
  banking_quarantine_db \
  "s3://$BUCKET_NAME/quarantine/transactions/"

if "${aws_cli[@]}" glue get-job --job-name banking-raw-to-silver >/dev/null 2>&1; then
  echo "Glue job already exists: banking-raw-to-silver"
else
  "${aws_cli[@]}" glue create-job \
    --name banking-raw-to-silver \
    --role "$ETL_ROLE" \
    --command "{\"Name\":\"glueetl\",\"ScriptLocation\":\"s3://$BUCKET_NAME/scripts/glue/raw_to_silver.py\",\"PythonVersion\":\"3\"}" \
    --glue-version "5.1" \
    --worker-type G.1X \
    --number-of-workers 2 \
    --timeout 10 \
    --default-arguments "{
      \"--job-language\":\"python\",
      \"--enable-metrics\":\"true\",
      \"--RAW_DATABASE\":\"banking_raw_db\",
      \"--RAW_TABLE\":\"transactions\",
      \"--SILVER_PATH\":\"s3://$BUCKET_NAME/silver/transactions/\",
      \"--QUARANTINE_PATH\":\"s3://$BUCKET_NAME/quarantine/transactions/\"
    }" >/dev/null
fi

echo "Glue resources deployed."
echo "Run the raw crawler before starting the ETL job."
