openwebui-stack/
├─ .env.sample
├─ compose/
│  └─ docker-compose.yml
├─ scripts/
│  ├─ local_up.sh
│  ├─ local_down.sh
│  ├─ pull_ollama_models.sh
│  ├─ aca_deploy.sh
│  ├─ aca_mount_files.sh
│  ├─ aca_update_env.sh
│  └─ aca_show_url.sh
└─ infra/
   └─ azure/
      └─ storage-vars.env          # keeps storage and mount names in one place




Step 1 = az login

Step 2 = az extension add --name containerapp

Step 3 = chmod +x ./scripts/aca_deploy.sh

Step 4 = ./scripts/aca_deploy.sh

Step 5 = ./scripts/aca_show_url.sh
# outputs something like: owui.somehash.uksouth.azurecontainerapps.io


Step 6---
First-run setup in the UI
Create the admin account when prompted.
Go to Settings → Models.
Manually add any providers you want:
OpenAI / OpenAI-compatible: paste API key + Base URL (e.g. https://api.openai.com/v1 or the provider’s URL).
Azure OpenAI: paste API key + https://<your-resource>.openai.azure.com, set the API version, and select the deployment name as the model.
Ollama: set Base URL to your Ollama host (e.g. http://<ip-or-dns>:11434). You manage model pulls on the Ollama server; Open WebUI will auto-list them.
All of these are stored under /app/backend/data on your Azure Files mount—so they persist across restarts/revisions.


------------------

Step 7---
4) (Optional) Change anything later—no rebuild needed
If you ever want to update environment variables instead of using the UI:
# examples; safe to skip if you configure only in the UI
./scripts/aca_update_env.sh OPENAI_API_BASE=https://api.openai.com/v1
./scripts/aca_update_env.sh OLLAMA_BASE_URL=http://10.0.0.5:11434
./scripts/aca_update_env.sh OPENAI_API_KEY=



------------------

Step 8---
5) (Optional) Verify it’s healthy
# Show current revision & ingress
az containerapp show -g $(grep '^RG=' infra/azure/storage-vars.env | cut -d= -f2) \
  -n $(grep '^APP_NAME=' infra/azure/storage-vars.env | cut -d= -f2) \
  --query "{fqdn:properties.configuration.ingress.fqdn, activeRev:properties.latestRevisionName}" -o yaml

# Tail logs if needed
az containerapp logs show -g owui-rg -n owui --follow





Debugging on 9th Sept.

Step-1
# pick a 64-hex secret or re-use the one in your CI secret
SECRET=$(openssl rand -hex 32)

az containerapp secret set -g owui-rg -n owui --secrets webui-secret="$SECRET"
az containerapp update     -g owui-rg -n owui --env-vars WEBUI_SECRET_KEY=secretref:webui-secret

Step2---
RG=owui-rg
APP=owui
APP_ID=$(az containerapp show -g "$RG" -n "$APP" --query id -o tsv)

SECRET=$(openssl rand -hex 32)

# 2) Build JSON payloads (no jq needed)
SECRETS_JSON=$(printf '[{"name":"%s","value":"%s"}]' "webui-secret" "$SECRET")
ENVS_JSON='[{"name":"WEBUI_SECRET_KEY","secretRef":"webui-secret"}]'
VOLUMES_JSON='[{"name":"owui-volume","storageName":"owuifiles","storageType":"AzureFile","mountOptions":"nobrl,dir_mode=0777,file_mode=0666"}]'
MOUNTS_JSON='[{"volumeName":"owui-volume","mountPath":"/app/backend/data"}]'

# 3) Patch everything atomically (secrets + env + volumes + mounts)
az resource update --ids "$APP_ID" \
  --set properties.configuration.secrets="$SECRETS_JSON" \
        properties.template.containers[0].env="$ENVS_JSON" \
        properties.template.volumes="$VOLUMES_JSON" \
        properties.template.containers[0].volumeMounts="$MOUNTS_JSON"

az containerapp update -g "$RG" -n "$APP" --min-replicas 2 --max-replicas 5

REV=$(az containerapp show -g "$RG" -n "$APP" --query properties.latestRevisionName -o tsv)
az containerapp revision restart -g "$RG" -n "$APP" --revision "$REV"

# 4) Roll a fresh revision
az resource update --ids "$APP_ID" --set properties.template.revisionSuffix="setup$(date +%s)"

# 5) Quick checks
az containerapp show -g "$RG" -n "$APP" --query "properties.template.{volumes:volumes, mounts:containers[0].volumeMounts}" -o yaml
az containerapp show -g "$RG" -n "$APP" --query "properties.template.containers[0].env" -o yaml