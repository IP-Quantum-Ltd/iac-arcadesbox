#!/usr/bin/env bash

set -euo pipefail

ENV_FILE="${1:-.env}"
SECRET_NAME="${2:-my-app/env}"
AWS_REGION="${3:-us-east-1}"
DRY_RUN="${DRY_RUN:-false}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ Env file not found: $ENV_FILE"
  exit 1
fi

# Convert .env to JSON using a robust, production-grade jq parser.
echo "📦 Converting $ENV_FILE to JSON"

JSON_CONTENT=$(jq -Rnc '
  [
    inputs
    | gsub("^export\\s+";"")
    | select(test("^[A-Za-z_][A-Za-z0-9_]*\\s*="))
    | capture("^(?<k>[A-Za-z_][A-Za-z0-9_]*)\\s*=\\s*(?<raw>.*)$")
    | .v = (
        if .raw == "" then
          ""
        elif (.raw | startswith("\"") and endswith("\"")) then
          # Double-quoted: strip quotes and process escapes
          .raw[1:-1] | gsub("\\\\n"; "\n") | gsub("\\\\t"; "\t") | gsub("\\\\\""; "\"")
        elif (.raw | startswith("'\''") and endswith("'\''")) then
          # Single-quoted: strip quotes only
          .raw[1:-1]
        else
          # Unquoted: use as-is
          .raw
        end
      )
    | { (.k): .v }
  ]
  | add
' < "$ENV_FILE")

if ! echo "$JSON_CONTENT" | jq empty 2>/dev/null; then
  echo "❌ Generated invalid JSON"
  exit 1
fi


if [[ "$DRY_RUN" == "true" ]]; then
  echo "🔍 Dry run - would upload:"
  echo "$JSON_CONTENT" | jq .
  exit 0
fi

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
