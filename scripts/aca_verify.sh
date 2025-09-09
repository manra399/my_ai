#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT_DIR/infra/azure/storage-vars.env"
if [[ -f "$ENV_FILE" ]]; then
  TMP_ENV="$(mktemp)"; awk 'NR==1{sub(/^\xef\xbb\xbf/,"")} {gsub(/\r/,""); print}' "$ENV_FILE" > "$TMP_ENV"; source "$TMP_ENV"; rm -f "$TMP_ENV"
fi
: "${RG:=owui-rg}"
: "${APP_NAME:=owui}"

echo "Mounts + volumes:"
az containerapp show -g "$RG" -n "$APP_NAME" --query "properties.template.{volumes:volumes, mounts:containers[0].volumeMounts}" -o yaml

echo
echo "WEBUI_SECRET_KEY present?"
az containerapp show -g "$RG" -n "$APP_NAME" --query "properties.template.containers[0].env[?name=='WEBUI_SECRET_KEY']" -o yaml

echo
echo "URL:"
az containerapp show -g "$RG" -n "$APP_NAME" --query properties.configuration.ingress.fqdn -o tsv
