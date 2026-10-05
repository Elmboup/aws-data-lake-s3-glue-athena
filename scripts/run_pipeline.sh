#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:?Set AWS_REGION}"
: "${BUCKET_NAME:?Set BUCKET_NAME}"
: "${AWS_PROFILE:=default}"

aws_cli=(aws --profile "$AWS_PROFILE" --region "$AWS_REGION")

wait_crawler() {
  local name="$1"
  while true; do
    state="$("${aws_cli[@]}" glue get-crawler \
      --name "$name" \
      --query 'Crawler.State' \
      --output text)"
    [[ "$state" == "READY" ]] && break
    echo "$name: $state"
    sleep 5
  done
}

echo "Starting raw crawler..."
"${aws_cli[@]}" glue start-crawler --name banking-raw-transactions-crawler
wait_crawler banking-raw-transactions-crawler

raw_status="$("${aws_cli[@]}" glue get-crawler \
  --name banking-raw-transactions-crawler \
  --query 'Crawler.LastCrawl.Status' \
  --output text)"

if [[ "$raw_status" != "SUCCEEDED" ]]; then
  echo "Raw crawler failed with status: $raw_status" >&2
  exit 1
fi

echo "Starting Glue ETL..."
run_id="$("${aws_cli[@]}" glue start-job-run \
  --job-name banking-raw-to-silver \
  --query 'JobRunId' \
  --output text)"

while true; do
  state="$("${aws_cli[@]}" glue get-job-run \
    --job-name banking-raw-to-silver \
    --run-id "$run_id" \
    --query 'JobRun.JobRunState' \
    --output text)"
  echo "ETL state: $state"
  case "$state" in
    SUCCEEDED) break ;;
    FAILED|ERROR|TIMEOUT|STOPPED)
      "${aws_cli[@]}" glue get-job-run \
        --job-name banking-raw-to-silver \
        --run-id "$run_id" \
        --query 'JobRun.{State:JobRunState,Error:ErrorMessage}' \
        --no-cli-pager
      exit 1
      ;;
  esac
  sleep 10
done

for crawler in \
  banking-silver-transactions-crawler \
  banking-quarantine-transactions-crawler
do
  echo "Starting $crawler..."
  "${aws_cli[@]}" glue start-crawler --name "$crawler"
  wait_crawler "$crawler"
done

echo "Pipeline completed."
echo "Glue Job Run ID: $run_id"
