#!/usr/bin/env bash

set -euo pipefail

ENV_FILE="${1:-.env}"
SECRET_NAME="${2:-my-app/env}"
AWS_REGION="${3:-us-east-1}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ Env file not found: $ENV_FILE"
  exit 1
fi

# Convert .env to JSON
echo "📦 Converting $ENV_FILE to JSON"
JSON_CONTENT=$(jq -Rn '
  ( input | split("=") ) as $first
  | reduce inputs as $line (
      { ($first[0]): $first[1] };
      . + ( $line | split("=") | { (.[0]): .[1] } )
    )
' < "$ENV_FILE")

echo "🚀 Uploading to Secrets Manager: $SECRET_NAME"

# Check if the secret already exists
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$AWS_REGION" > /dev/null 2>&1; then
  echo "🔁 Secret exists. Updating..."
  aws secretsmanager put-secret-value \
    --secret-id "$SECRET_NAME" \
    --secret-string "$JSON_CONTENT" \
    --region "$AWS_REGION"
else
  echo "🆕 Secret doesn't exist. Creating..."
  aws secretsmanager create-secret \
    --name "$SECRET_NAME" \
    --secret-string "$JSON_CONTENT" \
    --region "$AWS_REGION"
fi

echo "✅ Done."
