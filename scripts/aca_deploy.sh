#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# --- Load vars robustly (strip BOM/CR), then source ---
ENV_FILE="$ROOT_DIR/infra/azure/storage-vars.env"
if [[ -f "$ENV_FILE" ]]; then
  TMP_ENV="$(mktemp)"
  awk 'NR==1{sub(/^\xef\xbb\xbf/,"")} {gsub(/\r/,""); print}' "$ENV_FILE" > "$TMP_ENV"
  # shellcheck disable=SC1090
  source "$TMP_ENV"
  rm -f "$TMP_ENV"
fi

# --- Safe defaults ---
: "${RG:=owui-rg}"
: "${LOC:=uksouth}"
: "${ENV_NAME:=owui-env}"
: "${APP_NAME:=owui}"
: "${SA_NAME:=owuistorage$RANDOM}"
: "${SHARE_NAME:=owui-data}"
: "${MOUNT_PATH:=/app/backend/data}"
: "${TARGET_PORT:=8080}"

# Provider envs (ok to leave empty; you'll add models in UI)
: "${OPENAI_API_KEY:=}"
: "${OPENAI_API_BASE:=}"
: "${OLLAMA_BASE_URL:=}"
: "${AZURE_OPENAI_API_KEY:=}"
: "${AZURE_OPENAI_API_BASE:=}"
: "${AZURE_OPENAI_API_VERSION:=}"

echo ">> Config:"
echo "   RG=$RG LOC=$LOC ENV_NAME=$ENV_NAME APP_NAME=$APP_NAME"
echo "   SA_NAME=$SA_NAME SHARE_NAME=$SHARE_NAME"
echo "   MOUNT_PATH=${MOUNT_PATH:-/app/backend/data} TARGET_PORT=${TARGET_PORT:-8080}"

echo ">> Ensuring Azure CLI extension..."
az extension add -n containerapp --upgrade -y >/dev/null 2>&1 || true

echo ">> Ensuring Resource Group"
az group create -n "$RG" -l "$LOC" >/dev/null

echo ">> Ensuring Container Apps Environment"
az containerapp env create -g "$RG" -n "$ENV_NAME" -l "$LOC" >/devnull 2>&1 || true

echo ">> Ensuring Storage Account + File Share"
if az storage account show -g "$RG" -n "$SA_NAME" >/dev/null 2>&1; then
  SA="$SA_NAME"
else
  SA=$(az storage account create -g "$RG" -n "$SA_NAME" -l "$LOC" \
        --sku Standard_LRS --kind StorageV2 --query name -o tsv)
fi
KEY=$(az storage account keys list -g "$RG" -n "$SA" --query "[0].value" -o tsv)

az storage share-rm create \
  --resource-group "$RG" \
  --storage-account "$SA" \
  --name "$SHARE_NAME" \
  --quota 50 \
  --enabled-protocols SMB >/dev/null

echo ">> Linking Azure Files to Environment storage (owuifiles)"
if az containerapp env storage show \
  --name "$ENV_NAME" --resource-group "$RG" --storage-name owuifiles >/dev/null 2>&1; then
  CUR_SA=$(az containerapp env storage show \
    --name "$ENV_NAME" --resource-group "$RG" --storage-name owuifiles \
    --query properties.azureFile.accountName -o tsv)
  CUR_SHARE=$(az containerapp env storage show \
    --name "$ENV_NAME" --resource-group "$RG" --storage-name owuifiles \
    --query properties.azureFile.shareName -o tsv)
  if [[ "$CUR_SA" != "$SA" || "$CUR_SHARE" != "$SHARE_NAME" ]]; then
    echo "   Different account/share detected. Replacing storage binding..."
    az containerapp env storage remove \
      --name "$ENV_NAME" --resource-group "$RG" \
      --storage-name owuifiles --yes >/dev/null
    az containerapp env storage set \
      --name "$ENV_NAME" --resource-group "$RG" \
      --storage-name owuifiles \
      --azure-file-account-name "$SA" \
      --azure-file-account-key "$KEY" \
      --azure-file-share-name "$SHARE_NAME" \
      --access-mode ReadWrite >/dev/null
  else
    echo "   Same account/share. Updating account key..."
    az containerapp env storage set \
      --name "$ENV_NAME" --resource-group "$RG" \
      --storage-name owuifiles \
      --azure-file-account-key "$KEY" >/dev/null
  fi
else
  az containerapp env storage set \
    --name "$ENV_NAME" --resource-group "$RG" \
    --storage-name owuifiles \
    --azure-file-account-name "$SA" \
    --azure-file-account-key "$KEY" \
    --azure-file-share-name "$SHARE_NAME" \
    --access-mode ReadWrite >/dev/null
fi

echo ">> Creating/ensuring Container App: $APP_NAME"
if ! az containerapp show -g "$RG" -n "$APP_NAME" >/dev/null 2>&1; then
  echo "   App exists."
else
  az containerapp create \
    -g "$RG" -n "$APP_NAME" \
    --environment "$ENV_NAME" \
    --image ghcr.io/open-webui/open-webui:main \
    --ingress external --target-port "$TARGET_PORT" \
    --min-replicas 1 --max-replicas 1 \
    --env-vars \
      OPENAI_API_KEY="$OPENAI_API_KEY" \
      OPENAI_API_BASE="$OPENAI_API_BASE" \
      OLLAMA_BASE_URL="$OLLAMA_BASE_URL" \
      AZURE_OPENAI_API_KEY="$AZURE_OPENAI_API_KEY" \
      AZURE_OPENAI_API_BASE="$AZURE_OPENAI_API_BASE" \
      AZURE_OPENAI_API_VERSION="$AZURE_OPENAI_API_VERSION" \
    --cpu 1.0 --memory 2.0Gi >/dev/null
fi

echo ">> Mounting Azure Files at ${MOUNT_PATH:-/app/backend/data} (via az resource update)…"
APP_ID=$(az containerapp show -g "$RG" -n "$APP_NAME" --query id -o tsv)
VOLUMES_JSON=$(printf '[{"name":"owui-volume","storageName":"owuifiles","storageType":"AzureFile","mountOptions":"nobrl,dir_mode=0777,file_mode=0666"}]')
MOUNTS_JSON=$(printf '[{"volumeName":"owui-volume","mountPath":"%s"}]' "${MOUNT_PATH:-/app/backend/data}")


# Build JSON payloads safely
VOLUMES_JSON=$(printf '[{"name":"%s","storageName":"%s","storageType":"AzureFile"}]' "owui-volume" "owuifiles")
MOUNTS_JSON=$(printf '[{"volumeName":"%s","mountPath":"%s"}]' "owui-volume" "${MOUNT_PATH:-/app/backend/data}")

# Patch ARM properties directly (bypasses containerapp extension env-var parser)
az resource update --ids "$APP_ID" \
  --set properties.template.volumes="$VOLUMES_JSON" \
        properties.template.containers[0].volumeMounts="$MOUNTS_JSON" >/dev/null

# (Optional) bump revision suffix to ensure a fresh revision shows up
REV_SUFFIX="vol$(date +%s)"
az resource update --ids "$APP_ID" \
  --set properties.template.revisionSuffix="$REV_SUFFIX" >/dev/null

FQDN=$(az containerapp show -g "$RG" -n "$APP_NAME" --query properties.configuration.ingress.fqdn -o tsv)
echo "✅ Open WebUI: https://${FQDN}"
echo "   Persistence: Azure Files '${SHARE_NAME}' mounted at ${MOUNT_PATH:-/app/backend/data}"
echo "   Next: open the URL → create admin → Settings → Models → add providers/models."
