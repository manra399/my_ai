#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT_DIR/infra/azure/storage-vars.env"
if [[ -f "$ENV_FILE" ]]; then
  TMP_ENV="$(mktemp)"
  awk 'NR==1{sub(/^\xef\xbb\xbf/,"")} {gsub(/\r/,""); print}' "$ENV_FILE" > "$TMP_ENV"
  # shellcheck disable=SC1090
  source "$TMP_ENV"
  rm -f "$TMP_ENV"
fi

: "${RG:=owui-rg}"
: "${APP_NAME:=owui}"

if [[ "$#" -eq 0 ]]; then
  echo "Usage: $0 KEY=VALUE [KEY=VALUE ...]"
  exit 1
fi

az containerapp update -g "$RG" -n "$APP_NAME" --env-vars "$@"
echo "Updated env on $APP_NAME."
