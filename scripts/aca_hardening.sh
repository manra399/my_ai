#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT_DIR/infra/azure/storage-vars.env"
if [[ -f "$ENV_FILE" ]]; then
  TMP_ENV="$(mktemp)"; awk 'NR==1{sub(/^\xef\xbb\xbf/,"")} {gsub(/\r/,""); print}' "$ENV_FILE" > "$TMP_ENV"; source "$TMP_ENV"; rm -f "$TMP_ENV"
fi

: "${RG:=owui-rg}"
: "${APP_NAME:=owui}"

APP_EXISTS=0
az containerapp show -g "$RG" -n "$APP_NAME" >/dev/null 2>&1 && APP_EXISTS=1
if [[ $APP_EXISTS -ne 1 ]]; then
  echo "App $APP_NAME not found in $RG"; exit 1
fi

# 1) Stable session secret
# Prefer an injected secret from CI named WEBUI_SECRET_HEX; else generate once if missing.
WEBUI_SECRET_HEX="${WEBUI_SECRET_HEX:-}"
HAS_SECRET=$(az containerapp show -g "$RG" -n "$APP_NAME" --query "properties.template.containers[0].env[?name=='WEBUI_SECRET_KEY'] | length(@)" -o tsv)
if [[ -n "$WEBUI_SECRET_HEX" ]]; then
  az containerapp secret set -g "$RG" -n "$APP_NAME" --secrets webui-secret="$WEBUI_SECRET_HEX" >/dev/null
  az containerapp update -g "$RG" -n "$APP_NAME" --env-vars WEBUI_SECRET_KEY=secretref:webui-secret >/dev/null
elif [[ "$HAS_SECRET" = "0" ]]; then
  GEN=$(openssl rand -hex 32)
  az containerapp secret set -g "$RG" -n "$APP_NAME" --secrets webui-secret="$GEN" >/dev/null
  az containerapp update -g "$RG" -n "$APP_NAME" --env-vars WEBUI_SECRET_KEY=secretref:webui-secret >/dev/null
fi

# 2) Optional Postgres
if [[ -n "${DATABASE_URL:-}" ]]; then
  az containerapp secret set -g "$RG" -n "$APP_NAME" --secrets db-url="$DATABASE_URL" >/dev/null
  az containerapp update -g "$RG" -n "$APP_NAME" --env-vars DATABASE_URL=secretref:db-url >/dev/null
fi

# 3) Keep single replica (SQLite safety)
az containerapp update -g "$RG" -n "$APP_NAME" --min-replicas 1 --max-replicas 1 >/dev/null

echo "Hardening done."
