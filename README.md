# OpenWebUI Stack — Local & Azure Container Apps

A compact, batteries-included setup to run **Open WebUI** locally with Docker Compose (optionally with **Ollama**) and to deploy it to **Azure Container Apps** with persistent storage and stable sessions.

- **Local**: `docker compose` for quick testing.
- **Azure**: one command to deploy, plus optional hardening so you don’t lose chats/models after restarts.

---

## Repository Structure

```plaintext
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
      └─ storage-vars.env
```

# Prerequisites

- Docker Desktop (for local runs)
- Azure CLI (az) with the Container Apps extension
- An Azure subscription with permission to create resource groups and Container Apps

Install the extension (once):

	macOS/Linux (bash)
 	az extension add --name containerapp

  	Windows (PowerShell)
   	az extension add --name containerapp

# 1) Quick Start — Local (Docker Compose)
Runs Open WebUI at http://localhost:3000

	macOS/Linux (bash)
	# optional: set WEBUI_PORT or API keys in .env
	cp .env.sample .env
	./scripts/local_up.sh
	
# 2) Quick Start  — Azure Container Apps (ACA)
This deploys Open WebUI with external ingress and creates a persistent Azure Files mount at /app/backend/data so your chats/models survive restarts.

Configure variables
Edit infra/azure/storage-vars.env (these are safe to commit):

	RG=owui-rg
	LOC=uksouth
	ENV_NAME=owui-env
	APP_NAME=owui
	SA_NAME=owuistorage$RANDOM
	SHARE_NAME=owui-data
	MOUNT_PATH=/app/backend/data
	TARGET_PORT=8080

# Deploy
## macOS/Linux (bash):

	az login
 
	chmod +x ./scripts/aca_deploy.sh
	./scripts/aca_deploy.sh
	./scripts/aca_show_url.sh

## Windows (PowerShell):

	az login
	
	# make sure your shell can execute .sh (Git Bash) OR run the same commands inline in PowerShell (see below).
	bash ./scripts/aca_deploy.sh
	bash ./scripts/aca_show_url.sh

The URL will look like:

	https://owui.<something>.<region>.azurecontainerapps.io/

# First-run in the UI

	1.Open the URL, create the admin account.
	2.Go to Settings → Models and add any providers you want:
		- OpenAI / OpenAI-compatible: API key + Base URL (e.g. https://api.openai.com/v1).
		- Azure OpenAI: API key + https://<your-resource>.openai.azure.com, set API version, choose deployment name as the model.
		- Ollama: Base URL (e.g. http://<ip-or-dns>:11434). Model pulls happen on the Ollama host; Open WebUI will list them.
	These settings are stored under /app/backend/data on the mounted Azure Files share, so they persist.

# Hardening (Persistence + Stable Sessions)
To avoid losing sessions and ensure chats/models persist across updates:

A) Set a stable session secret

	macOS/Linux (bash):
 
  		RG=owui-rg; APP=owui
		APP_ID=$(az containerapp show -g "$RG" -n "$APP" --query id -o tsv)
		SECRET=$(openssl rand -hex 32)
		SECRETS_JSON=$(printf '[{"name":"%s","value":"%s"}]' "webui-secret" "$SECRET")
		ENVS_JSON='[{"name":"WEBUI_SECRET_KEY","secretRef":"webui-secret"}]'
		
		az resource update --ids "$APP_ID" \
		  --set properties.configuration.secrets="$SECRETS_JSON" \
		        properties.template.containers[0].env="$ENVS_JSON"
		
		# restart the latest revision (safe)
		REV=$(az containerapp show -g "$RG" -n "$APP" --query properties.latestRevisionName -o tsv)
		az containerapp revision restart -g "$RG" -n "$APP" --revision "$REV"

  Windows (PowerShell):
    
	$rg="owui-rg"; $app="owui"
	$appId = az containerapp show -g $rg -n $app --query id -o tsv
	
	# 32 bytes -> 64 hex chars
	$bytes = New-Object byte[] 32; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
	$secret = ($bytes | ForEach-Object { $_.ToString("x2") }) -join ''
	$secrets = "[{""name"":""webui-secret"",""value"":""$secret""}]"
	$envs    = "[{""name"":""WEBUI_SECRET_KEY"",""secretRef"":""webui-secret""}]"
	
	az resource update --ids $appId --set `
	  properties.configuration.secrets="$secrets" `
	  properties.template.containers[0].env="$envs"
	
	$rev = az containerapp show -g $rg -n $app --query properties.latestRevisionName -o tsv
	az containerapp revision restart -g $rg -n $app --revision $rev
	
B) Ensure the Azure Files mount is active (with nobrl)
	
 macOS/Linux (bash):
    
	RG=owui-rg; APP=owui
	APP_ID=$(az containerapp show -g "$RG" -n "$APP" --query id -o tsv)
	VOLUMES='[{"name":"owui-volume","storageName":"owuifiles","storageType":"AzureFile","mountOptions":"nobrl,dir_mode=0777,file_mode=0666"}]'
	MOUNTS='[{"volumeName":"owui-volume","mountPath":"/app/backend/data"}]'
	
	az resource update --ids "$APP_ID" \
	  --set properties.template.volumes="$VOLUMES" \
	        properties.template.containers[0].volumeMounts="$MOUNTS"
	
	# quick check inside the container
	az containerapp exec -g "$RG" -n "$APP" --command "sh -lc 'mount | grep /app/backend/data; ls -lh /app/backend/data/webui.db || echo NO_DB'"

 Windows (PowerShell):

	$rg="owui-rg"; $app="owui"
	$appId = az containerapp show -g $rg -n $app --query id -o tsv
	$vols  = '[{"name":"owui-volume","storageName":"owuifiles","storageType":"AzureFile","mountOptions":"nobrl,dir_mode=0777,file_mode=0666"}]'
	$mount = '[{"volumeName":"owui-volume","mountPath":"/app/backend/data"}]'
	
	az resource update --ids $appId --set `
	  properties.template.volumes="$vols" `
	  properties.template.containers[0].volumeMounts="$mount"
	
	# verify
	az containerapp exec -g $rg -n $app --command "sh -lc 'mount | grep /app/backend/data; ls -lh /app/backend/data/webui.db || echo NO_DB'"

 # C) Keep a single replica if using the default SQLite DB

 	az containerapp update -g owui-rg -n owui --min-replicas 1 --max-replicas 1

  
