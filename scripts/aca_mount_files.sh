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
: "${ENV_NAME:=owui-env}"
: "${APP_NAME:=owui}"
: "${MOUNT_PATH:=/app/backend/data}"

SA="$1"   # storage account
KEY="$2"  # key
SHARE="${3:-${SHARE_NAME:-owui-data}}"

echo ">> Relinking env storage 'owuifiles' to $SA/$SHARE"
az containerapp env storage remove --name "$ENV_NAME" --resource-group "$RG" --storage-name owuifiles --yes >/dev/null 2>&1 || true
az containerapp env storage set \
  --name "$ENV_NAME" --resource-group "$RG" \
  --storage-name owuifiles \
  --azure-file-account-name "$SA" \
  --azure-file-account-key "$KEY" \
  --azure-file-share-name "$SHARE" \
  --access-mode ReadWrite >/dev/null

APP_ID=$(az containerapp show -g "$RG" -n "$APP_NAME" --query id -o tsv)
VOLUMES_JSON='[{"name":"owui-volume","storageName":"owuifiles","storageType":"AzureFile"}]'
MOUNTS_JSON=$(printf '[{"volumeName":"owui-volume","mountPath":"%s"}]' "${MOUNT_PATH:-/app/backend/data}")

echo ">> Applying mount via ARM patch"
az resource update --ids "$APP_ID" \
  --set properties.template.volumes="$VOLUMES_JSON" \
        properties.template.containers[0].volumeMounts="$MOUNTS_JSON" >/dev/null

REV_SUFFIX="relink$(date +%s)"
az resource update --ids "$APP_ID" \
  --set properties.template.revisionSuffix="$REV_SUFFIX" >/dev/null

echo "Done."
