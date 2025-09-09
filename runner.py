#!/usr/bin/env python3
import os, subprocess, textwrap, shutil, sys

# ---- knobs you can change ----
WITH_OLLAMA = True         # set False if you only want Open WebUI
WEBUI_PORT  = 3000         # localhost:<WEBUI_PORT>
DATA_DIR    = os.path.abspath("./owui_data")  # persistent data
# ------------------------------

os.makedirs(DATA_DIR, exist_ok=True)

compose = textwrap.dedent(f"""
version: "3.8"

services:
  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    restart: unless-stopped
    ports:
      - "{WEBUI_PORT}:8080"
    volumes:
      - owui-data:/app/backend/data
    environment:
      # Add model endpoints here or set them later in the UI
      # Examples (uncomment + set as needed):
      # OPENAI_API_KEY: "sk-..."
      # OPENAI_API_BASE: "https://api.openai.com/v1"
      # AZURE_OPENAI_API_KEY: "..."
      # AZURE_OPENAI_API_BASE: "https://<your-aoai>.openai.azure.com"
      # AZURE_OPENAI_API_VERSION: "2024-02-15-preview"
      # OLLAMA_BASE_URL: "http://ollama:11434"
    {("depends_on:\n      - ollama" if WITH_OLLAMA else "")}

{textwrap.dedent("""
  ollama:
    image: ollama/ollama:latest
    restart: unless-stopped
    volumes:
      - ollama-models:/root/.ollama
    ports:
      - "11434:11434"
""") if WITH_OLLAMA else ""}

volumes:
  owui-data:
    driver: local
  """)

# If you want the OpenWebUI data volume mapped to a host folder, swap the volume with a bind:
# e.g. replace "owui-data:/app/backend/data" with f"{DATA_DIR}:/app/backend/data"

compose_path = os.path.abspath("docker-compose.yml")
with open(compose_path, "w", encoding="utf-8") as f:
    f.write(compose)

print(f"[+] Wrote {compose_path}")

# bring it up
if shutil.which("docker") is None:
    print("[-] Docker is not installed or not in PATH.")
    sys.exit(1)

cmd = ["docker", "compose", "up", "-d"]
print(f"[+] Running: {' '.join(cmd)}")
subprocess.check_call(cmd)

print(f"\n✅ Open WebUI is starting. Visit: http://localhost:{WEBUI_PORT}")
if WITH_OLLAMA:
    print("ℹ️  Ollama API is at: http://localhost:11434 (pull models with `ollama pull <model>` inside the container or via API)")
