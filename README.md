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