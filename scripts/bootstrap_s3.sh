#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:?Set AWS_REGION}"
: "${BUCKET_NAME:?Set BUCKET_NAME}"
: "${AWS_PROFILE:=default}"

aws_cli=(aws --profile "$AWS_PROFILE" --region "$AWS_REGION")

if ! "${aws_cli[@]}" s3api head-bucket --bucket "$BUCKET_NAME" >/dev/null 2>&1; then
  echo "Creating bucket: $BUCKET_NAME in $AWS_REGION"
  if [[ "$AWS_REGION" == "us-east-1" ]]; then
    "${aws_cli[@]}" s3api create-bucket --bucket "$BUCKET_NAME"
  else
    "${aws_cli[@]}" s3api create-bucket \
      --bucket "$BUCKET_NAME" \
      --create-bucket-configuration "LocationConstraint=$AWS_REGION"
  fi
fi

"${aws_cli[@]}" s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'

"${aws_cli[@]}" s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

echo "Uploading partitioned sample data..."
"${aws_cli[@]}" s3 sync \
  data/ \
  "s3://$BUCKET_NAME/raw/transactions/" \
  --exclude "*" \
  --include "*.csv"

echo "Uploading Glue script..."
"${aws_cli[@]}" s3 cp \
  src/glue/raw_to_silver.py \
  "s3://$BUCKET_NAME/scripts/glue/raw_to_silver.py"

echo "S3 bootstrap complete."
